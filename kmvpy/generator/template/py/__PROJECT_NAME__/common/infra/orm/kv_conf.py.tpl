# coding: utf-8

from kmvpy.common.infra.korm_base import KOrmBase
from sqlalchemy import Column, DateTime, String, func

from . import BIGINT_TYPE, AUTO_INCREMENT_PK_TYPE


class KvConf(KOrmBase):
    __tablename__ = "kv_conf"
    __table_args__ = {"sqlite_autoincrement": True}

    # SQLite 需要 INTEGER PRIMARY KEY 才能稳定自增，MySQL/PostgreSQL 则由 SQLAlchemy 自动适配。
    id = Column(
        AUTO_INCREMENT_PK_TYPE,
        primary_key=True,
        index=True,
        autoincrement=True,
        comment="自增主键ID",
    )
    kid = Column(BIGINT_TYPE, nullable=False, unique=True, comment="表全局唯一kid")
    key = Column(String(64), nullable=False, unique=True, comment="键")
    value = Column(String(255), nullable=False, comment="值")
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
