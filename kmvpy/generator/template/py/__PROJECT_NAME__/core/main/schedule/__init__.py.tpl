from kmvpy.common.tool.logger import logger


def register_app_schedule_jobs() -> None:
    """统一注册当前应用的所有 schedule 任务。"""

    logger.info("当前应用未注册 __PROJECT_NAME__ schedule 任务")
