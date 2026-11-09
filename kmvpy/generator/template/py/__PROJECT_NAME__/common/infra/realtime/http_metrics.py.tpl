"""Observe authenticated HTTP reads without inspecting or storing request/response bodies."""
import time
from starlette.requests import Request


class RealtimeHttpMetrics:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope['type'] != 'http':
            return await self.app(scope, receive, send)
        started = time.monotonic()
        size, status = 0, 499

        async def measured_send(message):
            nonlocal size, status
            if message['type'] == 'http.response.start':
                status = message['status']
            elif message['type'] == 'http.response.body':
                size += len(message.get('body', b''))
            await send(message)

        try:
            await self.app(scope, receive, measured_send)
        finally:
            guard = getattr(Request(scope).state, 'realtime_guard', None)
            if guard:
                await guard.metric('http_response_bytes', size)
                await guard.metric('http_duration_ms', round((time.monotonic() - started) * 1000))
                await guard.metric('http_responses')
                await guard.metric('http_failures', int(status >= 400))
