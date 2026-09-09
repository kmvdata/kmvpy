from datetime import datetime
from typing import Any, cast

from kmvpy.common.exception.kmv_exception import KmvException
from kmvpy.common.tool.logger import logger
from kmvpy.core.main.service.jwt_service import JwtUserInfo
from sqlalchemy.exc import IntegrityError

from __PROJECT_NAME__.common.infra.storage.default_storage import DefaultStorage
from __PROJECT_NAME__.common.dto.user.work_ticket import (
    UserWorkTicketCreateReq,
    UserWorkTicketDetailReq,
    UserWorkTicketDetailRes,
    UserWorkTicketListItemRes,
    UserWorkTicketListReq,
    UserWorkTicketListRes,
    UserWorkTicketMessageItemRes,
    UserWorkTicketReplyReq,
)
from __PROJECT_NAME__.common.infra.orm.work_ticket import WorkTicket
from __PROJECT_NAME__.common.infra.orm.work_ticket_message import WorkTicketMessage
from __PROJECT_NAME__.core.main.hub.work_ticket import WorkTicketHub
from __PROJECT_NAME__.core.main.service.work_ticket_notification import notify_admin_ticket_changed
from __PROJECT_NAME__.common.exception import work_ticket_errors as work_ticket_exc


class UserWorkTicketService:
    """用户端工单：创建、我的列表、详情、回复。"""

    @staticmethod
    def _ownership_filters(
        *,
        user_kid: int,
        status: int | None,
    ) -> tuple[Any, ...]:
        conds: list[Any] = [
            WorkTicket.delete_at.is_(None),
            WorkTicket.creator_user_kid == user_kid,
        ]
        if status is not None:
            conds.append(WorkTicket.status == status)
        return tuple(conds)

    @staticmethod
    async def _get_owned_ticket_or_raise(
        *,
        ticket_kid: int,
        user_kid: int,
        session: Any | None = None,
    ) -> WorkTicket:
        db = DefaultStorage.instance()
        ticket = await db.get_by_condition(
            WorkTicket,
            kid=ticket_kid,
            session=session,
        )
        if ticket is None:
            raise KmvException(error=work_ticket_exc.TICKET_NOT_FOUND_ERROR)
        WorkTicketHub.ensure_user_can_access_ticket(
            creator_user_kid=cast(Any, ticket).creator_user_kid,
            current_user_kid=user_kid,
            is_deleted=cast(Any, ticket).delete_at is not None,
        )
        return ticket

    @staticmethod
    async def create_ticket(
        req: UserWorkTicketCreateReq,
        user_info: JwtUserInfo,
    ) -> UserWorkTicketDetailRes:
        db = DefaultStorage.instance()
        now = datetime.now()
        ticket_kid = WorkTicket.gen_kid()
        uid = int(user_info.kid)
        title = WorkTicketHub.normalize_title(req.title)
        body = WorkTicketHub.normalize_body(req.body)
        cat = WorkTicketHub.normalize_category(req.category)

        async with db.session_scope() as session:
            ticket = WorkTicket(
                kid=ticket_kid,
                creator_user_kid=uid,
                title=title,
                category=cat,
                status=WorkTicketHub.STATUS_PENDING,
                last_message_time=now,
            )
            session.add(ticket)
            msg = WorkTicketMessage(
                kid=WorkTicketMessage.gen_kid(),
                ticket_kid=ticket_kid,
                sender_role=WorkTicketHub.USER_SENDER_ROLE,
                sender_user_kid=uid,
                body=body,
            )
            session.add(msg)
            try:
                await session.flush()
            except IntegrityError as exc:
                logger.warning("用户创建工单写库失败 uid=%s", uid, exc_info=exc)
                raise KmvException(error=work_ticket_exc.TICKET_CREATE_ERROR) from exc

        await notify_admin_ticket_changed(
            admin_kids=WorkTicketHub.admin_notification_targets(
                assigned_admin_kid=None,
            ),
            ticket_kid=ticket_kid,
        )
        return await UserWorkTicketService.get_ticket_detail(
            UserWorkTicketDetailReq(kid=str(ticket_kid)),
            user_info,
        )

    @staticmethod
    async def list_my_tickets(
        req: UserWorkTicketListReq,
        user_info: JwtUserInfo,
    ) -> UserWorkTicketListRes:
        uid = int(user_info.kid)
        db = DefaultStorage.instance()
        result = await db.gets_by_filters(
            WorkTicket,
            UserWorkTicketService._ownership_filters(user_kid=uid, status=req.status),
            page=req.page,
            size=req.size,
            sort=(("last_message_time", "desc"), ("create_time", "desc")),
        )
        if result is None:
            return UserWorkTicketListRes(items=[], total=0)
        rows, total = result
        items = [
            UserWorkTicketListItemRes(
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
        return UserWorkTicketListRes(items=items, total=total)

    @staticmethod
    async def get_ticket_detail(
        req: UserWorkTicketDetailReq,
        user_info: JwtUserInfo,
    ) -> UserWorkTicketDetailRes:
        uid = int(user_info.kid)
        db = DefaultStorage.instance()
        ticket = await UserWorkTicketService._get_owned_ticket_or_raise(
            ticket_kid=int(req.kid),
            user_kid=uid,
        )

        msg_result = await db.gets_by_filters(
            WorkTicketMessage,
            (WorkTicketMessage.ticket_kid == int(req.kid),),
            page=1,
            size=5000,
            sort=(("create_time", "asc"), ("id", "asc")),
        )
        messages: list[UserWorkTicketMessageItemRes] = []
        if msg_result is not None:
            msg_rows, _ = msg_result
            messages = [
                UserWorkTicketMessageItemRes(
                    kid=str(cast(Any, m).kid),
                    sender_role=int(cast(Any, m).sender_role),
                    sender_user_kid=str(cast(Any, m).sender_user_kid),
                    body=cast(Any, m).body,
                    create_time=cast(Any, m).create_time,
                )
                for m in msg_rows
            ]

        t = cast(Any, ticket)
        return UserWorkTicketDetailRes(
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
        req: UserWorkTicketReplyReq,
        user_info: JwtUserInfo,
    ) -> UserWorkTicketDetailRes:
        db = DefaultStorage.instance()
        now = datetime.now()
        uid = int(user_info.kid)
        assigned_admin_kid: int | None = None
        async with db.session_scope() as session:
            ticket = await UserWorkTicketService._get_owned_ticket_or_raise(
                ticket_kid=int(req.ticket_kid),
                user_kid=uid,
                session=session,
            )
            msg = WorkTicketMessage(
                kid=WorkTicketMessage.gen_kid(),
                ticket_kid=int(req.ticket_kid),
                sender_role=WorkTicketHub.USER_SENDER_ROLE,
                sender_user_kid=uid,
                body=WorkTicketHub.normalize_body(req.body),
            )
            session.add(msg)
            cast(Any, ticket).last_message_time = now
            assigned_admin_kid = (
                int(cast(Any, ticket).assigned_admin_kid)
                if cast(Any, ticket).assigned_admin_kid is not None
                else None
            )

            try:
                await session.flush()
            except IntegrityError as exc:
                logger.warning(
                    "用户工单回复写库失败 ticket_kid=%s", req.ticket_kid, exc_info=exc
                )
                raise KmvException(error=work_ticket_exc.TICKET_REPLY_ERROR) from exc

        await notify_admin_ticket_changed(
            admin_kids=WorkTicketHub.admin_notification_targets(
                assigned_admin_kid=assigned_admin_kid,
            ),
            ticket_kid=int(req.ticket_kid),
        )
        return await UserWorkTicketService.get_ticket_detail(
            UserWorkTicketDetailReq(kid=req.ticket_kid),
            user_info,
        )
