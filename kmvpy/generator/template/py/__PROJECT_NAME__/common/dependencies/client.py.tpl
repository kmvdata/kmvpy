from typing import Annotated

from fastapi import Header, Request
from pydantic import BaseModel, Field


class ClientRequestInfo(BaseModel):
    device_type: str = Field(default="", description="设备类型，如 iOS / Android")
    device_model: str = Field(default="", description="设备型号，如 iPhone 16 Pro / Xiaomi 14")
    os_version: str = Field(default="", description="操作系统版本，如 18.2 / 15")
    app_version: str = Field(default="", description="App 版本号，如 2.5.0")
    device_id: str = Field(default="", description="设备唯一标识")
    network: str = Field(default="", description="网络类型，如 WiFi / 5G")
    brand: str = Field(default="", description="设备品牌，如 Apple / Xiaomi")
    ip: str | None = Field(default=None, description="客户端 IP")
    user_agent: str = Field(default="", description="请求头 User-Agent")


def _extract_request_ip(request: Request) -> str | None:
    """优先读取代理透传 IP，没有时退化为客户端直连地址。"""
    forwarded_for = request.headers.get("X-Forwarded-For", "").strip()
    if forwarded_for:
        return forwarded_for.split(",")[0].strip()
    if request.client is None:
        return None
    return request.client.host


def client_request_info(
    request: Annotated[Request, "客户端请求信息"],
    device_type: Annotated[str | None, Header(alias="X-Device-Type")] = None,
    device_model: Annotated[str | None, Header(alias="X-Device-Model")] = None,
    os_version: Annotated[str | None, Header(alias="X-OS-Version")] = None,
    app_version: Annotated[str | None, Header(alias="X-App-Version")] = None,
    device_id: Annotated[str | None, Header(alias="X-Device-ID")] = None,
    network: Annotated[str | None, Header(alias="X-Network")] = None,
    brand: Annotated[str | None, Header(alias="X-Brand")] = None,
) -> ClientRequestInfo:
    """路由层统一客户端上下文依赖，解析设备、网络、IP 与 User-Agent。"""
    return ClientRequestInfo(
        device_type=(device_type or "").strip(),
        device_model=(device_model or "").strip(),
        os_version=(os_version or "").strip(),
        app_version=(app_version or "").strip(),
        device_id=(device_id or "").strip(),
        network=(network or "").strip(),
        brand=(brand or "").strip(),
        ip=_extract_request_ip(request),
        user_agent=request.headers.get("User-Agent", "").strip(),
    )
