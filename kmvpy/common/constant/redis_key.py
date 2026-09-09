from typing import Annotated, Union


class RedisKey(object):

    @staticmethod
    def admin_token(admin_kid: Annotated[str, '管理员kid']) -> str:
        return f'token:{admin_kid}'

    # 登录管理员拥有的权限列表
    @staticmethod
    def admin_auth() -> str:
        return 'admin-auth'

    @staticmethod
    def user_captcha(username: Annotated[str, '用户名']) -> str:
        return f'captcha:{username}'

    @staticmethod
    def user_token(user_kid: Annotated[Union[int, str], '用户kid'],
                   software: Annotated[Union[str, None], '终端类型']) -> str:
        # 支持多客户端登录
        return f'token:{user_kid}:{software}'

    @staticmethod
    def socketio_user_kid() -> str:
        """
        sid -> user_kid
        """
        return 'socketio:user_kid'

    @staticmethod
    def user_kid_socketio() -> str:
        """
        user_kid -> sid
        """
        return 'user_kid:socketio'
