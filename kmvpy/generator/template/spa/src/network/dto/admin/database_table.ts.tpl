export interface AdminDatabaseTablesListReq {
  /** 表清单请求不接受连接参数：服务端恒使用配置声明的数据库。 */
  [key: string]: never;
}

export interface AdminDatabaseTableActionReq {
  table_name: string;
  confirm_table_name: string;
}

export interface AdminDatabaseTableColumnRes {
  name: string;
  type: string;
  nullable: boolean;
  primary_key: boolean;
  indexed: boolean;
  unique: boolean;
}

export interface AdminDatabaseTableIndexRes {
  name: string;
  columns: string[];
  unique: boolean;
  primary: boolean;
}

export interface AdminDatabaseTableRes {
  table_name: string;
  registered: boolean;
  comment: string | null;
  row_count: number | null;
  column_count: number;
  columns: AdminDatabaseTableColumnRes[];
  indexes: AdminDatabaseTableIndexRes[];
}

export interface AdminDatabaseTablesListRes {
  items: AdminDatabaseTableRes[];
  total: number;
  dialect: string;
  connection_summary: string;
  database_name: string;
  registered_table_count: number;
}

export interface AdminDatabaseTableActionRes {
  table_name: string;
  success: boolean;
}

export interface AdminDatabaseTableRowsReq {
  table_name: string;
  /** 页码，从 1 开始。 */
  page: number;
  /** 每页行数，后端上限 200。 */
  size: number;
  /**
   * 本次查询最多返回的行数上限（LIMIT）。默认 100、最小 1、上限 10000；
   * 超过 10000 后端按数据安全返回 46014，不做静默收敛。
   */
  row_limit: number;
  /** 排序列名，必须在当前表列名单内；null 表示不指定排序。 */
  order_by: string | null;
  order_desc: boolean;
  /**
   * 受限 WHERE 条件文本，例如 `status = 'open' AND id > 100`。
   * 后端只接受比较、LIKE/ILIKE、IN、BETWEEN、IS NULL 与 AND/OR/NOT，
   * 列名必须在当前表列名单内；null 表示不过滤。
   */
  where_clause: string | null;
  /**
   * 受限 ORDER BY 条件文本，例如 `create_time DESC, id ASC`。
   * null 表示沿用 order_by / order_desc 的单列排序。
   */
  order_by_clause: string | null;
}

export interface AdminDatabaseTableRowsCellRes {
  kind: "null" | "text" | "number" | "bool" | "datetime" | "binary";
  /** binary 与 null 单元格为 null。 */
  text: string | null;
  truncated: boolean;
  /** 仅 binary 单元格非 null。 */
  byte_length: number | null;
}

export interface AdminDatabaseTableRowsColumnRes {
  name: string;
  type: string;
  nullable: boolean;
  primary_key: boolean;
}

export interface AdminDatabaseTableRowsRes {
  table_name: string;
  columns: AdminDatabaseTableRowsColumnRes[];
  rows: AdminDatabaseTableRowsCellRes[][];
  primary_key_columns: string[];
  /**
   * 仅第一页返回总行数，其余页为 null；带 where_clause 时是过滤后的行数。
   * 已按 row_limit 收敛，因此不会超过本次生效的行数上限。
   */
  total: number | null;
  /** total 是否已被 row_limit 截断；true 表示实际行数更多。 */
  total_truncated: boolean;
  page: number;
  size: number;
  /** 本次生效的行数上限。 */
  row_limit: number;
  elapsed_ms: number;
  /** 实际生效的 WHERE 条件文本；未提供时为 null。 */
  where_clause: string | null;
  /** 实际生效的 ORDER BY 条件文本；未提供时为 null。 */
  order_by_clause: string | null;
}