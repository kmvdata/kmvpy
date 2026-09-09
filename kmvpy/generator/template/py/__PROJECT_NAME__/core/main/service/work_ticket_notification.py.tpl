from kmvpy.common.tool.logger import logger

from __PROJECT_NAME__.core.main.service.admin.socket import AdminSocketService
from __PROJECT_NAME__.core.main.service.user.socket import UserSocketService

USER_WORK_TICKET_DETAIL_API_URI = "/api/user/work_ticket/detail"
ADMIN_WORK_TICKET_DETAIL_API_URI = "/api/admin/work_ticket/detail"


async def notify_user_ticket_changed(*, user_kid: int, ticket_kid: int) -> None:
    """通知普通用户端刷新指定工单详情。"""
    try:
        await UserSocketService.send_socket_message(
            user_kid,
            USER_WORK_TICKET_DETAIL_API_URI,
            ticket_kid,
        )
    except Exception as exc:
        logger.warning(
            "工单用户端 socket 通知失败 user_kid=%s ticket_kid=%s",
            user_kid,
            ticket_kid,
            exc_info=exc,
        )


async def notify_admin_ticket_changed(
    *,
    admin_kids: tuple[int, ...],
    ticket_kid: int,
) -> None:
    """通知相关在线管理员刷新指定工单详情。"""
    try:
        await AdminSocketService.send_socket_message(
            admin_kids,
            ADMIN_WORK_TICKET_DETAIL_API_URI,
            ticket_kid,
        )
    except Exception as exc:
        logger.warning(
            "工单管理端 socket 通知失败 admin_kids=%s ticket_kid=%s",
            admin_kids,
            ticket_kid,
            exc_info=exc,
        )
