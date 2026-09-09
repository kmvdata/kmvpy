# KMVPy

> English version: [README.en.md](README.en.md)

KMVPy 是面向 FastAPI 后端项目的基础库与工程脚手架。它的目标不是替你实现业务系统，而是把一个后端项目从空目录推进到可运行、可配置、可测试、可部署的工程底座。

当前仓库是一个由 KMVPy 生成并继续扩展的参考工程：后端位于 `__PY_PROJECT_NAME__/`，前端官网与示例 SPA 位于 `__SPA_PROJECT_NAME__/`。首页展示的 KMVPy 业务定位、能力范围和运行示例，已同步整理到本文档中。

## 项目状态

- 服务端框架：FastAPI
- Python 版本：`>= 3.11`
- KMVPy 当前展示版本：`0.2.3`
- 默认 JWT 算法：`RS256`
- 成熟度：Pre-Alpha，适合内部工程底座、试点项目和愿意快速反馈的团队
- MySQL：可选依赖，也可以按需要接入 PostgreSQL、SQLite 或其他存储

## KMVPy 解决什么问题

新建 FastAPI 项目时，团队通常会反复搭建这些基础设施：

- ASGI 应用入口、lifespan、路由聚合、全局异常、日志和 i18n
- YAML 配置到 Pydantic 配置模型的加载与校验
- 数据库、Redis、CORS、Socket.IO、JWT、日志等统一配置
- SQLAlchemy 2 async 存储层、分页、安全排序、Redis 缓存和 Snowflake kid
- `ApiResponse`、`SocketioResponse`、`KmvException` 与错误码约定
- 非对称 JWT、kid、公私钥路径、Redis 会话、自动续签和密钥轮换
- APScheduler cron 任务、启动型任务和统一生命周期管理
- REST API 与 Socket.IO 实时 API 的混合运行路径
- pytest、YAML 用例和 `StExpect` 必要字段断言
- Python 子项目、SPA 子项目、编辑器配置、Nginx 模板与部署配置生成

KMVPy 把这些约定收敛成基础库、运行路径和生成器，让团队可以更快开始写自己的业务路由、ORM 模型、schedule 任务和部署细节。

## 适用场景

- 需要快速搭建微服务底座的工程团队
- 同时需要普通 HTTP API 和 Socket.IO 实时通知的后端服务
- 希望在多个服务之间复用响应格式、错误码、配置结构和日志约定的团队
- 需要一键落地 Python 后端、SPA、测试模板、Nginx 和部署配置的项目
- 希望新项目天然带 Cursor / VS Code 调试配置、工作区结构和可运行示例的后端开发团队

KMVPy 不适合直接当作完整业务系统购买或使用。业务模型、业务流程和产品规则仍然由团队自己实现。

## 分层架构

KMVPy 生成工程的后端代码严格保持单向依赖：

```text
HTTP / Socket Router ─┐
Schedule ─────────────┴─> Service ─> Hub ─> Infra
                                      ├─> Config
                                      └─> Exception
```

| 层 | 职责 | 可调用 |
| --- | --- | --- |
| Router | HTTP/Socket 入口、鉴权、参数绑定、响应包装 | Service |
| Schedule | 定时触发、输入准备、任务日志 | Service |
| Service | 事务生命周期、无条件调用顺序、底层异常转换、DTO 组装 | Hub、DTO、Exception |
| Hub | 业务判断、校验、规范化、聚合操作、数据访问、配置读取 | Infra、Config、Exception |
| Infra | ORM、Storage、Redis、RPC、AI 等技术资源 | 不调用上层 |
| Config | 配置模型与安全读取 | 不调用上层 |
| Exception | 错误常量与 builder | 不调用上层 |

核心约束：

- `core/main/hub` 是业务规则与数据访问的唯一归属，不再建立平行的业务规则层。
- Service 只定义事务与固定调用顺序，不做业务 `if`/`match`/条件循环；权限、状态、存在性和流程决策全部放入 Hub。
- Service 之间不得互相调用，共享业务能力下沉 Hub。
- Hub 不依赖 FastAPI、DTO、Router 或 Service；需要数据库访问时显式接收 Service 传入的 `session`，不自行创建或提交事务。
- Router / Schedule 只做入口适配，不承载业务逻辑；对外 BIGINT/KID 一律使用字符串。

## 快速开始

作为 KMVPy 用户创建新项目时，典型流程如下：

```bash
pip install kmvpy
# 或在源码目录执行
pip install .

kmvpy create demo_project
cd demo_project/__PY_PROJECT_NAME__
python app/run.py

kmvpy rotate-jwt-keys app/etc/release/config.yaml
```

生成后的工程默认包含 Python 后端、SPA、编辑器配置、部署模板和冒烟测试目录。发布前可以轮换 JWT 密钥，并保留旧公钥完成客户端平滑过渡。

## 当前仓库如何运行

### 后端

当前后端工程位于 `__PY_PROJECT_NAME__/`。它的 `pyproject.toml` 依赖 PyPI 上发布的 KMVPy：

```toml
kmvpy>=0.2.3
```

如果你的环境没有这个本地路径，需要先安装可用的 KMVPy 包或调整依赖来源。

本地启动：

```bash
cd __PY_PROJECT_NAME__
python -m venv .venv
source .venv/bin/activate
pip install -e ".[test,sqlite]"
python app/run.py
```

默认配置读取 `__PY_PROJECT_NAME__/app/etc/develop/config.yaml`。也可以通过环境变量指定配置：

```bash
__CONFIG_ENV_VAR__=app/etc/release/config.yaml python app/run.py
```

### 前端

当前前端工程位于 `__SPA_PROJECT_NAME__/`，技术栈是 Quasar SPA、Vue 3、TypeScript 和 Vite。

```bash
cd __SPA_PROJECT_NAME__
bun install
bun run dev
```

生产构建：

```bash
cd __SPA_PROJECT_NAME__
bun run build
```

## 生成工程结构

典型 KMVPy 生成工程会包含：

```text
demo_project/
├─ __PY_PROJECT_NAME__/
│  ├─ app/etc/develop/config.yaml
│  ├─ app/st_test/
│  └─ __PROJECT_NAME__/core/main/
└─ __SPA_PROJECT_NAME__/
```

当前仓库的核心目录：

```text
__PY_PROJECT_NAME__/
  app/run.py                         # 后端启动入口
  app/etc/develop/config.yaml        # 本地开发配置
  app/etc/release/config.yaml        # 发布配置
  __PROJECT_NAME__/common/conf/              # AppConfig 与配置读取入口
  __PROJECT_NAME__/common/dto/               # user/admin 请求/响应 DTO
  __PROJECT_NAME__/common/dependencies/      # FastAPI 鉴权与审计依赖
  __PROJECT_NAME__/common/exception/         # 业务错误常量与 builder
  __PROJECT_NAME__/common/infra/orm/         # SQLAlchemy ORM 模型与集中注册
  __PROJECT_NAME__/common/infra/storage/     # 数据库、Redis 等资源生命周期
  __PROJECT_NAME__/core/main/__init__.py     # ASGI 应用生成入口
  __PROJECT_NAME__/core/main/router/         # user/admin 路由聚合
  __PROJECT_NAME__/core/main/service/        # user/admin 业务服务（事务协调）
  __PROJECT_NAME__/core/main/hub/            # 业务规则与数据访问（唯一归属）
  __PROJECT_NAME__/core/main/schedule/       # APScheduler 任务注册

__SPA_PROJECT_NAME__/
  src/pages/home/IndexPage.vue       # KMVPy 首页
  src/layouts/HomeLayout.vue         # 首页布局
  src/i18n/zh-CN/landing.ts          # 中文首页文案
  src/i18n/en-US/landing.ts          # 英文首页文案
  src/network/                       # API、DTO、Socket 封装
```

## ASGI 应用入口

当前工程通过 `gen_asgi_app()` 组合配置、路由、数据库初始化、Socket.IO 和定时任务。核心形态如下：

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI
from kmvpy.core.main import get_config_path, init_asgi_app

from __PROJECT_NAME__.common.conf import AppConfig
from __PROJECT_NAME__.core.main.router import routers
from __PROJECT_NAME__.core.main.schedule import register_app_schedule_jobs


def gen_asgi_app(config_path: str | None = None) -> FastAPI:
    resolved = get_config_path(config_path)
    config = AppConfig.load_config(resolved)
    app = init_asgi_app(config, routers)
    existing_lifespan = app.router.lifespan_context

    @asynccontextmanager
    async def lifespan(app_: FastAPI):
        async with existing_lifespan(app_):
            register_app_schedule_jobs()
            yield

    app.router.lifespan_context = lifespan
    return app
```

实际仓库中的 `__PY_PROJECT_NAME__/__PROJECT_NAME__/core/main/__init__.py` 还加入了默认表初始化、默认管理员初始化、用户 Socket 处理器注册和生产环境 Redis 检查。

## 配置与安全约定

KMVPy 倾向于把安全和运维约定从项目第一天放进工程底座：

- JWT 默认使用 `RS256` 等非对称算法，并通过 `kid` 标识当前密钥
- 配置文件只引用密钥文件路径，不直接写入 PEM 内容
- 支持 user/admin 分角色 JWT 配置，隔离 issuer、audience、会话时长和 Redis 库
- 支持 JWT 密钥轮换，并保留旧公钥完成客户端过渡
- Redis 会话、HttpOnly Cookie 和 CORS 限制共同提供登录态运行边界
- 提供 Nginx 模板和 release/develop 配置，适配部署和本地联调

JWT 配置示例：

```yaml
auth_config:
  user:
    jwt:
      algorithm: RS256
      active_kid: k-user-active
      private_key_path: ./secrets/jwt-private-user-k-user-active.pem
      public_keys:
        - kid: k-user-active
          public_key_path: ./secrets/jwt-public-user-k-user-active.pem
        - kid: k-user-previous
          public_key_path: ./secrets/jwt-public-user-k-user-previous.pem
      issuer: kmvpy
      audience: kmvpy-user-api
    session:
      idle_timeout_hours: 24
  admin:
    jwt:
      algorithm: RS256
      active_kid: k-admin-active
```

## 冒烟测试

KMVPy 生成工程默认内置 `app/st_test/` 冒烟测试目录。测试方式是：

- pytest 负责执行
- `StBasePyTest.data_driven` 把同名 YAML 用例转成参数化测试
- `TestClient` 直接调用 FastAPI 应用，不需要额外手工启动服务
- `StExpect` 只校验必要字段，适合接口冒烟测试

在生成工程中运行全部冒烟测试：

```bash
cd __PY_PROJECT_NAME__
source .venv/bin/activate
pip install -e ".[test,sqlite]"
pytest app/st_test
```

> 说明：当前参考仓库尚未包含 `app/st_test/` 用例目录，可按 KMVPy 生成模板补充。

YAML 用例示例：

```yaml
test_send_email_verify_code:
  comment: 用户邮箱验证码接口冒烟测试
  case_list:
    - comment: 发送注册验证码
      steps:
        - step_kid: STEP_SEND_EMAIL_VERIFY_CODE
          action: POST /api/user/email/verify-code
          request:
            email: smoke@example.com
            scene: register
      expected:
        code: 0
        data:
          sent: false
```

## 定时任务

当前工程保留 KMVPy schedule 的统一注册入口：

- `__PY_PROJECT_NAME__/__PROJECT_NAME__/core/main/schedule/__init__.py`

当前业务默认不注册定时任务。需要新增任务时，在 `__PROJECT_NAME__/core/main/schedule/` 下添加 `schedule_<topic>.py`，并在 `register_app_schedule_jobs()` 中集中注册。

## 技术栈

- FastAPI
- Uvicorn
- Pydantic v2
- SQLAlchemy 2 Async
- Redis
- APScheduler
- PyJWT
- Socket.IO
- PyYAML
- OpenAI SDK
- asyncpg
- aiosqlite
- Cassandra driver
- Quasar / Vue 3 / TypeScript / Vite

## 开发流程

推荐按下面路径扩展一个生成工程：

1. Create Project
2. Configure YAML
3. Add Routers / ORM / Schedules
4. Run Smoke Tests
5. Deploy
6. Rotate JWT Keys

当前仓库中，后端业务代码主要沿着 `router -> service -> hub -> infra` 的方向扩展；前端页面主要沿着 `route -> page -> network/api -> network/dto` 的方向扩展。

## FAQ

### KMVPy 是完整业务系统吗？

不是。KMVPy 是服务端基础库和项目生成器，帮助团队生成工程底座；业务模型、业务流程和产品规则仍由团队自己实现。

### Python 版本要求是什么？

Python `>= 3.11`。生成项目默认围绕现代类型标注、async I/O 与 Pydantic v2 组织代码。

### 当前成熟度如何？

当前首页展示版本为 `0.2.3`，Development Status 是 Beta。它更适合内部工程底座、试点项目和愿意快速反馈的团队。

### MySQL 是必须的吗？

不是。MySQL 是可选依赖；项目也可以按需要使用 PostgreSQL、SQLite 或其他可接入的存储配置。
