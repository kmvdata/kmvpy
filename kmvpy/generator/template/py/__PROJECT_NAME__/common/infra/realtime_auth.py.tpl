"""HTTP cookie adapter for authenticated Socket.IO handshakes and updates."""
import time
from fastapi import HTTPException, Request
from kmvpy.core.main.service.jwt_service import JwtService
import socketio
from __PROJECT_NAME__.common.auth_session import AuthSessionService


async def authenticate_transport(domain, token, scope):
    try:
        payload = await AuthSessionService.authenticate_access_token(Request(scope), auth_role=domain, token=token)
        info = JwtService.payload_to_user_info(payload)
        if info.user_type != (100 if domain == 'admin' else 0):
            raise HTTPException(401)
        return info
    except HTTPException as exc:
        if exc.status_code >= 500:
            kind = 'temporary'
        else:
            try:
                payload = JwtService.decode_token_without_exp(token, auth_role=domain)
                expired = int(payload.get('exp', 0)) <= time.time()
            except HTTPException:
                expired = False
            kind = 'token_expired' if expired else 'session_invalid'
        raise socketio.exceptions.ConnectionRefusedError('authentication rejected', {'kind': kind}) from exc
