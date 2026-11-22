# coding: utf-8
"""管理端数据库表维护 DTO。

配置文件中只声明一个业务库，请求不再携带任何连接参数，
从契约层面消除把服务指向其它数据库的可能。
"""

from typing import Optional

from pydantic import BaseModel, Field


class AdminDatabaseTablesListReq(BaseModel):
    """表清单请求：不接受连接参数，服务端恒使用配置声明的数据库。"""


class AdminDatabaseTableActionReq(BaseModel):
    table_name: str = Field(min_length=1, max_length=128, description="目标表名")
    confirm_table_name: str = Field(
        min_length=1,
        max_length=128,
        description="二次确认表名",
    )


class AdminDatabaseTableColumnRes(BaseModel):
    name: str = Field(description="列名")
    type: str = Field(description="数据库列类型")
    nullable: bool = Field(description="是否允许为空")
    primary_key: bool = Field(description="是否为主键")
    indexed: bool = Field(description="是否存在索引")
    unique: bool = Field(description="是否存在唯一约束或唯一索引")


class AdminDatabaseTableIndexRes(BaseModel):
    name: str = Field(description="索引名")
    columns: list[str] = Field(description="索引包含的列，按索引定义顺序")
    unique: bool = Field(description="是否为唯一索引")
    primary: bool = Field(description="是否为主键索引")


class AdminDatabaseTableRes(BaseModel):
    table_name: str = Field(description="表名")
    registered: bool = Field(description="是否在 ORM 初始化清单中注册")
    comment: Optional[str] = Field(default=None, description="表注释")
    row_count: Optional[int] = Field(default=None, description="当前行数")
    column_count: int = Field(description="列数量")
    columns: list[AdminDatabaseTableColumnRes] = Field(description="列清单")
    indexes: list[AdminDatabaseTableIndexRes] = Field(
        default_factory=list,
        description="索引清单，主键索引排在首位",
    )


class AdminDatabaseTablesListRes(BaseModel):
    items: list[AdminDatabaseTableRes] = Field(description="数据库表列表")
    total: int = Field(description="表总数")
    dialect: str = Field(description="当前连接数据库方言")
    connection_summary: str = Field(description="脱敏后的连接摘要")
    database_name: str = Field(description="当前查看的数据库名称")
    registered_table_count: int = Field(description="ORM 注册表数量")


class AdminDatabaseTableActionRes(BaseModel):
    table_name: str = Field(description="目标表名")
    success: bool = Field(description="是否执行成功")