<template>
  <q-dialog
    :model-value="modelValue"
    :maximized="isNarrow"
    persistent
    @update:model-value="onVisibleChange"
  >
    <q-card class="db-schema-editor">
      <q-card-section class="db-schema-editor__head">
        <div class="db-schema-editor__head-copy">
          <h2 class="db-schema-editor__title">
            {{ t("adminDatabaseTables.schemaEditor.title") }}
            <span class="mono db-schema-editor__table">{{ tableName }}</span>
          </h2>
          <p class="db-schema-editor__meta mono">
            {{ t("adminDatabaseTables.schemaEditor.dialect") }}:
            {{ schema?.dialect ?? emptyValue }} ·
            {{ t("adminDatabaseTables.schemaEditor.rows") }}:
            {{ rowCountText }}
          </p>
        </div>
        <div class="db-schema-editor__head-actions">
          <q-chip
            dense
            square
            color="status-warning-bg"
            text-color="main"
            :label="
              t('adminDatabaseTables.schemaEditor.badge.pendingChanges', {
                count: draft.dirtyCount.value,
              })
            "
          />
          <q-btn
            flat
            dense
            round
            icon="close"
            :aria-label="t('adminDatabaseTables.schemaEditor.actions.cancel')"
            @click="close"
          />
        </div>
      </q-card-section>

      <q-separator />

      <q-banner
        v-if="loadError"
        rounded
        class="db-schema-editor__banner db-schema-editor__banner--error"
      >
        <div class="db-schema-editor__banner-body">
          <span>{{ loadError }}</span>
          <q-btn
            flat
            dense
            no-caps
            color="primary"
            :label="t('adminDatabaseTables.schemaEditor.actions.reload')"
            :loading="loading"
            @click="loadSchema()"
          />
        </div>
      </q-banner>

      <q-inner-loading :showing="loading" color="primary" />

      <q-card-section class="db-schema-editor__body">
        <div class="db-schema-editor__main">
          <q-tabs v-model="activeTab" dense align="left" class="db-schema-editor__tabs">
            <q-tab
              name="columns"
              icon="view_column"
              :label="t('adminDatabaseTables.schemaEditor.tabs.columns')"
            />
            <q-tab
              name="indexes"
              icon="account_tree"
              :label="t('adminDatabaseTables.schemaEditor.tabs.indexes')"
            />
          </q-tabs>

          <q-tab-panels v-model="activeTab" animated class="db-schema-editor__panels">
            <q-tab-panel name="columns" class="db-schema-editor__panel">
              <AdminDatabaseTableColumnEditor
                v-if="schema"
                :columns="draft.columns.value"
                :can-suggest="schema.registered"
                :has-suggestion="schema.orm_suggestion !== null"
                @add="draft.addColumn()"
                @suggest="useOrmSuggestion"
                @rename="onRenameColumn"
                @remove="draft.removeAddedColumn($event)"
                @restore="draft.restoreColumn($event)"
                @type-change="onTypeChange"
                @type-arg-change="onTypeArgChange"
                @field-change="onFieldChange"
              />
            </q-tab-panel>

            <q-tab-panel name="indexes" class="db-schema-editor__panel">
              <AdminDatabaseTableIndexEditor
                v-if="schema"
                :indexes="draft.indexes.value"
                :columns="draft.columns.value"
                :primary-index="primaryIndex"
                @add="onAddIndex"
                @remove="draft.removeIndex($event)"
                @restore="draft.restoreIndex($event)"
                @name-change="onIndexNameChange"
                @columns-change="onIndexColumnsChange"
                @unique-change="onIndexUniqueChange"
              />
            </q-tab-panel>
          </q-tab-panels>
        </div>
      </q-card-section>

      <q-card-actions class="db-schema-editor__actions">
        <q-btn
          flat
          no-caps
          :label="t('adminDatabaseTables.schemaEditor.actions.cancel')"
          @click="close"
        />
        <div class="db-schema-editor__backup">
          <q-checkbox
            v-model="backupEnabled"
            dense
            :label="t('adminDatabaseTables.schemaEditor.confirm.backupLabel')"
          />
          <q-icon
            name="info_outline"
            size="14px"
            class="db-schema-editor__backup-info"
            tabindex="0"
            :aria-label="t('adminDatabaseTables.schemaEditor.confirm.backupHint')"
          >
            <q-tooltip>
              {{ t("adminDatabaseTables.schemaEditor.confirm.backupHint") }}
            </q-tooltip>
          </q-icon>
        </div>
        <q-space />
        <q-btn
          unelevated
          no-caps
          color="primary"
          icon="play_arrow"
          :label="t('adminDatabaseTables.schemaEditor.actions.execute')"
          :loading="applyLoading"
          :disable="draft.dirtyCount.value === 0 || previewLoading"
          @click="openConfirm"
        />
      </q-card-actions>
    </q-card>
  </q-dialog>

  <!-- 二次确认：输入表名 + 逐项勾选 confirm 级风险 + 备份开关 -->
  <q-dialog v-model="confirmOpen" persistent>
    <q-card class="db-schema-confirm">
      <q-card-section>
        <h3 class="db-schema-confirm__title">
          {{ t("adminDatabaseTables.schemaEditor.confirm.title") }}
        </h3>
        <p class="db-schema-confirm__message">
          {{ t("adminDatabaseTables.schemaEditor.confirm.message", { table: tableName }) }}
        </p>
      </q-card-section>

      <q-card-section v-if="confirmRisks.length > 0" class="db-schema-confirm__risks">
        <p class="db-schema-confirm__risks-title">
          {{ t("adminDatabaseTables.schemaEditor.risk.acknowledge") }}
        </p>
        <q-checkbox
          v-for="risk in confirmRisks"
          :key="risk.code"
          :model-value="acknowledged.includes(risk.code)"
          dense
          :label="riskText(risk)"
          @update:model-value="toggleAck(risk.code, $event)"
        />
      </q-card-section>

      <q-card-section>
        <q-input
          v-model="confirmTableName"
          dense
          outlined
          :label="t('adminDatabaseTables.dialog.confirmLabel')"
          :error="confirmTableName.trim() !== tableName && confirmTableName.length > 0"
        />
      </q-card-section>

      <!-- 直接展示本次变更将要执行的原始 SQL，避免不看语句就确认。 -->
      <q-card-section v-if="confirmSqlText.length > 0" class="db-schema-confirm__sql">
        <q-card flat bordered class="db-schema-confirm__sql-card">
          <q-card-section class="db-schema-confirm__sql-head">
            <span class="db-schema-confirm__sql-title">
              {{ t("adminDatabaseTables.schemaEditor.confirm.sqlPreview") }}
            </span>
            <q-chip
              dense
              square
              color="surface-muted"
              text-color="main"
              :label="preview?.statements.length ?? 0"
            />
          </q-card-section>
          <q-separator />
          <q-card-section class="db-schema-confirm__sql-body">
            <pre
              class="db-schema-confirm__sql-code mono"
              tabindex="0"
              :aria-label="t('adminDatabaseTables.schemaEditor.confirm.sqlPreview')"
            >{{ confirmSqlText }}</pre>
          </q-card-section>
        </q-card>
      </q-card-section>

      <q-card-actions align="right">
        <q-btn
          flat
          no-caps
          :label="t('adminDatabaseTables.schemaEditor.actions.cancel')"
          @click="confirmOpen = false"
        />
        <q-btn
          unelevated
          no-caps
          color="primary"
          :label="t('adminDatabaseTables.schemaEditor.confirm.confirmLabel')"
          :loading="applyLoading"
          :disable="!canApply"
          @click="runApply"
        />
      </q-card-actions>
    </q-card>
  </q-dialog>

  <!-- 手动处理视图 -->
  <q-dialog v-model="manualOpen" persistent>
    <q-card class="db-schema-manual-dialog">
      <q-card-section class="db-schema-manual-dialog__head">
        <h3 class="db-schema-manual-dialog__title">
          {{ t("adminDatabaseTables.schemaEditor.manual.title") }}
        </h3>
        <q-btn
          flat
          dense
          round
          icon="close"
          :aria-label="t('adminDatabaseTables.schemaEditor.actions.cancel')"
          @click="manualOpen = false"
        />
      </q-card-section>
      <q-card-section v-if="preview?.manual_plan">
        <AdminDatabaseTableManualPlan
          :plan="preview.manual_plan"
          :rechecking="previewLoading"
          :recheck-result="recheckResult"
          @recheck="recheckManual"
        />
      </q-card-section>
    </q-card>
  </q-dialog>

  <!-- 执行结果 -->
  <q-dialog v-model="resultOpen">
    <q-card class="db-schema-result">
      <q-card-section>
        <h3 class="db-schema-result__title">
          {{
            lastResult?.success
              ? t("adminDatabaseTables.schemaEditor.result.success")
              : t("adminDatabaseTables.schemaEditor.result.failed")
          }}
        </h3>
        <p v-if="lastResult?.success" class="db-schema-result__line">
          {{ t("adminDatabaseTables.schemaEditor.result.statements", {
            count: lastResult.executed_statements.length,
            duration: lastResult.duration_ms,
          }) }}
        </p>
        <p
          v-if="lastResult?.backup_table"
          class="db-schema-result__line mono"
        >
          {{ t("adminDatabaseTables.schemaEditor.result.backupTable") }}:
          {{ lastResult.backup_table }}
        </p>
        <p v-if="lastError" class="db-schema-result__error">{{ lastError }}</p>
        <pre
          v-if="lastResult?.executed_statements.length"
          class="db-schema-result__code mono"
        >{{ lastResult.executed_statements.join("\n") }}</pre>
      </q-card-section>
      <q-card-actions align="right">
        <q-btn
          unelevated
          no-caps
          color="primary"
          :label="t('adminDatabaseTables.schemaEditor.actions.cancel')"
          @click="resultOpen = false"
        />
      </q-card-actions>
    </q-card>
  </q-dialog>
</template>

<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useQuasar } from "quasar";
import { useI18n } from "vue-i18n";

import { ApiAdminDatabaseTable } from "src/network/api/admin/database_table";
import type {
  AdminDatabaseTableSchemaApplyRes,
  AdminDatabaseTableSchemaColumnType,
  AdminDatabaseTableSchemaPreviewRes,
  AdminDatabaseTableSchemaRes,
  AdminDatabaseTableSchemaRiskItemRes,
} from "src/network/dto/admin/database_table_schema";
import { useDatabaseTableSchemaDraft } from "src/composables/useDatabaseTableSchemaDraft";
import type {
  SchemaColumnDraft,
  SchemaIndexDraft,
} from "src/composables/useDatabaseTableSchemaDraft";
import { useKmvApiErrorMessage } from "src/i18n/kmv/useKmvApiErrorMessage";
import AdminDatabaseTableColumnEditor from "src/pages/admin/database/AdminDatabaseTableColumnEditor.vue";
import AdminDatabaseTableIndexEditor from "src/pages/admin/database/AdminDatabaseTableIndexEditor.vue";
import AdminDatabaseTableManualPlan from "src/pages/admin/database/AdminDatabaseTableManualPlan.vue";
import type { ManualRecheckResult } from "src/pages/admin/database/database_table_schema_view";

const props = defineProps<{
  modelValue: boolean;
  tableName: string;
  /** 打开时是否已有注册模型（决定是否显示 ORM 建议）。 */
  registered: boolean;
}>();

const emit = defineEmits<{
  "update:modelValue": [value: boolean];
  applied: [tableName: string];
}>();

const { t } = useI18n();
const $q = useQuasar();
const { resolveFromError } = useKmvApiErrorMessage();

const draft = useDatabaseTableSchemaDraft();

const activeTab = ref<"columns" | "indexes">("columns");
const schema = ref<AdminDatabaseTableSchemaRes | null>(null);
const preview = ref<AdminDatabaseTableSchemaPreviewRes | null>(null);
const loading = ref(false);
const previewLoading = ref(false);
const applyLoading = ref(false);
const loadError = ref("");
const backupEnabled = ref(true);
const confirmOpen = ref(false);
const manualOpen = ref(false);
const resultOpen = ref(false);
const confirmTableName = ref("");
const acknowledged = ref<string[]>([]);
const lastResult = ref<AdminDatabaseTableSchemaApplyRes | null>(null);
const lastError = ref("");
const recheckResult = ref<ManualRecheckResult | null>(null);

/**
 * 请求序号：打开弹层、重新加载、重新检测都会自增。
 * 迟到响应比对序号后直接丢弃，避免旧结果覆盖新草稿。
 */
let describeSeq = 0;
let previewSeq = 0;

const isNarrow = computed(() => $q.screen.lt.md);
const emptyValue = computed(() => t("common.emptyValue"));

const rowCountText = computed(() => {
  const count = schema.value?.row_count;
  if (count === null || count === undefined) {
    return t("adminDatabaseTables.table.rowUnknown");
  }
  return new Intl.NumberFormat().format(count);
});

/** 主键索引只读展示：由主键列推导，不允许编辑。 */
const primaryIndex = computed(() => {
  const columns = (schema.value?.indexes ?? []).find((index) => index.primary);
  if (!columns) {
    return null;
  }
  return { name: columns.name, columns: [...columns.columns] };
});

const confirmRisks = computed(() =>
  (preview.value?.risk_items ?? []).filter((item) => item.level === "confirm"),
);

/** 确认框里按执行顺序拼接全部语句，供用户在执行前逐条核对。 */
const confirmSqlText = computed(() =>
  (preview.value?.statements ?? [])
    .map((statement) =>
      statement.sql.endsWith(";") ? statement.sql : `${statement.sql};`,
    )
    .join("\n"),
);

const canApply = computed(() => {
  if (confirmTableName.value.trim() !== props.tableName) {
    return false;
  }
  return confirmRisks.value.every((risk) => acknowledged.value.includes(risk.code));
});

function riskText(item: AdminDatabaseTableSchemaRiskItemRes): string {
  const key = `adminDatabaseTables.schemaEditor.riskCodes.${item.code}`;
  const label = t(key);
  const base = label === key ? item.code : label;
  if (item.affected_rows === null) {
    return base;
  }
  return t("adminDatabaseTables.schemaEditor.risk.acknowledgeItem", {
    label: base,
    rows: new Intl.NumberFormat().format(item.affected_rows),
  });
}

function toggleAck(code: string, value: unknown): void {
  if (value) {
    if (!acknowledged.value.includes(code)) {
      acknowledged.value.push(code);
    }
    return;
  }
  acknowledged.value = acknowledged.value.filter((item) => item !== code);
}

function resolveMessage(error: unknown, fallbackKey: string): string {
  const fallback = t(fallbackKey);
  const kmvMessage = resolveFromError(error);
  if (kmvMessage && kmvMessage !== t("api.kmv.fallback")) {
    return kmvMessage;
  }
  return error instanceof Error && error.message ? error.message : fallback;
}

async function loadSchema(): Promise<void> {
  describeSeq += 1;
  const current = describeSeq;
  loading.value = true;
  loadError.value = "";
  preview.value = null;
  acknowledged.value = [];
  try {
    const result = await ApiAdminDatabaseTable.describeSchema({
      table_name: props.tableName,
    });
    if (current !== describeSeq) {
      return;
    }
    schema.value = result;
    draft.reset(result.columns, result.indexes);
  } catch (error) {
    if (current !== describeSeq) {
      return;
    }
    schema.value = null;
    loadError.value = resolveMessage(
      error,
      "adminDatabaseTables.schemaEditor.errors.loadFailed",
    );
  } finally {
    if (current === describeSeq) {
      loading.value = false;
    }
  }
}

/** 计算预览：manual 方案会展开手动 SQL 面板，auto 方案只在侧栏给出影响汇总。 */
async function runPreview(): Promise<void> {
  previewSeq += 1;
  const current = previewSeq;
  previewLoading.value = true;
  try {
    const result = await ApiAdminDatabaseTable.previewSchema({
      table_name: props.tableName,
      columns: draft.activeColumns.value,
      indexes: draft.activeIndexes.value,
      backup: backupEnabled.value,
    });
    if (current !== previewSeq) {
      return;
    }
    preview.value = result;
    if (result.mode === "manual") {
      manualOpen.value = true;
      $q.notify({
        type: "warning",
        message: t("adminDatabaseTables.schemaEditor.errors.manualRequired"),
      });
    }
  } catch (error) {
    if (current !== previewSeq) {
      return;
    }
    $q.notify({
      type: "negative",
      message: resolveMessage(
        error,
        "adminDatabaseTables.schemaEditor.errors.previewFailed",
      ),
    });
  } finally {
    if (current === previewSeq) {
      previewLoading.value = false;
    }
  }
}

/** 无风险项时同样走确认，避免误触直接执行。 */
async function openConfirm(): Promise<void> {
  await runPreview();
  if (!preview.value || preview.value.mode !== "auto") {
    return;
  }
  confirmTableName.value = "";
  acknowledged.value = [];
  confirmOpen.value = true;
}

async function runApply(): Promise<void> {
  if (!preview.value || !canApply.value) {
    return;
  }
  applyLoading.value = true;
  lastError.value = "";
  try {
    const result = await ApiAdminDatabaseTable.applySchema({
      table_name: props.tableName,
      confirm_table_name: confirmTableName.value.trim(),
      expected_fingerprint: preview.value.structure_fingerprint,
      backup: backupEnabled.value,
      columns: draft.activeColumns.value,
      indexes: draft.activeIndexes.value,
      acknowledged_risk_ids: [...acknowledged.value],
    });
    lastResult.value = result;
    confirmOpen.value = false;
    resultOpen.value = true;
    emit("applied", props.tableName);
    await loadSchema();
  } catch (error) {
    lastResult.value = null;
    lastError.value = resolveMessage(
      error,
      "adminDatabaseTables.schemaEditor.errors.applyFailed",
    );
    confirmOpen.value = false;
    resultOpen.value = true;
  } finally {
    applyLoading.value = false;
  }
}

/** 「我已执行，重新检测」：重读结构并重算差异，列出仍未完成项。 */
async function recheckManual(): Promise<void> {
  await loadSchema();
  const pending: string[] = [];
  for (const column of draft.columns.value) {
    if (column.dropped) {
      continue;
    }
    const kind = draft.columnChangeKind(column);
    if (kind !== "unchanged") {
      pending.push(`${column.name || "(new)"} · ${t(
        `adminDatabaseTables.schemaEditor.changeKind.${kind}`,
      )}`);
    }
  }
  recheckResult.value = { done: pending.length === 0, pending };
  if (pending.length === 0) {
    manualOpen.value = false;
    $q.notify({
      type: "positive",
      message: t("adminDatabaseTables.schemaEditor.manual.recheckDone"),
    });
  }
}

function useOrmSuggestion(): void {
  const suggestion = schema.value?.orm_suggestion;
  if (!suggestion) {
    return;
  }
  draft.applySuggestion(suggestion);
}

function onRenameColumn(column: SchemaColumnDraft, nextName: string): void {
  draft.renameColumn(column, nextName);
}

function onTypeChange(
  column: SchemaColumnDraft,
  type: AdminDatabaseTableSchemaColumnType,
): void {
  draft.setColumnType(column, type);
}

function onTypeArgChange(
  column: SchemaColumnDraft,
  index: number,
  value: number | null,
): void {
  const args = column.type_args ? [...column.type_args] : [];
  if (value === null) {
    return;
  }
  args[index] = value;
  column.type_args = args;
}

/** 组件回传的未收窄输入收敛为可写入草稿的文本，避免对象被隐式字符串化。 */
function toNullableText(value: unknown): string | null {
  if (value === null || value === undefined) {
    return null;
  }
  if (typeof value === "string") {
    return value;
  }
  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }
  return null;
}

function onFieldChange(
  column: SchemaColumnDraft,
  field: string,
  value: unknown,
): void {
  if (field === "unique") {
    draft.setColumnUnique(column, Boolean(value));
    return;
  }
  if (field === "name") {
    column.name = String(value);
    return;
  }
  if (field === "nullable") {
    column.nullable = Boolean(value);
  } else if (field === "server_default") {
    column.server_default = toNullableText(value);
  } else if (field === "primary_key") {
    const next = Boolean(value);
    if (next) {
      // 现有表均为单列主键：勾选新主键时撤销其它列的主键标记。
      for (const other of draft.columns.value) {
        if (other.key !== column.key) {
          other.primary_key = false;
          other.autoincrement = false;
        }
      }
    } else {
      column.autoincrement = false;
    }
    column.primary_key = next;
  } else if (field === "comment") {
    column.comment = toNullableText(value);
  }
  if (!column.touchedFields.includes(field)) {
    column.touchedFields.push(field);
  }
}

function onAddIndex(): void {
  draft.indexes.value.push(draft.addIndex());
}

function onIndexNameChange(index: SchemaIndexDraft, name: string | null): void {
  index.name = name;
}

function onIndexColumnsChange(index: SchemaIndexDraft, columns: string[]): void {
  index.columns = columns;
}

function onIndexUniqueChange(index: SchemaIndexDraft, unique: boolean): void {
  index.unique = unique;
}

function close(): void {
  emit("update:modelValue", false);
}

function onVisibleChange(value: boolean): void {
  emit("update:modelValue", value);
}

// 每次打开或切换表名都重新读取权威结构；关闭时不做任何请求。
watch(
  () => [props.modelValue, props.tableName] as const,
  ([visible, tableName], previous) => {
    const wasVisible = previous?.[0] ?? false;
    const previousTable = previous?.[1] ?? "";
    if (!visible) {
      return;
    }
    if (!wasVisible || tableName !== previousTable) {
      activeTab.value = "columns";
      recheckResult.value = null;
      void loadSchema();
    }
  },
  { immediate: true },
);
</script>

<style scoped>
.db-schema-editor {
  width: min(96vw, 1440px);
  height: 88vh;
  max-width: 96vw;
  display: flex;
  flex-direction: column;
  background: var(--bg-card);
}

.db-schema-editor__head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
}

.db-schema-editor__head-copy {
  min-width: 0;
}

.db-schema-editor__title {
  margin: 0;
  font-size: var(--spa-font-size-card-value);
  color: var(--text-primary);
}

.db-schema-editor__table {
  font-weight: 600;
}

.db-schema-editor__meta {
  margin: 4px 0 0;
  color: var(--workspace-text-muted);
  font-size: var(--spa-font-size-caption);
}

.db-schema-editor__head-actions {
  display: flex;
  align-items: center;
  gap: 8px;
  flex: none;
}

.db-schema-editor__banner {
  margin: 8px 16px 0;
}

.db-schema-editor__banner--error {
  background: var(--status-error-bg);
  color: var(--status-error-text);
  border: 1px solid var(--status-error-border);
}

.db-schema-editor__banner-body {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  flex-wrap: wrap;
}

.db-schema-editor__body {
  flex: 1;
  min-height: 0;
  display: flex;
  padding: 12px 16px;
  overflow: hidden;
}

.db-schema-editor__main {
  display: flex;
  flex: 1;
  flex-direction: column;
  min-width: 0;
  min-height: 0;
}

.db-schema-editor__tabs {
  flex: none;
}

.db-schema-editor__panels {
  flex: 1;
  min-height: 0;
  background: transparent;
}

.db-schema-editor__panel {
  display: flex;
  flex-direction: column;
  padding: 8px 0;
  height: 100%;
  /* 不能在这里滚动：外层滚动会让 QTable 的 sticky 表头失效。 */
  overflow: hidden;
}

.db-schema-editor__backup {
  display: flex;
  align-items: flex-start;
  gap: 2px;
  min-width: 0;
}

.db-schema-editor__backup-info {
  flex: none;
  margin-top: 8px;
  color: var(--workspace-text-muted);
  cursor: help;
}

.db-schema-editor__backup-info:focus-visible {
  outline: 2px solid var(--accent-1);
  outline-offset: 2px;
  border-radius: 4px;
}

.db-schema-editor__actions {
  flex: none;
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  padding: 8px 16px 16px;
  border-top: 1px solid var(--border);
}

.db-schema-confirm,
.db-schema-result,
.db-schema-manual-dialog {
  width: min(92vw, 720px);
  max-width: 92vw;
  background: var(--bg-card);
}

.db-schema-manual-dialog {
  width: min(96vw, 1200px);
}

.db-schema-confirm__title,
.db-schema-result__title,
.db-schema-manual-dialog__title {
  margin: 0 0 8px;
  font-size: var(--spa-font-size-card-value);
  color: var(--text-primary);
}

.db-schema-confirm__message {
  margin: 0;
  color: var(--text-secondary);
}

.db-schema-confirm__risks {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.db-schema-confirm__risks-title {
  margin: 0 0 4px;
  color: var(--workspace-text-muted);
  font-size: var(--spa-font-size-caption);
}

.db-schema-confirm__sql {
  padding-top: 0;
}

.db-schema-confirm__sql-card {
  background: var(--bg-secondary);
}

.db-schema-confirm__sql-head {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
}

.db-schema-confirm__sql-title {
  flex: 1;
  min-width: 0;
  color: var(--text-secondary);
  font-size: var(--spa-font-size-caption);
  font-weight: 600;
}

.db-schema-confirm__sql-body {
  padding: 0;
}

.db-schema-confirm__sql-code {
  margin: 0;
  padding: 12px;
  max-height: 30vh;
  overflow: auto;
  font-size: var(--spa-font-size-caption);
  line-height: 1.5;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}

.db-schema-confirm__sql-code:focus-visible {
  outline: 2px solid var(--accent-1);
  outline-offset: -2px;
}

.db-schema-manual-dialog__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.db-schema-result__line {
  margin: 4px 0;
  color: var(--text-secondary);
}

.db-schema-result__error {
  margin: 8px 0 0;
  color: var(--status-error-text);
}

.db-schema-result__code {
  margin: 8px 0 0;
  padding: 12px;
  max-height: 30vh;
  overflow: auto;
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--bg-secondary);
  font-size: var(--spa-font-size-caption);
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}

@media (max-width: 900px) {
  .db-schema-editor {
    width: 100vw;
    height: 100vh;
    max-width: 100vw;
  }

}
</style>