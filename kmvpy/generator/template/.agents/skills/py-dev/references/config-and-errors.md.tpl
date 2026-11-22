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

## 实时资源保护配置

`AppConfig.realtime_protection` / `RealtimeProtectionConfig` 当前默认值如下；修改模型不等于获得修改真实部署配置的授权。

| 字段 | 默认 | 语义 |
|---|---|---|
| `mode` | `observe` | `off` 关闭保护/观测，`observe` 记录但不按额度拒绝，`enforce` 执行限制 |
| `failure` | `allow` | 共享存储故障时对已鉴权资源放行；`deny` 仅在 enforce 拒绝，不清除登录 |
| `connections` | 8 | 每域/用户/稳定登录会话连接数，含正常交接与多设备余量 |
| `attempts_per_minute` | 60 | 连接尝试频率 |
| `subscriptions` | 200 | 订阅数量 |
| `subscription_ops_per_minute` | 240 | 订阅/取消操作频率 |
| `http_per_minute` | 300 | 对应身份的鉴权 HTTP 请求频率 |
| `ttl_seconds` | 90 | 活跃连接/订阅租期，模型最小 3 秒 |

默认 observe 的依据是缺少生产容量证据，不据本机测试宣称阈值可承载生产或收紧正常用户额度。两域不共用单连接额度；Hub 读取配置，Infra 用共享 Redis 原子执行，客户端标识不是权限/唯一额度依据。具体生命周期见主 Skill 的 Socket reference。

## 认证与传输错误

- HTTP 明确会话失效使用 401 与 `WWW-Authenticate`、`X-Auth-Role`、`X-Auth-Error: session_invalid`；临时故障传播 5xx，限流为 429 + `Retry-After`，不把它们转换成登录失效。
- access 到期但登录仍有效应尝试 HTTP 续签；Redis 会话存储不可用导致过期恢复不能完成时返回 503，保留登录。
- Socket 连接拒绝、`auth_status` 与 ACK 使用结构化 `kind`：`token_expired`、`session_invalid`、`temporary`、`rate_limited`；无效订阅参数为 `invalid_request`。
- 此类认证/传输错误遵循专用协议，不机械套业务三元组，也不靠错误文本包含 `401` 判定退出；业务失败仍遵守下列 KmvException 约束。

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
