import asyncio
import multiprocessing
import os
import time
import unittest
import uuid
from unittest.mock import patch

from fastapi import HTTPException, Request, Response
from kmvpy.core.main.service.jwt_service import JwtUserInfo, JwtService
from redis.asyncio import Redis
from redis.exceptions import ConnectionError
from __PROJECT_NAME__.common.auth_session import AuthSessionService
from __PROJECT_NAME__.common.dependencies.auth import auth_user
from __PROJECT_NAME__.common.infra.realtime_guard import RealtimeGuard, GuardPolicy
from __PROJECT_NAME__.common.infra.realtime_auth import authenticate_transport
from __PROJECT_NAME__.core.main.hub.realtime import RealtimeHub
from fixture_config import install_fixture_config

PORT = int(os.environ.get('__PROJECT_NAME_UPPER___TEST_REDIS_PORT', '16389'))


def competing_worker(session, event, queue):
    async def run():
        redis = Redis(host='127.0.0.1', port=PORT)
        g = RealtimeGuard(redis, GuardPolicy(mode='enforce', connections=3, ttl_seconds=2), 'user', '1', session)
        event.wait()
        result = await g.admit(uuid.uuid4().hex)
        queue.put((os.getpid(), result))
        await redis.aclose()
    asyncio.run(run())


def crashing_worker(session, queue):
    async def run():
        redis = Redis(host='127.0.0.1', port=PORT)
        guard = RealtimeGuard(redis, GuardPolicy(mode='enforce', connections=1, ttl_seconds=1), 'user', '1', session)
        queue.put(await guard.admit('crashed-process'))
        while True:
            await asyncio.sleep(.2)
            await guard.renew('crashed-process')
    asyncio.run(run())


class RedisGuardTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.redis = Redis(host='127.0.0.1', port=PORT)
        await self.redis.ping()
        self.sid = uuid.uuid4().hex

    async def asyncTearDown(self):
        await self.redis.aclose()

    def guard(self, **options):
        return RealtimeGuard(self.redis, GuardPolicy(**options), 'user', '1', self.sid)

    async def test_atomic_process_competition_and_crash_ttl(self):
        ctx = multiprocessing.get_context('spawn')
        event, queue = ctx.Event(), ctx.Queue()
        procs = [ctx.Process(target=competing_worker, args=(self.sid, event, queue)) for _ in range(8)]
        for p in procs:
            p.start()
        event.set()
        values = await asyncio.to_thread(lambda: [queue.get(timeout=20) for _ in procs])
        for p in procs:
            await asyncio.to_thread(p.join, 5)
            self.assertEqual(p.exitcode, 0)
        self.assertEqual(len({p for p, _ in values}), 8)
        self.assertEqual(sum(allowed for _, allowed in values), 3)
        g = self.guard(mode='enforce', connections=3, ttl_seconds=2)
        self.assertFalse(await g.admit('before-crash-cleanup'))
        await asyncio.sleep(2.1)
        self.assertTrue(await g.admit('replacement'))
        self.assertEqual(await self.redis.zcard(g.base + ':active'), 1)

    async def test_terminated_owner_is_cleaned_by_ttl(self):
        ctx = multiprocessing.get_context('spawn')
        queue = ctx.Queue()
        process = ctx.Process(target=crashing_worker, args=(self.sid, queue))
        process.start()
        try:
            self.assertTrue(await asyncio.to_thread(queue.get, True, 20))
            guard = self.guard(mode='enforce', connections=1, ttl_seconds=1)
            self.assertFalse(await guard.admit('before-termination'))
            process.terminate()
            await asyncio.to_thread(process.join, 5)
            self.assertLess(process.exitcode, 0)
            await asyncio.sleep(1.2)
            self.assertTrue(await guard.admit('after-termination'))
            self.assertFalse(await guard.renew('crashed-process'))
        finally:
            if process.is_alive():
                process.terminate()
                await asyncio.to_thread(process.join, 5)

    async def test_expired_lease_cannot_resurrect_and_old_cleanup_preserves_new(self):
        g = self.guard(ttl_seconds=1)
        self.assertTrue(await g.admit('old'))
        await asyncio.sleep(1.1)
        self.assertFalse(await g.renew('old'))
        self.assertTrue(await g.admit('new'))
        await g.release('old')
        self.assertIsNotNone(await self.redis.zscore(g.base + ':active', 'new'))

    async def test_observe_off_enforce_and_domain_isolation(self):
        observe = self.guard(mode='observe', connections=1)
        self.assertTrue(await observe.admit('a'))
        self.assertTrue(await observe.admit('b'))
        self.assertEqual(int(await self.redis.hget(observe.base + ':metrics', 'connection_over_limit')), 1)
        enforce = self.guard(mode='enforce', connections=1)
        self.assertFalse(await enforce.admit('c'))
        admin = RealtimeGuard(self.redis, GuardPolicy(mode='enforce', connections=1), 'admin', '1', self.sid)
        self.assertTrue(await admin.admit('c'))
        off = self.guard(mode='off', connections=1)
        self.assertTrue(await off.admit('d'))
        self.assertIsNone(await self.redis.zscore(off.base + ':active', 'd'))

    async def test_atomic_subscriptions_rates_and_release(self):
        g = self.guard(mode='enforce', subscriptions=1)
        await g.admit('a'); await g.admit('b')
        self.assertTrue(await g.subscription('a', 'subscribe', 'r'))
        self.assertFalse(await g.subscription('b', 'subscribe', 'r'))
        self.assertTrue(await g.subscription('a', 'unsubscribe', 'r'))
        self.assertTrue(await g.subscription('b', 'subscribe', 'r'))
        self.assertTrue(await g.rate('http', 'req1', 1))
        self.assertFalse(await g.rate('http', 'req2', 1))
        await g.release('b')
        self.assertEqual(await self.redis.zcard(g.base + ':subscriptions'), 0)

    async def test_shared_store_failure_policy(self):
        class Broken:
            async def eval(self, *args): raise ConnectionError('synthetic')
        for mode, failure, expected in [('observe','deny',True),('enforce','allow',True),('enforce','deny',False)]:
            g = RealtimeGuard(Broken(), GuardPolicy(mode=mode, failure=failure), 'user','1','s')
            self.assertEqual(await g.admit('a'), expected)


class AuthTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.keys = install_fixture_config(PORT)
        AuthSessionService._redis_clients = {}
        self.auth = await AuthSessionService.issue_token(JwtUserInfo(kid=90071992547409931,user_type=0), auth_role='user')
        self.scope = {'type':'http','method':'POST','path':'/api/user/socket/session','headers':[
            (b'authorization', ('Bearer '+self.auth.token).encode()),
            (b'cookie', (AuthSessionService._session_cookie_name('user')+'='+self.auth.session_cookie_value).encode())]}

    async def asyncTearDown(self):
        for domain, sid in list(RealtimeHub.sessions):
            await RealtimeHub.disconnect(domain, sid)
        for client in AuthSessionService._redis_clients.values():
            await client.aclose()
        import shutil
        shutil.rmtree(self.keys)

    async def test_real_signature_cookie_and_revoked_session(self):
        info = await authenticate_transport('user',self.auth.token,self.scope)
        self.assertEqual(info.sid,self.auth.sid)
        self.assertEqual(info.kid,90071992547409931)
        await AuthSessionService._redis('user').delete(AuthSessionService._session_key('user',self.auth.sid))
        with self.assertRaises(Exception) as raised:
            await auth_user(Request(self.scope),Response())
        self.assertEqual(raised.exception.status_code,401)
        self.assertEqual(raised.exception.headers['X-Auth-Error'],'session_invalid')

    async def test_expired_access_recovers_same_login_session(self):
        import jwt
        from kmvpy.common.kmv import kosmos
        cfg = kosmos.config.auth_config.user.jwt
        payload = JwtService.decode_token(self.auth.token, auth_role='user')
        payload['exp'] = int(time.time())-1
        payload.pop('kid',None)
        token = jwt.encode(payload,cfg.get_active_private_key(),algorithm='RS256',headers={'typ':'at+jwt','kid':cfg.active_kid})
        scope = {**self.scope,'headers':[(k, ('Bearer '+token).encode() if k==b'authorization' else v) for k,v in self.scope['headers']]}
        response = Response()
        info = await auth_user(Request(scope),response)
        self.assertEqual(info.sid,self.auth.sid)
        self.assertIn('x-auth-token',response.headers)

    async def test_expired_access_shared_store_outage_is_503_not_logout(self):
        import jwt
        from kmvpy.common.kmv import kosmos
        cfg=kosmos.config.auth_config.user.jwt
        payload=JwtService.decode_token(self.auth.token,auth_role='user');payload['exp']=int(time.time())-1;payload.pop('kid',None)
        token=jwt.encode(payload,cfg.get_active_private_key(),algorithm='RS256',headers={'typ':'at+jwt','kid':cfg.active_kid})
        scope={**self.scope,'headers':[(k,('Bearer '+token).encode() if k==b'authorization' else v) for k,v in self.scope['headers']]}
        class Broken:
            async def eval(self,*args): raise ConnectionError('synthetic')
        with patch.object(AuthSessionService,'_redis',return_value=Broken()):
            with self.assertRaises(HTTPException) as raised:
                await auth_user(Request(scope),Response())
        self.assertEqual(raised.exception.status_code,503)

    async def test_transport_update_is_same_session_only_and_rollback_releases(self):
        await RealtimeHub.connect('user','synthetic',self.auth.token,{'asgi.scope':self.scope})
        self.assertTrue((await RealtimeHub.update('user','synthetic',{'authorization':'Bearer '+self.auth.token}))['ok'])
        another=await AuthSessionService.issue_token(JwtUserInfo(kid=2,user_type=0),auth_role='user')
        self.assertFalse((await RealtimeHub.update('user','synthetic',{'authorization':'Bearer '+another.token}))['ok'])
        entry=RealtimeHub.sessions[('user','synthetic')]
        await RealtimeHub.disconnect('user','synthetic')
        self.assertIsNone(await self.redis_score(entry))

    async def test_initialization_failure_rolls_back_admission(self):
        from __PROJECT_NAME__.core.main.service.user.socket import UserSocketService
        with patch.object(UserSocketService, '_enter_user_room', side_effect=OSError('synthetic room failure')):
            with self.assertRaises(OSError):
                await UserSocketService._handle_connect('rollback', {'asgi.scope': self.scope}, {'authorization': 'Bearer ' + self.auth.token})
        self.assertNotIn(('user', 'rollback'), RealtimeHub.sessions)
        info = JwtService.payload_to_user_info(JwtService.decode_token(self.auth.token, auth_role='user'))
        guard = RealtimeHub.guard('user', info)
        self.assertEqual(await guard.redis.zcard(guard.base + ':active'), 0)

    async def redis_score(self,entry):
        return await entry.guard.redis.zscore(entry.guard.base+':active',entry.connection)


if __name__ == '__main__': unittest.main()
