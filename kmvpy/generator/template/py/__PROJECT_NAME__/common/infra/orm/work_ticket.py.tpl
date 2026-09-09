# coding: utf-8
"""工单主表：一条记录对应一个可多次沟通的会话主题。"""

from kmvpy.common.infra.korm_base import KOrmBase
from sqlalchemy import Column, DateTime, SmallInteger, String, func, text

from . import BIGINT_TYPE, AUTO_INCREMENT_PK_TYPE


class WorkTicket(KOrmBase):
    """
    用户发起的工单；管理员在后台浏览、回复，消息明细见 work_ticket_message。
    """

    __tablename__ = "work_ticket"
    __table_args__ = {"sqlite_autoincrement": True}

    id = Column(
        AUTO_INCREMENT_PK_TYPE,
        primary_key=True,
        index=True,
        autoincrement=True,
        comment="自增主键ID",
    )
    kid = Column(BIGINT_TYPE, nullable=False, unique=True, comment="表全局唯一kid")
    creator_user_kid = Column(
        BIGINT_TYPE,
        nullable=False,
        index=True,
        comment="发起用户 user_base.kid",
    )
    title = Column(String(255), nullable=False, comment="工单标题/主题")
    category = Column(
        String(64),
        nullable=True,
        index=True,
        comment="业务分类代号，可选",
    )
    status = Column(
        SmallInteger,
        nullable=False,
        server_default=text("'0'"),
        index=True,
        comment="0-待处理 1-处理中 2-待用户反馈 3-已解决 4-已关闭",
    )
    last_message_time = Column(
        DateTime,
        nullable=True,
        index=True,
        comment="最后一条消息时间，用于列表排序",
    )
    assigned_admin_kid = Column(
        BIGINT_TYPE,
        nullable=True,
        index=True,
        comment="当前跟进管理员 user_base.kid，可空",
    )
    delete_at = Column(DateTime, nullable=True, index=True, comment="软删除时间")
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
