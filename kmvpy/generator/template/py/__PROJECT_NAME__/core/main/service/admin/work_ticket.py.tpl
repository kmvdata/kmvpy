from datetime import datetime
from typing import Any, cast

from kmvpy.common.exception.kmv_exception import KmvException
from kmvpy.common.tool.logger import logger
from kmvpy.core.main.service.jwt_service import JwtUserInfo
from sqlalchemy.exc import IntegrityError

from __PROJECT_NAME__.common.infra.storage.default_storage import DefaultStorage
from __PROJECT_NAME__.common.dto.admin.work_ticket import (
    AdminWorkTicketDetailReq,
    AdminWorkTicketDetailRes,
    AdminWorkTicketListItemRes,
    AdminWorkTicketListReq,
    AdminWorkTicketListRes,
    AdminWorkTicketMessageItemRes,
    AdminWorkTicketReplyReq,
    AdminWorkTicketUpdateStatusReq,
)
from __PROJECT_NAME__.common.infra.orm.work_ticket import WorkTicket
from __PROJECT_NAME__.common.infra.orm.work_ticket_message import WorkTicketMessage
from __PROJECT_NAME__.core.main.hub.work_ticket import WorkTicketHub
from __PROJECT_NAME__.core.main.service.work_ticket_notification import (
    notify_admin_ticket_changed,
    notify_user_ticket_changed,
)
from __PROJECT_NAME__.common.exception import work_ticket_errors as work_ticket_exc


class AdminWorkTicketService:
    """管理端工单：列表、详情（含会话）、回复、状态更新。"""

    @staticmethod
    def _ticket_filters(
        *,
        status: int | None,
    ) -> tuple[Any, ...]:
        conds: list[Any] = [WorkTicket.delete_at.is_(None)]
        if status is not None:
            conds.append(WorkTicket.status == status)
        return tuple(conds)

    @staticmethod
    async def list_tickets(req: AdminWorkTicketListReq) -> AdminWorkTicketListRes:
        db = DefaultStorage.instance()
        result = await db.gets_by_filters(
            WorkTicket,
            AdminWorkTicketService._ticket_filters(status=req.status),
            page=req.page,
            size=req.size,
            sort=(("last_message_time", "desc"), ("create_time", "desc")),
        )
        if result is None:
            return AdminWorkTicketListRes(items=[], total=0)
        rows, total = result
        items = [
            AdminWorkTicketListItemRes(
                kid=str(cast(Any, row).kid),
                creator_user_kid=str(cast(Any, row).creator_user_kid),
                title=cast(Any, row).title,
                category=cast(Any, row).category,
                status=int(cast(Any, row).status),
                last_message_time=cast(Any, row).last_message_time,
                assigned_admin_kid=(
                    str(cast(Any, row).assigned_admin_kid)
                    if cast(Any, row).assigned_admin_kid is not None
                    else None
                ),
                create_time=cast(Any, row).create_time,
            )
            for row in rows
        ]
        return AdminWorkTicketListRes(items=items, total=total)

    @staticmethod
    async def get_ticket_detail(req: AdminWorkTicketDetailReq) -> AdminWorkTicketDetailRes:
        db = DefaultStorage.instance()
        ticket = await db.get_by_condition(
            WorkTicket,
            kid=int(req.kid),
        )
        if ticket is None:
            raise KmvException(error=work_ticket_exc.TICKET_NOT_FOUND_ERROR)
        WorkTicketHub.ensure_admin_can_access_ticket(
            is_deleted=cast(Any, ticket).delete_at is not None,
        )

        msg_result = await db.gets_by_filters(
            WorkTicketMessage,
            (WorkTicketMessage.ticket_kid == int(req.kid),),
            page=1,
            size=5000,
            sort=(("create_time", "asc"), ("id", "asc")),
        )
        messages: list[AdminWorkTicketMessageItemRes] = []
        if msg_result is not None:
            msg_rows, _ = msg_result
            messages = [
                AdminWorkTicketMessageItemRes(
                    kid=str(cast(Any, m).kid),
                    sender_role=int(cast(Any, m).sender_role),
                    sender_user_kid=str(cast(Any, m).sender_user_kid),
                    body=cast(Any, m).body,
                    create_time=cast(Any, m).create_time,
                )
                for m in msg_rows
            ]

        t = cast(Any, ticket)
        return AdminWorkTicketDetailRes(
            kid=str(t.kid),
            creator_user_kid=str(t.creator_user_kid),
            title=t.title,
            category=t.category,
            status=int(t.status),
            last_message_time=t.last_message_time,
            assigned_admin_kid=(
                str(t.assigned_admin_kid) if t.assigned_admin_kid is not None else None
            ),
            create_time=t.create_time,
            messages=messages,
        )

    @staticmethod
    async def reply_ticket(
        req: AdminWorkTicketReplyReq,
        admin_info: JwtUserInfo,
    ) -> AdminWorkTicketDetailRes:
        db = DefaultStorage.instance()
        now = datetime.now()
        ticket_kid = int(req.ticket_kid)
        creator_user_kid: int | None = None
        assigned_admin_kid: int | None = None
        async with db.session_scope() as session:
            ticket = await db.get_by_condition(
                WorkTicket,
                kid=ticket_kid,
                session=session,
            )
            if ticket is None:
                raise KmvException(error=work_ticket_exc.TICKET_NOT_FOUND_ERROR)
            WorkTicketHub.ensure_admin_can_access_ticket(
                is_deleted=cast(Any, ticket).delete_at is not None,
            )

            creator_user_kid = int(cast(Any, ticket).creator_user_kid)
            msg = WorkTicketMessage(
                kid=WorkTicketMessage.gen_kid(),
                ticket_kid=ticket_kid,
                sender_role=WorkTicketHub.ADMIN_SENDER_ROLE,
                sender_user_kid=int(admin_info.kid),
                body=WorkTicketHub.normalize_body(req.body),
            )
            session.add(msg)

            cast(Any, ticket).last_message_time = now
            if req.status is not None:
                cast(Any, ticket).status = int(req.status)
            if WorkTicketHub.should_assign_admin(cast(Any, ticket).assigned_admin_kid):
                cast(Any, ticket).assigned_admin_kid = int(admin_info.kid)
            assigned_admin_kid = int(cast(Any, ticket).assigned_admin_kid)

            try:
                await session.flush()
            except IntegrityError as exc:
                logger.warning(
                    "工单回复写库失败 ticket_kid=%s", req.ticket_kid, exc_info=exc
                )
                raise KmvException(error=work_ticket_exc.TICKET_REPLY_ERROR) from exc

        if creator_user_kid is not None:
            await notify_user_ticket_changed(
                user_kid=creator_user_kid,
                ticket_kid=ticket_kid,
            )
        await notify_admin_ticket_changed(
            admin_kids=WorkTicketHub.admin_notification_targets(
                assigned_admin_kid=assigned_admin_kid,
                acting_admin_kid=int(admin_info.kid),
            ),
            ticket_kid=ticket_kid,
        )

        return await AdminWorkTicketService.get_ticket_detail(
            AdminWorkTicketDetailReq(kid=req.ticket_kid)
        )

    @staticmethod
    async def update_status(
        req: AdminWorkTicketUpdateStatusReq,
        admin_info: JwtUserInfo,
    ) -> AdminWorkTicketDetailRes:
        db = DefaultStorage.instance()
        assigned_admin_kid: int | None = None
        async with db.session_scope() as session:
            ticket = await db.get_by_condition(
                WorkTicket,
                kid=int(req.ticket_kid),
                session=session,
            )
            if ticket is None:
                raise KmvException(error=work_ticket_exc.TICKET_NOT_FOUND_ERROR)
            WorkTicketHub.ensure_admin_can_access_ticket(
                is_deleted=cast(Any, ticket).delete_at is not None,
            )

            cast(Any, ticket).status = int(req.status)
            assigned_admin_kid = (
                int(cast(Any, ticket).assigned_admin_kid)
                if cast(Any, ticket).assigned_admin_kid is not None
                else None
            )

            try:
                await session.flush()
            except IntegrityError as exc:
                logger.warning(
                    "工单状态更新写库失败 ticket_kid=%s",
                    req.ticket_kid,
                    exc_info=exc,
                )
                raise KmvException(
                    error=work_ticket_exc.TICKET_STATUS_ERROR
                ) from exc

        await notify_admin_ticket_changed(
            admin_kids=WorkTicketHub.admin_notification_targets(
                assigned_admin_kid=assigned_admin_kid,
                acting_admin_kid=int(admin_info.kid),
            ),
            ticket_kid=int(req.ticket_kid),
        )
        return await AdminWorkTicketService.get_ticket_detail(
            AdminWorkTicketDetailReq(kid=req.ticket_kid)
        )
