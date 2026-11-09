<template>
  <div class="db-schema-columns">
    <q-table
      class="db-schema-columns__table"
      :rows="columns"
      :columns="tableColumns"
      row-key="key"
      dense
      flat
      square
      hide-pagination
      :rows-per-page-options="[0]"
      :row-class="rowClass"
      :pagination="{ page: 1, rowsPerPage: 0 }"
    >
      <template #header="headerProps">
        <q-tr :props="headerProps">
          <q-th
            v-for="col in headerProps.cols"
            :key="col.name"
            :props="headerProps"
            :col="col"
            class="db-schema-columns__th"
          >
            <span>{{ col.label }}</span>
            <!-- 说明性文字只在悬停时出现，避免表头被注解撑高。 -->
            <q-icon
              v-if="headerHintOf(col)"
              name="info_outline"
              size="14px"
              class="db-schema-columns__th-info"
              tabindex="0"
              :aria-label="headerHintOf(col)"
            >
              <q-tooltip>{{ headerHintOf(col) }}</q-tooltip>
            </q-icon>
          </q-th>
        </q-tr>
      </template>

      <template #no-data>
        <div class="db-schema-columns__empty">
          {{ t("adminDatabaseTables.schemaEditor.columns.empty") }}
        </div>
      </template>

      <template #body="bodyProps">
        <q-tr :props="bodyProps">
          <q-td key="state" :props="bodyProps" class="db-schema-columns__state">
            <span class="db-schema-columns__bar" aria-hidden="true" />
            <span class="db-schema-columns__state-chip">
              <q-chip
                dense
                square
                :color="stateChipColor(changeKind(bodyProps.row))"
                text-color="main"
                :label="stateLabel(changeKind(bodyProps.row))"
              />
              <q-tooltip v-if="rowNotes(bodyProps.row).length > 0">
                <span
                  v-for="note in rowNotes(bodyProps.row)"
                  :key="note"
                  class="db-schema-columns__note"
                >
                  {{ note }}
                </span>
              </q-tooltip>
            </span>
          </q-td>

          <q-td key="name" :props="bodyProps">
            <div class="db-schema-columns__name-cell">
              <q-input
                v-if="isRenaming(bodyProps.row)"
                v-model="renameDraft"
                dense
                outlined
                autofocus
                :label="t('adminDatabaseTables.schemaEditor.columns.rename')"
                :error="renameInvalid"
                :error-message="
                  renameInvalid
                    ? t('adminDatabaseTables.schemaEditor.columns.nameInvalid')
                    : undefined
                "
                @keyup.enter="commitRename(bodyProps.row)"
                @keyup.esc="cancelRename(bodyProps.row)"
              />
              <template v-else>
                <q-input
                  :model-value="bodyProps.row.name"
                  dense
                  outlined
                  :disable="bodyProps.row.dropped"
                  :label="t('adminDatabaseTables.schemaEditor.columns.name')"
                  :error="nameInvalid(bodyProps.row)"
                  :error-message="
                    nameInvalid(bodyProps.row)
                      ? t('adminDatabaseTables.schemaEditor.columns.nameInvalid')
                      : undefined
                  "
                  @update:model-value="onNameInput(bodyProps.row, $event)"
                />
                <q-btn
                  v-if="bodyProps.row.baseline"
                  flat
                  dense
                  round
                  icon="drive_file_rename_outline"
                  :disable="bodyProps.row.dropped"
                  :aria-label="t('adminDatabaseTables.schemaEditor.columns.rename')"
                  @click="startRename(bodyProps.row)"
                >
                  <q-tooltip>
                    {{ t("adminDatabaseTables.schemaEditor.columns.rename") }}
                  </q-tooltip>
                </q-btn>
              </template>
              <template v-if="isRenaming(bodyProps.row)">
                <q-btn
                  flat
                  dense
                  round
                  icon="check"
                  color="primary"
                  :aria-label="t('adminDatabaseTables.schemaEditor.columns.renameConfirm')"
                  @click="commitRename(bodyProps.row)"
                >
                  <q-tooltip>
                    {{ t("adminDatabaseTables.schemaEditor.columns.renameConfirm") }}
                  </q-tooltip>
                </q-btn>
                <q-btn
                  flat
                  dense
                  round
                  icon="close"
                  :aria-label="t('adminDatabaseTables.schemaEditor.columns.renameCancel')"
                  @click="cancelRename(bodyProps.row)"
                >
                  <q-tooltip>
                    {{ t("adminDatabaseTables.schemaEditor.columns.renameCancel") }}
                  </q-tooltip>
                </q-btn>
              </template>
            </div>
          </q-td>

          <q-td key="type" :props="bodyProps">
            <q-select
              :model-value="bodyProps.row.type"
              :options="typeOptions"
              dense
              outlined
              emit-value
              map-options
              :disable="bodyProps.row.dropped"
              :label="t('adminDatabaseTables.schemaEditor.columns.type')"
              @update:model-value="onTypeChange(bodyProps.row, $event)"
            />
          </q-td>

          <q-td key="typeArgs" :props="bodyProps">
            <div
              v-if="argLabels(bodyProps.row).length > 0"
              class="db-schema-columns__args"
            >
              <q-input
                v-for="(argLabel, argIndex) in argLabels(bodyProps.row)"
                :key="argLabel"
                :model-value="bodyProps.row.type_args?.[argIndex] ?? ''"
                dense
                outlined
                type="number"
                min="1"
                :disable="bodyProps.row.dropped"
                :label="argLabelText(argLabel)"
                @update:model-value="onTypeArgInput(bodyProps.row, argIndex, $event)"
              />
            </div>
            <span v-else class="db-schema-columns__dash">
              {{ t("adminDatabaseTables.schemaEditor.columns.typeArgsNone") }}
            </span>
          </q-td>

          <q-td key="nullable" :props="bodyProps">
            <q-checkbox
              :model-value="bodyProps.row.nullable"
              dense
              :disable="bodyProps.row.dropped || bodyProps.row.primary_key"
              :aria-label="t('adminDatabaseTables.schemaEditor.columns.nullable')"
              @update:model-value="onNullableChange(bodyProps.row, $event)"
            />
          </q-td>

          <q-td key="serverDefault" :props="bodyProps">
            <q-input
              :model-value="bodyProps.row.server_default ?? ''"
              dense
              outlined
              :disable="bodyProps.row.dropped"
              :label="t('adminDatabaseTables.schemaEditor.columns.default')"
              @update:model-value="onDefaultInput(bodyProps.row, $event)"
            />
          </q-td>

          <q-td key="primaryKey" :props="bodyProps">
            <q-checkbox
              :model-value="bodyProps.row.primary_key"
              dense
              :disable="bodyProps.row.dropped"
              :aria-label="t('adminDatabaseTables.schemaEditor.columns.primaryKey')"
              @update:model-value="onPrimaryKeyChange(bodyProps.row, $event)"
            />
          </q-td>

          <q-td key="unique" :props="bodyProps">
            <q-checkbox
              :model-value="bodyProps.row.unique"
              dense
              :disable="bodyProps.row.dropped || bodyProps.row.primary_key"
              :aria-label="t('adminDatabaseTables.schemaEditor.columns.unique')"
              @update:model-value="onUniqueChange(bodyProps.row, $event)"
            />
          </q-td>

          <q-td key="comment" :props="bodyProps">
            <q-input
              :model-value="bodyProps.row.comment ?? ''"
              dense
              outlined
              :disable="bodyProps.row.dropped"
              :label="t('adminDatabaseTables.schemaEditor.columns.comment')"
              @update:model-value="onCommentInput(bodyProps.row, $event)"
            />
          </q-td>

          <q-td key="actions" :props="bodyProps" class="db-schema-columns__actions">
            <q-btn
              v-if="bodyProps.row.dropped"
              flat
              dense
              round
              icon="undo"
              color="primary"
              :aria-label="t('adminDatabaseTables.schemaEditor.columns.restore')"
              @click="emit('restore', bodyProps.row)"
            >
              <q-tooltip>
                {{ t("adminDatabaseTables.schemaEditor.columns.restore") }}
              </q-tooltip>
            </q-btn>
            <q-btn
              v-else
              flat
              dense
              round
              icon="delete_outline"
              color="negative"
              :aria-label="t('adminDatabaseTables.schemaEditor.columns.remove')"
              @click="onRemove(bodyProps.row)"
            >
              <q-tooltip>
                {{ t("adminDatabaseTables.schemaEditor.columns.remove") }}
              </q-tooltip>
            </q-btn>
          </q-td>
        </q-tr>
      </template>
    </q-table>

    <div class="db-schema-columns__footer">
      <q-btn
        flat
        dense
        no-caps
        icon="add"
        color="primary"
        :label="t('adminDatabaseTables.schemaEditor.columns.add')"
        @click="emit('add')"
      />
      <q-btn
        v-if="canSuggest"
        flat
        dense
        no-caps
        icon="auto_fix_high"
        :label="t('adminDatabaseTables.schemaEditor.columns.suggestFromOrm')"
        :disable="!hasSuggestion"
        @click="emit('suggest')"
      >
        <q-tooltip>
          {{
            hasSuggestion
              ? t("adminDatabaseTables.schemaEditor.columns.suggestHint")
              : t("adminDatabaseTables.schemaEditor.columns.suggestUnavailable")
          }}
        </q-tooltip>
      </q-btn>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, ref } from "vue";
import { useI18n } from "vue-i18n";
import type { QTableColumn } from "quasar";

import {
  AUTOINCREMENT_TYPES,
  COLUMN_TYPE_ARG_RULES,
  type ColumnTypeArgLabel,
  type SchemaColumnChangeKind,
  type SchemaColumnDraft,
} from "src/composables/useDatabaseTableSchemaDraft";
import type {
  AdminDatabaseTableSchemaColumnRes,
  AdminDatabaseTableSchemaColumnType,
} from "src/network/dto/admin/database_table_schema";

defineProps<{
  columns: SchemaColumnDraft[];
  /** 是否显示「从 ORM 建议…」入口。 */
  canSuggest: boolean;
  /** 是否存在可用的 ORM 建议。 */
  hasSuggestion: boolean;
}>();

const emit = defineEmits<{
  add: [];
  suggest: [];
  rename: [column: SchemaColumnDraft, nextName: string];
  remove: [column: SchemaColumnDraft];
  restore: [column: SchemaColumnDraft];
  typeChange: [column: SchemaColumnDraft, type: AdminDatabaseTableSchemaColumnType];
  typeArgChange: [column: SchemaColumnDraft, index: number, value: number | null];
  fieldChange: [column: SchemaColumnDraft, field: string, value: unknown];
}>();

const { t } = useI18n();

const typeOptions = computed(() =>
  (Object.keys(COLUMN_TYPE_ARG_RULES) as AdminDatabaseTableSchemaColumnType[]).map(
    (type) => ({
      label: t(`adminDatabaseTables.schemaEditor.types.${type}`),
      value: type,
    }),
  ),
);

const NAME_PATTERN = /^[a-z][a-z0-9_]{0,62}$/;

/** 正在行内改名的列 key 集合；改名不走 prompt，避免脱离页面语义。 */
const renamingKeys = ref<string[]>([]);
const renameDraft = ref("");
const renameInvalid = ref(false);

/**
 * 列定义。`headerHint` 用于把说明性文字收敛到表头 tooltip，
 * 不再逐行渲染 hint，保证每行高度一致。
 */
interface SchemaColumnTableColumn extends QTableColumn {
  headerHint?: string;
}

const tableColumns = computed<SchemaColumnTableColumn[]>(() => [
  {
    name: "state",
    label: t("adminDatabaseTables.schemaEditor.columns.state"),
    field: "state",
    align: "left",
    headerStyle: "width: 128px",
    style: "width: 128px",
  },
  {
    name: "name",
    label: t("adminDatabaseTables.schemaEditor.columns.name"),
    field: "name",
    align: "left",
    headerStyle: "min-width: 200px",
    style: "min-width: 200px",
  },
  {
    name: "type",
    label: t("adminDatabaseTables.schemaEditor.columns.type"),
    field: "type",
    align: "left",
    headerStyle: "min-width: 140px",
    style: "min-width: 140px",
  },
  {
    name: "typeArgs",
    label: t("adminDatabaseTables.schemaEditor.columns.typeArgs"),
    field: "type_args",
    align: "left",
    headerStyle: "min-width: 160px",
    style: "min-width: 160px",
  },
  {
    name: "nullable",
    label: t("adminDatabaseTables.schemaEditor.columns.nullable"),
    field: "nullable",
    align: "center",
    headerStyle: "width: 80px",
    style: "width: 80px",
  },
  {
    name: "serverDefault",
    label: t("adminDatabaseTables.schemaEditor.columns.default"),
    field: "server_default",
    align: "left",
    headerStyle: "min-width: 160px",
    style: "min-width: 160px",
    headerHint: t("adminDatabaseTables.schemaEditor.columns.defaultHint"),
  },
  {
    name: "primaryKey",
    label: t("adminDatabaseTables.schemaEditor.columns.primaryKey"),
    field: "primary_key",
    align: "center",
    headerStyle: "width: 88px",
    style: "width: 88px",
  },
  {
    name: "unique",
    label: t("adminDatabaseTables.schemaEditor.columns.unique"),
    field: "unique",
    align: "center",
    headerStyle: "width: 80px",
    style: "width: 80px",
  },
  {
    name: "comment",
    label: t("adminDatabaseTables.schemaEditor.columns.comment"),
    field: "comment",
    align: "left",
    headerStyle: "min-width: 160px",
    style: "min-width: 160px",
  },
  {
    name: "actions",
    label: t("adminDatabaseTables.schemaEditor.columns.actions"),
    field: "actions",
    align: "right",
    headerStyle: "width: 72px",
    style: "width: 72px",
  },
]);

/** 行级变更样式：保持状态条、淡化和删除线语义不变。 */
function rowClass(row: SchemaColumnDraft): string {
  const classes = [`db-schema-columns__row--${changeKind(row)}`];
  if (row.dropped) {
    classes.push("db-schema-columns__row--dropped");
  }
  return classes.join(" ");
}

/** 表头说明只在悬停时展开；没有说明的列不渲染图标。 */
function headerHintOf(col: QTableColumn): string {
  const hint = (col as SchemaColumnTableColumn).headerHint;
  return typeof hint === "string" ? hint : "";
}

function changeKind(column: SchemaColumnDraft): SchemaColumnChangeKind {
  if (column.dropped) {
    return "dropped";
  }
  if (!column.baseline) {
    return "added";
  }
  if (column.original_name && column.original_name !== column.baseline.name) {
    return "renamed";
  }
  const signature = (item: AdminDatabaseTableSchemaColumnRes): string =>
    JSON.stringify([
      item.name,
      item.type,
      item.type_args ?? null,
      item.nullable,
      item.primary_key,
      item.autoincrement,
      item.server_default,
    ]);
  return signature(column) === signature(column.baseline)
    ? "unchanged"
    : "modified";
}

/** 状态必须有文字，颜色只作辅助。 */
function stateLabel(kind: SchemaColumnChangeKind): string {
  return t(`adminDatabaseTables.schemaEditor.changeKind.${kind}`);
}

function stateChipColor(kind: SchemaColumnChangeKind): string {
  if (kind === "added") {
    return "status-success-bg";
  }
  if (kind === "modified" || kind === "renamed") {
    return "status-warning-bg";
  }
  if (kind === "dropped") {
    return "status-error-bg";
  }
  return "surface-muted";
}

function nameInvalid(column: SchemaColumnDraft): boolean {
  return column.name.length > 0 && !NAME_PATTERN.test(column.name);
}

/**
 * 行级补充说明（原列名 / 原值）只作为状态 chip 的 tooltip 内容。
 * 常驻 hint 会把单行撑高，也会让整张表被重复注释淹没。
 */
function rowNotes(column: SchemaColumnDraft): string[] {
  if (column.original_name && column.baseline) {
    return [
      t("adminDatabaseTables.schemaEditor.columns.renamedFrom", {
        name: column.original_name,
      }),
    ];
  }
  if (column.baseline && column.touchedFields.includes("name")) {
    return [
      t("adminDatabaseTables.schemaEditor.columns.originalValue", {
        value: column.baseline.name,
      }),
    ];
  }
  return [];
}

function argLabels(column: SchemaColumnDraft): ColumnTypeArgLabel[] {
  const rule = COLUMN_TYPE_ARG_RULES[column.type];
  return [...rule.labels];
}

function argLabelText(label: ColumnTypeArgLabel): string {
  return t(`adminDatabaseTables.schemaEditor.typeArgs.${label}`);
}

function onNameInput(column: SchemaColumnDraft, value: string | number | null) {
  const next = typeof value === "string" ? value : String(value ?? "");
  if (!column.baseline) {
    emit("fieldChange", column, "name", next.trim().toLowerCase());
    return;
  }
  emit("rename", column, next);
}

function isRenaming(column: SchemaColumnDraft): boolean {
  return renamingKeys.value.includes(column.key);
}

function startRename(column: SchemaColumnDraft) {
  // 改名必须走显式入口：进入行内改名态，由用户确认后再写入 original_name。
  renamingKeys.value = [...renamingKeys.value, column.key];
  renameDraft.value = column.name;
}

/** 确认改名：空值或与原名相同则取消，不产生 rename 事件。 */
function commitRename(column: SchemaColumnDraft) {
  const next = renameDraft.value.trim().toLowerCase();
  cancelRename(column);
  if (!next || next === column.name) {
    return;
  }
  if (!NAME_PATTERN.test(next)) {
    renameInvalid.value = true;
    return;
  }
  emit("rename", column, next);
}

function cancelRename(column: SchemaColumnDraft) {
  renamingKeys.value = renamingKeys.value.filter((key) => key !== column.key);
  renameDraft.value = "";
  renameInvalid.value = false;
}

function onTypeChange(column: SchemaColumnDraft, value: unknown) {
  emit("typeChange", column, value as AdminDatabaseTableSchemaColumnType);
}

function onTypeArgInput(
  column: SchemaColumnDraft,
  index: number,
  value: string | number | null,
) {
  const numeric = Number(value);
  emit(
    "typeArgChange",
    column,
    index,
    Number.isFinite(numeric) && numeric > 0 ? Math.trunc(numeric) : null,
  );
}

function onNullableChange(column: SchemaColumnDraft, value: unknown) {
  emit("fieldChange", column, "nullable", Boolean(value));
}

function onDefaultInput(column: SchemaColumnDraft, value: string | number | null) {
  const raw = typeof value === "string" ? value.trim() : String(value ?? "");
  emit("fieldChange", column, "server_default", raw === "" ? null : raw);
}

function onPrimaryKeyChange(column: SchemaColumnDraft, value: unknown) {
  emit("fieldChange", column, "primary_key", Boolean(value));
}

function onUniqueChange(column: SchemaColumnDraft, value: unknown) {
  emit("fieldChange", column, "unique", Boolean(value));
}

function onCommentInput(column: SchemaColumnDraft, value: string | number | null) {
  const raw = typeof value === "string" ? value : String(value ?? "");
  emit("fieldChange", column, "comment", raw.trim() === "" ? null : raw);
}

function onRemove(column: SchemaColumnDraft) {
  emit("remove", column);
}

/** 供父组件判断是否需要提示：自增只允许整型。 */
function autoincrementAllowed(column: SchemaColumnDraft): boolean {
  return AUTOINCREMENT_TYPES.includes(column.type) && column.primary_key;
}

defineExpose({ autoincrementAllowed });
</script>

<style scoped>
.db-schema-columns {
  display: flex;
  flex-direction: column;
  gap: 12px;
  min-width: 0;
  height: 100%;
}

/*
 * QTable 是唯一的滚动容器：外层不滚动，表头 sticky 才真正生效。
 * 表格撑满剩余高度，页脚按钮固定在其下方。
 */
.db-schema-columns__table {
  flex: 1;
  min-height: 0;
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--bg-card);
}

.db-schema-columns__table :deep(.q-table__container) {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
  border: 0;
  border-radius: 8px;
  background: transparent;
}

.db-schema-columns__table :deep(.q-table__middle) {
  min-height: 0;
  overflow: auto;
}

.db-schema-columns__table :deep(thead tr th) {
  position: sticky;
  top: 0;
  z-index: 2;
  color: var(--workspace-text-muted);
  background: var(--bg-secondary);
  font-size: var(--spa-font-size-caption);
  font-weight: 600;
  white-space: nowrap;
  border-bottom: 1px solid var(--border);
}

.db-schema-columns__table :deep(tbody td) {
  height: 56px;
  padding: 8px;
  border-bottom: 1px solid var(--border);
  vertical-align: middle;
}

.db-schema-columns__th {
  display: table-cell;
  white-space: nowrap;
}

.db-schema-columns__th-info {
  margin-left: 2px;
  color: var(--workspace-text-muted);
  cursor: help;
}

.db-schema-columns__th-info:focus-visible {
  outline: 2px solid var(--accent-1);
  outline-offset: 2px;
  border-radius: 4px;
}

.db-schema-columns__row--dropped :deep(td) {
  opacity: 0.55;
  text-decoration: line-through;
}

.db-schema-columns__state {
  display: flex;
  align-items: center;
  gap: 6px;
}

.db-schema-columns__state-chip {
  display: inline-flex;
  min-width: 0;
}

.db-schema-columns__note {
  display: block;
}

.db-schema-columns__bar {
  display: inline-block;
  width: 3px;
  height: 24px;
  flex: none;
  border-radius: 2px;
  background: var(--border);
}

:deep(.db-schema-columns__row--added) .db-schema-columns__bar {
  background: var(--status-success-text);
}

:deep(.db-schema-columns__row--modified) .db-schema-columns__bar,
:deep(.db-schema-columns__row--renamed) .db-schema-columns__bar {
  background: var(--status-warning-text);
}

:deep(.db-schema-columns__row--dropped) .db-schema-columns__bar {
  background: var(--status-error-text);
}

.db-schema-columns__name-cell {
  display: flex;
  align-items: center;
  gap: 4px;
  min-width: 160px;
}

.db-schema-columns__args {
  display: flex;
  gap: 4px;
  min-width: 140px;
}

.db-schema-columns__dash {
  color: var(--workspace-text-muted);
}

.db-schema-columns__actions {
  display: flex;
  gap: 2px;
  justify-content: flex-end;
}

.db-schema-columns__empty {
  padding: 16px;
  text-align: center;
  color: var(--workspace-text-muted);
}

.db-schema-columns__footer {
  display: flex;
  flex: none;
  flex-wrap: wrap;
  gap: 8px;
  align-items: center;
}

@media (max-width: 600px) {
  .db-schema-columns__table :deep(table) {
    min-width: 720px;
  }
}
</style>