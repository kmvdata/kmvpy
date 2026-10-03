from __PROJECT_NAME__.core.main.hub.realtime import RealtimeHub


class RealtimeService:
    @staticmethod
    async def connect(domain, sid, token, environ):
        return await RealtimeHub.connect(domain, sid, token, environ)

    @staticmethod
    async def disconnect(domain, sid):
        await RealtimeHub.disconnect(domain, sid)

    @staticmethod
    async def update(domain, sid, data):
        return await RealtimeHub.update(domain, sid, data)

    @staticmethod
    async def subscription(domain, sid, data):
        return await RealtimeHub.subscription(domain, sid, data)

    @staticmethod
    async def http_request(domain, info):
        return await RealtimeHub.http_request(domain, info)
