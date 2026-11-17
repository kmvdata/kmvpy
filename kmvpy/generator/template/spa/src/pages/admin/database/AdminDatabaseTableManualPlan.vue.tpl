<template>
  <div class="db-schema-manual">
    <q-banner rounded class="db-schema-manual__banner">
      {{ t("adminDatabaseTables.schemaEditor.manual.intro") }}
    </q-banner>

    <div class="db-schema-manual__sections">
      <section
        v-for="section in sections"
        :key="section.key"
        class="db-schema-manual__section"
      >
        <div class="db-schema-manual__head">
          <h3 class="db-schema-manual__title">
            {{ section.title }}
          </h3>
          <q-btn
            flat
            dense
            no-caps
            icon="content_copy"
            :label="t('adminDatabaseTables.schemaEditor.manual.copy')"
            :aria-label="copyLabel(section.title)"
            @click="copy(section)"
          />
        </div>
        <pre
          class="db-schema-manual__code mono"
          tabindex="0"
          :aria-label="section.title"
        >{{ section.sql }}</pre>
        <p v-if="section.statements.length === 0" class="db-schema-manual__empty">
          {{ t("adminDatabaseTables.schemaEditor.manual.emptySection") }}
        </p>
      </section>
    </div>

    <div class="db-schema-manual__footer">
      <q-btn
        outline
        no-caps
        icon="refresh"
        color="primary"
        :label="t('adminDatabaseTables.schemaEditor.manual.recheck')"
        :loading="rechecking"
        @click="$emit('recheck')"
      >
        <q-tooltip>
          {{ t("adminDatabaseTables.schemaEditor.manual.recheckHint") }}
        </q-tooltip>
      </q-btn>
    </div>

    <div v-if="recheckResult" class="db-schema-manual__result">
      <p v-if="recheckResult.done" class="db-schema-manual__result-ok">
        {{ t("adminDatabaseTables.schemaEditor.manual.recheckDone") }}
      </p>
      <template v-else>
        <p class="db-schema-manual__result-pending">
          {{ t("adminDatabaseTables.schemaEditor.manual.stillPending") }}
        </p>
        <ul class="db-schema-manual__result-list">
          <li v-for="item in recheckResult.pending" :key="item">{{ item }}</li>
        </ul>
      </template>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from "vue";
import { useI18n } from "vue-i18n";

import type { AdminDatabaseTableSchemaManualPlanRes } from "src/network/dto/admin/database_table_schema";
import type { ManualRecheckResult } from "src/pages/admin/database/database_table_schema_view";

const props = defineProps<{
  plan: AdminDatabaseTableSchemaManualPlanRes;
  rechecking: boolean;
  recheckResult: ManualRecheckResult | null;
}>();

defineEmits<{
  recheck: [];
}>();

const { t } = useI18n();

const sections = computed(() => [
  {
    key: "precheck",
    title: t("adminDatabaseTables.schemaEditor.manual.precheck"),
    statements: props.plan.precheck,
    sql: joinSql(props.plan.precheck),
  },
  {
    key: "changes",
    title: t("adminDatabaseTables.schemaEditor.manual.changes"),
    statements: props.plan.changes,
    sql: joinSql(props.plan.changes),
  },
  {
    key: "rollback",
    title: t("adminDatabaseTables.schemaEditor.manual.rollback"),
    statements: props.plan.rollback,
    sql: joinSql(props.plan.rollback),
  },
]);

function joinSql(statements: { sql: string }[]): string {
  return statements
    .map((statement) => (statement.sql.endsWith(";") ? statement.sql : `${statement.sql};`))
    .join("\n");
}

function copyLabel(sectionTitle: string): string {
  return t("adminDatabaseTables.schemaEditor.manual.copySection", {
    section: sectionTitle,
  });
}

async function copy(section: { sql: string }): Promise<void> {
  try {
    await navigator.clipboard.writeText(section.sql);
  } catch {
    // 剪贴板不可用时保持静默；文本区可手动全选复制。
  }
}
</script>

<style scoped>
.db-schema-manual {
  display: flex;
  flex-direction: column;
  gap: 12px;
  min-width: 0;
}

.db-schema-manual__banner {
  background: var(--status-warning-bg);
  color: var(--status-warning-text);
  border: 1px solid var(--status-warning-border);
}

.db-schema-manual__sections {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 12px;
}

.db-schema-manual__section {
  display: flex;
  flex-direction: column;
  gap: 6px;
  min-width: 0;
}

.db-schema-manual__head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.db-schema-manual__title {
  margin: 0;
  font-size: var(--spa-font-size-small);
  font-weight: 600;
  color: var(--text-primary);
}

.db-schema-manual__code {
  flex: 1;
  min-height: 200px;
  max-height: 40vh;
  margin: 0;
  padding: 12px;
  overflow: auto;
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--bg-secondary);
  color: var(--text-primary);
  font-size: var(--spa-font-size-caption);
  line-height: 1.5;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}

.db-schema-manual__code:focus-visible {
  outline: 2px solid var(--accent-1);
  outline-offset: 2px;
}

.db-schema-manual__empty {
  margin: 0;
  color: var(--workspace-text-muted);
  font-size: var(--spa-font-size-caption);
}

.db-schema-manual__footer {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  align-items: center;
}

.db-schema-manual__result {
  padding: 12px;
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--bg-card);
}

.db-schema-manual__result-ok {
  margin: 0;
  color: var(--status-success-text);
}

.db-schema-manual__result-pending {
  margin: 0 0 8px;
  color: var(--status-warning-text);
}

.db-schema-manual__result-list {
  margin: 0;
  padding-left: 20px;
  color: var(--text-secondary);
}

@media (max-width: 900px) {
  .db-schema-manual__sections {
    grid-template-columns: minmax(0, 1fr);
  }

  .db-schema-manual__code {
    max-height: 30vh;
  }
}
</style>