export interface AdminDatabaseCatalogReq {
  /** 目录请求不接受参数：服务端恒返回配置声明的数据库。 */
  [key: string]: never;
}

export interface AdminDatabaseServerRes {
  dialect: string;
  version: string;
  host: string;
  port: number | null;
  username: string;
  default_database: string;
}

export interface AdminDatabaseCatalogItemRes {
  name: string;
  is_default: boolean;
  is_system: boolean;
  connectable: boolean;
  dialect: string;
  size_bytes: number | null;
  table_count: number | null;
  registered_table_count: number | null;
  owner: string | null;
  encoding: string | null;
  preview_tables: string[];
  inspected: boolean;
}

export interface AdminDatabaseCatalogRes {
  server: AdminDatabaseServerRes;
  items: AdminDatabaseCatalogItemRes[];
  total: number;
  business_total: number;
}

export interface AdminDatabaseCatalogTablesReq {
  database: string;
}

export interface AdminDatabaseCatalogTableItemRes {
  name: string;
  registered: boolean;
}

export interface AdminDatabaseCatalogTablesRes {
  database: string;
  items: AdminDatabaseCatalogTableItemRes[];
  total: number;
}