<template>
  <q-page class="spa-page admin-database-tables-page page-section">
    <div class="spa-shell spa-shell--wide admin-database-tables__shell">
      <div class="admin-database-tables__header">
        <div class="admin-database-tables__header-copy">
          <h2 class="spa-page-title admin-database-tables__title">
            {{
              highlightedTableName
                ? t("adminDatabaseTables.titleWithTable", {
                    database: metadata.database_name || configuredDatabaseName,
                    table: highlightedTableName,
                  })
                : t("adminDatabaseTables.titleWithDatabase", {
                    database: metadata.database_name || configuredDatabaseName,
                  })
            }}
          </h2>
          <p class="spa-page-subtitle admin-database-tables__subtitle">
            {{ t("adminDatabaseTables.subtitle") }}
          </p>
        </div>
      </div>

      <q-banner
        v-if="isForeignDatabase"
        rounded
        class="spa-inline-alert--error admin-database-tables__banner"
      >
        <div class="admin-database-tables__banner-body">
          <span>{{ t("adminDatabaseTables.errors.foreignDatabase") }}</span>
          <q-btn
            flat
            dense
            no-caps
            color="primary"
            :label="
              t('adminDatabaseTables.actions.switchToConfiguredDatabase', {
                database: configuredDatabaseName,
              })
            "
            @click="goToConfiguredDatabase"
          />
        </div>
      </q-banner>

      <q-card
        v-if="!isTableDetailMode && !isForeignDatabase"
        flat
        bordered
        class="spa-card admin-database-tables__card"
      >
        <div class="spa-section-title admin-database-tables__section-title">
          {{ t("adminDatabaseTables.connection.summary") }}
        </div>

        <div class="admin-database-tables__summary">
          <div class="admin-database-tables__summary-line">
            <span>{{ t("adminDatabaseTables.stats.database") }}</span>
            <strong class="mono">{{ metadata.database_name || emptyValue }}</strong>
          </div>
          <div class="admin-database-tables__summary-line">
            <span>{{ t("adminDatabaseTables.stats.dialect") }}</span>
            <strong class="mono">{{ metadata.dialect || emptyValue }}</strong>
          </div>
          <div class="admin-database-tables__summary-line">
            <span>{{ t("adminDatabaseTables.connection.summary") }}</span>
            <strong class="mono">{{
              metadata.connection_summary || emptyValue
            }}</strong>
          </div>
        </div>

        <div class="admin-database-tables__stats">
          <div class="admin-database-tables__stat">
            <span>{{ t("adminDatabaseTables.stats.total") }}</span>
            <strong>{{ items.length }}</strong>
          </div>
          <div class="admin-database-tables__stat">
            <span>{{ t("adminDatabaseTables.stats.registered") }}</span>
            <strong>{{ registeredCount }}</strong>
          </div>
          <div class="admin-database-tables__stat">
            <span>{{ t("adminDatabaseTables.stats.external") }}</span>
            <strong>{{ externalCount }}</strong>
          </div>
        </div>
      </q-card>

      <q-banner
        v-if="errorText && !isForeignDatabase"
        rounded
        class="spa-inline-alert--error admin-database-tables__banner"
      >
        {{ errorText }}
      </q-banner>

      <div
        v-if="!isTableDetailMode && !isForeignDatabase"
        class="admin-database-tables__toolbar"
      >
        <q-input
          v-model="searchText"
          dense
          outlined
          clearable
          debounce="250"
          class="admin-database-tables__search"
          :label="t('adminDatabaseTables.filters.search')"
        >
          <template #prepend>
            <q-icon name="search" />
          </template>
        </q-input>
        <q-btn
          flat
          no-caps
          icon="refresh"
          :label="t('adminDatabaseTables.actions.refresh')"
          :loading="loading"
          :disable="hasBlockingAction"
          @click="loadTables(true)"
        />
      </div>

      <div
        v-if="!isTableDetailMode && !isForeignDatabase"
        class="admin-database-tables__table-card"
      >
        <q-inner-loading :showing="loading" color="primary" />
        <div class="admin-database-tables__table-scroll">
          <table class="data-table admin-database-tables__table">
            <thead>
              <tr>
                <th>{{ t("adminDatabaseTables.table.tableName") }}</th>
                <th>{{ t("adminDatabaseTables.table.rows") }}</th>
                <th>{{ t("adminDatabaseTables.table.columns") }}</th>
                <th>{{ t("adminDatabaseTables.table.state") }}</th>
                <th class="admin-table-th--actions">
                  {{ t("adminDatabaseTables.table.actions") }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr v-if="!loading && filteredItems.length === 0">
                <td colspan="5" class="admin-database-tables__empty-cell">
                  {{ t("adminDatabaseTables.table.empty") }}
                </td>
              </tr>
              <tr v-for="row in filteredItems" :key="row.table_name">
                <td>
                  <router-link
                    class="mono admin-database-tables__table-link"
                    :to="tableRoute(row.table_name)"
                    :title="
                      t('adminDatabaseTables.actions.openTable', {
                        table: row.table_name,
                      })
                    "
                  >
                    {{ row.table_name }}
                  </router-link>
                </td>
                <td class="mono">{{ rowCountText(row) }}</td>
                <td class="mono">{{ row.column_count }}</td>
                <td>
                  <q-chip
                    dense
                    square
                    :color="row.registered ? 'primary' : 'surface-muted'"
                    :text-color="row.registered ? 'on-primary' : 'main'"
                  >
                    {{
                      row.registered
                        ? t("adminDatabaseTables.table.registered")
                        : t("adminDatabaseTables.table.external")
                    }}
                  </q-chip>
                </td>
                <td class="admin-table-td--actions">
                  <!-- 打开可视化结构编辑器；不再有「重建表」黑盒流程。 -->
                  <q-btn
                    dense
                    flat
                    no-caps
                    icon="edit_note"
                    color="primary"
                    :label="t('adminDatabaseTables.actions.editSchema')"
                    :disable="hasBlockingAction"
                    @click="openSchemaEditor(row)"
                  />
                  <q-btn
                    dense
                    flat
                    no-caps
                    icon="delete"
                    color="negative"
                    :label="
                      isRowAction(row, 'drop')
                        ? t('adminDatabaseTables.actions.dropping')
                        : t('adminDatabaseTables.actions.drop')
                    "
                    :loading="isRowAction(row, 'drop')"
                    :disable="hasBlockingAction"
                    @click="openDropDialog(row)"
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <div class="admin-database-tables__table-footer mono">
          {{ t("adminDatabaseTables.table.total", { total: filteredItems.length }) }}
        </div>
      </div>

      <div
        v-if="isTableDetailMode && !isForeignDatabase"
        class="admin-database-tables__detail-panel"
      >
        <q-inner-loading :showing="loading" color="primary" />
        <div class="admin-database-tables__detail-toolbar">
          <q-btn
            flat
            dense
            no-caps
            icon="arrow_back"
            :label="t('adminDatabaseTables.actions.backToList')"
            @click="backToList"
          />
          <div v-if="detailTable" class="admin-database-tables__detail-actions">
            <!-- 详情页入口：与列表行操作共用同一个编辑器组件。 -->
            <q-btn
              dense
              flat
              no-caps
              icon="edit_note"
              color="primary"
              :label="t('adminDatabaseTables.actions.editSchema')"
              :disable="hasBlockingAction"
              @click="openSchemaEditor(detailTable)"
            />
            <q-btn
              dense
              flat
              no-caps
              icon="delete"
              color="negative"
              :label="
                isRowAction(detailTable, 'drop')
                  ? t('adminDatabaseTables.actions.dropping')
                  : t('adminDatabaseTables.actions.drop')
              "
              :loading="isRowAction(detailTable, 'drop')"
              :disable="hasBlockingAction"
              @click="openDropDialog(detailTable)"
            />
          </div>
        </div>
        <AdminDatabaseTableStructure
          v-if="detailTable"
          :columns="detailTable.columns"
          :indexes="detailTable.indexes"
        />
        <div v-else-if="!loading" class="admin-database-tables__detail-missing">
          {{ t("adminDatabaseTables.detail.tableMissing") }}
        </div>
      </div>
    </div>

    <!-- 可视化结构编辑器：不新增路由，桌面大弹层 / 窄屏全屏。 -->
    <AdminDatabaseTableSchemaEditor
      v-model="schemaEditorOpen"
      :table-name="schemaEditorTable"
      :registered="schemaEditorRegistered"
      @applied="onSchemaApplied"
    />
  </q-page>
</template>

<script setup lang="ts">
import { computed, onMounted, reactive, ref, watch } from "vue";
import { Dialog, useQuasar } from "quasar";
import { useI18n } from "vue-i18n";
import { useRoute, useRouter } from "vue-router";
import type { RouteLocationRaw } from "vue-router";

import { ApiAdminDatabaseTable } from "src/network/api/admin/database_table";
import type { AdminDatabaseTableRes } from "src/network/dto/admin/database_table";
import { useKmvApiErrorMessage } from "src/i18n/kmv/useKmvApiErrorMessage";
import { useDatabaseCatalogStore } from "src/stores/databaseCatalog";
import AdminDatabaseTableSchemaEditor from "src/pages/admin/database/AdminDatabaseTableSchemaEditor.vue";
import AdminDatabaseTableStructure from "src/pages/admin/database/AdminDatabaseTableStructure.vue";

/** 同一时刻只允许一个行操作在跑；结构编辑走独立弹层，不占用此状态。 */
type TableAction = "drop";

const { t } = useI18n();
const $q = useQuasar();
const route = useRoute();
const router = useRouter();
const databaseCatalog = useDatabaseCatalogStore();
const { resolveFromError } = useKmvApiErrorMessage();

/** 路由里的目标数据库；只用于校验，不能改变实际连接目标。 */
const scopedDatabaseName = computed(() => {
  const raw = route.params.databaseName;
  const value = Array.isArray(raw) ? raw[0] : raw;
  return typeof value === "string" && value.trim() ? value.trim() : "";
});

/** 配置文件声明的唯一数据库，来自后端目录接口。 */
const configuredDatabaseName = computed(
  () => databaseCatalog.databases[0]?.name ?? "",
);

/**
 * 深链可能带入配置之外的库名：此时只提示，不发起任何数据库请求，
 * 更不能在该库上执行删除或重建。
 */
const isForeignDatabase = computed(
  () =>
    scopedDatabaseName.value !== "" &&
    configuredDatabaseName.value !== "" &&
    scopedDatabaseName.value !== configuredDatabaseName.value,
);

/** 侧边菜单点选具体数据表时携带 `?table=`，用于定位并高亮该表。 */
const highlightedTableName = computed(() => {
  const raw = route.query.table;
  const value = Array.isArray(raw) ? raw[0] : raw;
  return typeof value === "string" ? value.trim() : "";
});

const items = ref<AdminDatabaseTableRes[]>([]);
const loading = ref(false);
const errorText = ref("");
const searchText = ref("");
const actionState = ref<{ tableName: string; action: TableAction } | null>(null);
const schemaEditorOpen = ref(false);
const schemaEditorTable = ref("");
const schemaEditorRegistered = ref(false);
const metadata = reactive({
  dialect: "",
  database_name: "",
  connection_summary: "",
  registered_table_count: 0,
});

const emptyValue = computed(() => t("common.emptyValue"));

const registeredCount = computed(
  () => items.value.filter((row) => row.registered).length,
);
const externalCount = computed(() => items.value.length - registeredCount.value);
const hasBlockingAction = computed(() => Boolean(actionState.value));
const filteredItems = computed(() => {
  const keyword = searchText.value.trim().toLowerCase();
  if (!keyword) {
    return items.value;
  }
  return items.value.filter((row) => {
    const inTable =
      row.table_name.toLowerCase().includes(keyword) ||
      (row.comment || "").toLowerCase().includes(keyword);
    const inColumns = row.columns.some((column) =>
      column.name.toLowerCase().includes(keyword),
    );
    return inTable || inColumns;
  });
});

/** 携带 `?table=` 时进入单表明细模式：只展示该表的列结构与索引。 */
const isTableDetailMode = computed(() => highlightedTableName.value !== "");

/** 当前明细模式聚焦的表；加载未完成或该表已不存在时为 null。 */
const detailTable = computed<AdminDatabaseTableRes | null>(() => {
  const tableName = highlightedTableName.value;
  if (!tableName) {
    return null;
  }
  return items.value.find((row) => row.table_name === tableName) ?? null;
});

function buildActionReq(
  row: AdminDatabaseTableRes,
  confirmTableName: string,
): { table_name: string; confirm_table_name: string } {
  return {
    table_name: row.table_name,
    confirm_table_name: confirmTableName.trim(),
  };
}

function resolveErrorMessage(error: unknown, fallbackKey: string): string {
  const fallback = t(fallbackKey);
  const kmvMessage = resolveFromError(error);
  if (kmvMessage && kmvMessage !== t("api.kmv.fallback")) {
    return kmvMessage;
  }
  return error instanceof Error && error.message ? error.message : fallback;
}

async function loadTables(showSuccess = false) {
  if (isForeignDatabase.value) {
    return;
  }
  loading.value = true;
  errorText.value = "";
  try {
    const res = await ApiAdminDatabaseTable.listTables({});
    items.value = res.items;
    metadata.dialect = res.dialect;
    metadata.database_name = res.database_name;
    metadata.connection_summary = res.connection_summary;
    metadata.registered_table_count = res.registered_table_count;
    if (showSuccess) {
      $q.notify({
        type: "positive",
        message: t("adminDatabaseTables.messages.loaded"),
      });
    }
  } catch (error) {
    errorText.value = resolveErrorMessage(
      error,
      "adminDatabaseTables.errors.loadFailed",
    );
    items.value = [];
    metadata.dialect = "";
    metadata.database_name = "";
    metadata.connection_summary = "";
    metadata.registered_table_count = 0;
  } finally {
    loading.value = false;
  }
}

function goToConfiguredDatabase() {
  const databaseName = configuredDatabaseName.value;
  if (!databaseName) {
    return;
  }
  void router.replace({
    name: "admin-database-tables",
    params: { databaseName },
    query: {},
  });
}

function rowCountText(row: AdminDatabaseTableRes): string {
  if (row.row_count === null) {
    return t("adminDatabaseTables.table.rowUnknown");
  }
  return new Intl.NumberFormat().format(row.row_count);
}

/** 单表页与侧边菜单共用同一条路由，仅用 `?table=` 标明当前表。 */
function tableRoute(tableName: string): RouteLocationRaw {
  return {
    name: "admin-database-tables",
    params: { databaseName: scopedDatabaseName.value },
    query: { table: tableName },
  };
}

/** 从单表页回到列表：只清掉 `?table=`，仍停留在当前数据库范围。 */
function backToList() {
  void router.replace({ query: {} });
}

function isRowAction(row: AdminDatabaseTableRes, action: TableAction): boolean {
  return (
    actionState.value?.tableName === row.table_name &&
    actionState.value.action === action
  );
}

function openDropDialog(row: AdminDatabaseTableRes) {
  Dialog.create({
    title: t("adminDatabaseTables.dialog.dropTitle"),
    message: t("adminDatabaseTables.dialog.dropMessage", {
      tableName: row.table_name,
    }),
    prompt: {
      model: "",
      type: "text",
      label: t("adminDatabaseTables.dialog.confirmLabel"),
    },
    cancel: {
      label: t("common.cancel"),
      flat: true,
      noCaps: true,
    },
    ok: {
      label: t("adminDatabaseTables.actions.drop"),
      color: "negative",
      unelevated: true,
      noCaps: true,
    },
  }).onOk((confirmTableName: string) => {
    void runTableAction("drop", row, confirmTableName);
  });
}

function openSchemaEditor(row: AdminDatabaseTableRes) {
  // 不占用 actionState：编辑器自己管理请求状态与迟到结果隔离。
  schemaEditorTable.value = row.table_name;
  schemaEditorRegistered.value = row.registered;
  schemaEditorOpen.value = true;
}

async function onSchemaApplied() {
  // 结构已变化：重新拉列表刷新只读展示。
  await loadTables();
  // 结构变更可能新建表，抽屉菜单同样需要重新对齐。
  syncDrawerTables();
}

/** 让抽屉菜单重新拉当前库的表名清单；失败不打断页面主流程。 */
function syncDrawerTables(): void {
  const database = scopedDatabaseName.value || configuredDatabaseName.value;
  if (!database) {
    return;
  }
  void databaseCatalog.refreshTables(database).catch(() => undefined);
}

async function runTableAction(
  action: TableAction,
  row: AdminDatabaseTableRes,
  confirmTableName: string,
) {
  if (isForeignDatabase.value) {
    return;
  }
  if (confirmTableName.trim() !== row.table_name) {
    $q.notify({
      type: "negative",
      message: t("adminDatabaseTables.errors.confirmRequired"),
    });
    return;
  }

  actionState.value = { tableName: row.table_name, action };
  try {
    await ApiAdminDatabaseTable.dropTable(buildActionReq(row, confirmTableName));
    $q.notify({
      type: "positive",
      message: t("adminDatabaseTables.messages.dropped"),
    });
    // 明细页删除后该表已不存在：先退回表列表，再刷新权威数据，
    // 避免停留在「未找到该表」的空详情页。
    if (isTableDetailMode.value) {
      backToList();
    }
    await loadTables();
    // 抽屉菜单的表名来自 catalog store 缓存，必须强制重取，
    // 否则已删除的表还会留在菜单里。
    syncDrawerTables();
  } catch (error) {
    $q.notify({
      type: "negative",
      message: resolveErrorMessage(error, "adminDatabaseTables.errors.dropFailed"),
    });
  } finally {
    actionState.value = null;
  }
}

// 目录未就绪时先取权威库名，才能判断深链是否越界。
async function ensureCatalogLoaded() {
  try {
    await databaseCatalog.ensureLoaded();
  } catch {
    // 失败时保持占位，页面仍按后端返回的错误提示。
  }
}

watch(scopedDatabaseName, () => {
  searchText.value = "";
  void loadTables();
});

// 权威库名到位后重新判定越界状态：合法则加载，非法则停留在提示。
watch(configuredDatabaseName, () => {
  void loadTables();
});

onMounted(() => {
  void ensureCatalogLoaded();
  void loadTables();
});
</script>

<style scoped>
.admin-database-tables-page {
  --admin-db-card-bg: var(--bg-card);
  --admin-db-border: var(--border);
  --admin-db-muted: var(--workspace-text-muted);
  --admin-db-soft: var(--bg-secondary);
}

.admin-database-tables__shell {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.admin-database-tables__header,
.admin-database-tables__toolbar,
.admin-database-tables__summary-line,
.admin-database-tables__stats {
  display: flex;
  align-items: center;
}

.admin-database-tables__header {
  justify-content: space-between;
  gap: 16px;
}

.admin-database-tables__header-copy {
  min-width: 0;
}

.admin-database-tables__title {
  margin: 8px 0 4px;
}

.admin-database-tables__subtitle {
  margin: 0;
}

.admin-database-tables__card,
.admin-database-tables__table-card {
  position: relative;
  border-radius: 8px;
  background: var(--admin-db-card-bg);
}

.admin-database-tables__card {
  padding: 16px;
}

.admin-database-tables__section-title {
  margin-bottom: 12px;
}

.admin-database-tables__summary {
  display: flex;
  flex-direction: column;
  gap: 10px;
  min-width: 0;
}

.admin-database-tables__summary-line {
  justify-content: space-between;
  gap: 12px;
  min-width: 0;
  color: var(--text-secondary);
}

.admin-database-tables__summary-line strong {
  min-width: 0;
  color: var(--text-primary);
  overflow-wrap: anywhere;
  text-align: right;
}

.admin-database-tables__stats {
  justify-content: space-between;
  gap: 10px;
  margin-top: 16px;
  flex-wrap: wrap;
}

.admin-database-tables__stat {
  flex: 1;
  min-width: 0;
  padding: 12px;
  border: 1px solid var(--admin-db-border);
  border-radius: 8px;
  background: var(--admin-db-soft);
}

.admin-database-tables__stat span {
  display: block;
  color: var(--admin-db-muted);
}

.admin-database-tables__stat strong {
  display: block;
  margin-top: 4px;
  color: var(--text-primary);
  font-size: var(--spa-font-size-card-value);
  line-height: 1.2;
}

.admin-database-tables__banner {
  margin: 0;
}

.admin-database-tables__banner-body {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 12px;
}

.admin-database-tables__toolbar {
  justify-content: space-between;
  gap: 12px;
  flex-wrap: wrap;
}

.admin-database-tables__search {
  width: min(520px, 100%);
}

.admin-database-tables__table-card {
  border: 1px solid var(--admin-db-border);
  overflow: hidden;
}

.admin-database-tables__table-scroll {
  overflow-x: auto;
}

.admin-database-tables__table {
  width: 100%;
  min-width: 820px;
}

.admin-database-tables__table-link {
  color: var(--accent-1);
  font-weight: 600;
  text-decoration: none;
  border-radius: 4px;
}

.admin-database-tables__table-link:hover,
.admin-database-tables__table-link:focus-visible {
  text-decoration: underline;
}

.admin-database-tables__table-link:focus-visible {
  outline: 2px solid color-mix(in srgb, var(--accent-1) 50%, transparent);
  outline-offset: 2px;
}

.admin-database-tables__empty-cell {
  text-align: center;
  color: var(--admin-db-muted);
}

.admin-database-tables__detail-panel {
  position: relative;
  display: flex;
  flex-direction: column;
  gap: 12px;
  min-height: 120px;
}

.admin-database-tables__detail-toolbar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
}

.admin-database-tables__detail-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-left: auto;
}

.admin-database-tables__detail-missing {
  padding: 24px 0;
  color: var(--admin-db-muted);
  text-align: center;
}

.admin-database-tables__table-footer {
  padding: 10px 14px;
  color: var(--admin-db-muted);
  border-top: 1px solid var(--admin-db-border);
  text-align: right;
}

:deep(.q-field--outlined .q-field__control) {
  border-radius: 8px;
}

@media (max-width: 720px) {
  .admin-database-tables__toolbar,
  .admin-database-tables__stats {
    align-items: stretch;
    flex-direction: column;
  }
}
</style>