import { postAdminApi } from "src/boot/axios_admin";
import type {
  AdminDatabaseCatalogReq,
  AdminDatabaseCatalogRes,
  AdminDatabaseCatalogTablesReq,
  AdminDatabaseCatalogTablesRes,
} from "src/network/dto/admin/database_catalog";

export class ApiAdminDatabaseCatalog {
  static listDatabases(
    requestData: AdminDatabaseCatalogReq,
  ): Promise<AdminDatabaseCatalogRes> {
    return postAdminApi<AdminDatabaseCatalogReq, AdminDatabaseCatalogRes>(
      "/api/admin/database_catalog/list",
      requestData,
      "获取数据库目录失败",
    );
  }

  static listTables(
    requestData: AdminDatabaseCatalogTablesReq,
  ): Promise<AdminDatabaseCatalogTablesRes> {
    return postAdminApi<
      AdminDatabaseCatalogTablesReq,
      AdminDatabaseCatalogTablesRes
    >("/api/admin/database_catalog/tables", requestData, "获取数据表清单失败");
  }
}