"""管理端数据库表维护相关业务错误（46xxx）。"""

DATABASE_CONNECTION_INVALID_ERROR = [
    46001,
    "数据库连接无效",
    "无法连接到指定数据库，请检查连接配置",
]

DATABASE_TABLE_NOT_FOUND_ERROR = [
    46002,
    "数据表不存在",
    "未找到指定数据表",
]

DATABASE_TABLE_CONFIRM_MISMATCH_ERROR = [
    46003,
    "确认表名不一致",
    "确认表名与目标表名不一致",
]

DATABASE_TABLE_REGENERATE_UNREGISTERED_ERROR = [
    46004,
    "数据表未注册",
    "该数据表未在 ORM 初始化清单中注册，无法按 ORM 建议",
]

DATABASE_TABLE_OPERATION_FAILED_ERROR = [
    46005,
    "数据表操作失败",
    "数据表操作失败，请稍后重试",
]

DATABASE_SCOPE_FORBIDDEN_ERROR = [
    46007,
    "数据库不在允许清单",
    "当前只允许操作配置文件指定的数据库",
]

SCHEMA_SPEC_INVALID_ERROR = [
    46008,
    "结构定义不合法",
    "表结构定义不合法，请检查类型、默认值或标识符",
]

SCHEMA_STALE_ERROR = [
    46009,
    "表结构已变化",
    "表结构已发生变化，请重新加载后再试",
]

SCHEMA_MANUAL_REQUIRED_ERROR = [
    46010,
    "需要手动处理",
    "该变更无法自动执行，请按生成的手动方案处理",
]

SCHEMA_APPLY_FAILED_ERROR = [
    46011,
    "结构变更执行失败",
    "结构变更执行失败，已回滚到执行前状态",
]

DATABASE_TABLE_COLUMN_UNKNOWN_ERROR = [
    46012,
    "未知列",
    "查询条件或排序使用的列不存在",
]

QUERY_CLAUSE_SYNTAX_INVALID_ERROR = [
    46013,
    "查询条件不合法",
    "查询条件不合法或包含不允许的内容，仅支持比较、LIKE/ILIKE、IN、BETWEEN、IS NULL 与 AND/OR/NOT",
]
