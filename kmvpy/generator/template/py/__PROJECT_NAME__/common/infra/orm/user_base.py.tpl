# coding: utf-8
import copy
import uuid

from kmvpy.common.infra.korm_base import KOrmBase
from sqlalchemy import Column, DateTime, Integer, SmallInteger, String, func, text

from . import BIGINT_TYPE, AUTO_INCREMENT_PK_TYPE


class UserBase(KOrmBase):
    """
    用户基础信息表，存储用户账号、个人信息、实名认证、地理位置等基础数据。
    kid为全局唯一标识，与user_tree等关联表保持一致。
    """
    __tablename__ = 'user_base'
    __table_args__ = {"sqlite_autoincrement": True}

    id = Column(AUTO_INCREMENT_PK_TYPE, primary_key=True, index=True,
                autoincrement=True, comment='自增主键ID')
    kid = Column(BIGINT_TYPE, nullable=False,
                 unique=True, comment='表全局唯一kid')
    username = Column(String(64), nullable=True,
                      unique=True, comment='用户名，可用于登录账户')
    user_type = Column(Integer, nullable=False,
                       server_default=text("'0'"), comment='用户类型：0-普通用户；100-管理员')
    state = Column(Integer, nullable=False,
                   comment='用户状态：0-不可用；1-可用')
    country_code = Column(String(8), nullable=True,
                          server_default=text("'+86'"), comment='手机国际区号')
    phone = Column(String(20), nullable=True, unique=True, comment='手机号')
    nickname = Column(String(32), nullable=True, comment='用户昵称')
    email = Column(String(64), nullable=True, unique=True, comment='邮箱地址')
    avatar_uri = Column(String(255), nullable=True, comment='用户头像地址')
    salt = Column(String(64), nullable=False, comment='密码盐值，用于加密')
    password = Column(String(64), nullable=False, comment='加密后的用户密码')
    delete_at = Column(DateTime, nullable=True, comment='软删除时间（删除时记录）')
    gender = Column(SmallInteger, nullable=True, comment='性别：0-女；1-男')
    ip = Column(String(32), nullable=True, comment='注册IP地址')
    signature = Column(String(128), nullable=True, comment='个性签名')
    deviceid = Column(String(255), nullable=True, comment='设备唯一标识符')
    balance_power = Column(Integer, nullable=False, server_default=text(
        "'0'"), index=True, comment='算力余额（单位：TOKEN）')
    create_time = Column(DateTime, nullable=False, index=True,
                         server_default=func.now(), comment='创建时间')
    update_time = Column(
        DateTime,
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
        comment='更新时间',
    )
    comment = Column(String(64), nullable=True, comment='备注')

    def token(self, software: str) -> str:
        """
        生成用户登录凭据token
        格式：user_kid:software:uuid
        :param software: 软件标识
        :return: 登录token字符串
        """
        return '%s:%s:%s' % (self.kid, software, uuid.uuid1().__str__().replace('-', ''))

    def masking(self):
        # 直接修改self会导致"SQL Alchemy NULL identity key"错误
        cls = copy.copy(self)
        cls.id = None
        cls.password = None
        cls.salt = None
        cls.create_time = None
        cls.update_time = None
        return cls
