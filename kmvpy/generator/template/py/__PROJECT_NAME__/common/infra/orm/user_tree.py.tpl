# coding: utf-8

from kmvpy.common.infra.korm_base import KOrmBase
from sqlalchemy import Column, DateTime, Integer, String, func

from . import BIGINT_TYPE, AUTO_INCREMENT_PK_TYPE


class UserTree(KOrmBase):
    """
    用户推广关系表，记录用户上下级推广链路。
    kid与user_base表保持一致，p1_kid为直推人，p2_kid为间接推荐人，以此类推。
    """
    __tablename__ = 'user_tree'
    __table_args__ = {"sqlite_autoincrement": True}

    id = Column(AUTO_INCREMENT_PK_TYPE, primary_key=True, index=True,
                autoincrement=True, comment='自增主键ID')
    kid = Column(BIGINT_TYPE, nullable=False,
                 unique=True, comment='当前用户kid，与user_base表保持一致')
    invitation_code = Column(String(16), unique=True,
                             nullable=True, comment='邀请码')
    p1_kid = Column(BIGINT_TYPE, nullable=True, index=True,
                    comment='直推人kid（直接推广该用户的用户kid）')
    p2_kid = Column(BIGINT_TYPE, nullable=True, index=True,
                    comment='间接推荐人kid（推广直推人的用户kid）')
    p3_kid = Column(BIGINT_TYPE, nullable=True, index=True,
                    comment='三级推荐人kid')
    p4_kid = Column(BIGINT_TYPE, nullable=True, index=True,
                    comment='四级推荐人kid')
    p5_kid = Column(BIGINT_TYPE, nullable=True, index=True,
                    comment='五级推荐人kid')
    p6_kid = Column(BIGINT_TYPE, nullable=True, index=True,
                    comment='六级推荐人kid')
    p7_kid = Column(BIGINT_TYPE, nullable=True, index=True,
                    comment='七级推荐人kid')
    p8_kid = Column(BIGINT_TYPE, nullable=True, index=True,
                    comment='八级推荐人kid')
    p9_kid = Column(BIGINT_TYPE, nullable=True, index=True,
                    comment='九级推荐人kid')
    delete_at = Column(DateTime, nullable=True, index=True,
                       comment='删除用户时间（软删除）')
    create_time = Column(DateTime, nullable=False, index=True,
                         server_default=func.now(), comment='创建时间')
    update_time = Column(
        DateTime,
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
        comment='更新时间',
    )
