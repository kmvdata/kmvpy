"""Atomic, domain/session-scoped protection. Browser identifiers never grant authority."""
import hashlib
import logging
import time
from dataclasses import dataclass
from typing import Literal

from redis.exceptions import RedisError


@dataclass(frozen=True)
class GuardPolicy:
    mode: Literal['off', 'observe', 'enforce'] = 'observe'
    failure: Literal['allow', 'deny'] = 'allow'
    connections: int = 8
    attempts_per_minute: int = 60
    subscriptions: int = 200
    subscription_ops_per_minute: int = 240
    http_per_minute: int = 300
    ttl_seconds: int = 90


class RealtimeGuard:
    _last_store_warning = 0.0
    # Server Redis time and a unique transport ID avoid cross-process clock and cleanup races.
    ADMIT = r'''
local clock = redis.call('TIME')
local now = tonumber(clock[1]) * 1000 + tonumber(clock[2]) / 1000
local ttl = tonumber(ARGV[2]) * 1000
redis.call('ZREMRANGEBYSCORE', KEYS[1], '-inf', now)
redis.call('ZREMRANGEBYSCORE', KEYS[2], '-inf', now - 60000)
redis.call('ZADD', KEYS[2], now, ARGV[1])
redis.call('PEXPIRE', KEYS[2], 120000)
local count = redis.call('ZCARD', KEYS[1])
local attempts = redis.call('ZCARD', KEYS[2])
local limited = (count >= tonumber(ARGV[3]) or attempts > tonumber(ARGV[4]))
redis.call('HINCRBY', KEYS[3], 'attempts', 1)
if limited then redis.call('HINCRBY', KEYS[3], 'connection_over_limit', 1) end
redis.call('EXPIRE', KEYS[3], 86400)
if limited and ARGV[5] == 'enforce' then return {0, count, attempts} end
redis.call('ZADD', KEYS[1], now + ttl, ARGV[1])
redis.call('PEXPIRE', KEYS[1], ttl + 1000)
return {1, count + 1, attempts}
'''
    RENEW = r'''
local clock = redis.call('TIME')
local now = tonumber(clock[1]) * 1000 + tonumber(clock[2]) / 1000
local until_at = tonumber(redis.call('ZSCORE', KEYS[1], ARGV[1]) or '0')
if until_at <= now then redis.call('ZREM', KEYS[1], ARGV[1]); return 0 end
local ttl = tonumber(ARGV[2]) * 1000
redis.call('ZADD', KEYS[1], now + ttl, ARGV[1])
redis.call('PEXPIRE', KEYS[1], ttl + 1000)
local subscriptions = redis.call('ZRANGE', KEYS[2], 0, -1)
for _, member in ipairs(subscriptions) do
    if string.sub(member, 1, string.len(ARGV[1]) + 1) == ARGV[1] .. ':' then
        redis.call('ZADD', KEYS[2], now + ttl, member)
    end
end
redis.call('PEXPIRE', KEYS[2], ttl + 1000)
return 1
'''
    RATE = r'''
local clock = redis.call('TIME')
local now = tonumber(clock[1]) * 1000 + tonumber(clock[2]) / 1000
redis.call('ZREMRANGEBYSCORE', KEYS[1], '-inf', now - 60000)
redis.call('ZADD', KEYS[1], now, ARGV[1])
redis.call('PEXPIRE', KEYS[1], 120000)
local count = redis.call('ZCARD', KEYS[1])
redis.call('HINCRBY', KEYS[2], ARGV[2], 1)
local limited = count > tonumber(ARGV[3])
if limited then redis.call('HINCRBY', KEYS[2], ARGV[2] .. '_over_limit', 1) end
redis.call('EXPIRE', KEYS[2], 86400)
if limited and ARGV[4] == 'enforce' then return 0 end
return 1
'''

    SUBSCRIPTION = r"""
local clock = redis.call('TIME')
local now = tonumber(clock[1]) * 1000 + tonumber(clock[2]) / 1000
redis.call('ZREMRANGEBYSCORE', KEYS[2], '-inf', now)
if tonumber(redis.call('ZSCORE', KEYS[1], ARGV[1]) or '0') <= now then return 0 end
if ARGV[3] == 'unsubscribe' then redis.call('ZREM', KEYS[2], ARGV[2]); return 1 end
local exists = redis.call('ZSCORE', KEYS[2], ARGV[2])
if not exists and redis.call('ZCARD', KEYS[2]) >= tonumber(ARGV[5]) then
    redis.call('HINCRBY', KEYS[3], 'subscription_over_limit', 1)
    if ARGV[6] == 'enforce' then return 0 end
end
redis.call('ZADD', KEYS[2], now + tonumber(ARGV[4]) * 1000, ARGV[2])
redis.call('EXPIRE', KEYS[2], tonumber(ARGV[4]) + 1)
return 1
"""

    def __init__(self, redis, policy: GuardPolicy, domain: str, user: str, session: str):
        self.redis = redis
        self.policy = policy
        identity = hashlib.sha256(f'{domain}:{user}:{session}'.encode()).hexdigest()
        self.base = f'realtime:{{{identity}}}'  # one Redis Cluster hash slot

    async def _eval(self, script, keys, *args):
        if self.policy.mode == 'off':
            return 1
        if self.redis is None:
            return None
        try:
            return await self.redis.eval(script, len(keys), *keys, *args)
        except (RedisError, OSError, TimeoutError):
            if time.monotonic() - RealtimeGuard._last_store_warning > 30:
                RealtimeGuard._last_store_warning = time.monotonic()
                logging.getLogger('__PROJECT_NAME__.realtime').warning('shared_storage_unavailable mode=%s failure=%s', self.policy.mode, self.policy.failure)
            return None

    def _allowed(self, result) -> bool:
        if result is None:
            # Auth is completed before invoking protection; fail-open never bypasses it.
            return self.policy.failure == 'allow' or self.policy.mode != 'enforce'
        return bool(result[0] if isinstance(result, (list, tuple)) else result)

    async def admit(self, connection: str) -> bool:
        p = self.policy
        result = await self._eval(self.ADMIT, [self.base + ':active', self.base + ':attempts', self.base + ':metrics'],
                                  connection, p.ttl_seconds, p.connections, p.attempts_per_minute, p.mode)
        return self._allowed(result)

    async def renew(self, connection: str) -> bool:
        result = await self._eval(self.RENEW, [self.base + ':active', self.base + ':subscriptions'], connection, self.policy.ttl_seconds)
        return self._allowed(result)

    async def release(self, connection: str):
        if self.redis is not None and self.policy.mode != 'off':
            try:
                # Unique connection members cannot remove a replacement connection.
                await self.redis.zrem(self.base + ':active', connection)
                members = await self.redis.zrange(self.base + ':subscriptions', 0, -1)
                owned = [m for m in members if (m.decode() if isinstance(m, bytes) else m).startswith(connection + ':')]
                if owned:
                    await self.redis.zrem(self.base + ':subscriptions', *owned)
            except (RedisError, OSError, TimeoutError):
                pass  # TTL cleans up crashes and unavailable Redis.

    async def rate(self, event: str, request_id: str, limit: int) -> bool:
        started = time.monotonic()
        result = await self._eval(self.RATE, [self.base + ':' + event, self.base + ':metrics'],
                                  request_id, event, limit, self.policy.mode)
        await self.metric(event + '_wait_ms', round((time.monotonic() - started) * 1000))
        return self._allowed(result)

    async def metric(self, name: str, value: int = 1):
        if self.redis is not None and self.policy.mode != 'off':
            try:
                async with self.redis.pipeline(transaction=True) as pipe:
                    pipe.hincrby(self.base + ':metrics', name, value)
                    pipe.expire(self.base + ':metrics', 86400)
                    await pipe.execute()
            except (RedisError, OSError, TimeoutError):
                pass

    async def subscription(self, connection, action, resource):
        member = connection + ':' + hashlib.sha256(resource.encode()).hexdigest()
        result = await self._eval(self.SUBSCRIPTION,
            [self.base + ':active', self.base + ':subscriptions', self.base + ':metrics'],
            connection, member, action, self.policy.ttl_seconds, self.policy.subscriptions, self.policy.mode)
        return self._allowed(result)
