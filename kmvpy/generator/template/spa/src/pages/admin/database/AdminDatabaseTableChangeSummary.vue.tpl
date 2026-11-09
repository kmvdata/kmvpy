<template>
  <div class="db-schema-summary">
    <div class="spa-section-title db-schema-summary__title">
      {{ t("adminDatabaseTables.schemaEditor.risk.summaryTitle") }}
    </div>

    <ul class="db-schema-summary__levels">
      <li class="db-schema-summary__level db-schema-summary__level--auto">
        <q-icon name="check_circle" aria-hidden="true" />
        <span>
          {{ t("adminDatabaseTables.schemaEditor.risk.auto") }}
        </span>
        <strong>{{ counts.auto }}</strong>
      </li>
      <li class="db-schema-summary__level db-schema-summary__level--confirm">
        <q-icon name="warning" aria-hidden="true" />
        <span>
          {{ t("adminDatabaseTables.schemaEditor.risk.confirm") }}
        </span>
        <strong>{{ counts.confirm }}</strong>
      </li>
      <li class="db-schema-summary__level db-schema-summary__level--manual">
        <q-icon name="pan_tool" aria-hidden="true" />
        <span>
          {{ t("adminDatabaseTables.schemaEditor.risk.manual") }}
        </span>
        <strong>{{ counts.manual }}</strong>
      </li>
    </ul>

    <div class="db-schema-summary__rows">
      <div class="db-schema-summary__row">
        <span>{{ t("adminDatabaseTables.schemaEditor.risk.affectedRows") }}</span>
        <strong class="mono">{{ affectedRowsText }}</strong>
      </div>
      <div
        v-for="(count, key) in planSummaryRows"
        :key="key"
        class="db-schema-summary__row"
      >
        <span>{{ summaryLabel(key) }}</span>
        <strong class="mono">{{ count }}</strong>
      </div>
    </div>

    <q-expansion-item
      v-if="riskItems.length > 0"
      dense
      dense-toggle
      icon="expand_more"
      :label="t('adminDatabaseTables.schemaEditor.risk.details')"
      class="db-schema-summary__details"
    >
      <ul class="db-schema-summary__risk-list">
        <li v-for="item in riskItems" :key="`${item.code}-${item.column ?? ''}`">
          <span
            :class="[
              'db-schema-summary__risk-level',
              `db-schema-summary__risk-level--${item.level}`,
            ]"
          >
            {{ levelLabel(item.level) }}
          </span>
          <span class="db-schema-summary__risk-text">
            {{ riskLabel(item) }}
          </span>
          <span v-if="item.affected_rows !== null" class="mono">
            {{ formatNumber(item.affected_rows) }}
          </span>
        </li>
      </ul>
    </q-expansion-item>

    <p v-if="!loading && noChanges" class="db-schema-summary__empty">
      {{ t("adminDatabaseTables.schemaEditor.changeKind.noChanges") }}
    </p>
  </div>
</template>

<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";

import type { AdminDatabaseTableSchemaRiskLevel } from "src/network/dto/admin/database_table_schema";
import type { SchemaRiskItemView } from "src/pages/admin/database/database_table_schema_view";

const props = defineProps<{
  riskItems: SchemaRiskItemView[];
  planSummary: Record<string, number>;
  estimatedRows: number | null;
  loading: boolean;
  noChanges: boolean;
  /** auto / confirm / manual 三档的数量，由父组件按风险等级汇总。 */
  counts: { auto: number; confirm: number; manual: number };
}>();

const { t } = useI18n();

const affectedRowsText = computed(() => {
  if (props.estimatedRows === null) {
    return t("adminDatabaseTables.table.rowUnknown");
  }
  return formatNumber(props.estimatedRows);
});

const SUMMARY_KEYS = [
  "added",
  "modified",
  "removed",
  "renamed",
  "indexes_added",
  "indexes_removed",
] as const;

/** 只展示非零项，避免摘要被一堆 0 淹没。 */
const planSummaryRows = computed(() => {
  const rows: Record<string, number> = {};
  for (const key of SUMMARY_KEYS) {
    const value = props.planSummary[key] ?? 0;
    if (value > 0) {
      rows[key] = value;
    }
  }
  return rows;
});

function summaryLabel(key: string): string {
  return t(`adminDatabaseTables.schemaEditor.summary.${key}`);
}

function levelLabel(level: AdminDatabaseTableSchemaRiskLevel): string {
  if (level === "blocking") {
    return t("adminDatabaseTables.schemaEditor.risk.manual");
  }
  if (level === "confirm") {
    return t("adminDatabaseTables.schemaEditor.risk.confirm");
  }
  return t("adminDatabaseTables.schemaEditor.risk.auto");
}

/** 风险码 → 本地化文案；未知 code 回退为自身，便于排查。 */
function riskLabel(item: SchemaRiskItemView): string {
  const base = t(`adminDatabaseTables.schemaEditor.riskCodes.${item.code}`);
  if (base === `adminDatabaseTables.schemaEditor.riskCodes.${item.code}`) {
    return item.code;
  }
  return item.column ? `${base} · ${item.column}` : base;
}

function formatNumber(value: number): string {
  return new Intl.NumberFormat().format(value);
}
</script>

<style scoped>
.db-schema-summary {
  display: flex;
  flex-direction: column;
  gap: 12px;
  min-width: 0;
}

.db-schema-summary__title {
  margin: 0;
}

.db-schema-summary__levels {
  display: flex;
  flex-direction: column;
  gap: 8px;
  margin: 0;
  padding: 0;
  list-style: none;
}

.db-schema-summary__level {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--bg-secondary);
}

.db-schema-summary__level span {
  flex: 1;
  min-width: 0;
}

.db-schema-summary__level strong {
  font-variant-numeric: tabular-nums;
}

.db-schema-summary__level--auto {
  color: var(--status-success-text);
  border-color: var(--status-success-border);
  background: var(--status-success-bg);
}

.db-schema-summary__level--confirm {
  color: var(--status-warning-text);
  border-color: var(--status-warning-border);
  background: var(--status-warning-bg);
}

.db-schema-summary__level--manual {
  color: var(--status-error-text);
  border-color: var(--status-error-border);
  background: var(--status-error-bg);
}

.db-schema-summary__rows {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.db-schema-summary__row {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  color: var(--text-secondary);
}

.db-schema-summary__row strong {
  color: var(--text-primary);
  font-variant-numeric: tabular-nums;
}

.db-schema-summary__details {
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--bg-card);
}

.db-schema-summary__risk-list {
  display: flex;
  flex-direction: column;
  gap: 6px;
  margin: 0;
  padding: 8px 12px 12px;
  list-style: none;
}

.db-schema-summary__risk-list li {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  align-items: baseline;
}

.db-schema-summary__risk-level {
  flex: none;
  padding: 0 6px;
  border-radius: 4px;
  font-size: var(--spa-font-size-caption);
}

.db-schema-summary__risk-level--info {
  background: var(--status-info-bg);
  color: var(--status-info-text);
}

.db-schema-summary__risk-level--confirm {
  background: var(--status-warning-bg);
  color: var(--status-warning-text);
}

.db-schema-summary__risk-level--blocking {
  background: var(--status-error-bg);
  color: var(--status-error-text);
}

.db-schema-summary__risk-text {
  flex: 1;
  min-width: 0;
  overflow-wrap: anywhere;
}

.db-schema-summary__empty {
  margin: 0;
  color: var(--workspace-text-muted);
}

@media (max-width: 900px) {
  .db-schema-summary__levels {
    flex-direction: row;
    flex-wrap: wrap;
  }

  .db-schema-summary__level {
    flex: 1 1 140px;
  }
}
</style>