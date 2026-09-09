# coding: utf-8
"""管理端系统维护 DTO。"""

from typing import Optional

from pydantic import BaseModel, Field


class AdminServiceRestartReq(BaseModel):
    confirm_text: str = Field(
        min_length=1,
        max_length=64,
        description="重启服务的二次确认文本",
    )


class AdminServiceRestartRes(BaseModel):
    accepted: bool = Field(description="是否已接受重启请求")
    restart_pid: Optional[int] = Field(default=None, description="重启脚本进程 PID")
