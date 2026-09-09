# coding: utf-8
"""用户 Socket 离线消息表：用户不在线时暂存待推送的 API 通知。"""

from kmvpy.common.infra.korm_base import KOrmBase
from sqlalchemy import Column, DateTime, String, func

from . import BIGINT_TYPE, AUTO_INCREMENT_PK_TYPE


class UserSocketMessage(KOrmBase):
    """
    固定格式的用户端 socket 通知；发送成功后由 service 删除对应记录。
    """

    __tablename__ = "user_socket_message"
    __table_args__ = {"sqlite_autoincrement": True}

    id = Column(
        AUTO_INCREMENT_PK_TYPE,
        primary_key=True,
        index=True,
        autoincrement=True,
        comment="自增主键ID",
    )
    kid = Column(BIGINT_TYPE, nullable=False, unique=True, comment="表全局唯一kid")
    user_kid = Column(
        BIGINT_TYPE,
        nullable=False,
        index=True,
        comment="接收消息的 user_base.kid",
    )
    api_uri = Column(
        String(255),
        nullable=False,
        comment="客户端收到消息后需要立即调用的 API URI",
    )
    kid_for_api = Column(
        BIGINT_TYPE,
        nullable=True,
        index=True,
        comment="调用 API 时可选携带的业务 kid",
    )
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
