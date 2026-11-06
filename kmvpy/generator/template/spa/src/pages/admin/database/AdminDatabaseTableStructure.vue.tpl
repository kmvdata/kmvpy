<template>
  <div class="admin-db-structure">
    <div class="admin-db-structure__block">
      <div class="spa-section-title admin-db-structure__title">
        {{ t("adminDatabaseTables.detail.columnsTitle") }}
      </div>
      <div class="admin-db-structure__scroll">
        <table class="admin-db-structure__table">
          <thead>
            <tr>
              <th>{{ t("adminDatabaseTables.detail.columnName") }}</th>
              <th>{{ t("adminDatabaseTables.detail.columnType") }}</th>
              <th>{{ t("adminDatabaseTables.table.primaryKey") }}</th>
              <th>{{ t("adminDatabaseTables.table.indexed") }}</th>
              <th>{{ t("adminDatabaseTables.table.unique") }}</th>
              <th>{{ t("adminDatabaseTables.table.nullable") }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="columns.length === 0">
              <td colspan="6" class="admin-db-structure__empty">
                {{ t("adminDatabaseTables.detail.columnsEmpty") }}
              </td>
            </tr>
            <tr v-for="column in columns" :key="column.name">
              <td class="mono admin-db-structure__key">{{ column.name }}</td>
              <td class="mono">{{ column.type }}</td>
              <td>{{ flagText(column.primary_key) }}</td>
              <td>{{ flagText(column.indexed) }}</td>
              <td>{{ flagText(column.unique) }}</td>
              <td>
                {{
                  column.nullable
                    ? t("adminDatabaseTables.table.nullable")
                    : t("adminDatabaseTables.table.notNull")
                }}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <div class="admin-db-structure__block">
      <div class="spa-section-title admin-db-structure__title">
        {{ t("adminDatabaseTables.detail.indexesTitle") }}
      </div>
      <div class="admin-db-structure__scroll">
        <table class="admin-db-structure__table">
          <thead>
            <tr>
              <th>{{ t("adminDatabaseTables.detail.indexName") }}</th>
              <th>{{ t("adminDatabaseTables.detail.indexColumns") }}</th>
              <th>{{ t("adminDatabaseTables.detail.indexKind") }}</th>
              <th>{{ t("adminDatabaseTables.table.unique") }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="indexes.length === 0">
              <td colspan="4" class="admin-db-structure__empty">
                {{ t("adminDatabaseTables.detail.indexesEmpty") }}
              </td>
            </tr>
            <tr v-for="index in indexes" :key="index.name">
              <td class="mono admin-db-structure__key">{{ index.name }}</td>
              <td class="mono">{{ index.columns.join(", ") }}</td>
              <td>{{ indexKindText(index) }}</td>
              <td>{{ flagText(index.unique) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { useI18n } from "vue-i18n";

import type {
  AdminDatabaseTableColumnRes,
  AdminDatabaseTableIndexRes,
} from "src/network/dto/admin/database_table";

defineProps<{
  columns: AdminDatabaseTableColumnRes[];
  indexes: AdminDatabaseTableIndexRes[];
}>();

const { t } = useI18n();

/** 布尔标记以文案表达，不依赖颜色区分。 */
function flagText(value: boolean): string {
  return value
    ? t("adminDatabaseTables.detail.yes")
    : t("adminDatabaseTables.detail.no");
}

/** 索引类型：主键优先，其次唯一索引，其余按普通索引展示。 */
function indexKindText(index: AdminDatabaseTableIndexRes): string {
  if (index.primary) {
    return t("adminDatabaseTables.detail.indexPrimary");
  }
  if (index.unique) {
    return t("adminDatabaseTables.detail.indexUnique");
  }
  return t("adminDatabaseTables.detail.indexSecondary");
}
</script>

<style scoped>
.admin-db-structure {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.admin-db-structure__title {
  margin-bottom: 8px;
}

.admin-db-structure__scroll {
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--bg-card);
  overflow-x: auto;
}

.admin-db-structure__table {
  width: 100%;
  min-width: 560px;
  border-collapse: collapse;
}

.admin-db-structure__table th,
.admin-db-structure__table td {
  padding: 8px 12px;
  border-bottom: 1px solid var(--border);
  text-align: left;
  vertical-align: middle;
}

.admin-db-structure__table thead th {
  color: var(--workspace-text-muted);
  background: var(--bg-secondary);
  font-size: var(--spa-font-size-caption);
  font-weight: 600;
  white-space: nowrap;
}

.admin-db-structure__table tbody td {
  color: var(--text-primary);
  font-size: var(--spa-font-size-small);
}

.admin-db-structure__table tbody tr:last-child td {
  border-bottom: none;
}

.admin-db-structure__key {
  font-weight: 600;
}

.admin-db-structure__empty {
  text-align: center;
  color: var(--workspace-text-muted);
}
</style>
