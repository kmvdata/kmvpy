<template>
  <div class="db-data-panel">
    <q-banner v-if="errorText" rounded class="db-data-panel__banner">
      <div class="db-data-panel__banner-body">
        <span>{{ errorText }}</span>
        <q-btn
          flat
          dense
          no-caps
          color="primary"
          icon="refresh"
          :label="t('common.retry')"
          :loading="loading || refreshing"
          @click="reload()"
        />
      </div>
    </q-banner>

    <!-- 查询条件：WHERE 必填、ORDER BY 可选；两行同高，输入占满整行。 -->
    <div class="db-data-panel__query">
      <div class="db-data-panel__query-rows">
        <div class="db-data-panel__query-row">
          <q-icon
            name="filter_alt"
            size="16px"
            class="db-data-panel__query-icon"
            aria-hidden="true"
          />
          <div class="db-data-panel__query-code">
            <span class="mono db-data-panel__query-keyword" aria-hidden="true">
              WHERE
            </span>
            <q-input
              ref="whereField"
              v-model="whereDraft"
              borderless
              dense
              class="mono db-data-panel__query-input"
              :placeholder="t('adminDatabaseTables.data.query.wherePlaceholder')"
              :aria-label="t('adminDatabaseTables.data.query.whereAria')"
              :maxlength="WHERE_MAX_LENGTH"
              :disable="loading"
              @keydown.ctrl.enter.prevent="applyQuery"
              @keydown.meta.enter.prevent="applyQuery"
            />
          </div>
          <q-btn
            flat
            dense
            round
            size="sm"
            icon="playlist_add"
            :aria-label="t('adminDatabaseTables.data.query.insertColumn')"
            :disable="loading || columnNames.length === 0"
          >
            <q-menu>
              <q-list dense class="db-data-panel__column-menu">
                <q-item
                  v-for="name in columnNames"
                  :key="`insert-${name}`"
                  clickable
                  @click="insertColumnName(name)"
                >
                  <q-item-section>
                    <q-item-label class="mono">{{ name }}</q-item-label>
                  </q-item-section>
                </q-item>
              </q-list>
            </q-menu>
          </q-btn>
          <q-btn
            v-if="whereDraft !== ''"
            flat
            dense
            round
            size="sm"
            icon="close"
            class="db-data-panel__query-clear"
            :aria-label="t('adminDatabaseTables.data.query.clearWhere')"
            :disable="loading"
            @click="clearQueryField('where')"
          >
            <q-tooltip>
              {{ t("adminDatabaseTables.data.query.clearWhere") }}
            </q-tooltip>
          </q-btn>
        </div>

        <div class="db-data-panel__query-row">
          <q-icon
            name="swap_vert"
            size="16px"
            class="db-data-panel__query-icon"
            aria-hidden="true"
          />
          <div class="db-data-panel__query-code">
            <span class="mono db-data-panel__query-keyword" aria-hidden="true">
              ORDER BY
            </span>
            <q-input
              v-model="orderByDraft"
              borderless
              dense
              class="mono db-data-panel__query-input"
              :placeholder="t('adminDatabaseTables.data.query.orderByPlaceholder')"
              :aria-label="t('adminDatabaseTables.data.query.orderByAria')"
              :maxlength="ORDER_BY_MAX_LENGTH"
              :disable="loading"
              @keydown.ctrl.enter.prevent="applyQuery"
              @keydown.meta.enter.prevent="applyQuery"
            />
          </div>
          <q-btn
            v-if="orderByDraft !== ''"
            flat
            dense
            round
            size="sm"
            icon="close"
            class="db-data-panel__query-clear"
            :aria-label="t('adminDatabaseTables.data.query.clearOrderBy')"
            :disable="loading"
            @click="clearQueryField('order')"
          >
            <q-tooltip>
              {{ t("adminDatabaseTables.data.query.clearOrderBy") }}
            </q-tooltip>
          </q-btn>
        </div>
      </div>

      <div class="db-data-panel__query-actions">
        <q-btn
          unelevated
          no-caps
          color="primary"
          icon="play_arrow"
          :label="t('adminDatabaseTables.data.query.apply')"
          :disable="loading"
          @click="applyQuery"
        />
        <q-btn
          flat
          no-caps
          icon="restart_alt"
          :label="t('adminDatabaseTables.data.query.reset')"
          :disable="loading"
          @click="resetQuery"
        />
        <span class="db-data-panel__query-hint">
          {{ t("adminDatabaseTables.data.query.grammarHint") }}
        </span>

        <!-- 视图设置：与条件应用同一行，贴近下方表格。 -->
        <div class="db-data-panel__view-tools">
          <span
            v-if="primaryKeyColumns.length === 0"
            class="db-data-panel__hint mono"
          >
            {{ t("adminDatabaseTables.data.noPrimaryKey") }}
          </span>
          <q-btn
            flat
            dense
            no-caps
            icon="refresh"
            :label="t('adminDatabaseTables.data.refresh')"
            :loading="refreshing"
            :disable="loading"
            @click="reload()"
          />
          <q-select
            v-model="pageSize"
            :options="PAGE_SIZE_OPTIONS"
            dense
            outlined
            emit-value
            map-options
            class="db-data-panel__size"
            :label="t('adminDatabaseTables.data.pageSize')"
            :disable="loading"
            @update:model-value="onPageSizeChange"
          />
          <q-btn
            flat
            dense
            no-caps
            icon="view_column"
            :label="t('adminDatabaseTables.data.columns')"
          >
            <q-menu>
              <q-list dense class="db-data-panel__column-menu">
                <q-item
                  v-for="column in dataColumns"
                  :key="`menu-${column.name}`"
                  tag="label"
                  clickable
                >
                  <q-item-section side>
                    <q-checkbox
                      :model-value="!hiddenColumns.has(column.name)"
                      dense
                      @update:model-value="(value) => toggleColumn(column.name, value)"
                    />
                  </q-item-section>
                  <q-item-section>
                    <q-item-label class="mono">{{ column.name }}</q-item-label>
                  </q-item-section>
                </q-item>
              </q-list>
            </q-menu>
          </q-btn>
        </div>
      </div>
    </div>
    <div class="db-data-panel__hint">{{ queryStateText }}</div>

    <div class="db-data-panel__table-wrap">
      <q-inner-loading :showing="loading" color="primary" />
      <table class="data-table db-data-panel__table">
        <thead>
          <tr>
            <th
              v-for="column in visibleColumns"
              :key="`th-${column.name}`"
              scope="col"
            >
              <button
                type="button"
                class="db-data-panel__sort"
                :aria-label="
                  t('adminDatabaseTables.data.sortColumn', {
                    column: column.name,
                  })
                "
                @click="toggleSort(column.name)"
              >
                <span class="mono">{{ column.name }}</span>
                <q-icon
                  v-if="column.primary_key"
                  name="key"
                  size="12px"
                  aria-hidden="true"
                />
                <q-icon
                  :name="sortIcon(column.name)"
                  size="14px"
                  :class="{
                    'db-data-panel__sort-icon': true,
                    'is-active': orderBy === column.name,
                  }"
                  aria-hidden="true"
                />
              </button>
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="!loading && !errorText && displayRows.length === 0">
            <td
              :colspan="visibleColumns.length || 1"
              class="db-data-panel__empty"
            >
              {{ emptyText }}
            </td>
          </tr>
          <tr v-for="displayRow in displayRows" :key="displayRow.key">
            <td
              v-for="(entry, cellIndex) in displayRow.cells"
              :key="`${displayRow.key}-${cellIndex}`"
              :class="cellClass(entry.cell)"
            >
              <span
                v-if="entry.cell === null || entry.cell.kind === 'null'"
                class="db-data-panel__null"
              >
                {{ t("adminDatabaseTables.data.cellNull") }}
              </span>
              <span
                v-else-if="entry.cell.kind === 'binary'"
                class="mono db-data-panel__binary"
              >
                {{
                  t("adminDatabaseTables.data.cellBinary", {
                    bytes: entry.cell.byte_length ?? 0,
                  })
                }}
              </span>
              <button
                v-else-if="entry.cell.truncated"
                type="button"
                class="db-data-panel__cell-button mono"
                :aria-label="t('adminDatabaseTables.data.cellExpand')"
                @click="openCellDialog(entry.column, entry.cell.text ?? '')"
              >
                {{ entry.cell.text }}…
              </button>
              <span v-else class="mono">{{ entry.cell.text }}</span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <div class="db-data-panel__footer">
      <span class="mono">{{ rangeText }}</span>
      <span class="mono">{{ totalText }}</span>
      <div class="db-data-panel__pager">
        <q-btn
          flat
          dense
          no-caps
          icon="chevron_left"
          :label="t('adminDatabaseTables.data.prevPage')"
          :disable="page <= 1 || loading"
          @click="goToPage(page - 1)"
        />
        <span class="mono">{{ page }}</span>
        <q-btn
          flat
          dense
          no-caps
          icon-right="chevron_right"
          :label="t('adminDatabaseTables.data.nextPage')"
          :disable="!hasNextPage || loading"
          @click="goToPage(page + 1)"
        />
      </div>
    </div>

    <q-dialog v-model="cellDialogOpen" :maximized="$q.screen.lt.md">
      <q-card class="db-data-panel__cell-dialog">
        <q-card-section class="db-data-panel__cell-dialog-head">
          <div class="db-data-panel__cell-dialog-copy">
            <div class="spa-section-title">
              {{ t("adminDatabaseTables.data.cellDialogTitle") }}
            </div>
            <div class="mono db-data-panel__cell-dialog-column">
              {{ cellDialogColumn }}
            </div>
          </div>
          <q-btn
            flat
            dense
            round
            icon="close"
            :aria-label="t('adminDatabaseTables.data.cellDialogClose')"
            @click="cellDialogOpen = false"
          />
        </q-card-section>
        <q-separator />
        <q-card-section class="db-data-panel__cell-dialog-body">
          <pre class="mono db-data-panel__cell-dialog-code" tabindex="0">{{
            cellDialogText
          }}</pre>
        </q-card-section>
      </q-card>
    </q-dialog>
  </div>
</template>

<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { useQuasar } from "quasar";
import { useI18n } from "vue-i18n";

import { ApiAdminDatabaseTable } from "src/network/api/admin/database_table";
import type {
  AdminDatabaseTableColumnRes,
  AdminDatabaseTableIndexRes,
  AdminDatabaseTableRowsCellRes,
  AdminDatabaseTableRowsColumnRes,
} from "src/network/dto/admin/database_table";
import { useKmvApiErrorMessage } from "src/i18n/kmv/useKmvApiErrorMessage";

const props = defineProps<{
  tableName: string;
  columns: AdminDatabaseTableColumnRes[];
  indexes: AdminDatabaseTableIndexRes[];
}>();

const { t } = useI18n();
const $q = useQuasar();
const { resolveFromError } = useKmvApiErrorMessage();

const PAGE_SIZE_OPTIONS = [20, 50, 100, 200];
const DEFAULT_PAGE_SIZE = 50;
const WHERE_MAX_LENGTH = 500;
const ORDER_BY_MAX_LENGTH = 200;

const dataColumns = ref<AdminDatabaseTableRowsColumnRes[]>([]);
const rows = ref<AdminDatabaseTableRowsCellRes[][]>([]);
const primaryKeyColumns = ref<string[]>([]);
const total = ref<number | null>(null);
const page = ref(1);
const pageSize = ref(DEFAULT_PAGE_SIZE);
const orderBy = ref<string | null>(null);
const orderDesc = ref(false);
const loading = ref(false);
const refreshing = ref(false);
const loaded = ref(false);
const errorText = ref("");
const whereDraft = ref("");
const orderByDraft = ref("");
/**
 * 已提交给后端的条件：只有「应用条件」、排序切换与重置会写入。
 * 草稿与它不一致时界面提示未生效，避免用户以为改动已作用于当前结果。
 */
const appliedWhere = ref<string | null>(null);
const appliedOrderBy = ref<string | null>(null);
const whereField = ref<{ focus: () => void } | null>(null);
const cellDialogOpen = ref(false);
const cellDialogColumn = ref("");
const cellDialogText = ref("");

/**
 * 列显隐只存组件内存：关闭/离开页面即恢复全显，不写 localStorage。
 * 这样每次进入数据视图都是一致的全列视图。
 */
const hiddenColumns = ref<Set<string>>(new Set());

/**
 * 请求序号：首次加载、刷新、翻页、排序、切换数据表都会自增。
 * 迟到响应比对序号后直接丢弃，避免旧表或旧排序的结果覆盖新状态。
 */
let requestSeq = 0;

const columnNames = computed(() => dataColumns.value.map((item) => item.name));

/** 空串与纯空白都视为「没有条件」，与后端归一规则保持一致。 */
function normalizeClause(text: string): string | null {
  const trimmed = text.trim();
  return trimmed === "" ? null : trimmed;
}

/** 草稿是否还有未提交的改动。 */
const queryDirty = computed(
  () =>
    normalizeClause(whereDraft.value) !== appliedWhere.value ||
    normalizeClause(orderByDraft.value) !== appliedOrderBy.value,
);

/** 条件区的一行状态说明：优先提示未提交的改动，其次说明当前过滤范围。 */
const queryStateText = computed(() => {
  if (queryDirty.value) {
    return t("adminDatabaseTables.data.query.dirtyHint");
  }
  if (appliedWhere.value === null) {
    return t("adminDatabaseTables.data.query.appliedNone");
  }
  return t("adminDatabaseTables.data.query.appliedWhere", {
    clause: appliedWhere.value,
  });
});

const visibleColumns = computed(() =>
  dataColumns.value.filter((item) => !hiddenColumns.value.has(item.name)),
);

/** 列名 → 在行数组中的下标；行单元格顺序与响应 columns 一致。 */
const columnIndexByName = computed(() => {
  const index = new Map<string, number>();
  dataColumns.value.forEach((item, position) => {
    index.set(item.name, position);
  });
  return index;
});

function cellOf(
  row: AdminDatabaseTableRowsCellRes[],
  columnName: string,
): AdminDatabaseTableRowsCellRes | null {
  const position = columnIndexByName.value.get(columnName);
  if (position === undefined) {
    return null;
  }
  return row[position] ?? null;
}

/** 有主键时用主键值拼行标识；无主键降级为下标。 */
function rowKey(row: AdminDatabaseTableRowsCellRes[], rowIndex: number): string {
  if (primaryKeyColumns.value.length === 0) {
    return `row-${rowIndex}`;
  }
  const parts = primaryKeyColumns.value.map((name) => {
    const cell = cellOf(row, name);
    return cell?.text ?? "null";
  });
  return parts.join("|");
}

const displayRows = computed(() =>
  rows.value.map((row, rowIndex) => ({
    key: rowKey(row, rowIndex),
    cells: visibleColumns.value.map((column) => ({
      column: column.name,
      cell: cellOf(row, column.name),
    })),
  })),
);

const hasNextPage = computed(() => {
  if (total.value !== null) {
    return page.value * pageSize.value < total.value;
  }
  // 总数未知时用“本页是否满”判断是否还有下一页。
  return rows.value.length === pageSize.value;
});

const rangeText = computed(() => {
  if (rows.value.length === 0) {
    return "";
  }
  const from = (page.value - 1) * pageSize.value + 1;
  const to = (page.value - 1) * pageSize.value + rows.value.length;
  return t("adminDatabaseTables.data.rowRange", { from, to });
});

const totalText = computed(() => {
  if (total.value !== null) {
    return t("adminDatabaseTables.data.total", { total: total.value });
  }
  // 总数只在第一页读取；翻页后给保守下界，不假装精确。
  const known = (page.value - 1) * pageSize.value + rows.value.length;
  return t("adminDatabaseTables.data.totalUnknown", { count: known });
});

/**
 * 两种空态：当前页无数据且不在第一页时按「翻阅到空结果」呈现，
 * 其余情况是该表本身没有数据。
 */
const emptyText = computed(() =>
  page.value > 1
    ? t("adminDatabaseTables.data.emptyFiltered")
    : t("adminDatabaseTables.data.emptyTable"),
);

function resolveMessage(error: unknown, fallbackKey: string): string {
  const fallback = t(fallbackKey);
  const kmvMessage = resolveFromError(error);
  if (kmvMessage && kmvMessage !== t("api.kmv.fallback")) {
    return kmvMessage;
  }
  return error instanceof Error && error.message ? error.message : fallback;
}

function cellClass(cell: AdminDatabaseTableRowsCellRes | null): string[] {
  if (cell === null) {
    return ["db-data-panel__cell", "db-data-panel__cell--muted"];
  }
  if (cell.kind === "number") {
    return ["db-data-panel__cell", "db-data-panel__cell--number"];
  }
  if (cell.kind === "null") {
    return ["db-data-panel__cell", "db-data-panel__cell--muted"];
  }
  return ["db-data-panel__cell"];
}

function sortIcon(columnName: string): string {
  if (orderBy.value !== columnName) {
    return "unfold_more";
  }
  return orderDesc.value ? "arrow_downward" : "arrow_upward";
}

function toggleColumn(columnName: string, visible: unknown): void {
  const next = new Set(hiddenColumns.value);
  if (visible) {
    next.delete(columnName);
  } else {
    next.add(columnName);
  }
  hiddenColumns.value = next;
}

async function load(): Promise<void> {
  requestSeq += 1;
  const current = requestSeq;
  const isFirstLoad = !loaded.value;
  if (isFirstLoad) {
    loading.value = true;
  } else {
    refreshing.value = true;
  }
  errorText.value = "";
  try {
    const res = await ApiAdminDatabaseTable.listRows({
      table_name: props.tableName,
      page: page.value,
      size: pageSize.value,
      // 单列 order_by/order_desc 保留为默认排序；应用了 ORDER BY 条件时后端以
      // order_by_clause 优先，两者不会互相覆盖。
      order_by: orderBy.value,
      order_desc: orderDesc.value,
      where_clause: appliedWhere.value,
      order_by_clause: appliedOrderBy.value,
    });
    if (current !== requestSeq) {
      return;
    }
    dataColumns.value = res.columns;
    rows.value = res.rows;
    primaryKeyColumns.value = res.primary_key_columns;
    total.value = res.total;
    loaded.value = true;
  } catch (error) {
    if (current !== requestSeq) {
      return;
    }
    // 保留已展示的旧行，只在顶部提示失败并提供重试。
    errorText.value = resolveMessage(
      error,
      "adminDatabaseTables.data.errors.loadFailed",
    );
    if (isFirstLoad) {
      rows.value = [];
      total.value = null;
    }
  } finally {
    if (current === requestSeq) {
      loading.value = false;
      refreshing.value = false;
    }
  }
}

function reload(): void {
  void load();
}

function goToPage(nextPage: number): void {
  if (nextPage < 1) {
    return;
  }
  page.value = nextPage;
  void load();
}

function onPageSizeChange(): void {
  page.value = 1;
  void load();
}

function toggleSort(columnName: string): void {
  if (orderBy.value === columnName) {
    orderDesc.value = !orderDesc.value;
  } else {
    orderBy.value = columnName;
    orderDesc.value = false;
  }
  // 列头是排序的快捷入口：同步写回 ORDER BY 输入框并立即作为生效条件下发，
  // 让「界面显示」与「实际查询」始终一致。
  const clause = `${columnName} ${orderDesc.value ? "DESC" : "ASC"}`;
  orderByDraft.value = clause;
  appliedOrderBy.value = clause;
  // 排序改变后原页码可能越界，回到第一页并重新读取总行数。
  page.value = 1;
  void load();
}

/**
 * 应用查询条件：把两块草稿提交为生效条件并回到第一页。
 * 空文本表示「不限制」，因此清空 WHERE 再应用等价于取消过滤。
 * 语法与列名由后端受限查询语言校验，失败以 46013 / 46012 返回并显示在顶部提示区。
 */
function applyQuery(): void {
  appliedWhere.value = normalizeClause(whereDraft.value);
  appliedOrderBy.value = normalizeClause(orderByDraft.value);
  page.value = 1;
  void load();
}

/**
 * 行内 × 只清空目标行的文本，不改变已生效条件：仍需点「应用条件」才会取消
 * 该行过滤，状态提示会先显示为未生效。
 */
function clearQueryField(target: "where" | "order"): void {
  if (target === "where") {
    whereDraft.value = "";
    // 清空后把光标留在 WHERE 行，用户可以直接重新输入。
    whereField.value?.focus();
  } else {
    orderByDraft.value = "";
  }
}

/**
 * 重置回到初始视图：无 WHERE 条件 + 默认排序，并立即生效。
 * 它表达的是「回到初始查询」，因此会重新读取第一页数据。
 */
function resetQuery(): void {
  whereDraft.value = "";
  appliedWhere.value = null;
  const defaultOrderBy =
    orderBy.value === null
      ? null
      : `${orderBy.value} ${orderDesc.value ? "DESC" : "ASC"}`;
  orderByDraft.value = defaultOrderBy ?? "";
  appliedOrderBy.value = defaultOrderBy;
  page.value = 1;
  void load();
}

/** 把列名追加到 WHERE 末尾，减少手写列名的拼写错误。 */
function insertColumnName(columnName: string): void {
  const current = whereDraft.value;
  const separator = current === "" || /\s$/.test(current) ? "" : " ";
  whereDraft.value = `${current}${separator}${columnName}`;
}

function openCellDialog(columnName: string, text: string): void {
  cellDialogColumn.value = columnName;
  cellDialogText.value = text;
  cellDialogOpen.value = true;
}

/**
 * 首次进入与切换数据表：重置分页、排序、列显隐与搜索状态。
 * 显隐不落盘，因此换表后同样回到全显，避免隐式沿用上一张表的可见列。
 */
function resetForTable(): void {
  dataColumns.value = props.columns.map((column) => ({
    name: column.name,
    type: column.type,
    nullable: column.nullable,
    primary_key: column.primary_key,
  }));
  rows.value = [];
  primaryKeyColumns.value = [];
  total.value = null;
  page.value = 1;
  pageSize.value = DEFAULT_PAGE_SIZE;
  orderDesc.value = false;
  loaded.value = false;
  errorText.value = "";
  hiddenColumns.value = new Set();
  whereDraft.value = "";
  appliedWhere.value = null;
  // 默认按首个主键列排序；没有主键时不指定排序。
  const primaryIndex = props.indexes.find((index) => index.primary);
  const primaryColumn = primaryIndex?.columns[0] ?? "";
  orderBy.value = primaryColumn || null;
  orderByDraft.value = primaryColumn ? `${primaryColumn} ASC` : "";
  appliedOrderBy.value = orderByDraft.value === "" ? null : orderByDraft.value;
}

watch(
  () => props.tableName,
  () => {
    resetForTable();
    void load();
  },
  { immediate: true },
);

// 显隐当前列后至少要保留一列可见，否则表格会退化成空白。
watch(hiddenColumns, (hidden) => {
  if (dataColumns.value.length > 0 && hidden.size >= dataColumns.value.length) {
    const keep = dataColumns.value[0]?.name;
    if (keep) {
      const next = new Set(hidden);
      next.delete(keep);
      hiddenColumns.value = next;
    }
  }
});
</script>

<style scoped>
.db-data-panel {
  display: flex;
  flex-direction: column;
  gap: 12px;
  min-width: 0;
}

.db-data-panel__banner {
  margin: 0;
}

.db-data-panel__banner-body {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 12px;
}

.db-data-panel__footer,
.db-data-panel__pager {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
}

.db-data-panel__query {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.db-data-panel__query-rows {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.db-data-panel__query-row {
  display: flex;
  align-items: center;
  gap: 8px;
  /* 两行等高：单行文字 + 统一内边距。 */
  min-height: 40px;
  padding: 0 6px 0 10px;
  border: 1px solid var(--border);
  border-radius: 6px;
  /* 代码行观感：用主题次级底色，深色主题下即为深底浅字，浅色主题下仍可读。 */
  background: var(--bg-secondary);
  color: var(--text-primary);
}

.db-data-panel__query-row:focus-within {
  border-color: var(--accent-1);
}

.db-data-panel__query-row.is-invalid {
  border-color: var(--spa-danger);
}

.db-data-panel__query-icon {
  flex: none;
  color: var(--workspace-text-muted);
}

.db-data-panel__query-code {
  display: flex;
  flex: 1;
  align-items: center;
  gap: 6px;
  min-width: 0;
  font-size: var(--spa-font-size-small);
}

/* 两行关键字等宽，保证两个输入框的左边缘上下对齐。 */
.db-data-panel__query-keyword {
  flex: none;
  min-width: 8ch;
  color: var(--accent-1);
  font-size: var(--spa-font-size-small);
  font-weight: 600;
  user-select: none;
}

.db-data-panel__query-input {
  flex: 1;
  min-width: 0;
  font-size: var(--spa-font-size-small);
}

/* 输入区不再叠第二层边框，与行底色融为一体，只保留整行的外框。 */
.db-data-panel__query-input :deep(.q-field__control) {
  min-height: 36px;
  padding: 0;
}

.db-data-panel__query-input :deep(.q-field__native) {
  color: var(--text-primary);
}

.db-data-panel__query-input :deep(.q-field__native)::placeholder {
  color: var(--workspace-text-muted);
  opacity: 1;
}

.db-data-panel__query-clear {
  flex: none;
  color: var(--workspace-text-muted);
}

.db-data-panel__query-hint {
  margin-top: 4px;
  color: var(--workspace-text-muted);
  font-size: var(--spa-font-size-caption);
  overflow-wrap: anywhere;
}

.db-data-panel__query-actions {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
}

/* 视图设置靠右收在同一行末尾；窄屏整组换行但仍在条件区底部。 */
.db-data-panel__view-tools {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  margin-left: auto;
}

.db-data-panel__size {
  width: 120px;
}

.db-data-panel__column-menu {
  max-height: 320px;
  overflow-y: auto;
  min-width: 200px;
}

.db-data-panel__hint {
  color: var(--workspace-text-muted);
  font-size: var(--spa-font-size-caption);
  overflow-wrap: anywhere;
}

.db-data-panel__table-wrap {
  position: relative;
  border: 1px solid var(--border);
  border-radius: 8px;
  background: var(--bg-card);
  /* 列多时只在本容器内横向滚动，页面主体不产生整体横向滚动。 */
  overflow-x: auto;
}

.db-data-panel__table {
  width: 100%;
  min-width: 640px;
}

.db-data-panel__table thead th {
  position: sticky;
  top: 0;
  z-index: 1;
  color: var(--workspace-text-muted);
  background: var(--bg-secondary);
  font-size: var(--spa-font-size-caption);
  font-weight: 600;
  white-space: nowrap;
  text-align: left;
}

.db-data-panel__sort {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 2px 4px;
  border: none;
  border-radius: 4px;
  background: transparent;
  color: inherit;
  font: inherit;
  cursor: pointer;
}

.db-data-panel__sort:hover {
  color: var(--text-primary);
}

.db-data-panel__sort:focus-visible {
  outline: 2px solid color-mix(in srgb, var(--accent-1) 50%, transparent);
  outline-offset: 2px;
}

.db-data-panel__sort-icon {
  opacity: 0.5;
}

.db-data-panel__sort-icon.is-active {
  opacity: 1;
  color: var(--accent-1);
}

.db-data-panel__cell {
  color: var(--text-primary);
  font-size: var(--spa-font-size-small);
  vertical-align: top;
  max-width: 320px;
  overflow-wrap: anywhere;
}

.db-data-panel__cell--number {
  text-align: right;
  white-space: nowrap;
}

.db-data-panel__cell--muted {
  color: var(--workspace-text-muted);
}

.db-data-panel__null {
  font-style: italic;
}

.db-data-panel__binary {
  color: var(--workspace-text-muted);
}

.db-data-panel__cell-button {
  padding: 0;
  border: none;
  background: transparent;
  color: var(--accent-1);
  font: inherit;
  text-align: left;
  cursor: pointer;
  overflow-wrap: anywhere;
}

.db-data-panel__cell-button:hover {
  text-decoration: underline;
}

.db-data-panel__cell-button:focus-visible {
  outline: 2px solid color-mix(in srgb, var(--accent-1) 50%, transparent);
  outline-offset: 2px;
}

.db-data-panel__empty {
  padding: 20px 12px;
  text-align: center;
  color: var(--workspace-text-muted);
}

.db-data-panel__footer {
  justify-content: space-between;
  color: var(--workspace-text-muted);
  font-size: var(--spa-font-size-caption);
}

.db-data-panel__pager {
  margin-left: auto;
}

.db-data-panel__cell-dialog {
  width: min(720px, 100%);
}

.db-data-panel__cell-dialog-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
}

.db-data-panel__cell-dialog-copy {
  min-width: 0;
}

.db-data-panel__cell-dialog-column {
  color: var(--workspace-text-muted);
  font-size: var(--spa-font-size-caption);
  overflow-wrap: anywhere;
}

.db-data-panel__cell-dialog-code {
  margin: 0;
  max-height: 60vh;
  overflow: auto;
  color: var(--text-primary);
  font-size: var(--spa-font-size-small);
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}

@media (max-width: 720px) {
  .db-data-panel__size {
    width: 100%;
  }

  .db-data-panel__footer {
    flex-direction: column;
    align-items: flex-start;
  }

  .db-data-panel__pager {
    margin-left: 0;
  }

  /* 窄屏不继承 640px 最小宽度，避免整页被撑出横向滚动。 */
  .db-data-panel__table {
    min-width: 520px;
  }
}
</style>