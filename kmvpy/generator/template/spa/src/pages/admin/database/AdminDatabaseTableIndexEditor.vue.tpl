<template>
  <div class="db-schema-indexes">
    <q-table
      class="db-schema-indexes__table"
      :rows="tableRows"
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
            class="db-schema-indexes__th"
          >
            <span>{{ col.label }}</span>
            <!-- 说明性文字只在悬停时出现，避免表头被注解撑高。 -->
            <q-icon
              v-if="headerHintOf(col)"
              name="info_outline"
              size="14px"
              class="db-schema-indexes__th-info"
              tabindex="0"
              :aria-label="headerHintOf(col)"
            >
              <q-tooltip>{{ headerHintOf(col) }}</q-tooltip>
            </q-icon>
          </q-th>
        </q-tr>
      </template>

      <template #no-data>
        <div class="db-schema-indexes__empty">
          {{ t("adminDatabaseTables.schemaEditor.indexes.empty") }}
        </div>
      </template>

      <template #body="bodyProps">
        <q-tr :props="bodyProps">
          <q-td key="state" :props="bodyProps">
            <q-chip
              dense
              square
              :color="
                bodyProps.row.primary
                  ? 'surface-muted'
                  : stateChipColor(changeKind(bodyProps.row))
              "
              text-color="main"
              :label="stateLabel(bodyProps.row)"
            />
          </q-td>

          <q-td key="name" :props="bodyProps">
            <span v-if="bodyProps.row.primary" class="mono">
              {{ bodyProps.row.name ?? "" }}
            </span>
            <q-input
              v-else
              :model-value="bodyProps.row.name ?? ''"
              dense
              outlined
              :disable="bodyProps.row.dropped"
              :placeholder="t('adminDatabaseTables.schemaEditor.indexes.generated')"
              :label="t('adminDatabaseTables.schemaEditor.indexes.name')"
              @update:model-value="onNameInput(bodyProps.row, $event)"
            />
          </q-td>

          <q-td key="columns" :props="bodyProps">
            <span v-if="bodyProps.row.primary" class="mono">
              {{ bodyProps.row.columns.join(", ") }}
            </span>
            <q-select
              v-else
              :model-value="bodyProps.row.columns"
              :options="columnOptions"
              dense
              outlined
              multiple
              use-chips
              emit-value
              map-options
              :disable="bodyProps.row.dropped"
              :label="t('adminDatabaseTables.schemaEditor.indexes.columns')"
              :error="bodyProps.row.columns.length === 0"
              @update:model-value="onColumnsChange(bodyProps.row, $event)"
            />
          </q-td>

          <q-td key="unique" :props="bodyProps">
            <!-- 主键索引只读：用锁图标 + tooltip 说明，不再重复整句文案。 -->
            <q-icon
              v-if="bodyProps.row.primary"
              name="lock"
              size="16px"
              class="db-schema-indexes__locked"
              tabindex="0"
              :aria-label="t('adminDatabaseTables.schemaEditor.indexes.primaryLocked')"
            >
              <q-tooltip>
                {{ t("adminDatabaseTables.schemaEditor.indexes.primaryLocked") }}
              </q-tooltip>
            </q-icon>
            <q-checkbox
              v-else
              :model-value="bodyProps.row.unique"
              dense
              :disable="bodyProps.row.dropped"
              :aria-label="t('adminDatabaseTables.schemaEditor.indexes.unique')"
              @update:model-value="onUniqueChange(bodyProps.row, $event)"
            />
          </q-td>

          <q-td key="actions" :props="bodyProps" class="db-schema-indexes__actions">
            <template v-if="!bodyProps.row.primary">
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
                :aria-label="t('adminDatabaseTables.schemaEditor.indexes.remove')"
                @click="emit('remove', bodyProps.row)"
              >
                <q-tooltip>
                  {{ t("adminDatabaseTables.schemaEditor.indexes.remove") }}
                </q-tooltip>
              </q-btn>
            </template>
          </q-td>
        </q-tr>
      </template>
    </q-table>

    <div class="db-schema-indexes__footer">
      <q-btn
        flat
        dense
        no-caps
        icon="add"
        color="primary"
        :label="t('adminDatabaseTables.schemaEditor.indexes.add')"
        :disable="columnOptions.length === 0"
        @click="emit('add')"
      />
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";
import type { QTableColumn } from "quasar";

import type {
  SchemaColumnDraft,
  SchemaIndexChangeKind,
  SchemaIndexDraft,
} from "src/composables/useDatabaseTableSchemaDraft";
import type { AdminDatabaseTableSchemaIndexRes } from "src/network/dto/admin/database_table_schema";

const props = defineProps<{
  indexes: SchemaIndexDraft[];
  columns: SchemaColumnDraft[];
  /** 主键索引只读展示，不可编辑、不可删除。 */
  primaryIndex: { name: string | null; columns: string[] } | null;
}>();

const emit = defineEmits<{
  add: [];
  remove: [index: SchemaIndexDraft];
  restore: [index: SchemaIndexDraft];
  nameChange: [index: SchemaIndexDraft, name: string | null];
  columnsChange: [index: SchemaIndexDraft, columns: string[]];
  uniqueChange: [index: SchemaIndexDraft, unique: boolean];
}>();

const { t } = useI18n();

const primaryIndexes = computed<SchemaIndexDraft[]>(() => {
  const primary = props.primaryIndex;
  if (!primary || primary.columns.length === 0) {
    return [];
  }
  return [
    {
      name: primary.name,
      columns: [...primary.columns],
      unique: true,
      primary: true,
      key: "idx-primary",
      baseline: null,
      dropped: false,
    },
  ];
});

const editableIndexes = computed(() =>
  props.indexes.filter((index) => !index.primary),
);

/**
 * 主键索引与可编辑索引合并成一份行数据：
 * QTable 统一渲染、统一固定表头，避免用两段 tbody 拼接。
 */
const tableRows = computed<SchemaIndexDraft[]>(() => [
  ...primaryIndexes.value,
  ...editableIndexes.value,
]);

const columnOptions = computed(() =>
  props.columns
    .filter((column) => !column.dropped && column.name.length > 0)
    .map((column) => ({ label: column.name, value: column.name })),
);

/** 索引列；`headerHint` 把说明文字收敛到表头 tooltip。 */
interface SchemaIndexTableColumn extends QTableColumn {
  headerHint?: string;
}

const tableColumns = computed<SchemaIndexTableColumn[]>(() => [
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
    label: t("adminDatabaseTables.schemaEditor.indexes.name"),
    field: "name",
    align: "left",
    headerStyle: "min-width: 200px",
    style: "min-width: 200px",
  },
  {
    name: "columns",
    label: t("adminDatabaseTables.schemaEditor.indexes.columns"),
    field: "columns",
    align: "left",
    headerStyle: "min-width: 240px",
    style: "min-width: 240px",
  },
  {
    name: "unique",
    label: t("adminDatabaseTables.schemaEditor.indexes.unique"),
    field: "unique",
    align: "center",
    headerStyle: "width: 96px",
    style: "width: 96px",
    headerHint: t("adminDatabaseTables.schemaEditor.indexes.sourceHint"),
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

/** 表头说明只在悬停时展开；没有说明的列不渲染图标。 */
function headerHintOf(col: QTableColumn): string {
  const hint = (col as SchemaIndexTableColumn).headerHint;
  return typeof hint === "string" ? hint : "";
}

function rowClass(row: SchemaIndexDraft): string {
  const classes: string[] = [];
  if (row.primary) {
    classes.push("db-schema-indexes__row--primary");
  } else {
    classes.push(`db-schema-indexes__row--${changeKind(row)}`);
  }
  if (row.dropped) {
    classes.push("db-schema-indexes__row--dropped");
  }
  return classes.join(" ");
}

function signature(index: AdminDatabaseTableSchemaIndexRes): string {
  return JSON.stringify([[...index.columns].sort(), index.unique]);
}

function changeKind(index: SchemaIndexDraft): SchemaIndexChangeKind {
  if (index.dropped) {
    return "dropped";
  }
  if (!index.baseline) {
    return "added";
  }
  return signature(index) === signature(index.baseline) ? "unchanged" : "modified";
}

/** 主键行固定显示「未变」，其余行按其变更状态显示。 */
function stateLabel(row: SchemaIndexDraft): string {
  if (row.primary) {
    return t("adminDatabaseTables.schemaEditor.changeKind.unchanged");
  }
  return t(`adminDatabaseTables.schemaEditor.changeKind.${changeKind(row)}`);
}

function stateChipColor(kind: SchemaIndexChangeKind): string {
  if (kind === "added") {
    return "status-success-bg";
  }
  if (kind === "modified") {
    return "status-warning-bg";
  }
  if (kind === "dropped") {
    return "status-error-bg";
  }
  return "surface-muted";
}

function onNameInput(index: SchemaIndexDraft, value: string | number | null) {
  const raw = typeof value === "string" ? value.trim().toLowerCase() : "";
  emit("nameChange", index, raw === "" ? null : raw);
}

function onColumnsChange(index: SchemaIndexDraft, value: unknown) {
  const names = Array.isArray(value) ? value.map((item) => String(item)) : [];
  emit("columnsChange", index, names);
}

function onUniqueChange(index: SchemaIndexDraft, value: unknown) {
  emit("uniqueChange", index, Boolean(value));
}
</script>

<style scoped>
.db-schema-indexes {
  display: flex;
  flex-direction: column;
  gap: 12px;
  min-width: 0;
  height: 100%;
}

/*
 * 与字段表保持一致：QTable 是唯一滚动容器，外层不滚动，
 * 切换 tab 时两张表的行高与表头位置不会跳动。
 */
.db-schema-indexes__table {
  flex: 1;
  min-height: 0;
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--bg-card);
}

.db-schema-indexes__table :deep(.q-table__container) {
  display: flex;
  flex-direction: column;
  height: 100%;
  min-height: 0;
  border: 0;
  border-radius: 8px;
  background: transparent;
}

.db-schema-indexes__table :deep(.q-table__middle) {
  min-height: 0;
  overflow: auto;
}

.db-schema-indexes__table :deep(thead tr th) {
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

.db-schema-indexes__table :deep(tbody td) {
  height: 56px;
  padding: 8px;
  border-bottom: 1px solid var(--border);
  vertical-align: middle;
}

.db-schema-indexes__th {
  display: table-cell;
  white-space: nowrap;
}

.db-schema-indexes__th-info {
  margin-left: 2px;
  color: var(--workspace-text-muted);
  cursor: help;
}

.db-schema-indexes__th-info:focus-visible {
  outline: 2px solid var(--accent-1);
  outline-offset: 2px;
  border-radius: 4px;
}

.db-schema-indexes__table :deep(.db-schema-indexes__row--primary td) {
  background: var(--bg-secondary);
}

.db-schema-indexes__table :deep(.db-schema-indexes__row--dropped td) {
  opacity: 0.55;
  text-decoration: line-through;
}

.db-schema-indexes__actions {
  display: flex;
  justify-content: flex-end;
}

.db-schema-indexes__empty {
  padding: 16px;
  text-align: center;
  color: var(--workspace-text-muted);
}

.db-schema-indexes__footer {
  display: flex;
  flex: none;
  flex-wrap: wrap;
  gap: 8px;
}

.db-schema-indexes__locked {
  color: var(--workspace-text-muted);
}
</style>