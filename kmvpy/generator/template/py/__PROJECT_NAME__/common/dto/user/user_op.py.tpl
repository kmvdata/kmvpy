from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, Field


class EmailCaptchaReq(BaseModel):
    email: str = Field(description="目标邮箱地址，用于接收验证码")
    scene: Literal["register", "login"] = Field(
        default="register",
        description="验证码使用场景：register-邮箱注册；login-邮箱登录辅助校验",
    )


class EmailCaptchaRes(BaseModel):
    email: str = Field(description="已处理的邮箱地址")
    scene: Literal["register", "login"] = Field(description="本次验证码所属业务场景")
    expire_seconds: int = Field(default=300, description="验证码有效期，单位秒")
    sent: bool = Field(description="是否已尝试发送邮件")
    message: str = Field(description="发送结果说明")


class EmailRegisterReq(BaseModel):
    email: str = Field(description="注册邮箱，注册后将作为默认登录账号")
    verify_code: str = Field(description="邮箱验证码，通常为 6 位数字")
    password: str = Field(
        min_length=6,
        max_length=64,
        description="登录密码，明文仅用于本次请求，服务端会加盐哈希后入库",
    )
    nickname: Optional[str] = Field(
        default=None,
        max_length=32,
        description="用户昵称，未传时默认取邮箱前缀",
    )
    invitation_code: Optional[str] = Field(
        default=None,
        max_length=16,
        description="邀请码，默认不传表示非邀请注册",
    )


class EmailLoginReq(BaseModel):
    email: str = Field(description="注册时使用的邮箱地址")
    password: str = Field(
        min_length=6,
        max_length=64,
        description="登录密码，服务端会使用同样的加盐规则进行校验",
    )


class UsernameLoginReq(BaseModel):
    """用户端使用用户名与密码登录（仅匹配 `user_base.username`，不按邮箱解析）。"""

    username: str = Field(
        min_length=1,
        max_length=64,
        description="登录用户名，服务端会 trim 并转小写后查询",
    )
    password: str = Field(
        min_length=6,
        max_length=64,
        description="登录密码，服务端会使用同样的加盐规则进行校验",
    )


class PhoneLoginReq(BaseModel):
    """用户端使用手机号与密码登录（仅匹配 `user_base.phone`）。"""

    phone: str = Field(
        min_length=1,
        max_length=20,
        description="登录手机号，服务端会 trim 并按手机号格式校验后查询",
    )
    password: str = Field(
        min_length=6,
        max_length=64,
        description="登录密码，服务端会使用同样的加盐规则进行校验",
    )


class AccountLoginReq(BaseModel):
    """用户端统一账号登录：邮箱 / 手机号 / 用户名，服务端按格式自动识别类型。"""

    account: str = Field(
        min_length=1,
        max_length=128,
        description="登录账号：邮箱、手机号或用户名，服务端按格式自动识别",
    )
    password: str = Field(
        min_length=6,
        max_length=64,
        description="登录密码，服务端会使用同样的加盐规则进行校验",
    )


class UpdateUserProfileReq(BaseModel):
    nickname: Optional[str] = Field(
        default=None,
        max_length=32,
        description="用户昵称；传 None 表示不修改，传空字符串表示清空",
    )
    signature: Optional[str] = Field(
        default=None,
        max_length=128,
        description="个性签名；传 None 表示不修改，传空字符串表示清空",
    )
    phone: Optional[str] = Field(
        default=None,
        max_length=20,
        description="手机号，对应 user_base.phone；传 None 表示不修改，传空字符串表示清空",
    )


class UserProfileRes(BaseModel):
    kid: str = Field(description="用户全局唯一 kid，使用字符串避免前端精度丢失")
    user_type: int = Field(
        default=0,
        description="用户类型：0-普通用户；100-管理员；2-审核员（与 user_base.user_type 一致）",
    )
    state: Optional[int] = Field(default=None, description="用户状态：0-不可用；1-可用")
    country_code: Optional[str] = Field(default=None, description="手机国际区号")
    phone: Optional[str] = Field(default=None, description="手机号")
    email: Optional[str] = Field(default=None, description="用户邮箱")
    username: Optional[str] = Field(default=None, description="登录用户名")
    nickname: Optional[str] = Field(default=None, description="用户昵称")
    signature: Optional[str] = Field(default=None, description="个性签名")
    avatar_uri: Optional[str] = Field(default=None, description="头像地址")
    delete_at: Optional[datetime] = Field(default=None, description="软删除时间")
    gender: Optional[int] = Field(default=None, description="性别：0-女；1-男")
    ip: Optional[str] = Field(default=None, description="注册 IP 地址")
    deviceid: Optional[str] = Field(default=None, description="设备唯一标识符")
    balance_power: Optional[int] = Field(default=None, description="算力余额")
    create_time: Optional[datetime] = Field(default=None, description="账号创建时间")
    update_time: Optional[datetime] = Field(default=None, description="更新时间")
    comment: Optional[str] = Field(default=None, description="备注")


class EmailAuthRes(BaseModel):
    token: str = Field(description="登录成功后签发的 JWT token")
    token_type: str = Field(default="Bearer", description="认证头类型")
    expire_hours: float = Field(description="access token 有效时长，单位小时，支持小数")
    expires_at: int = Field(description="access token 过期时间，Unix 时间戳（秒）")
    sid: str = Field(description="登录 session id，用于服务端会话关联")
    is_new_user: bool = Field(description="是否为本次注册新创建的账号")
    user: UserProfileRes = Field(description="当前登录用户信息")
    session_cookie_value: str = Field(default="", exclude=True)
    session_cookie_max_age: int = Field(default=0, exclude=True)
