import os
import sys

import uvicorn

from kmvpy.common.kmv import kosmos
from kmvpy.common.tool.logger import logger

from __PROJECT_NAME__.core.main import gen_asgi_app


def main():
    default_config = os.path.abspath(
        os.path.join(
            os.path.dirname(__file__), "..", "..", "..", "app", "etc", "release", "config.yaml"
        )
    )
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

    uvicorn.run(
        app=app,
        host=kosmos.config.service.host,
        port=kosmos.config.service.port,
        workers=kosmos.config.service.workers or 1,
        reload=False,
    )


if __name__ == "__main__":
    main()
