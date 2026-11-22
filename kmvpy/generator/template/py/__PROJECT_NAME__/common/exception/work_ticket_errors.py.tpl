"""工单领域业务的 KmvException 错误三元组（42xxx）。"""

TICKET_NOT_FOUND_ERROR = [42001, "工单不存在", "未找到工单或已删除"]
TICKET_REPLY_ERROR = [42002, "回复失败", "工单回复保存失败，请重试"]
TICKET_STATUS_ERROR = [42003, "状态更新失败", "工单状态更新失败，请重试"]
TICKET_CREATE_ERROR = [42004, "创建失败", "工单创建失败，请重试"]
