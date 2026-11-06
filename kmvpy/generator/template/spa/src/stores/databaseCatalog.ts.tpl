import { computed, ref } from "vue";
import { defineStore } from "pinia";

import { ApiAdminDatabaseCatalog } from "src/network/api/admin/database_catalog";
import type {
  AdminDatabaseCatalogItemRes,
  AdminDatabaseCatalogTableItemRes,
} from "src/network/dto/admin/database_catalog";

export type DatabaseCatalogStatus = "idle" | "loading" | "ready" | "error";
export type DatabaseTablesStatus = "idle" | "loading" | "ready" | "error";

/**
 * 识别到的数据库目录：供管理后台抽屉的“数据库”下拉子菜单使用。
 * 状态只保存传输数据，错误文案由调用方按 i18n/Kmv 链解析。
 */
export const useDatabaseCatalogStore = defineStore("databaseCatalog", () => {
  const items = ref<AdminDatabaseCatalogItemRes[]>([]);
  const status = ref<DatabaseCatalogStatus>("idle");
  let inFlight: Promise<void> | null = null;

  const databases = computed(() =>
    items.value.filter((item) => !item.is_system),
  );
  const isLoading = computed(() => status.value === "loading");

  const tablesByDatabase = ref<
    Record<string, AdminDatabaseCatalogTableItemRes[]>
  >({});
  const tableStatusByDatabase = ref<Record<string, DatabaseTablesStatus>>({});
  const tablesInFlight = new Map<string, Promise<void>>();

  function tablesOf(database: string): AdminDatabaseCatalogTableItemRes[] {
    return tablesByDatabase.value[database] ?? [];
  }

  function tableStatusOf(database: string): DatabaseTablesStatus {
    return tableStatusByDatabase.value[database] ?? "idle";
  }

  function setTableStatus(
    database: string,
    nextStatus: DatabaseTablesStatus,
  ): void {
    tableStatusByDatabase.value = {
      ...tableStatusByDatabase.value,
      [database]: nextStatus,
    };
  }

  /** 按库懒加载表名清单：并发请求合并，失败后下一次调用可重试。 */
  function ensureTablesLoaded(database: string): Promise<void> {
    const name = database.trim();
    if (!name) {
      return Promise.resolve();
    }
    const pending = tablesInFlight.get(name);
    if (pending) {
      return pending;
    }
    if (tableStatusOf(name) === "ready") {
      return Promise.resolve();
    }
    setTableStatus(name, "loading");
    const request = (async () => {
      try {
        const res = await ApiAdminDatabaseCatalog.listTables({
          database: name,
        });
        tablesByDatabase.value = { ...tablesByDatabase.value, [name]: res.items };
        setTableStatus(name, "ready");
      } catch (error) {
        setTableStatus(name, "error");
        throw error;
      } finally {
        tablesInFlight.delete(name);
      }
    })();
    tablesInFlight.set(name, request);
    return request;
  }

  async function refresh(): Promise<void> {
    if (inFlight) {
      return inFlight;
    }
    status.value = "loading";
    const request = (async () => {
      try {
        const res = await ApiAdminDatabaseCatalog.listDatabases({});
        items.value = res.items;
        status.value = "ready";
      } catch (error) {
        status.value = "error";
        throw error;
      } finally {
        inFlight = null;
      }
    })();
    inFlight = request;
    return request;
  }

  function ensureLoaded(): Promise<void> {
    if (status.value === "ready") {
      return Promise.resolve();
    }
    return refresh();
  }

  return {
    items,
    databases,
    status,
    isLoading,
    refresh,
    ensureLoaded,
    tablesOf,
    tableStatusOf,
    ensureTablesLoaded,
  };
});