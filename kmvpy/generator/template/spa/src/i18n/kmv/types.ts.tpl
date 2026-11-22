/** 与后端 KmvException / ApiResponse 对齐的业务错误载荷（用于按 code 做前端 i18n）。 */
export interface KmvApiErrorParams {
  minScore?: number;
  maxScore?: number;
}

export interface KmvApiErrorPayload {
  code: number;
  msg: string | null;
  /** Kmv 三元组第二段；仅当多个语义共用同一 code 时参与歧义消解。 */
  title?: string;
  /** 预留：后端若下发结构化字段（如评分区间），先填入此处再交给文案插值。 */
  params?: KmvApiErrorParams;
}
