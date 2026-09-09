"""管理端系统维护相关业务错误（47xxx）。"""

SERVICE_RESTART_CONFIRM_MISMATCH_ERROR = [
    47001,
    "服务重启确认不一致",
    "服务重启确认文本不一致",
]

SERVICE_RESTART_SCRIPT_NOT_FOUND_ERROR = [
    47002,
    "未找到服务重启脚本",
    "未找到当前运行配置对应的 deploy.sh，无法由管理后台触发重启",
]

SERVICE_RESTART_TRIGGER_FAILED_ERROR = [
    47003,
    "服务重启触发失败",
    "服务重启触发失败，请稍后重试",
]
