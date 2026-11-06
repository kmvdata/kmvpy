# coding: utf-8
"""管理端数据库目录 DTO。"""

from typing import Optional

from pydantic import BaseModel, Field


class AdminDatabaseCatalogReq(BaseModel):
    """数据库目录请求：不接受参数，恒返回配置声明的数据库。"""


class AdminDatabaseServerRes(BaseModel):
    dialect: str = Field(description="数据库方言")
    version: str = Field(description="数据库服务版本")
    host: str = Field(description="数据库服务地址")
    port: Optional[int] = Field(default=None, description="数据库服务端口")
    username: str = Field(description="连接用户")
    default_database: str = Field(description="当前系统默认库名称")


class AdminDatabaseCatalogItemRes(BaseModel):
    name: str = Field(description="数据库名称")
    is_default: bool = Field(description="是否为当前系统默认库")
    is_system: bool = Field(description="是否为数据库服务自带的系统库")
    connectable: bool = Field(description="是否允许建立连接")
    dialect: str = Field(description="数据库方言")
    size_bytes: Optional[int] = Field(default=None, description="数据体积（字节）")
    table_count: Optional[int] = Field(default=None, description="表数量")
    registered_table_count: Optional[int] = Field(
        default=None,
        description="该库中已注册 ORM 表数量",
    )
    owner: Optional[str] = Field(default=None, description="数据库所有者")
    encoding: Optional[str] = Field(default=None, description="数据库字符集或编码")
    preview_tables: list[str] = Field(default_factory=list, description="表名预览")
    inspected: bool = Field(default=False, description="是否已完成表结构探测")


class AdminDatabaseCatalogRes(BaseModel):
    server: AdminDatabaseServerRes = Field(description="数据库服务信息")
    items: list[AdminDatabaseCatalogItemRes] = Field(description="识别到的数据库")
    total: int = Field(description="本次返回的数据库数量")
    business_total: int = Field(description="非系统库数量")


class AdminDatabaseCatalogTablesReq(BaseModel):
    database: str = Field(
        min_length=1,
        max_length=255,
        description="要读取数据表清单的目标数据库名称，必须与配置一致",
    )


class AdminDatabaseCatalogTableItemRes(BaseModel):
    name: str = Field(description="数据表名称")
    registered: bool = Field(description="是否在 ORM 初始化清单中注册")


class AdminDatabaseCatalogTablesRes(BaseModel):
    database: str = Field(description="目标数据库名称")
    items: list[AdminDatabaseCatalogTableItemRes] = Field(description="数据表清单")
    total: int = Field(description="数据表数量")