# coding: utf-8
"""工单会话消息表：同一 ticket_kid 下按时间顺序组成对话上下文。"""

from kmvpy.common.infra.korm_base import KOrmBase
from sqlalchemy import Column, DateTime, SmallInteger, Text, func, text

from . import BIGINT_TYPE, AUTO_INCREMENT_PK_TYPE


class WorkTicketMessage(KOrmBase):
    """
    工单的一条回复或用户补充；sender_role 区分用户端与管理员端。
    """

    __tablename__ = "work_ticket_message"
    __table_args__ = {"sqlite_autoincrement": True}

    id = Column(
        AUTO_INCREMENT_PK_TYPE,
        primary_key=True,
        index=True,
        autoincrement=True,
        comment="自增主键ID",
    )
    kid = Column(BIGINT_TYPE, nullable=False, unique=True, comment="表全局唯一kid")
    ticket_kid = Column(
        BIGINT_TYPE,
        nullable=False,
        index=True,
        comment="所属工单 work_ticket.kid",
    )
    sender_role = Column(
        SmallInteger,
        nullable=False,
        server_default=text("'0'"),
        index=True,
        comment="0-用户 1-管理员",
    )
    sender_user_kid = Column(
        BIGINT_TYPE,
        nullable=False,
        index=True,
        comment="发送方 user_base.kid（含管理员账号）",
    )
    body = Column(Text, nullable=False, comment="消息正文")
    create_time = Column(
        DateTime,
        nullable=False,
        index=True,
        server_default=func.now(),
        comment="创建时间",
    )
    update_time = Column(
        DateTime,
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
        comment="更新时间",
    )
