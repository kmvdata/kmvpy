# coding: utf-8
"""管理端数据库表维护 DTO。"""

from typing import Literal, Optional

from pydantic import BaseModel, Field


DatabaseConnectionMode = Literal["default", "custom"]
DatabaseDriver = Literal["postgresql", "mysql", "sqlite"]


class AdminDatabaseConnectionReq(BaseModel):
    mode: DatabaseConnectionMode = Field(
        default="default",
        description="连接模式：default 使用当前系统默认库；custom 使用本次请求提供的连接配置",
    )
    driver: Optional[DatabaseDriver] = Field(default=None, description="数据库类型")
    host: Optional[str] = Field(default=None, max_length=255, description="数据库主机")
    port: Optional[int] = Field(default=None, ge=1, le=65535, description="数据库端口")
    database: Optional[str] = Field(default=None, max_length=255, description="数据库名")
    username: Optional[str] = Field(default=None, max_length=255, description="用户名")
    password: Optional[str] = Field(default=None, max_length=2048, description="密码")
    sqlite_path: Optional[str] = Field(
        default=None,
        max_length=1024,
        description="SQLite 数据库文件路径或 :memory:",
    )
    ssl: bool = Field(default=False, description="是否启用 SSL")
    options: Optional[str] = Field(
        default=None,
        max_length=512,
        description="PostgreSQL options 等连接参数",
    )
    timeout: int = Field(default=30, ge=1, le=120, description="连接超时秒数")


class AdminDatabaseTablesListReq(BaseModel):
    connection: AdminDatabaseConnectionReq = Field(description="数据库连接配置")


class AdminDatabaseTableActionReq(BaseModel):
    connection: AdminDatabaseConnectionReq = Field(description="数据库连接配置")
    table_name: str = Field(min_length=1, max_length=128, description="目标表名")
    confirm_table_name: str = Field(
        min_length=1,
        max_length=128,
        description="二次确认表名",
    )


class AdminDatabaseTablesInitializeAllReq(BaseModel):
    confirm_text: str = Field(
        min_length=1,
        max_length=64,
        description="重新初始化全部 ORM 表的二次确认文本",
    )


class AdminDatabaseTableColumnRes(BaseModel):
    name: str = Field(description="列名")
    type: str = Field(description="数据库列类型")
    nullable: bool = Field(description="是否允许为空")
    primary_key: bool = Field(description="是否为主键")
    indexed: bool = Field(description="是否存在索引")
    unique: bool = Field(description="是否存在唯一约束或唯一索引")


class AdminDatabaseTableRes(BaseModel):
    table_name: str = Field(description="表名")
    registered: bool = Field(description="是否在 ORM 初始化清单中注册")
    comment: Optional[str] = Field(default=None, description="表注释")
    row_count: Optional[int] = Field(default=None, description="当前行数")
    column_count: int = Field(description="列数量")
    columns: list[AdminDatabaseTableColumnRes] = Field(description="列清单")


class AdminDatabaseTablesListRes(BaseModel):
    items: list[AdminDatabaseTableRes] = Field(description="数据库表列表")
    total: int = Field(description="表总数")
    dialect: str = Field(description="当前连接数据库方言")
    connection_summary: str = Field(description="脱敏后的连接摘要")
    registered_table_count: int = Field(description="ORM 注册表数量")


class AdminDatabaseTableActionRes(BaseModel):
    table_name: str = Field(description="目标表名")
    success: bool = Field(description="是否执行成功")


class AdminDatabaseTablesInitializeAllRes(BaseModel):
    initialized_table_count: int = Field(description="本次按 ORM 注册清单初始化的表数量")
    success: bool = Field(description="是否执行成功")
