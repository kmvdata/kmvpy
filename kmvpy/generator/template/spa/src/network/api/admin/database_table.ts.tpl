import { postAdminApi } from "src/boot/axios_admin";
import type {
  AdminDatabaseTableActionReq,
  AdminDatabaseTableActionRes,
  AdminDatabaseTablesInitializeAllReq,
  AdminDatabaseTablesInitializeAllRes,
  AdminDatabaseTablesListReq,
  AdminDatabaseTablesListRes,
} from "src/network/dto/admin/database_table";

export class ApiAdminDatabaseTable {
  static listTables(
    requestData: AdminDatabaseTablesListReq,
  ): Promise<AdminDatabaseTablesListRes> {
    return postAdminApi<AdminDatabaseTablesListReq, AdminDatabaseTablesListRes>(
      "/api/admin/database_table/list",
      requestData,
      "获取数据库表列表失败",
    );
  }

  static dropTable(
    requestData: AdminDatabaseTableActionReq,
  ): Promise<AdminDatabaseTableActionRes> {
    return postAdminApi<AdminDatabaseTableActionReq, AdminDatabaseTableActionRes>(
      "/api/admin/database_table/drop",
      requestData,
      "删除数据库表失败",
    );
  }

  static regenerateTable(
    requestData: AdminDatabaseTableActionReq,
  ): Promise<AdminDatabaseTableActionRes> {
    return postAdminApi<AdminDatabaseTableActionReq, AdminDatabaseTableActionRes>(
      "/api/admin/database_table/regenerate",
      requestData,
      "重建数据库表失败",
    );
  }

  static initializeAllTables(
    requestData: AdminDatabaseTablesInitializeAllReq,
  ): Promise<AdminDatabaseTablesInitializeAllRes> {
    return postAdminApi<
      AdminDatabaseTablesInitializeAllReq,
      AdminDatabaseTablesInitializeAllRes
    >(
      "/api/admin/database_table/initialize_all",
      requestData,
      "重新初始化全部数据表失败",
    );
  }
}
