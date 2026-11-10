# 更新日志

## 0.2.3

- 首次以 `kmvpy` 名称发布 FastAPI 服务端基础库，提供 YAML 配置、异步 SQLAlchemy 领域层、统一响应与异常、JWT、APScheduler 调度、Socket.IO 和工程脚手架。
- `kmvpy.core.main` 提供 ASGI 装配：`init_asgi_app` 一次性完成日志、国际化、CORS、Socket.IO、路由和全局异常处理；`lifespan` 负责初始化与释放应用显式注入的 Storage，并在退出时依次关闭调度器、Socket.IO 与连接池。
- 应用不再隐式创建 Storage，改为由应用显式持有并传入 `init_asgi_app`，使 ORM/服务访问与启动、关闭共用同一套数据库和 Redis 资源。
- 新增可选的启动期表结构初始化 `init_tables_by_orms`：MySQL 支持列级 diffs、ALTER 与索引同步；PostgreSQL/SQLite 支持自动建表、补齐新增列并保留默认值，对库中存在但 ORM 未声明的列只告警不删除。
- 配置体系以 `BaseConfig` 统一描述数据库、Redis、日志、服务与 CORS、国际化、Socket.IO、认证、首个管理员、雪花 ID 与时区；保留顶层 `database`/`redis` 以兼容旧工程，新工程推荐使用 `default_storage`。
- 数据库默认包含异步 SQLite（aiosqlite）与 PostgreSQL（asyncpg）驱动，MySQL 通过 `mysql` extra 安装 `aiomysql`；表单上传、冒烟测试与构建工具分别由 `multipart`、`test`、`dev` 提供，OpenAI、Cassandra、aiofiles、同步 mysqlclient 等未实际使用的依赖不再默认安装。
- ORM 层 `KOrmStorage`/`KOrmBase` 提供异步会话、分页、结构化安全排序（不拼接 SQL 文本）、缓存协作与雪花 ID；Redis 配置新增可选 `username`，未配置时保持原有仅密码认证，Socket.IO 的 Redis 客户端同样支持 ACL。
- 认证改为「短寿命非对称 access JWT + Redis 登录 session」：JWT 仅允许 RS/PS/ES 系列算法，配置只接受密钥文件路径并拒绝内联 PEM 与旧字段，启动时校验 `kid` 唯一性与私钥/公钥匹配，生产环境拒绝过宽的私钥文件权限。
- 新增 `AuthSessionService`：签发登录令牌、空闲与绝对双重超时、自动续签、并发会话上限、单会话注销与按用户批量注销；会话 Cookie 采用 `__Host-` 前缀、HttpOnly 且管理员更严格的 SameSite 策略，检测到会话密钥重放时整族会话失效。
- JWT 支持公钥集合验签、`kid` 轮换过渡期、`extra_claims` 扩展以及导出 JWKS 公钥集，便于资源服务在本地验签。
- Socket.IO 改用受维护的 python-socketio 直接适配（`SocketManager`），替换已归档的 fastapi-socketio 包装；保持默认 `/ws/socket.io` 端点与既有命名空间、鉴权、房间和事件接口，暴露 `server`/`asgi_app` 公开对象，并在关闭时释放 Engine.IO 与 Redis 管理器监听连接。
- 调度模块提供 `Schedule`、`ScheduleConfig`、`ScheduleManager` 与 `schedule_task` 装饰器，支持 cron 任务与启动型任务（`cron=None` 启动时触发一次），按 `kid` 唯一注册并允许同类任务多实例，启停已与 ASGI 生命周期联动。
- 统一响应 `ApiResponse`/`SocketioResponse` 与 `KmvException`/`KmvError` 约定业务码，应用层将业务异常、参数校验失败与未捕获异常统一转换为结构化 JSON。
- 日志模块提供 `init_logger`、`api_log` 装饰器等能力：按大小轮转并异步归档为 `.tar.gz`、按 `backup_count` 清理最旧归档、默认脱敏敏感字段、非 debug 模式下仅摘要打印返回体。
- 冒烟测试骨架 `StBasePyTest`/`StTestCase`/`StExpect` 支持 YAML 数据驱动接口验收，可通过 `build_request_kwargs`、`after_step_hook` 与 `NextStepRequest` 扩展动态参数与鉴权流程。
- 新增 CLI `kmvpy`：`create` 生成后端 + SPA 一体工程，`update` 增量补齐缺失文件并安全升级旧版 `biu` 与 `deploy.sh`，`gentpl` 从调试工程反向回写模板，`nginx` 输出 API/SPA 网关模板，`rotate-jwt-keys` 自动轮换 user/admin JWT 密钥。
- 脚手架生成物包含 VS Code 配置、AI 开发指引（`.agents/skills`）、后端 DTO/Router/Service/Hub/ORM/调度注册、Quasar/Vue 页面、实时连接验收用例、`biu` 构建部署命令与运维文档；支持按工程名、相对路径或当前目录定位工程。
- `gentpl` 按 Git 目录作用域与规则优先级跳过被忽略文件，并叠加内置忽略规则，避免把 `node_modules`、`__pycache__`、构建产物等运行时内容写回模板。
- 生成的 `biu` 覆盖本地构建、`deploy`（整体 / `py` / `spa` / `config`）、`--update-config` 远端配置备份覆盖、`--rotate-jwt-keys` 启动前轮换密钥、`--no-deps` 与 `conda create`，并按域名生成 nginx 配置。
- nginx 模板覆盖 API 反向代理（WebSocket 升级、CORS 透传、multipart 体积与超时预留）和 SPA 静态站点（history 回退、长缓存静态资源、`index.html` 不缓存）两类场景。
- 新增依赖与发布治理：`pyproject.toml` 使用 PEP 621 元数据与动态版本（唯一来源 `kmvpy/__init__.py`），支持 Python 3.11–3.13，Intel macOS 与其它平台分别使用 cryptography 48.x/50.x 兼容范围，并配套 `docs/DEPENDENCIES.md` 迁移与验收说明以及 PyPI Trusted Publishing 发布流程文档。
- 补充完整的回归与兼容性保障：覆盖配置、JWT、会话、Socket.IO、调度、ORM 初始化和生成器的测试，GitHub Actions 在干净环境安装声明依赖并执行 `pip check` 与全量回归，发布工作流依赖该兼容性检查后再上传。