# Python dependencies / Python 依赖治理

Baseline: Python >=3.11. Dependency review: 2026-11-07.

## Installation / 安装

```bash
python -m pip install .
python -m pip install '.[mysql]'
python -m pip install '.[multipart]'
python -m pip install -e '.[mysql,multipart,test,dev]'
python -m pip check
python -m pytest kmvpy -q
```

The core includes FastAPI, Uvicorn with an explicit WebSocket backend, Socket.IO,
SQLAlchemy asyncio, SQLite/PostgreSQL drivers, Redis, YAML, translations, asymmetric
JWT and time zone data. MySQL adds only the asynchronous `aiomysql` driver.
`multipart` enables downstream FastAPI form/upload endpoints. `test` installs
pytest, HTTPX and the asynchronous Socket.IO client; `dev` installs build/twine.

默认安装包含 Web、WebSocket、Socket.IO、异步 SQLite/PostgreSQL、Redis、YAML、
国际化、非对称 JWT 和时区数据。MySQL 只增加异步驱动 `aiomysql`。
表单/上传由 `multipart` extra 提供；冒烟测试用户也需要安装 `test` extra。
构建工具与测试工具分别归入 `dev`、`test`，不进入默认运行依赖。

OpenAI, Cassandra, aiofiles, Deprecated, pycryptodome and synchronous mysqlclient
are no longer installed as conveniences: neither the library nor generated Python
code uses them. Applications that use those packages must declare them directly.
Database URLs must use async drivers: `mysql+aiomysql`, `postgresql+asyncpg` or
`sqlite+aiosqlite`; `mysql://`/`mysql+mysqldb://` do not select an async MySQL driver.

移除未使用依赖后，下游自行调用 OpenAI、Cassandra 等库的项目应自行声明依赖。
MySQL URL 应使用 `mysql+aiomysql://`，不要继续依赖同步 `mysqlclient`。
新生成项目仍默认使用 MySQL，声明 `kmvpy[mysql]`；发布脚本也安装这个 extra，
避免 `--no-deps` 部署遗漏驱动。新生成项目安装测试环境使用 `pip install -e '.[test]'`。
旧项目若沿用自己的依赖/部署文件，应手动同步这些安装项。

## Version policy / 版本策略

| Integration | Selected range | Reason |
| --- | --- | --- |
| FastAPI | >=0.162.0,<0.163 | Upgrade within an explicit minor series |
| Uvicorn | >=0.54.0,<0.55 | Current ASGI/WebSocket behavior; explicit websockets backend |
| Pydantic | >=2.14.3,<3 | Keep v2 model/validator contracts |
| SQLAlchemy[asyncio] | >=2.0.57,<2.1 | Ensure greenlet; defer 2.1 autoflush/API changes |
| APScheduler | >=3.11.3,<4 | Current implementation uses 3.x schedulers/jobs |
| redis-py | >=7.4.1,<8 | Keep RESP2 behavior; clients explicitly use protocol=2 |
| python-socketio | >=5.18.1,<6 | Maintained upstream, compatible with JS Socket.IO 4.x |
| PyJWT | >=2.15.1,<3 | Include upstream fixes while retaining v2 semantics |
| asyncpg | >=0.32.0,<0.33 | Updated PostgreSQL driver |
| PyYAML / aiosqlite / aiomysql | Existing current stable series | Retain used drivers and configuration parser |

These are declared compatibility targets. A local test with older packages is
useful regression evidence, but does not certify a fresh installation of the
declared targets. The compatibility workflow installs declared dependencies and
runs `pip check` plus the complete suite on Linux Python 3.11–3.15, Windows,
Apple Silicon macOS and legacy Intel macOS. It also installs a generated project's
test extra into a separate clean environment using the current checkout.
The publishing workflow requires that workflow and also
installs the built wheel with dependencies before importing runtime modules.

表中范围是升级后的依赖目标。不能用旧环境的测试结果声称新版依赖已验证。
兼容工作流在干净环境安装依赖、执行 `pip check` 并运行全量回归；发布工作流
依赖兼容检查，并实际安装 wheel 的运行依赖，防止仅 `import kmvpy` 掩盖缺包。
SQLAlchemy 2.1、APScheduler 4、Redis 8 的放开应单独评估行为变化，再更新范围。
发布基础库保留兼容范围；使用方应为自己的部署保存解析后的依赖约束或锁文件。

## Cryptography platform exception / 加密库平台例外

The dependency markers are complementary:

- Intel macOS: `cryptography>=48.0.1,<49` (legacy compatibility).
- Other supported platforms: `cryptography>=50.0.2,<51`.

Cryptography 49 removed upstream support for Intel macOS and 32-bit Windows.
Windows support here means a 64-bit Python installation. The last official Intel
macOS line is 48.x, but upstream security support covers only its most recent
release and main branch: **48.x is not a security-maintained LTS**. The Intel
marker preserves existing installations as a transition; it is not a claim of
equivalent security maintenance. Deployments requiring current upstream security
support should use a supported platform or an independently maintained provider.

Intel macOS 暂时保留 48.x 兼容路径，其余受支持平台升级到 50.x；这不是把
48.x 当作仍获安全维护的 LTS。上游已移除 Intel macOS 和 32 位 Windows 支持。
Windows 应使用 64 位 Python。需要持续获得上游安全维护的部署应迁移到受支持
平台，或采用有独立维护承诺的分发渠道。不要添加统一的 `cryptography>=50`
约束覆盖 Intel 分流；JWT 和密钥管理继续直接依赖 cryptography。

Sources: [changelog](https://cryptography.io/en/latest/changelog/),
[security support policy](https://cryptography.io/en/latest/security/).

## Socket.IO migration / Socket.IO 迁移

The archived `fastapi-socketio` wrapper has been replaced with
`kmvpy.common.socketio.SocketManager`, backed by upstream `AsyncServer`/`ASGIApp`.
The default public endpoint remains `/ws/socket.io`, with the existing namespace,
authentication, room and event interfaces. Application lifespan shuts down
Engine.IO and the Redis manager listener/connections.

Use `manager.server` for the raw server and `manager.asgi_app` for its ASGI app.
The old `_sio`/`_app` aliases remain temporarily for already generated projects.
New templates no longer mutate private `engineio_path`; remove that old workaround
when updating existing applications. `app.sio` remains the upstream server.
Generated applications explicitly pass their one `DefaultStorage` instance into
`init_asgi_app`, so ORM/services and startup/shutdown share the same resources.

自有薄适配直接调用受维护的 python-socketio。旧工程的事件/房间接口和默认路径
保持兼容；新工程使用公开 `server`/`asgi_app`，不再修改私有挂载路径。
生成项目显式注入同一个 Storage，确保数据库初始化、业务访问与关闭释放一致。

## Translations and time zones / 国际化与时区

`python-i18n` 0.3.9 has no newer release, but is actively called by kmvpy.
Keep it for now and test JSON loading, locale and interpolation; replacing the
translation model is a separate migration. `tzdata` is explicit because standard
library `zoneinfo` does not bundle IANA data, notably on Windows/minimal images.

python-i18n 长期没有新版，但当前存在真实调用，暂不删除或改动翻译数据格式。
zoneinfo 是标准库，时区数据库不是；显式安装 tzdata 保证回退数据可用。

## Release verification / 发布前验收

1. Install `.[mysql,multipart,test,dev]` into a clean Python >=3.11 environment.
2. Run `pip check`, `pytest kmvpy -q`, `python -m build`, and `twine check --strict dist/*`.
3. Install the wheel in a second clean environment with dependencies; import
   `BaseConfig`, `init_asgi_app`, and construct `ZoneInfo('Asia/Shanghai')`.
4. Generate a project; install its `.[test]` extra and inspect its deployment
   installation of `kmvpy[mysql]`. Verify `/ws/socket.io` polling and WebSocket.
5. Run actual PostgreSQL/MySQL/Redis integration acceptance against disposable
   services before production deployment; local tests do not require live services.

## Local validation record / 本次本地验证记录

2026-11-07, Intel macOS, Python 3.13.5:

- Unmodified HEAD `10d258d`: **122 passed, 12 failed**. Failures included stale
  generator fixtures, Redis ACL credentials and generated Storage ownership.
- Updated full suite: **155 passed, 2 skipped**. The two skips are real loopback
  tests denied at `socket.bind` by this environment. They run by default on an
  ordinary CI runner. The in-memory HTTP Upgrade/WebSocket framing tests passed
  against the mounted kmvpy app for both the default and `/api` deployment paths.
- Final regressions used cached Uvicorn **0.54.0**, websockets **16.0** and PyJWT
  **2.15.0**, over an existing environment with FastAPI 0.135.1, Pydantic 2.12.5,
  SQLAlchemy 2.0.52, redis-py 8.1.0, python-socketio 5.16.1, asyncpg 0.31.0 and
  cryptography 46.0.3. These versions do **not** satisfy all new declared targets.
- Wheel and sdist built with `python -m build --no-isolation`; both passed
  `twine check --strict`. Python source and Python templates parsed with the 3.11
  syntax grammar. Wheel metadata selected exactly one cryptography range for
  Intel macOS, Apple Silicon macOS, Windows x64 and Linux.
- The wheel's configuration, ASGI and smoke-test modules imported outside the
  source tree with imports of removed libraries explicitly blocked. This used
  existing dependencies; it was not a clean dependency installation.
- Fresh target installation was attempted against the configured index and
  official PyPI. DNS resolution failed (`nodename nor servname provided`), so
  target-resolution `pip check`, clean generated-project installation and the
  cross-platform CI matrix remain **pending in a network-enabled environment**.

本次本地行为与打包检查已通过，但新声明的完整依赖组合尚未完成干净安装验证。
未执行真实 PostgreSQL/MySQL/Redis 服务验收；未运行远程 CI、提交或发布。
Intel macOS 的 cryptography 48.x 仍是前述维护例外，不能表述为已获得当前上游安全支持。
