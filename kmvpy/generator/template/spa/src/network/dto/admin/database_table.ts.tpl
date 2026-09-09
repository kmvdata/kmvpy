export type DatabaseConnectionMode = "default" | "custom";
export type DatabaseDriver = "postgresql" | "mysql" | "sqlite";

export interface AdminDatabaseConnectionReq {
  mode: DatabaseConnectionMode;
  driver: DatabaseDriver | null;
  host: string | null;
  port: number | null;
  database: string | null;
  username: string | null;
  password: string | null;
  sqlite_path: string | null;
  ssl: boolean;
  options: string | null;
  timeout: number;
}

export interface AdminDatabaseTablesListReq {
  connection: AdminDatabaseConnectionReq;
}

export interface AdminDatabaseTableActionReq {
  connection: AdminDatabaseConnectionReq;
  table_name: string;
  confirm_table_name: string;
}

export interface AdminDatabaseTablesInitializeAllReq {
  confirm_text: string;
}

export interface AdminDatabaseTableColumnRes {
  name: string;
  type: string;
  nullable: boolean;
  primary_key: boolean;
  indexed: boolean;
  unique: boolean;
}

export interface AdminDatabaseTableRes {
  table_name: string;
  registered: boolean;
  comment: string | null;
  row_count: number | null;
  column_count: number;
  columns: AdminDatabaseTableColumnRes[];
}

export interface AdminDatabaseTablesListRes {
  items: AdminDatabaseTableRes[];
  total: number;
  dialect: string;
  connection_summary: string;
  registered_table_count: number;
}

export interface AdminDatabaseTableActionRes {
  table_name: string;
  success: boolean;
}

export interface AdminDatabaseTablesInitializeAllRes {
  initialized_table_count: number;
  success: boolean;
}
