/**
 * 表结构编辑器的本地视图类型。
 *
 * 放在独立模块而不是 `.vue` 里：`<script setup>` 不允许 `export`，
 * 而编辑器编排器需要从组件外部引用这些类型。
 */

import type { AdminDatabaseTableSchemaRiskItemRes } from "src/network/dto/admin/database_table_schema";

/** 风险项附带「哪一列」，便于在 UI 上给出定位信息。 */
export interface SchemaRiskItemView extends AdminDatabaseTableSchemaRiskItemRes {
  column: string | null;
}

/** 手动方案「重新检测」的结果：是否全部完成，以及仍未完成的项。 */
export interface ManualRecheckResult {
  done: boolean;
  pending: string[];
}