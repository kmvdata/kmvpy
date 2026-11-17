/**
 * 管理端表结构编辑传输契约。
 *
 * 字段与后端 `common/dto/admin/database_table_schema.py` 严格一致：
 * snake_case、可空字段用 `T | null`、后端不下发任何中文文案，
 * 用户可见文字全部由 SPA 按 code 翻译。
 */

export type AdminDatabaseTableSchemaColumnType =
  | "int"
  | "bigint"
  | "smallint"
  | "varchar"
  | "text"
  | "datetime"
  | "boolean"
  | "numeric";

export type AdminDatabaseTableSchemaRiskLevel = "info" | "confirm" | "blocking";

export type AdminDatabaseTableSchemaMode = "auto" | "manual";

export type AdminDatabaseTableSchemaStatementCategory =
  | "backup"
  | "create_table"
  | "alter_table"
  | "migrate_data"
  | "rename_table"
  | "create_index"
  | "drop_index";

export interface AdminDatabaseTableSchemaReq {
  table_name: string;
}

export interface AdminDatabaseTableSchemaColumnRes {
  name: string;
  /** 仅「改名」时非空，用于列映射；绝不能用「删列 + 加列」代替。 */
  original_name: string | null;
  type: AdminDatabaseTableSchemaColumnType;
  /** varchar 为 [长度]，numeric 为 [精度, 小数位]，其余为 null。 */
  type_args: number[] | null;
  nullable: boolean;
  primary_key: boolean;
  autoincrement: boolean;
  /** 归一化后的默认值：null / "0" / "+86" / "now()" / "true"。 */
  server_default: string | null;
  /** 由索引清单派生，只用于展示。 */
  unique: boolean;
  /** 由索引清单派生，只用于展示。 */
  indexed: boolean;
  comment: string | null;
}

export interface AdminDatabaseTableSchemaIndexRes {
  /** 允许为 null，表示交给数据库生成索引名。 */
  name: string | null;
  columns: string[];
  unique: boolean;
  primary: boolean;
}

export interface AdminDatabaseTableSchemaCapabilitiesRes {
  atomic_ddl: boolean;
  rename_column: boolean;
  alter_type: boolean;
  reorder_column: boolean;
}

export interface AdminDatabaseTableSchemaSpecRes {
  columns: AdminDatabaseTableSchemaColumnRes[];
  indexes: AdminDatabaseTableSchemaIndexRes[];
}

export interface AdminDatabaseTableSchemaRes {
  table_name: string;
  dialect: string;
  table_exists: boolean;
  registered: boolean;
  row_count: number | null;
  columns: AdminDatabaseTableSchemaColumnRes[];
  indexes: AdminDatabaseTableSchemaIndexRes[];
  capabilities: AdminDatabaseTableSchemaCapabilitiesRes;
  structure_fingerprint: string;
  /** 按 ORM 定义生成的结构建议，只作为草稿初值；未注册时为 null。 */
  orm_suggestion: AdminDatabaseTableSchemaSpecRes | null;
}

export interface AdminDatabaseTableSchemaPreviewReq {
  table_name: string;
  columns: AdminDatabaseTableSchemaColumnRes[];
  indexes: AdminDatabaseTableSchemaIndexRes[];
  backup: boolean;
}

export interface AdminDatabaseTableSchemaStatementRes {
  sql: string;
  category: AdminDatabaseTableSchemaStatementCategory;
  destructive: boolean;
  statement_index: number;
}

export interface AdminDatabaseTableSchemaRiskItemRes {
  code: string;
  level: AdminDatabaseTableSchemaRiskLevel;
  statement_index: number | null;
  affected_rows: number | null;
}

export interface AdminDatabaseTableSchemaManualPlanRes {
  precheck: AdminDatabaseTableSchemaStatementRes[];
  changes: AdminDatabaseTableSchemaStatementRes[];
  rollback: AdminDatabaseTableSchemaStatementRes[];
}

export interface AdminDatabaseTableSchemaPreviewRes {
  table_name: string;
  mode: AdminDatabaseTableSchemaMode;
  statements: AdminDatabaseTableSchemaStatementRes[];
  manual_plan: AdminDatabaseTableSchemaManualPlanRes | null;
  risk_items: AdminDatabaseTableSchemaRiskItemRes[];
  estimated_rows: number | null;
  plan_summary: Record<string, number>;
  structure_fingerprint: string;
}

export interface AdminDatabaseTableSchemaApplyReq {
  table_name: string;
  confirm_table_name: string;
  expected_fingerprint: string;
  backup: boolean;
  columns: AdminDatabaseTableSchemaColumnRes[];
  indexes: AdminDatabaseTableSchemaIndexRes[];
  acknowledged_risk_ids: string[];
}

export interface AdminDatabaseTableSchemaApplyRes {
  table_name: string;
  success: boolean;
  executed_statements: string[];
  backup_table: string | null;
  duration_ms: number;
}