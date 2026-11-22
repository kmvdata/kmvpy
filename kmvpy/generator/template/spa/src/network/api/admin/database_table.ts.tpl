import { postAdminApi } from "src/boot/axios_admin";
import type {
  AdminDatabaseTableActionReq,
  AdminDatabaseTableActionRes,
  AdminDatabaseTableRowsReq,
  AdminDatabaseTableRowsRes,
  AdminDatabaseTablesListReq,
  AdminDatabaseTablesListRes,
} from "src/network/dto/admin/database_table";
import type {
  AdminDatabaseTableSchemaApplyReq,
  AdminDatabaseTableSchemaApplyRes,
  AdminDatabaseTableSchemaPreviewReq,
  AdminDatabaseTableSchemaPreviewRes,
  AdminDatabaseTableSchemaReq,
  AdminDatabaseTableSchemaRes,
} from "src/network/dto/admin/database_table_schema";

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

  /** 只读分页读取表数据；不执行任何写操作。 */
  static listRows(
    requestData: AdminDatabaseTableRowsReq,
  ): Promise<AdminDatabaseTableRowsRes> {
    return postAdminApi<AdminDatabaseTableRowsReq, AdminDatabaseTableRowsRes>(
      "/api/admin/database_table/rows",
      requestData,
      "读取数据表行数据失败",
    );
  }

  /** 读当前结构、方言能力与 ORM 建议初值；只读，不改结构。 */
  static describeSchema(
    requestData: AdminDatabaseTableSchemaReq,
  ): Promise<AdminDatabaseTableSchemaRes> {
    return postAdminApi<AdminDatabaseTableSchemaReq, AdminDatabaseTableSchemaRes>(
      "/api/admin/database_table/schema/describe",
      requestData,
      "读取数据表结构失败",
    );
  }

  /** 权威复核目标结构；只读，不执行任何 DDL。 */
  static previewSchema(
    requestData: AdminDatabaseTableSchemaPreviewReq,
  ): Promise<AdminDatabaseTableSchemaPreviewRes> {
    return postAdminApi<
      AdminDatabaseTableSchemaPreviewReq,
      AdminDatabaseTableSchemaPreviewRes
    >(
      "/api/admin/database_table/schema/preview",
      requestData,
      "预览数据表结构变更失败",
    );
  }

  /** 执行结构变更；需先通过 preview 并由用户逐项确认风险。 */
  static applySchema(
    requestData: AdminDatabaseTableSchemaApplyReq,
  ): Promise<AdminDatabaseTableSchemaApplyRes> {
    return postAdminApi<
      AdminDatabaseTableSchemaApplyReq,
      AdminDatabaseTableSchemaApplyRes
    >(
      "/api/admin/database_table/schema/apply",
      requestData,
      "执行数据表结构变更失败",
    );
  }
}