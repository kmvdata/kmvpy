# 仓库地图与命名

在定位文件、创建/移动/重命名后端模块、判断 user/admin/public 归属或查找注册点时读取本文件。

## 技术与运行基线

- 使用 Python >= 3.11、FastAPI + kmvpy、Pydantic v2、SQLAlchemy 2.x 异步 ORM。
- 开发环境使用 SQLite，生产主要使用 MySQL；新增数据库代码同时考虑 PostgreSQL 兼容性。
- 主 Python 包位于 `__PY_PROJECT_NAME__/__PROJECT_NAME__`。
- 应用入口位于 `__PY_PROJECT_NAME__/app/run.py`；包内启动实现位于 `__PY_PROJECT_NAME__/__PROJECT_NAME__/core/app/run.py`。
- 环境配置位于 `__PY_PROJECT_NAME__/app/etc/develop` 与 `__PY_PROJECT_NAME__/app/etc/release`。
- 冒烟测试位于 `__PY_PROJECT_NAME__/app/st_test`。
- 对应 SPA 位于 `__SPA_PROJECT_NAME__/src`。

## 目录职责

| 路径 | 职责 |
|---|---|
| `common/dto/user` | 用户端请求/响应 DTO |
| `common/dto/admin` | 管理端请求/响应 DTO |
| `common/dependencies` | FastAPI 鉴权、客户端上下文、审计等依赖 |
| `common/exception` | 业务错误常量与 builder |
| `common/conf` | `AppConfig` 与配置读取入口 |
| `common/infra/orm` | SQLAlchemy 表模型与集中注册 |
| `common/infra/storage` | 数据库、Redis 等技术资源生命周期 |
| `core/main/router/user` | 用户端 HTTP/Socket.IO 入口 |
| `core/main/router/admin` | 管理端 HTTP/Socket.IO 入口 |
| `core/main/service/user` | 用户端事务协调与响应组装 |
| `core/main/service/admin` | 管理端事务协调与响应组装 |
| `core/main/service/common` | 中性入口 Service；其他 Service 仍不得调用它 |
| `core/main/hub` | 按业务主题组织的规则与数据访问 |
| `core/main/schedule` | 定时任务入口与集中注册 |

`core/main/hub` 是业务规则与数据访问的唯一归属。新业务规则统一按主 Skill 放入 Hub，不再建立平行的业务规则层。

## 放置规则

1. 先确认入口属于 user、admin 还是 public。
2. 优先扩展已有业务主题文件；只有没有合适主题时才新建文件。
3. DTO、Router、Service 按入口域组织；Hub 按业务主题组织，不区分 user/admin。
4. 新 Router 文件加入 `core/main/router/__init__.py` 的 `routers`。
5. 新 ORM 文件加入 `common/infra/orm/__init__.py` 的 `_REGISTERED_ORM_MODELS`。
6. 新 Schedule 类在 `core/main/schedule/__init__.py` 集中注册。
7. 不因现有文件违反新架构就复制该模式；把现有违规视为技术债，并将本次新增代码保持在正确边界内。

## 命名

| 元素 | 规范 | 示例 |
|---|---|---|
| DTO 请求 | `XxxReq` | `EmailCaptchaReq` |
| DTO 响应 | `XxxRes` | `EmailAuthRes` |
| Router 处理函数 | `api_xxx` | `api_send_email_verify_code` |
| Service 类 | `XxxService` | `UserOpService` |
| Hub 类 | `XxxHub` | `UserOpHub` |
| 只读 Hub（可选） | `XxxQueryHub` | `OrderQueryHub` |
| ORM 模型 | 名词式 `Xxx` | `UserBase` |
| Schedule 类 | `ScheduleXxx` | `ScheduleHelloDemo` |
| Schedule 文件 | `schedule_<topic>.py` | `schedule_demo.py` |
| 错误模块 | `<topic>_errors.py` | `user_op_errors.py` |
| 错误常量 | `UPPER_SNAKE` | `INVALID_EMAIL_ERROR` |
| Config helper | `get_xxx_config()` / `get_current_xxx()` | `get_default_storage_database_config()` |
