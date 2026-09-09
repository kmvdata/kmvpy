from typing import Annotated

from kmvpy.common.constant.redis_key import RedisKey
from kmvpy.common.infra.korm_storage import KOrmStorage
from kmvpy.common.tool import logger


def socketio_bind_router(socketio, storage: KOrmStorage | None = None):
    """
    在线测试 https://amritb.github.io/socketio-client-tool/
    连接地址: http://localhost:5000/ws  这里的/ws是namespace
    连接参数: {"path": "/ws/socket.io", "forceNew": true, "reconnectionAttempts": 3, "timeout": 2000}
    """

    @socketio.on(event='connect', namespace='/ws')
    async def connect(sid: Annotated[str, 'sid'], environ):
        logger.info(f'客户端: {sid} 连接')
        # await socketio.enter_room(sid=sid, room='ideaOS')
        # print(f'客户端: {sid} 加入 room ideaOS')
        # await kosmos.socketio.emit(event='vision', data={'data': 'hello'}, namespace='/ws')
        # 未disconnect会导致残留大量连接记录，因此只保存登录的连接
        # kosmos.config.redis.redis_client.hset(name=RedisKey.socketio_user_kid(), key=sid, value='')

    @socketio.on(event='disconnect', namespace='/ws')
    async def disconnect(sid: Annotated[str, 'sid']):
        logger.info(f'客户端: {sid} 断开连接')
        # await socketio.leave_room(sid=sid, room='ideaOS')
        try:
            if storage is None or not storage.has_redis_client():
                return
            user_kid = await storage.redis_client.hget(
                name=RedisKey.socketio_user_kid(), key=sid)
            if user_kid:
                await storage.redis_client.hdel(
                    RedisKey.user_kid_socketio(), user_kid)
            await storage.redis_client.hdel(RedisKey.socketio_user_kid(), sid)
        except AttributeError as e:
            logger.error(e)

    # @socketio.on(event='signin', namespace='/ws')
    # async def signin(sid: Annotated[str, 'sid'], data: Annotated[str, '入参']):
    #     try:
    #         _data = json.loads(data)
    #         _token = _data.get('token')
    #         # 解密
    #         _token = decode_token(encoded_token=_token)
    #     except Exception as e:
    #         logger.error(e)
    #         # await socketio.emit(SocketioResponse.response_with_kmv_exception(
    #         #     kmv_exception=KmvException(error=KmvError.SIGNIN_ERROR)))
    #         return SocketioResponse.response_with_kmv_exception(
    #             kmv_exception=KmvException(error=KmvError.SIGNIN_ERROR))
    #     if not UserService.is_signin(token=_token):
    #         # 登录失败
    #         return SocketioResponse.response_with_kmv_exception(
    #             kmv_exception=KmvException(error=KmvError.SIGNIN_ERROR))
    #     # 登录成功
    #     _tokens = _token.split(':')
    #     user_kid = _tokens[0]
    #     logger.info(f'用户 {user_kid} 客户端 {sid} 登录成功')
    #     kosmos.config.redis.redis_client.hset(name=RedisKey.socketio_user_kid(), key=sid, value=user_kid)
    #     kosmos.config.redis.redis_client.hset(name=RedisKey.user_kid_socketio(), key=user_kid, value=sid)
    #     return SocketioResponse.success_response()
    #
    # # 向客户端推送消息
    # # await socketio.emit(event='消息名称', data='消息内容')
