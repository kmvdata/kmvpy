import { computed, ref } from "vue";

import type {
  AdminDatabaseTableSchemaColumnRes,
  AdminDatabaseTableSchemaColumnType,
  AdminDatabaseTableSchemaIndexRes,
} from "src/network/dto/admin/database_table_schema";

/** 单列在草稿中的变更状态；用于状态条与 chip 文案。 */
export type SchemaColumnChangeKind =
  | "unchanged"
  | "added"
  | "modified"
  | "dropped"
  | "renamed";

/** 索引在草稿中的变更状态。 */
export type SchemaIndexChangeKind = "unchanged" | "added" | "modified" | "dropped";

export interface SchemaColumnDraft extends AdminDatabaseTableSchemaColumnRes {
  /** 稳定的本地行标识；改名不影响它，避免列表 key 抖动。 */
  key: string;
  /** 该行的原始定义；新增列为 null。 */
  baseline: AdminDatabaseTableSchemaColumnRes | null;
  /** 被标记删除但没有真从数组移除，便于撤销。 */
  dropped: boolean;
  /** 本次编辑中被改动过的字段名，用于显示角标与原值 tooltip。 */
  touchedFields: string[];
}

export interface SchemaIndexDraft extends AdminDatabaseTableSchemaIndexRes {
  key: string;
  baseline: AdminDatabaseTableSchemaIndexRes | null;
  dropped: boolean;
}

/** `type_args` 单个输入项的语义标签，决定输入框文案，不做展示文案硬编码。 */
export type ColumnTypeArgLabel = "length" | "precision" | "scale";

/** 各类型的 `type_args` 输入规则，用于动态显示长度/精度输入框。 */
export const COLUMN_TYPE_ARG_RULES: Record<
  AdminDatabaseTableSchemaColumnType,
  { count: number; labels: ColumnTypeArgLabel[] }
> = {
  int: { count: 0, labels: [] },
  bigint: { count: 0, labels: [] },
  smallint: { count: 0, labels: [] },
  text: { count: 0, labels: [] },
  datetime: { count: 0, labels: [] },
  boolean: { count: 0, labels: [] },
  varchar: { count: 1, labels: ["length"] },
  numeric: { count: 2, labels: ["precision", "scale"] },
};

/** 可自增的整型家族。 */
export const AUTOINCREMENT_TYPES: AdminDatabaseTableSchemaColumnType[] = [
  "smallint",
  "int",
  "bigint",
];

let sequence = 0;

function nextKey(prefix: string): string {
  sequence += 1;
  return `${prefix}-${sequence}`;
}

function cloneColumn(
  column: AdminDatabaseTableSchemaColumnRes,
): AdminDatabaseTableSchemaColumnRes {
  return {
    name: column.name,
    original_name: column.original_name,
    type: column.type,
    type_args: column.type_args ? [...column.type_args] : null,
    nullable: column.nullable,
    primary_key: column.primary_key,
    autoincrement: column.autoincrement,
    server_default: column.server_default,
    unique: column.unique,
    indexed: column.indexed,
    comment: column.comment,
  };
}

function columnSignature(column: AdminDatabaseTableSchemaColumnRes): string {
  return JSON.stringify([
    column.name,
    column.type,
    column.type_args ?? null,
    column.nullable,
    column.primary_key,
    column.autoincrement,
    column.server_default,
  ]);
}

function indexSignature(index: AdminDatabaseTableSchemaIndexRes): string {
  return JSON.stringify([[...index.columns].sort(), index.unique]);
}

function draftColumn(
  column: AdminDatabaseTableSchemaColumnRes,
  baseline: AdminDatabaseTableSchemaColumnRes | null,
): SchemaColumnDraft {
  return {
    ...cloneColumn(column),
    key: nextKey("col"),
    baseline: baseline ? cloneColumn(baseline) : null,
    dropped: false,
    touchedFields: [],
  };
}

/**
 * 表结构编辑器的本地草稿状态。
 *
 * 只做纯本地状态：baseline / draft / 变更计数 / 增删改操作。
 * **不调用任何 API** —— 请求留在编辑器组件里，本 composable 可单测。
 */
export function useDatabaseTableSchemaDraft() {
  const baselineColumns = ref<AdminDatabaseTableSchemaColumnRes[]>([]);
  const baselineIndexes = ref<AdminDatabaseTableSchemaIndexRes[]>([]);
  const columns = ref<SchemaColumnDraft[]>([]);
  const indexes = ref<SchemaIndexDraft[]>([]);

  /** 用 describe 结果初始化草稿；原始结构记为 baseline。 */
  function reset(
    currentColumns: AdminDatabaseTableSchemaColumnRes[],
    currentIndexes: AdminDatabaseTableSchemaIndexRes[],
  ): void {
    baselineColumns.value = currentColumns.map(cloneColumn);
    baselineIndexes.value = currentIndexes
      .filter((index) => !index.primary)
      .map((index) => ({ ...index, columns: [...index.columns] }));
    columns.value = currentColumns.map((column) => draftColumn(column, column));
    indexes.value = baselineIndexes.value.map((index) => ({
      ...index,
      columns: [...index.columns],
      key: nextKey("idx"),
      baseline: { ...index, columns: [...index.columns] },
      dropped: false,
    }));
  }

  /** 把 ORM 建议预填成草稿初值；baseline 仍是当前库结构，因此差异立即可见。 */
  function applySuggestion(
    suggestion: {
      columns: AdminDatabaseTableSchemaColumnRes[];
      indexes: AdminDatabaseTableSchemaIndexRes[];
    },
  ): void {
    columns.value = suggestion.columns.map((column) => {
      const base =
        baselineColumns.value.find((item) => item.name === column.name) ?? null;
      return draftColumn(column, base);
    });
    indexes.value = suggestion.indexes
      .filter((index) => !index.primary)
      .map((index) => {
        const base =
          baselineIndexes.value.find(
            (item) => indexSignature(item) === indexSignature(index),
          ) ?? null;
        return {
          ...index,
          columns: [...index.columns],
          key: nextKey("idx"),
          baseline: base ? { ...base, columns: [...base.columns] } : null,
          dropped: false,
        };
      });
  }

  function markTouched(column: SchemaColumnDraft, field: string): void {
    if (!column.touchedFields.includes(field)) {
      column.touchedFields.push(field);
    }
  }

  function addColumn(): SchemaColumnDraft {
    const draft = draftColumn(
      {
        name: "",
        original_name: null,
        type: "int",
        type_args: null,
        nullable: true,
        primary_key: false,
        autoincrement: false,
        server_default: null,
        unique: false,
        indexed: false,
        comment: null,
      },
      null,
    );
    draft.touchedFields = ["name", "type"];
    columns.value.push(draft);
    return draft;
  }

  /**
   * 显式改名：写入 `original_name`，绝不退化成「删列 + 加列」。
   * 只有本来就来自库的列才记录改名来源；新增列改名不写 original_name。
   */
  function renameColumn(column: SchemaColumnDraft, nextName: string): void {
    const normalized = nextName.trim().toLowerCase();
    if (column.baseline && normalized !== column.baseline.name) {
      column.original_name = column.baseline.name;
    } else {
      column.original_name = null;
    }
    column.name = normalized;
    markTouched(column, "name");
  }

  /** 删除不立即移除行：整行灰化 + 删除线 + 可撤销。 */
  function dropColumn(column: SchemaColumnDraft): void {
    column.dropped = true;
  }

  function restoreColumn(column: SchemaColumnDraft): void {
    column.dropped = false;
  }

  /** 真正把新增列从数组移除；已有列只能 drop + restore。 */
  function removeAddedColumn(column: SchemaColumnDraft): void {
    if (column.baseline) {
      dropColumn(column);
      return;
    }
    columns.value = columns.value.filter((item) => item.key !== column.key);
  }

  function moveColumn(column: SchemaColumnDraft, offset: -1 | 1): void {
    const from = columns.value.findIndex((item) => item.key === column.key);
    const to = from + offset;
    if (from < 0 || to < 0 || to >= columns.value.length) {
      return;
    }
    const moved = columns.value[from];
    if (!moved) {
      return;
    }
    const next = [...columns.value];
    next.splice(from, 1);
    next.splice(to, 0, moved);
    columns.value = next;
  }

  function setColumnType(
    column: SchemaColumnDraft,
    type: AdminDatabaseTableSchemaColumnType,
  ): void {
    column.type = type;
    markTouched(column, "type");
    const rule = COLUMN_TYPE_ARG_RULES[type];
    if (rule.count === 0) {
      column.type_args = null;
    } else if (rule.count === 1) {
      column.type_args = [column.type_args?.[0] ?? 255];
    } else {
      column.type_args = [
        column.type_args?.[0] ?? 18,
        column.type_args?.[1] ?? 6,
      ];
    }
    if (!AUTOINCREMENT_TYPES.includes(type)) {
      column.autoincrement = false;
    }
  }

  /**
   * 列上的 `unique` 勾选同步索引条目：索引清单是唯一权威，
   * 因此这里增删单列唯一索引，而不是让两处各自为政。
   */
  function setColumnUnique(column: SchemaColumnDraft, unique: boolean): void {
    markTouched(column, "unique");
    if (!column.name) {
      return;
    }
    const exists = indexes.value.find(
      (index) =>
        index.columns.length === 1 &&
        index.columns[0] === column.name &&
        index.unique,
    );
    if (unique && !exists) {
      indexes.value.push({
        name: null,
        columns: [column.name],
        unique: true,
        primary: false,
        key: nextKey("idx"),
        baseline: null,
        dropped: false,
      });
    } else if (!unique && exists) {
      indexes.value = indexes.value.filter((item) => item.key !== exists.key);
    }
  }

  function addIndex(): SchemaIndexDraft {
    return {
      name: null,
      columns: [],
      unique: false,
      primary: false,
      key: nextKey("idx"),
      baseline: null,
      dropped: false,
    };
  }

  function removeIndex(index: SchemaIndexDraft): void {
    if (index.baseline) {
      index.dropped = true;
      return;
    }
    indexes.value = indexes.value.filter((item) => item.key !== index.key);
  }

  function restoreIndex(index: SchemaIndexDraft): void {
    index.dropped = false;
  }

  /** 当前生效的目标列：排除已标记删除的行。 */
  const activeColumns = computed(() =>
    columns.value.filter((column) => !column.dropped),
  );

  const activeIndexes = computed(() =>
    indexes.value.filter((index) => !index.dropped && index.columns.length > 0),
  );

  function columnChangeKind(column: SchemaColumnDraft): SchemaColumnChangeKind {
    if (column.dropped) {
      return "dropped";
    }
    if (!column.baseline) {
      return "added";
    }
    if (column.original_name && column.original_name !== column.baseline.name) {
      return "renamed";
    }
    return columnSignature(column) === columnSignature(column.baseline)
      ? "unchanged"
      : "modified";
  }

  function indexChangeKind(index: SchemaIndexDraft): SchemaIndexChangeKind {
    if (index.dropped) {
      return "dropped";
    }
    if (!index.baseline) {
      return "added";
    }
    return indexSignature(index) === indexSignature(index.baseline)
      ? "unchanged"
      : "modified";
  }

  /** 待执行变更项数量，用于标题徽标。 */
  const dirtyCount = computed(() => {
    const columnChanges = columns.value.filter(
      (column) => columnChangeKind(column) !== "unchanged",
    ).length;
    const indexChanges = indexes.value.filter(
      (index) => indexChangeKind(index) !== "unchanged",
    ).length;
    return columnChanges + indexChanges;
  });

  /** 已存在的列：只有它们参与列顺序调整。 */
  const hasExistingColumns = computed(() =>
    columns.value.some((column) => column.baseline !== null),
  );

  return {
    columns,
    indexes,
    activeColumns,
    activeIndexes,
    dirtyCount,
    hasExistingColumns,
    reset,
    applySuggestion,
    addColumn,
    renameColumn,
    dropColumn,
    restoreColumn,
    removeAddedColumn,
    moveColumn,
    setColumnType,
    setColumnUnique,
    addIndex,
    removeIndex,
    restoreIndex,
    columnChangeKind,
    indexChangeKind,
  };
}