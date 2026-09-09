# coding: utf-8
"""在 ASGI 请求生命周期内保存当前 `Request`，供装饰器等无法注入 Request 的代码使用。"""

from contextvars import ContextVar, Token

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

current_http_request: ContextVar[Request | None] = ContextVar(
    "current_http_request", default=None
)


def get_current_request() -> Request | None:
    return current_http_request.get()


def _set_request(request: Request) -> Token:
    return current_http_request.set(request)


def _reset_request(token: Token) -> None:
    current_http_request.reset(token)


class HttpRequestContextMiddleware(BaseHTTPMiddleware):
    """将当前 `Request` 放入 ContextVar，请求结束后重置。"""

    async def dispatch(self, request: Request, call_next):
        token = _set_request(request)
        try:
            return await call_next(request)
        finally:
            _reset_request(token)
