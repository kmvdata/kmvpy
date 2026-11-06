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