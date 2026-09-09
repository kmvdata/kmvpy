from datetime import datetime
from typing import Literal, Optional

from pydantic import AliasChoices, BaseModel, Field


class AdminLoginReq(BaseModel):
    """管理端登录：支持邮箱或用户名（与 user_base 中字段对应）。"""

    account: str = Field(
        ...,
        min_length=1,
        max_length=128,
        validation_alias=AliasChoices("account", "email"),
        description="登录账号：邮箱或用户名",
    )
    password: str = Field(
        min_length=6,
        max_length=64,
        description="登录密码",
    )


class AdminUsernameLoginReq(BaseModel):
    """管理端按用户名登录（仅匹配 user_base.username，不按邮箱解析）。"""

    username: str = Field(
        ...,
        min_length=1,
        max_length=64,
        description="登录用户名，服务端会 trim 并转小写后查询",
    )
    password: str = Field(
        min_length=6,
        max_length=64,
        description="登录密码",
    )


class AdminUserListReq(BaseModel):
    page: int = Field(default=1, ge=1, description="页码，从 1 开始")
    size: int = Field(default=500, ge=1, le=1000, description="每页条数")


class AdminUserListItemRes(BaseModel):
    kid: str = Field(description="用户全局唯一 kid")
    email: Optional[str] = Field(default=None, description="邮箱")
    username: Optional[str] = Field(default=None, description="用户名")
    nickname: Optional[str] = Field(default=None, description="昵称")
    user_type: int = Field(description="用户类型：0-普通用户；1-管理员；2-审核员")
    state: int = Field(description="用户状态：0-不可用；1-可用")
    create_time: Optional[datetime] = Field(default=None, description="创建时间")


class AdminUserListRes(BaseModel):
    items: list[AdminUserListItemRes] = Field(description="用户列表")
    total: int = Field(description="符合条件的总条数")


class AdminCreateReviewerReq(BaseModel):
    email: str = Field(description="审核员邮箱，注册后将作为默认登录账号")
    password: str = Field(min_length=6, max_length=64, description="登录密码")
    nickname: Optional[str] = Field(default=None, max_length=32, description="审核员昵称，未传时默认取邮箱前缀")


class AdminUpdateUserRoleReq(BaseModel):
    kid: str = Field(description="目标用户全局唯一kid")
    user_type: Literal[0, 1, 2] = Field(description="用户类型：0-普通用户；1-管理员；2-审核员")


class AdminUpdateUserStateReq(BaseModel):
    kid: str = Field(description="目标用户全局唯一kid")
    state: Literal[0, 1] = Field(description="用户状态：0-不可用；1-可用")


class AdminCreateUserReq(BaseModel):
    username: str = Field(
        min_length=1,
        max_length=64,
        description="登录用户名，服务端会 trim 并转小写后保存",
    )
    password: str = Field(min_length=6, max_length=64, description="登录密码")
    user_type: Literal[0, 1, 2] = Field(
        description="0-普通用户；1-管理员；2-审核员；入库时管理员将映射为与 JWT/鉴权一致的数据库值",
    )


class AdminResetUserPasswordReq(BaseModel):
    kid: str = Field(description="目标用户 kid")
    password: str = Field(min_length=6, max_length=64, description="新密码")


class AdminDeleteUserReq(BaseModel):
    kid: str = Field(description="要软删除的用户 kid")
