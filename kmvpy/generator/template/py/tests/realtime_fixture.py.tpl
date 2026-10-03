"""Loopback-only synthetic acceptance server using the project's actual auth and socket handlers.
No business database, real accounts, repository secrets, production proxy or production configuration.
"""
import asyncio
import os
from contextlib import asynccontextmanager
from pathlib import Path
import shutil

from fastapi import FastAPI, Depends, Request, Response
from fastapi.responses import FileResponse
from kmvpy.common.kmv import kosmos
from kmvpy.core.main.service.jwt_service import JwtUserInfo
import socketio
import uvicorn

from fixture_config import install_fixture_config
from __PROJECT_NAME__.common.auth_session import AuthSessionService
from __PROJECT_NAME__.common.dependencies.auth import auth_user, auth_admin
from __PROJECT_NAME__.common.infra.realtime_http import RealtimeHttpMetrics
from __PROJECT_NAME__.core.main.router.user.socket import router as user_router, register_user_socket_handlers
from __PROJECT_NAME__.core.main.router.admin.socket import router as admin_router, register_admin_socket_handlers
from __PROJECT_NAME__.core.main.service.user.socket import UserSocketService
from __PROJECT_NAME__.core.main.service.admin.socket import AdminSocketService
from __PROJECT_NAME__.core.main.hub.realtime import RealtimeHub

keys = install_fixture_config(int(os.environ.get('__PROJECT_NAME_UPPER___TEST_REDIS_PORT', '16389')))
sio = socketio.AsyncServer(async_mode='asgi', cors_allowed_origins=[], ping_interval=25, ping_timeout=20)
kosmos.socketio = sio
# Test cookie name avoids the production __Host- requirement on this HTTP loopback fixture.
AuthSessionService._session_cookie_name = classmethod(lambda cls, domain: 'fixture-session-' + domain)

async def no_business_database(**kwargs):
    pass
# Only the existing business offline table hook is omitted; transport/auth/guard code is real.
UserSocketService._on_user_socket_authenticated = staticmethod(no_business_database)
register_user_socket_handlers(sio)
register_admin_socket_handlers(sio)
counts = {'user': 0, 'admin': 0}

@asynccontextmanager
async def lifespan(app):
    yield
    for domain, sid in list(RealtimeHub.sessions):
        service = UserSocketService if domain == 'user' else AdminSocketService
        await service.handle_socket_connection('disconnect', sid)
    for client in AuthSessionService._redis_clients.values():
        await client.aclose()
    shutil.rmtree(keys)

http = FastAPI(lifespan=lifespan)
http.add_middleware(RealtimeHttpMetrics)
http.include_router(user_router)
http.include_router(admin_router)

@http.middleware('http')
async def renew(request, call_next):
    response = await call_next(request)
    await AuthSessionService.renew_from_request_state(request, response)
    return response

@http.post('/fixture/login/{domain}')
async def login(domain: str, response: Response):
    assert domain in ('user', 'admin')
    auth = await AuthSessionService.issue_token(JwtUserInfo(kid=42 if domain=='user' else 100, user_type=0 if domain=='user' else 100), auth_role=domain)
    # Test-only HTTP localhost cookie; production remains Secure/HttpOnly.
    response.set_cookie(AuthSessionService._session_cookie_name(domain), auth.session_cookie_value, httponly=True, samesite='lax')
    return {'authorization': 'Bearer '+auth.token, 'sid': auth.sid}

@http.get('/fixture/stats')
async def stats():
    active = []
    for (domain, sid), entry in RealtimeHub.sessions.items():
        active.append({'domain': domain, 'sid': sid, 'engine': sio.manager.eio_sid_from_sid(sid, '/ws' if domain=='user' else '/admin_ws'),
                       'subscriptions': len(entry.subscriptions)})
    return {'active': active, 'reads': counts.copy()}

@http.post('/fixture/notice/{domain}')
async def notice(domain: str):
    await sio.emit('api_notice', {'user_kid': '42', 'api_uri': '/api/'+domain+'/work_ticket/detail', 'kid_for_api': '1'}, namespace='/ws' if domain=='user' else '/admin_ws')
    return {'ok': True}

@http.post('/fixture/disconnect/{domain}')
async def disconnect(domain: str):
    for d, sid in list(RealtimeHub.sessions):
        if d == domain:
            await sio.disconnect(sid, namespace='/ws' if domain=='user' else '/admin_ws')
    return {'ok': True}

@http.post('/fixture/revoke/{domain}')
async def revoke(domain: str):
    for (d, _), entry in list(RealtimeHub.sessions.items()):
        if d == domain:
            await AuthSessionService._redis(domain).delete(AuthSessionService._session_key(domain, entry.info.sid))
    return {'ok': True}

@http.post('/api/user/work_ticket/list')
async def user_list(info=Depends(auth_user)):
    counts['user'] += 1
    return {'code': 0, 'data': {'items': [], 'total': 0}}

@http.post('/api/admin/work_ticket/list')
async def admin_list(info=Depends(auth_admin)):
    counts['admin'] += 1
    return {'code': 0, 'data': {'items': [], 'total': 0}}

@http.post('/api/user/profile')
async def user_profile(info=Depends(auth_user)):
    return {'code':0,'data':{'kid':str(info.kid),'user_type':0,'nickname':'Local test','email':None}}

@http.post('/api/admin/profile')
async def admin_profile(info=Depends(auth_admin)):
    return {'code':0,'data':{'kid':str(info.kid),'user_type':100,'nickname':'Local test','email':None}}

spa = Path(__file__).resolve().parents[2] / '__SPA_PROJECT_NAME__/dist/spa'
@http.get('/{path:path}')
async def asset(path: str):
    requested = (spa / path).resolve()
    if not requested.is_relative_to(spa.resolve()) or not requested.is_file():
        requested = spa / 'index.html'
    return FileResponse(requested)

app = socketio.ASGIApp(sio, http, socketio_path='/ws/socket.io')
if __name__ == '__main__':
    uvicorn.run(app, host='127.0.0.1', port=18761, log_level='warning', access_log=False)
