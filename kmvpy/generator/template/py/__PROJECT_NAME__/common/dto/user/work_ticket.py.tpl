from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, Field


class UserWorkTicketCreateReq(BaseModel):
    title: str = Field(min_length=1, max_length=255, description="工单标题")
    category: Optional[str] = Field(
        default=None,
        max_length=64,
        description="可选分类",
    )
    body: str = Field(
        min_length=1,
        max_length=20000,
        description="首条问题描述",
    )


class UserWorkTicketListReq(BaseModel):
    page: int = Field(default=1, ge=1, description="页码，从 1 开始")
    size: int = Field(default=20, ge=1, le=500, description="每页条数")
    status: Optional[Literal[0, 1, 2, 3, 4]] = Field(
        default=None,
        description="按状态筛选；不传表示不限",
    )


class UserWorkTicketListItemRes(BaseModel):
    kid: str = Field(description="工单 kid")
    creator_user_kid: str = Field(description="发起用户 kid")
    title: str = Field(description="标题")
    category: Optional[str] = Field(default=None, description="分类")
    status: int = Field(description="状态：0-待处理 1-处理中 2-待用户反馈 3-已解决 4-已关闭")
    last_message_time: Optional[datetime] = Field(
        default=None, description="最后消息时间"
    )
    assigned_admin_kid: Optional[str] = Field(default=None, description="跟进管理员 kid")
    create_time: Optional[datetime] = Field(default=None, description="创建时间")


class UserWorkTicketListRes(BaseModel):
    items: list[UserWorkTicketListItemRes] = Field(description="工单列表")
    total: int = Field(description="总条数")


class UserWorkTicketDetailReq(BaseModel):
    kid: str = Field(description="工单 kid")


class UserWorkTicketMessageItemRes(BaseModel):
    kid: str = Field(description="消息 kid")
    sender_role: int = Field(description="0-用户 1-管理员")
    sender_user_kid: str = Field(description="发送者 user kid")
    body: str = Field(description="正文")
    create_time: Optional[datetime] = Field(default=None, description="创建时间")


class UserWorkTicketDetailRes(BaseModel):
    kid: str = Field(description="工单 kid")
    creator_user_kid: str = Field(description="发起用户 kid")
    title: str = Field(description="标题")
    category: Optional[str] = Field(default=None, description="分类")
    status: int = Field(description="状态")
    last_message_time: Optional[datetime] = Field(
        default=None, description="最后消息时间"
    )
    assigned_admin_kid: Optional[str] = Field(default=None, description="跟进管理员 kid")
    create_time: Optional[datetime] = Field(default=None, description="创建时间")
    messages: list[UserWorkTicketMessageItemRes] = Field(
        description="按时间升序的对话消息"
    )


class UserWorkTicketReplyReq(BaseModel):
    ticket_kid: str = Field(description="工单 kid")
    body: str = Field(
        min_length=1,
        max_length=20000,
        description="回复正文",
    )
