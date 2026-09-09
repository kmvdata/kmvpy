from kmvpy.common.conf import BaseConfig
from kmvpy.common.kmv import kosmos


class AppConfig(BaseConfig):  # pyright: ignore[reportUndefinedVariable]
    pass


def get_app_config() -> AppConfig:
    """
    获取应用配置对象

    返回:
        AppConfig 配置对象，如果未设置则抛出异常
    """
    _app_config = getattr(kosmos, "config", None)
    if not _app_config:
        raise RuntimeError("未设置应用配置对象")
    return _app_config
