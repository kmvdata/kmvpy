"""Transport infrastructure; resource intents do not confer business permissions."""
import asyncio
import hashlib
import time
import uuid
from dataclasses import dataclass, field
from typing import Any

from kmvpy.common.kmv import kosmos
from redis.exceptions import RedisError
import socketio

from __PROJECT_NAME__.common.auth_session import AuthSessionService
from __PROJECT_NAME__.common.infra.realtime.auth import authenticate_transport
from __PROJECT_NAME__.common.conf import get_app_config
from __PROJECT_NAME__.common.infra.realtime.guard import GuardPolicy, RealtimeGuard


@dataclass
class TransportSession:
    info: Any
    scope: dict
    guard: RealtimeGuard
    connection: str
    recovery: bool = False
    subscriptions: dict[str, int | None] = field(default_factory=dict)
    task: asyncio.Task | None = None
    subscription_lock: asyncio.Lock = field(default_factory=asyncio.Lock)


class RealtimeHub:
    sessions: dict[tuple[str, str], TransportSession] = {}

    @staticmethod
    def guard(domain, info):
        policy = GuardPolicy(**get_app_config().realtime_protection.model_dump())
        return RealtimeGuard(AuthSessionService._redis(domain), policy, domain, str(info.kid), str(info.sid))

    @staticmethod
    async def connect(domain, sid, token, environ, observation=None):
        scope = (environ or {}).get('asgi.scope')
        if not scope:
            raise socketio.exceptions.ConnectionRefusedError('authentication rejected', {'kind': 'session_invalid'})
        info = await authenticate_transport(domain, token, scope)
        guard = RealtimeHub.guard(domain, info)
        connection = uuid.uuid4().hex
        recovery = isinstance(observation, dict) and observation.get('recovery') is True
        if recovery:
            await guard.metric('recovery_attempts')
        if not await guard.admit(connection):
            raise socketio.exceptions.ConnectionRefusedError('connection limited', {'kind': 'rate_limited'})
        entry = TransportSession(info, scope, guard, connection, recovery)
        RealtimeHub.sessions[(domain, sid)] = entry

        async def renew_lease():
            try:
                while RealtimeHub.sessions.get((domain, sid)) is entry:
                    await asyncio.sleep(max(1, guard.policy.ttl_seconds / 3))
                    if RealtimeHub.sessions.get((domain, sid)) is not entry:
                        return
                    if not await guard.renew(connection):
                        await kosmos.socketio.disconnect(sid, namespace='/admin_ws' if domain == 'admin' else '/ws')
                        return
            except asyncio.CancelledError:
                raise
            except (RedisError, OSError):
                await guard.metric('shared_storage_failure')
        entry.task = asyncio.create_task(renew_lease())
        await guard.metric('connection_initializing')
        return info

    @staticmethod
    async def http_request(domain, info):
        guard = RealtimeHub.guard(domain, info)
        allowed = await guard.rate('http_requests', uuid.uuid4().hex, guard.policy.http_per_minute)
        return guard, allowed

    @staticmethod
    async def disconnect(domain, sid):
        entry = RealtimeHub.sessions.pop((domain, sid), None)
        if entry:
            if entry.task:
                entry.task.cancel()
            await entry.guard.release(entry.connection)
            await entry.guard.metric('disconnects')

    @staticmethod
    async def update(domain, sid, data):
        entry = RealtimeHub.sessions.get((domain, sid))
        if not entry or not isinstance(data, dict) or not isinstance(data.get('authorization'), str):
            return {'ok': False, 'kind': 'session_invalid'}
        token = data['authorization'].removeprefix('Bearer ').strip()
        try:
            info = await authenticate_transport(domain, token, entry.scope)
        except socketio.exceptions.ConnectionRefusedError as exc:
            return {'ok': False, **exc.error_args.get('data', {'kind': 'temporary'})}
        if RealtimeHub.sessions.get((domain, sid)) is not entry:
            return {'ok': False, 'kind': 'temporary'}
        if (info.kid, info.sid) != (entry.info.kid, entry.info.sid):
            return {'ok': False, 'kind': 'session_invalid'}
        if info.expires_at > entry.info.expires_at:
            entry.info = info
        await entry.guard.metric('renewals')
        return {'ok': True, 'expires_at': entry.info.expires_at}

    @staticmethod
    async def subscription(domain, sid, data):
        entry = RealtimeHub.sessions.get((domain, sid))
        if not entry or entry.info.expires_at <= time.time():
            return {'ok': False, 'kind': 'token_expired'}
        if not isinstance(data, dict):
            return {'ok': False, 'kind': 'invalid_request'}
        action, resource, baseline = data.get('action'), data.get('resource'), data.get('baseline')
        if action not in ('subscribe', 'unsubscribe') or not isinstance(resource, str) or not 0 < len(resource) <= 255:
            return {'ok': False, 'kind': 'invalid_request'}
        if baseline is not None and (type(baseline) is not int or baseline < 0 or baseline > 2**53 - 1):
            return {'ok': False, 'kind': 'invalid_request'}
        p = entry.guard.policy
        if not await entry.guard.rate('subscription_ops', uuid.uuid4().hex, p.subscription_ops_per_minute):
            return {'ok': False, 'kind': 'rate_limited'}
        async with entry.subscription_lock:
            if RealtimeHub.sessions.get((domain, sid)) is not entry:
                return {'ok': False, 'kind': 'temporary'}
            if not await entry.guard.subscription(entry.connection, action, resource):
                return {'ok': False, 'kind': 'rate_limited'}
            digest = hashlib.sha256(resource.encode()).hexdigest()
            room = f'realtime:{domain}:{entry.info.kid}:{digest}'
            namespace = '/admin_ws' if domain == 'admin' else '/ws'
            try:
                if action == 'subscribe':
                    await kosmos.socketio.enter_room(sid=sid, room=room, namespace=namespace)
                    entry.subscriptions[resource] = baseline
                else:
                    await kosmos.socketio.leave_room(sid=sid, room=room, namespace=namespace)
                    entry.subscriptions.pop(resource, None)
            except Exception:
                if action == 'subscribe':
                    await entry.guard.subscription(entry.connection, 'unsubscribe', resource)
                return {'ok': False, 'kind': 'temporary'}
        await entry.guard.metric(action)
        return {'ok': True, 'calibrate': True}  # current scaffold has no authoritative version handshake
