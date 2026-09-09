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
    "该数据表未在 ORM 初始化清单中注册，无法自动重建",
]

DATABASE_TABLE_OPERATION_FAILED_ERROR = [
    46005,
    "数据表操作失败",
    "数据表操作失败，请稍后重试",
]

DATABASE_TABLE_INITIALIZE_CONFIRM_MISMATCH_ERROR = [
    46006,
    "全量初始化确认不一致",
    "全量初始化确认文本不一致",
]
