# 配置与业务异常

在修改 `AppConfig`、环境配置 helper、业务错误常量、动态错误 builder 或 `KmvException` 使用方式时读取本文件。

## Configuration

- 让项目 `AppConfig` 继承 kmvpy `BaseConfig`，保持 `get_app_config()` 为统一读取入口。
- 只把真正随部署环境变化的值建模为配置；不要把业务状态或运行结果放入配置。
- 为一个明确用途提供一个读取 helper，使用 `get_xxx_config()` 或 `get_current_xxx()` 命名。
- 对必需配置快速失败并给出明确异常；对可选配置返回类型稳定的安全回退值。
- 需要按环境映射时，优先在 `AppConfig` 内部基于 `self.general.env` 完成。
- 不在配置方法中放业务规则、数据库访问、网络 IO 或资源初始化。
- Service 不直接读取 Config；由 Hub 读取并转换成稳定业务输入。

## Business Exceptions

- 只在 `__PROJECT_NAME__/common/exception/*_errors.py` 定义 `[code, title, message]` 错误三元组。
- 新错误先选择现有业务主题模块；没有匹配主题时才创建新模块，并先检查现有编号区间避免冲突。
- 动态用户可见消息使用 builder 函数，不在调用点拼装或内联三元组。
- Router、Service、Hub、Dependency、Schedule 只引用错误常量或 builder。
- 使用 `KmvException(error=<module>.<ERROR>)` 抛出统一业务/API 异常；不要称其为“DTO 错误”。
- 异常包不得依赖 Router、Service、FastAPI、`DefaultStorage` 或 ORM。
- 捕获底层异常时保留异常链：`raise KmvException(...) from exc`；不要用宽泛捕获掩盖未知故障。

## 自检

- 搜索新增错误码，确认唯一且位于正确模块。
- 搜索 `[code, title, message]` 形态，确认业务代码没有内联。
- 确认用户可见文案稳定，动态内容只由 builder 生成。
- 确认配置默认值在 develop/release 环境下语义一致。
