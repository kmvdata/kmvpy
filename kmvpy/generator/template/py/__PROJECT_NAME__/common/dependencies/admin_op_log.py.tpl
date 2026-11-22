# coding: utf-8
import functools
import json
import time
from collections.abc import Mapping
from typing import Any

from fastapi.encoders import jsonable_encoder
from kmvpy.common.tool.logger import logger
from kmvpy.core.main.service.jwt_service import JwtUserInfo
from pydantic import BaseModel
from starlette.datastructures import UploadFile as StarletteUploadFile
from starlette.requests import Request

from __PROJECT_NAME__.common.dependencies.auth import UserType
from __PROJECT_NAME__.common.dependencies.client import ClientRequestInfo
from __PROJECT_NAME__.common.dependencies.http_request_context import get_current_request
from __PROJECT_NAME__.common.infra.orm.admin_op_log import AdminOperationLog
from __PROJECT_NAME__.common.infra.storage.default_storage import DefaultStorage

# 当参数为 Starlette `Request` 且参数名在此集合时，不入 JSON（与 body 的 `req` 无冲突）
_SKIP_REQUEST_PARAM_NAMES = frozenset({"request"})

# 当参数名为以下之一且值为 JwtUserInfo 时，不入 request_params（admin_kid 已单独存）
_JWT_KWARG_NAMES = frozenset(
    {
        "user_info",
        "_user_info",
        "_admin_user",
        "admin_user",
    }
)

_SENSITIVE_KEYS = frozenset(
    {
        "password",
        "old_password",
        "new_password",
        "access_token",
        "refresh_token",
        "token",
        "api_key",
        "ai_api_key",
        "authorization",
        "csv_content",
    }
)

_MAX_TEXT = 48_000


def _redact_obj(obj: Any) -> Any:
    if obj is None:
        return None
    if isinstance(obj, BaseModel):
        return _redact_obj(obj.model_dump(mode="json"))
    if isinstance(obj, Mapping):
        out: dict[str, Any] = {}
        for k, v in obj.items():
            lk = k.lower() if isinstance(k, str) else k
            if isinstance(lk, str) and lk in _SENSITIVE_KEYS:
                out[str(k)] = "***"
            else:
                out[str(k)] = _redact_obj(v)
        return out
    if isinstance(obj, (list, tuple)):
        return [_redact_obj(x) for x in obj]
    return obj


def _serialize_value_for_params(name: str, value: Any) -> Any:
    if isinstance(value, StarletteUploadFile):
        return {
            "filename": value.filename,
            "size": getattr(value, "size", None),
            "content_type": value.content_type,
        }
    if isinstance(value, JwtUserInfo):
        return {
            "kid": value.kid,
            "user_type": value.user_type,
        }
    if isinstance(value, ClientRequestInfo):
        return {
            "ip": value.ip,
            "device_id": (value.device_id or "")[:64],
            "app_version": (value.app_version or "")[:32],
        }
    if isinstance(value, BaseModel):
        return _redact_obj(value)
    if isinstance(value, Request):
        return None
    return _redact_obj(value)


def _build_request_params_from_kwargs(kwargs: dict[str, Any]) -> str | None:
    parts: dict[str, Any] = {}
    for name, value in kwargs.items():
        if name in _SKIP_REQUEST_PARAM_NAMES and isinstance(value, Request):
            continue
        if name in _JWT_KWARG_NAMES and isinstance(value, JwtUserInfo):
            continue
        if isinstance(value, Request):
            continue
        ser = _serialize_value_for_params(name, value)
        if ser is not None:
            parts[name] = ser
    if not parts:
        return None
    try:
        s = json.dumps(
            parts,
            ensure_ascii=False,
            default=str,
        )
        if len(s) > _MAX_TEXT:
            s = s[: _MAX_TEXT - 20] + "...(truncated)"
        return s
    except Exception as exc:  # noqa: BLE001
        logger.debug("admin_op_log 序列化入参失败: %s", exc)
        return None


def _extract_admin_kid(kwargs: dict[str, Any]) -> int | None:
    for key in _JWT_KWARG_NAMES:
        v = kwargs.get(key)
        if isinstance(v, JwtUserInfo) and v.user_type == int(UserType.ADMIN):
            return v.kid
    for v in kwargs.values():
        if isinstance(v, JwtUserInfo) and v.user_type == int(UserType.ADMIN):
            return v.kid
    return None


def _serialize_response(result: Any) -> str | None:
    try:
        enc = jsonable_encoder(result)
        s = json.dumps(enc, ensure_ascii=False, default=str)
        if len(s) > _MAX_TEXT:
            s = s[: _MAX_TEXT - 20] + "...(truncated)"
        return s
    except Exception as exc:  # noqa: BLE001
        logger.debug("admin_op_log 序列化响应失败: %s", exc)
        return f"<{type(result).__name__}>"


async def _persist(
    *,
    action: str,
    method: str,
    path: str,
    admin_kid: int | None,
    request_params: str | None,
    response_body: str | None,
    success: bool,
    error_message: str | None,
    duration_ms: int,
    client_ip: str | None,
    user_agent: str | None,
) -> None:
    from kmvpy.common.kmv import kosmos

    if kosmos.config is None or getattr(kosmos.config, "database", None) is None:
        return
    try:
        row = AdminOperationLog(
            kid=AdminOperationLog.gen_kid(),
            admin_kid=admin_kid,
            action=action,
            method=method,
            path=path[:512],
            request_params=request_params,
            response_body=response_body,
            success=success,
            error_message=(error_message or "")[:2000] or None,
            duration_ms=duration_ms,
            client_ip=(client_ip or None) and client_ip[:64],
            user_agent=(user_agent or None) and user_agent[:512],
        )
        db = DefaultStorage.instance()
        async with db.session_scope() as session:
            session.add(row)
    except Exception as exc:  # noqa: BLE001
        logger.warning(
            "写入管理员操作日志失败 action=%s path=%s: %s",
            action,
            path,
            exc,
            exc_info=exc,
        )


def admin_op_log(handler):
    """
    装饰器：在路由处理前后记录管理员操作(入参/返回/成功失败)。

    需配合 ``HttpRequestContextMiddleware``(在 ``gen_asgi_app`` 中已挂载) 以获取 URL 路径与客户端信息。

    与 ``@api_log`` 可叠放，建议顺序::

        @router.post(...)
        @api_log
        @admin_op_log
        async def api_xxx(...):
            ...
    """
    if not hasattr(handler, "__name__"):
        return handler

    @functools.wraps(handler)
    async def async_wrapper(*args, **kwargs):
        started = time.perf_counter()
        request = get_current_request()
        method = (request.method if request else "POST") or "POST"
        path = (request.url.path if request else f"<no_request:{handler.__name__}>") or ""
        client_ip: str | None = None
        user_agent: str | None = None
        if request and request.client:
            xf = request.headers.get("X-Forwarded-For", "").strip()
            if xf:
                client_ip = xf.split(",")[0].strip()[:64]
            else:
                client_ip = (request.client.host or "")[:64] or None
            user_agent = (request.headers.get("User-Agent", "") or "")[:512] or None

        params_str = _build_request_params_from_kwargs(dict(kwargs))
        admin_kid = _extract_admin_kid(dict(kwargs))

        result: Any = None
        err_msg: str | None = None
        ok = True
        try:
            result = await handler(*args, **kwargs)
        except Exception as exc:  # noqa: BLE001
            ok = False
            err_msg = str(exc) or repr(exc)
            raise
        finally:
            elapsed_ms = int((time.perf_counter() - started) * 1000)
            resp_s = _serialize_response(result) if ok else None
            await _persist(
                action=handler.__name__,
                method=method,
                path=path,
                admin_kid=admin_kid,
                request_params=params_str,
                response_body=resp_s,
                success=ok,
                error_message=err_msg,
                duration_ms=elapsed_ms,
                client_ip=client_ip,
                user_agent=user_agent,
            )
        return result

    return async_wrapper
