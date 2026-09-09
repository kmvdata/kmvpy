<template>
  <q-page class="spa-page admin-database-tables-page page-section">
    <div class="spa-shell spa-shell--wide admin-database-tables__shell">
      <div class="admin-database-tables__header">
        <div>
          <div class="admin-database-tables__badge">
            {{ t("adminDatabaseTables.badge") }}
          </div>
          <h2 class="spa-page-title admin-database-tables__title">
            {{ t("adminDatabaseTables.title") }}
          </h2>
          <p class="spa-page-subtitle admin-database-tables__subtitle">
            {{ t("adminDatabaseTables.subtitle") }}
          </p>
        </div>
        <div class="admin-database-tables__header-actions">
          <q-btn
            flat
            no-caps
            color="warning"
            icon="sync"
            :label="
              initializingAll
                ? t('adminDatabaseTables.actions.initializingAll')
                : t('adminDatabaseTables.actions.initializeAll')
            "
            :loading="initializingAll"
            :disable="loading || hasBlockingAction"
            @click="openInitializeAllDialog"
          />
          <q-btn
            flat
            no-caps
            icon="restart_alt"
            :label="t('adminDatabaseTables.actions.reset')"
            :disable="loading || hasBlockingAction"
            @click="resetConnection"
          />
          <q-btn
            unelevated
            no-caps
            color="primary"
            icon="storage"
            :label="
              loading
                ? t('adminDatabaseTables.actions.connecting')
                : t('adminDatabaseTables.actions.connect')
            "
            :loading="loading"
            :disable="hasBlockingAction"
            @click="loadTables(true)"
          />
        </div>
      </div>

      <div class="admin-database-tables__top-grid">
        <q-card flat bordered class="spa-card admin-database-tables__card">
          <div class="spa-section-title admin-database-tables__section-title">
            {{ t("adminDatabaseTables.connection.title") }}
          </div>

          <q-btn-toggle
            v-model="form.mode"
            class="admin-database-tables__mode-toggle"
            spread
            no-caps
            unelevated
            toggle-color="primary"
            :options="connectionModeOptions"
          />

          <div
            v-if="form.mode === 'custom'"
            class="admin-database-tables__connection-grid"
          >
            <q-select
              v-model="form.driver"
              dense
              outlined
              emit-value
              map-options
              :options="driverOptions"
              :label="t('adminDatabaseTables.connection.driver')"
              @update:model-value="onDriverChange"
            />
            <q-input
              v-if="form.driver !== 'sqlite'"
              v-model="form.host"
              dense
              outlined
              autocomplete="off"
              :label="t('adminDatabaseTables.connection.host')"
            />
            <q-input
              v-if="form.driver !== 'sqlite'"
              v-model.number="form.port"
              dense
              outlined
              type="number"
              :label="t('adminDatabaseTables.connection.port')"
            />
            <q-input
              v-if="form.driver !== 'sqlite'"
              v-model="form.database"
              dense
              outlined
              autocomplete="off"
              :label="t('adminDatabaseTables.connection.database')"
            />
            <q-input
              v-if="form.driver !== 'sqlite'"
              v-model="form.username"
              dense
              outlined
              autocomplete="off"
              :label="t('adminDatabaseTables.connection.username')"
            />
            <q-input
              v-if="form.driver !== 'sqlite'"
              v-model="form.password"
              dense
              outlined
              type="password"
              autocomplete="new-password"
              :label="t('adminDatabaseTables.connection.password')"
            />
            <q-input
              v-if="form.driver === 'sqlite'"
              v-model="form.sqlite_path"
              dense
              outlined
              autocomplete="off"
              class="admin-database-tables__field-wide"
              :label="t('adminDatabaseTables.connection.sqlitePath')"
            />
            <q-input
              v-model.number="form.timeout"
              dense
              outlined
              type="number"
              :label="t('adminDatabaseTables.connection.timeout')"
            />
            <q-toggle
              v-if="form.driver === 'postgresql'"
              v-model="form.ssl"
              dense
              :label="t('adminDatabaseTables.connection.ssl')"
            />
            <q-input
              v-if="form.driver === 'postgresql'"
              v-model="form.options"
              dense
              outlined
              class="admin-database-tables__field-wide"
              autocomplete="off"
              :label="t('adminDatabaseTables.connection.options')"
            />
          </div>
        </q-card>

        <q-card flat bordered class="spa-card admin-database-tables__card">
          <div class="spa-section-title admin-database-tables__section-title">
            {{ t("adminDatabaseTables.connection.summary") }}
          </div>

          <div class="admin-database-tables__summary">
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
      </div>

      <q-banner
        v-if="errorText"
        rounded
        class="spa-inline-alert--error admin-database-tables__banner"
      >
        {{ errorText }}
      </q-banner>

      <div class="admin-database-tables__toolbar">
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

      <div class="admin-database-tables__table-card">
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
              <template v-for="row in filteredItems" :key="row.table_name">
                <tr>
                  <td>
                    <div class="admin-database-tables__row-main mono">
                      {{ row.table_name }}
                    </div>
                    <div class="admin-database-tables__row-meta">
                      {{ row.comment || emptyValue }}
                    </div>
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
                    <q-btn
                      dense
                      flat
                      no-caps
                      icon="view_column"
                      :label="t('adminDatabaseTables.actions.columns')"
                      @click="toggleColumns(row)"
                    />
                    <q-btn
                      dense
                      flat
                      no-caps
                      icon="auto_fix_high"
                      color="primary"
                      :label="
                        isRowAction(row, 'regenerate')
                          ? t('adminDatabaseTables.actions.regenerating')
                          : t('adminDatabaseTables.actions.regenerate')
                      "
                      :loading="isRowAction(row, 'regenerate')"
                      :disable="!row.registered || hasBlockingAction"
                      @click="openRegenerateDialog(row)"
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
                <tr v-if="expandedTableName === row.table_name">
                  <td colspan="5" class="admin-database-tables__columns-cell">
                    <div class="admin-database-tables__columns-grid">
                      <div
                        v-for="column in row.columns"
                        :key="`${row.table_name}:${column.name}`"
                        class="admin-database-tables__column"
                      >
                        <div class="admin-database-tables__column-name mono">
                          {{ column.name }}
                        </div>
                        <div class="admin-database-tables__column-type mono">
                          {{ column.type }}
                        </div>
                        <div class="admin-database-tables__column-tags">
                          <q-chip v-if="column.primary_key" dense square>
                            {{ t("adminDatabaseTables.table.primaryKey") }}
                          </q-chip>
                          <q-chip v-if="column.indexed" dense square>
                            {{ t("adminDatabaseTables.table.indexed") }}
                          </q-chip>
                          <q-chip v-if="column.unique" dense square>
                            {{ t("adminDatabaseTables.table.unique") }}
                          </q-chip>
                          <q-chip dense square>
                            {{
                              column.nullable
                                ? t("adminDatabaseTables.table.nullable")
                                : t("adminDatabaseTables.table.notNull")
                            }}
                          </q-chip>
                        </div>
                      </div>
                    </div>
                  </td>
                </tr>
              </template>
            </tbody>
          </table>
        </div>
        <div class="admin-database-tables__table-footer mono">
          {{ t("adminDatabaseTables.table.total", { total: filteredItems.length }) }}
        </div>
      </div>
    </div>
  </q-page>
</template>

<script setup lang="ts">
import { computed, onMounted, reactive, ref } from "vue";
import { Dialog, useQuasar } from "quasar";
import { useI18n } from "vue-i18n";

import { ApiAdminDatabaseTable } from "src/network/api/admin/database_table";
import type {
  AdminDatabaseConnectionReq,
  AdminDatabaseTableActionReq,
  AdminDatabaseTableRes,
  DatabaseConnectionMode,
  DatabaseDriver,
} from "src/network/dto/admin/database_table";
import { useKmvApiErrorMessage } from "src/i18n/kmv/useKmvApiErrorMessage";

interface ConnectionForm {
  mode: DatabaseConnectionMode;
  driver: DatabaseDriver;
  host: string;
  port: number | null;
  database: string;
  username: string;
  password: string;
  sqlite_path: string;
  ssl: boolean;
  options: string;
  timeout: number;
}

type TableAction = "drop" | "regenerate";

const { t } = useI18n();
const $q = useQuasar();
const { resolveFromError } = useKmvApiErrorMessage();

const defaultForm = (): ConnectionForm => ({
  mode: "default",
  driver: "postgresql",
  host: "localhost",
  port: 5432,
  database: "",
  username: "",
  password: "",
  sqlite_path: "",
  ssl: false,
  options: "",
  timeout: 30,
});

const form = reactive<ConnectionForm>(defaultForm());
const items = ref<AdminDatabaseTableRes[]>([]);
const loading = ref(false);
const initializingAll = ref(false);
const errorText = ref("");
const searchText = ref("");
const expandedTableName = ref<string | null>(null);
const actionState = ref<{ tableName: string; action: TableAction } | null>(null);
const metadata = reactive({
  dialect: "",
  connection_summary: "",
  registered_table_count: 0,
});

const emptyValue = computed(() => t("common.emptyValue"));
const connectionModeOptions = computed(() => [
  {
    label: t("adminDatabaseTables.connection.defaultMode"),
    value: "default",
  },
  {
    label: t("adminDatabaseTables.connection.customMode"),
    value: "custom",
  },
]);
const driverOptions = computed(() => [
  { label: "PostgreSQL", value: "postgresql" },
  { label: "MySQL", value: "mysql" },
  { label: "SQLite", value: "sqlite" },
]);

const registeredCount = computed(
  () => items.value.filter((row) => row.registered).length,
);
const externalCount = computed(() => items.value.length - registeredCount.value);
const hasBlockingAction = computed(
  () => Boolean(actionState.value) || initializingAll.value,
);
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

function trimOrNull(value: string): string | null {
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

function buildConnectionReq(): AdminDatabaseConnectionReq {
  if (form.mode === "default") {
    return {
      mode: "default",
      driver: null,
      host: null,
      port: null,
      database: null,
      username: null,
      password: null,
      sqlite_path: null,
      ssl: false,
      options: null,
      timeout: 30,
    };
  }

  return {
    mode: "custom",
    driver: form.driver,
    host: form.driver === "sqlite" ? null : trimOrNull(form.host),
    port: form.driver === "sqlite" ? null : form.port,
    database: form.driver === "sqlite" ? null : trimOrNull(form.database),
    username: form.driver === "sqlite" ? null : trimOrNull(form.username),
    password: form.driver === "sqlite" ? null : trimOrNull(form.password),
    sqlite_path:
      form.driver === "sqlite" ? trimOrNull(form.sqlite_path) : null,
    ssl: form.driver === "postgresql" ? form.ssl : false,
    options: form.driver === "postgresql" ? trimOrNull(form.options) : null,
    timeout: Number.isFinite(form.timeout) && form.timeout > 0 ? form.timeout : 30,
  };
}

function buildActionReq(
  row: AdminDatabaseTableRes,
  confirmTableName: string,
): AdminDatabaseTableActionReq {
  return {
    connection: buildConnectionReq(),
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
  loading.value = true;
  errorText.value = "";
  try {
    const res = await ApiAdminDatabaseTable.listTables({
      connection: buildConnectionReq(),
    });
    items.value = res.items;
    metadata.dialect = res.dialect;
    metadata.connection_summary = res.connection_summary;
    metadata.registered_table_count = res.registered_table_count;
    expandedTableName.value = null;
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
    metadata.connection_summary = "";
    metadata.registered_table_count = 0;
  } finally {
    loading.value = false;
  }
}

function resetConnection() {
  Object.assign(form, defaultForm());
  searchText.value = "";
  void loadTables();
}

function onDriverChange(value: DatabaseDriver | null) {
  if (value === "postgresql") {
    form.port = 5432;
  } else if (value === "mysql") {
    form.port = 3306;
  } else {
    form.port = null;
  }
}

function rowCountText(row: AdminDatabaseTableRes): string {
  if (row.row_count === null) {
    return t("adminDatabaseTables.table.rowUnknown");
  }
  return new Intl.NumberFormat().format(row.row_count);
}

function toggleColumns(row: AdminDatabaseTableRes) {
  expandedTableName.value =
    expandedTableName.value === row.table_name ? null : row.table_name;
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

function openRegenerateDialog(row: AdminDatabaseTableRes) {
  Dialog.create({
    title: t("adminDatabaseTables.dialog.regenerateTitle"),
    message: t("adminDatabaseTables.dialog.regenerateMessage", {
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
      label: t("adminDatabaseTables.actions.regenerate"),
      color: "primary",
      unelevated: true,
      noCaps: true,
    },
  }).onOk((confirmTableName: string) => {
    void runTableAction("regenerate", row, confirmTableName);
  });
}

const INIT_ALL_CONFIRM_TEXT = "INIT_ALL_TABLES";

function openInitializeAllDialog() {
  Dialog.create({
    title: t("adminDatabaseTables.dialog.initializeAllTitle"),
    message: t("adminDatabaseTables.dialog.initializeAllMessage", {
      confirmText: INIT_ALL_CONFIRM_TEXT,
    }),
    prompt: {
      model: "",
      type: "text",
      label: t("adminDatabaseTables.dialog.initializeAllConfirmLabel"),
    },
    cancel: {
      label: t("common.cancel"),
      flat: true,
      noCaps: true,
    },
    ok: {
      label: t("adminDatabaseTables.actions.initializeAll"),
      color: "warning",
      unelevated: true,
      noCaps: true,
    },
  }).onOk((confirmText: string) => {
    void runInitializeAllTables(confirmText);
  });
}

async function runInitializeAllTables(confirmText: string) {
  if (confirmText.trim() !== INIT_ALL_CONFIRM_TEXT) {
    $q.notify({
      type: "negative",
      message: t("adminDatabaseTables.errors.initializeAllConfirmRequired"),
    });
    return;
  }

  initializingAll.value = true;
  try {
    const res = await ApiAdminDatabaseTable.initializeAllTables({
      confirm_text: confirmText.trim(),
    });
    $q.notify({
      type: "positive",
      message: t("adminDatabaseTables.messages.initializedAll", {
        count: res.initialized_table_count,
      }),
    });
    await loadTables();
  } catch (error) {
    $q.notify({
      type: "negative",
      message: resolveErrorMessage(
        error,
        "adminDatabaseTables.errors.initializeAllFailed",
      ),
    });
  } finally {
    initializingAll.value = false;
  }
}

async function runTableAction(
  action: TableAction,
  row: AdminDatabaseTableRes,
  confirmTableName: string,
) {
  if (confirmTableName.trim() !== row.table_name) {
    $q.notify({
      type: "negative",
      message: t("adminDatabaseTables.errors.confirmRequired"),
    });
    return;
  }

  actionState.value = { tableName: row.table_name, action };
  try {
    if (action === "drop") {
      await ApiAdminDatabaseTable.dropTable(buildActionReq(row, confirmTableName));
      $q.notify({
        type: "positive",
        message: t("adminDatabaseTables.messages.dropped"),
      });
    } else {
      await ApiAdminDatabaseTable.regenerateTable(
        buildActionReq(row, confirmTableName),
      );
      $q.notify({
        type: "positive",
        message: t("adminDatabaseTables.messages.regenerated"),
      });
    }
    await loadTables();
  } catch (error) {
    $q.notify({
      type: "negative",
      message: resolveErrorMessage(
        error,
        action === "drop"
          ? "adminDatabaseTables.errors.dropFailed"
          : "adminDatabaseTables.errors.regenerateFailed",
      ),
    });
  } finally {
    actionState.value = null;
  }
}

onMounted(() => {
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
.admin-database-tables__stats,
.admin-database-tables__column-tags {
  display: flex;
  align-items: center;
}

.admin-database-tables__header {
  justify-content: space-between;
  gap: 16px;
}

.admin-database-tables__header-actions {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}

.admin-database-tables__badge {
  display: inline-flex;
  align-items: center;
  min-height: 24px;
  padding: 0 10px;
  border: 1px solid var(--admin-db-border);
  border-radius: 8px;
  color: var(--text-secondary);
  background: var(--admin-db-soft);
}

.admin-database-tables__title {
  margin: 8px 0 4px;
}

.admin-database-tables__subtitle {
  margin: 0;
}

.admin-database-tables__top-grid {
  display: grid;
  grid-template-columns: minmax(0, 1.4fr) minmax(300px, 0.8fr);
  gap: 16px;
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

.admin-database-tables__mode-toggle {
  width: 100%;
}

.admin-database-tables__connection-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 12px;
  margin-top: 14px;
}

.admin-database-tables__field-wide {
  grid-column: span 2;
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
}

.admin-database-tables__stat {
  flex: 1;
  min-width: 0;
  padding: 12px;
  border: 1px solid var(--admin-db-border);
  border-radius: 8px;
  background: var(--admin-db-soft);
}

.admin-database-tables__stat span,
.admin-database-tables__row-meta,
.admin-database-tables__column-type {
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

.admin-database-tables__row-main,
.admin-database-tables__column-name {
  color: var(--text-primary);
  font-weight: 600;
}

.admin-database-tables__empty-cell {
  text-align: center;
  color: var(--admin-db-muted);
}

.admin-database-tables__columns-cell {
  background: var(--admin-db-soft);
}

.admin-database-tables__columns-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 10px;
  padding: 12px 0;
}

.admin-database-tables__column {
  min-width: 0;
  padding: 10px;
  border: 1px solid var(--admin-db-border);
  border-radius: 8px;
  background: var(--admin-db-card-bg);
}

.admin-database-tables__column-tags {
  flex-wrap: wrap;
  gap: 4px;
  margin-top: 8px;
}

.admin-database-tables__table-footer {
  padding: 10px 14px;
  color: var(--admin-db-muted);
  border-top: 1px solid var(--admin-db-border);
  text-align: right;
}

:deep(.admin-database-tables__mode-toggle .q-btn) {
  min-height: 36px;
}

:deep(.q-field--outlined .q-field__control) {
  border-radius: 8px;
}

@media (max-width: 1100px) {
  .admin-database-tables__top-grid,
  .admin-database-tables__connection-grid {
    grid-template-columns: 1fr;
  }

  .admin-database-tables__field-wide {
    grid-column: span 1;
  }

  .admin-database-tables__columns-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}

@media (max-width: 720px) {
  .admin-database-tables__header,
  .admin-database-tables__toolbar,
  .admin-database-tables__stats {
    align-items: stretch;
    flex-direction: column;
  }

  .admin-database-tables__header-actions {
    width: 100%;
  }

  .admin-database-tables__header-actions :deep(.q-btn) {
    flex: 1;
  }

  .admin-database-tables__columns-grid {
    grid-template-columns: 1fr;
  }
}
</style>
