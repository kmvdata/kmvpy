# coding: utf-8
"""管理端表结构编辑 DTO。

后端只下发结构化事实（类型、风险码、语句、受影响行数），不下发任何中文
句子；用户可见文案由 SPA 侧按 code 翻译。
"""

from typing import Literal, Optional

from pydantic import BaseModel, Field


class AdminDatabaseTableSchemaReq(BaseModel):
    """结构描述请求：只接受表名，连接恒为配置声明的数据库。"""

    table_name: str = Field(min_length=1, max_length=128, description="目标表名")


class AdminDatabaseTableSchemaColumnRes(BaseModel):
    """单列定义。``original_name`` 仅在同一列被改名时非空。"""

    name: str = Field(description="列名")
    original_name: Optional[str] = Field(
        default=None,
        description="改名前的列名，仅改名时非空，用于列映射",
    )
    type: Literal[
        "int",
        "bigint",
        "smallint",
        "varchar",
        "text",
        "datetime",
        "boolean",
        "numeric",
    ] = Field(description="白名单列类型")
    type_args: Optional[list[int]] = Field(
        default=None,
        description="类型参数：varchar 为 [长度]，numeric 为 [精度, 小数位]",
    )
    nullable: bool = Field(description="是否允许为空")
    primary_key: bool = Field(description="是否为主键")
    autoincrement: bool = Field(description="是否自增")
    server_default: Optional[str] = Field(
        default=None,
        description="归一化后的默认值：None/0/+86/now()/true 等",
    )
    unique: bool = Field(default=False, description="是否存在单列唯一索引（由索引派生）")
    indexed: bool = Field(default=False, description="是否存在索引（由索引派生）")
    comment: Optional[str] = Field(default=None, description="列注释")


class AdminDatabaseTableSchemaIndexRes(BaseModel):
    """单个索引定义；``name`` 允许为空表示交给数据库生成。"""

    name: Optional[str] = Field(default=None, description="索引名，可为空")
    columns: list[str] = Field(description="索引包含的列，按定义顺序")
    unique: bool = Field(default=False, description="是否为唯一索引")
    primary: bool = Field(default=False, description="是否为主键索引，主键只读")


class AdminDatabaseTableSchemaCapabilitiesRes(BaseModel):
    """当前方言的能力矩阵，供 SPA 决定哪些控件可用。"""

    atomic_ddl: bool = Field(description="是否支持事务内原子回滚 DDL")
    rename_column: bool = Field(description="是否支持原地改列名")
    alter_type: bool = Field(description="是否支持原地改列类型")
    reorder_column: bool = Field(description="是否支持调整已有列顺序")


class AdminDatabaseTableSchemaSpecRes(BaseModel):
    """一套完整的表结构定义，用于 ORM 建议初值。"""

    columns: list[AdminDatabaseTableSchemaColumnRes] = Field(description="列定义")
    indexes: list[AdminDatabaseTableSchemaIndexRes] = Field(description="索引定义")


class AdminDatabaseTableSchemaRes(BaseModel):
    """describe 响应：当前库结构与并发指纹。"""

    table_name: str = Field(description="目标表名")
    dialect: str = Field(description="当前连接方言")
    table_exists: bool = Field(description="表是否已存在")
    registered: bool = Field(description="是否在 ORM 初始化清单中注册")
    row_count: Optional[int] = Field(default=None, description="当前行数")
    columns: list[AdminDatabaseTableSchemaColumnRes] = Field(description="当前列")
    indexes: list[AdminDatabaseTableSchemaIndexRes] = Field(description="当前索引")
    capabilities: AdminDatabaseTableSchemaCapabilitiesRes = Field(
        description="当前方言能力"
    )
    structure_fingerprint: str = Field(description="当前结构指纹，用于并发保护")
    orm_suggestion: Optional[AdminDatabaseTableSchemaSpecRes] = Field(
        default=None,
        description="按 ORM 定义生成的结构建议，仅作为草稿初值；未注册时为空",
    )


class AdminDatabaseTableSchemaPreviewReq(BaseModel):
    """预览请求：目标结构与备份意图。"""

    table_name: str = Field(min_length=1, max_length=128, description="目标表名")
    columns: list[AdminDatabaseTableSchemaColumnRes] = Field(description="目标列定义")
    indexes: list[AdminDatabaseTableSchemaIndexRes] = Field(
        default_factory=list, description="目标索引定义"
    )
    backup: bool = Field(default=True, description="是否在执行前创建备份快照表")


class AdminDatabaseTableSchemaStatementRes(BaseModel):
    """单条 SQL 语句。"""

    sql: str = Field(description="SQL 文本")
    category: Literal[
        "backup",
        "create_table",
        "alter_table",
        "migrate_data",
        "rename_table",
        "create_index",
        "drop_index",
    ] = Field(description="语句类别")
    destructive: bool = Field(description="是否会丢弃已有数据")
    statement_index: int = Field(description="语句序号，从 0 开始")


class AdminDatabaseTableSchemaRiskItemRes(BaseModel):
    """风险项：只下发稳定 code、等级与结构化事实。"""

    code: str = Field(description="稳定风险码")
    level: Literal["info", "confirm", "blocking"] = Field(description="风险等级")
    statement_index: Optional[int] = Field(
        default=None, description="关联语句序号，未绑定语句时为空"
    )
    affected_rows: Optional[int] = Field(default=None, description="受影响行数")


class AdminDatabaseTableSchemaManualPlanRes(BaseModel):
    """无法自动执行时交给用户的三段 SQL。"""

    precheck: list[AdminDatabaseTableSchemaStatementRes] = Field(
        description="预检查语句，只读"
    )
    changes: list[AdminDatabaseTableSchemaStatementRes] = Field(
        description="变更语句"
    )
    rollback: list[AdminDatabaseTableSchemaStatementRes] = Field(
        description="尽力而为的回滚语句"
    )


class AdminDatabaseTableSchemaPreviewRes(BaseModel):
    """preview 响应。"""

    table_name: str = Field(description="目标表名")
    mode: Literal["auto", "manual"] = Field(
        description="auto 可直接执行；manual 只能复制 SQL 手动处理"
    )
    statements: list[AdminDatabaseTableSchemaStatementRes] = Field(
        default_factory=list, description="mode=auto 时用于执行的语句"
    )
    manual_plan: Optional[AdminDatabaseTableSchemaManualPlanRes] = Field(
        default=None, description="mode=manual 时的手动方案"
    )
    risk_items: list[AdminDatabaseTableSchemaRiskItemRes] = Field(
        default_factory=list, description="风险项"
    )
    estimated_rows: Optional[int] = Field(default=None, description="预估影响行数")
    plan_summary: dict[str, int] = Field(
        default_factory=dict, description="变更计数摘要"
    )
    structure_fingerprint: str = Field(description="预览时读到的当前结构指纹")


class AdminDatabaseTableSchemaApplyReq(BaseModel):
    """apply 请求：携带用户对结构、风险与并发指纹的确认。"""

    table_name: str = Field(min_length=1, max_length=128, description="目标表名")
    confirm_table_name: str = Field(
        min_length=1, max_length=128, description="二次确认表名"
    )
    expected_fingerprint: str = Field(
        min_length=1, max_length=128, description="预览时读到的结构指纹"
    )
    backup: bool = Field(default=True, description="是否创建备份快照表")
    columns: list[AdminDatabaseTableSchemaColumnRes] = Field(description="目标列定义")
    indexes: list[AdminDatabaseTableSchemaIndexRes] = Field(
        default_factory=list, description="目标索引定义"
    )
    acknowledged_risk_ids: list[str] = Field(
        default_factory=list, description="用户已勾选确认的风险码"
    )


class AdminDatabaseTableSchemaApplyRes(BaseModel):
    """apply 响应。"""

    table_name: str = Field(description="目标表名")
    success: bool = Field(description="是否执行成功")
    executed_statements: list[str] = Field(
        default_factory=list, description="实际执行的语句，按执行顺序"
    )
    backup_table: Optional[str] = Field(
        default=None, description="保留的备份表名，未创建时为空"
    )
    duration_ms: int = Field(description="执行耗时（毫秒）")