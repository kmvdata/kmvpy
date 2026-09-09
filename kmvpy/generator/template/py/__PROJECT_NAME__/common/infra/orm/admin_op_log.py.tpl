# coding: utf-8
"""管理员操作审计日志表：记录受装饰器标记的管理员接口的入参、返回与结果摘要。"""

from kmvpy.common.infra.korm_base import KOrmBase
from sqlalchemy import Boolean, Column, DateTime, Integer, String, Text, func, true

from . import BIGINT_TYPE, AUTO_INCREMENT_PK_TYPE


class AdminOperationLog(KOrmBase):
    """
    管理员操作记录。

    典型写入路径：`__PROJECT_NAME__.common.dependencies.admin_op_log` 中的 ``@admin_op_log`` 装饰器。
    """

    __tablename__ = "admin_operation_log"
    __table_args__ = {"sqlite_autoincrement": True}

    id = Column(
        AUTO_INCREMENT_PK_TYPE,
        primary_key=True,
        index=True,
        autoincrement=True,
        comment="自增主键ID",
    )
    kid = Column(BIGINT_TYPE, nullable=False, unique=True, comment="表全局唯一kid")
    admin_kid = Column(
        BIGINT_TYPE,
        nullable=True,
        index=True,
        comment="操作者用户 kid，未鉴权时可为空(如登录前)",
    )
    action = Column(
        String(128),
        nullable=False,
        index=True,
        comment="路由处理函数名，如 api_update_user_state",
    )
    method = Column(String(16), nullable=False, comment="HTTP 方法，如 POST")
    path = Column(String(512), nullable=False, index=True, comment="请求路径(不含 host)")
    request_params = Column(
        Text,
        nullable=True,
        comment="入参 JSON（已脱敏），不含 Request 对象本身",
    )
    response_body = Column(
        Text,
        nullable=True,
        comment="返回体 JSON 摘要，超长截断；异常时可能为空",
    )
    success = Column(
        Boolean,
        nullable=False,
        server_default=true(),
        index=True,
        comment="是否成功",
    )
    error_message = Column(
        String(2000), nullable=True, comment="失败时的错误信息(截断)"
    )
    duration_ms = Column(Integer, nullable=True, comment="处理耗时(毫秒，近似)")
    client_ip = Column(String(64), nullable=True, comment="客户端 IP(若有)")
    user_agent = Column(
        String(512), nullable=True, comment="User-Agent(截断,若有)"
    )
    create_time = Column(
        DateTime,
        nullable=False,
        index=True,
        server_default=func.now(),
        comment="记录时间",
    )
    update_time = Column(
        DateTime,
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
        comment="更新时间",
    )
