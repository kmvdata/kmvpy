from kmvpy.common.exception.kmv_exception import KmvException

from __PROJECT_NAME__.common.exception import work_ticket_errors as work_ticket_exc


class WorkTicketHub:
    """工单Hub规则；只处理权限、状态和值规范化。"""

    STATUS_PENDING = 0
    USER_SENDER_ROLE = 0
    ADMIN_SENDER_ROLE = 1

    @staticmethod
    def normalize_title(title: str) -> str:
        return title.strip()

    @staticmethod
    def normalize_category(category: str | None) -> str | None:
        normalized = (category or "").strip()
        return normalized or None

    @staticmethod
    def normalize_body(body: str) -> str:
        return body.strip()

    @staticmethod
    def ensure_user_can_access_ticket(
        *,
        creator_user_kid: int,
        current_user_kid: int,
        is_deleted: bool,
    ) -> None:
        if is_deleted or int(creator_user_kid) != int(current_user_kid):
            raise KmvException(error=work_ticket_exc.TICKET_NOT_FOUND_ERROR)

    @staticmethod
    def ensure_admin_can_access_ticket(*, is_deleted: bool) -> None:
        if is_deleted:
            raise KmvException(error=work_ticket_exc.TICKET_NOT_FOUND_ERROR)

    @staticmethod
    def should_assign_admin(assigned_admin_kid: int | None) -> bool:
        return assigned_admin_kid is None

    @staticmethod
    def admin_notification_targets(
        *,
        assigned_admin_kid: int | None,
        acting_admin_kid: int | None = None,
    ) -> tuple[int, ...]:
        """返回应收到工单详情刷新信号的相关管理员，保持顺序并去重。"""
        targets: list[int] = []
        for admin_kid in (assigned_admin_kid, acting_admin_kid):
            if admin_kid is None:
                continue
            normalized_kid = int(admin_kid)
            if normalized_kid not in targets:
                targets.append(normalized_kid)
        return tuple(targets)
