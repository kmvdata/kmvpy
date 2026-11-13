# coding: utf-8
"""管理端数据表行数据 DTO。

只表达只读分页浏览所需的最小契约：分页参数、受限的 WHERE / ORDER BY 文本条件、
单元格归一化结构、列元数据与总数。

``where_clause`` / ``order_by_clause`` 是**受限查询语言**文本，不是原生 SQL：
语法白名单、列白名单与参数绑定都在 ``common/infra/database/query_lang.py`` 与
``DatabaseTableRowsHub`` 内完成，调用方无法借此执行任意 SQL。
"""

from typing import Literal, Optional

from pydantic import BaseModel, Field

# 页码上限：翻页使用 OFFSET，深页会让数据库扫描大量被丢弃的行。
# 管理端只做人工浏览，100000 页已远超实际需要，超限直接按参数非法拒绝。
MAX_PAGE = 100000


class AdminDatabaseTableRowsReq(BaseModel):
    """行数据请求：只接受表名、分页与排序列，连接恒为配置声明的数据库。"""

    table_name: str = Field(min_length=1, max_length=128, description="目标表名")
    page: int = Field(
        default=1,
        ge=1,
        le=MAX_PAGE,
        description="页码，从 1 开始；上限 100000，避免超深 OFFSET 消耗数据库资源",
    )
    size: int = Field(default=50, ge=1, le=200, description="每页行数上限 200")
    order_by: Optional[str] = Field(
        default=None,
        max_length=128,
        description="排序列名，必须在当前表列名单内",
    )
    order_desc: bool = Field(default=False, description="是否倒序")
    where_clause: Optional[str] = Field(
        default=None,
        max_length=512,
        description=(
            "受限 WHERE 条件文本，例如 status = 'open' AND id > 100；"
            "只支持比较、LIKE/ILIKE、IN、BETWEEN、IS NULL 与 AND/OR/NOT"
        ),
    )
    order_by_clause: Optional[str] = Field(
        default=None,
        max_length=512,
        description=(
            "受限 ORDER BY 条件文本，例如 create_time DESC, id ASC；"
            "列名必须在当前表列名单内"
        ),
    )


class AdminDatabaseTableRowsCellRes(BaseModel):
    """单个单元格：只下发结构化事实，展示文案由 SPA 侧按 kind 渲染。"""

    kind: Literal["null", "text", "number", "bool", "datetime", "binary"] = Field(
        description="单元格内容类别"
    )
    text: Optional[str] = Field(
        default=None,
        description="可展示文本；binary 与 null 单元格为空",
    )
    truncated: bool = Field(description="文本是否已按上限截断")
    byte_length: Optional[int] = Field(
        default=None,
        description="二进制内容的字节长度，仅 binary 单元格非空",
    )


class AdminDatabaseTableRowsColumnRes(BaseModel):
    name: str = Field(description="列名")
    type: str = Field(description="数据库列类型")
    nullable: bool = Field(description="是否允许为空")
    primary_key: bool = Field(description="是否为主键")


class AdminDatabaseTableRowsRes(BaseModel):
    table_name: str = Field(description="表名")
    columns: list[AdminDatabaseTableRowsColumnRes] = Field(description="列元数据")
    rows: list[list[AdminDatabaseTableRowsCellRes]] = Field(
        description="当前页行数据，按 columns 顺序排列"
    )
    primary_key_columns: list[str] = Field(description="主键列名，可为空")
    total: Optional[int] = Field(
        default=None,
        description="总行数；仅在请求第一页时读取，其余页为 null",
    )
    page: int = Field(description="当前页码")
    size: int = Field(description="当前每页行数")
    elapsed_ms: int = Field(description="服务端读取耗时（毫秒）")
    where_clause: Optional[str] = Field(
        default=None,
        description="实际生效的 WHERE 条件文本；未提供时为 null",
    )
    order_by_clause: Optional[str] = Field(
        default=None,
        description="实际生效的 ORDER BY 条件文本；未提供时为 null",
    )
