import os
import sys

import uvicorn

from kmvpy.common.kmv import kosmos
from kmvpy.common.tool.logger import logger

from __PROJECT_NAME__.core.main import gen_asgi_app


def create_app():
    """
    供 uvicorn 在 reload/workers 模式下通过 import string 加载的工厂函数。

    约定：配置路径从环境变量 __CONFIG_ENV_VAR__ 读取。
    """
    return gen_asgi_app(os.getenv("__CONFIG_ENV_VAR__"))


def main():
    """
    安装develop数据库依赖：
        pip install sqlalchemy aiosqlite
    启动服务：
        PYTHONPATH=. python app/run.py
    """
    default_config = os.path.join(os.path.dirname(__file__), "etc", "develop", "config.yaml")
    if len(sys.argv) > 1:
        config_path = sys.argv[1]
    elif os.getenv("__CONFIG_ENV_VAR__"):
        config_path = os.getenv("__CONFIG_ENV_VAR__") or default_config
    else:
        config_path = default_config

    os.environ["__CONFIG_ENV_VAR__"] = config_path

    app = gen_asgi_app(config_path)
    if kosmos.config.service is None:
        logger.info("service config not set")
        raise SystemExit(0)

    logger.info(f"准备启动服务：{kosmos.config.service}")

    use_import_string = kosmos.config.service.reload or (
        kosmos.config.service.workers and kosmos.config.service.workers > 1
    )
    if use_import_string:
        uvicorn.run(
            "app.run:create_app",
            host=kosmos.config.service.host,
            port=kosmos.config.service.port,
            workers=kosmos.config.service.workers or 1,
            reload=kosmos.config.service.reload,
            factory=True,
        )
    else:
        uvicorn.run(
            app=app,
            host=kosmos.config.service.host,
            port=kosmos.config.service.port,
            workers=kosmos.config.service.workers or 1,
            reload=False,
        )


if __name__ == "__main__":
    main()
