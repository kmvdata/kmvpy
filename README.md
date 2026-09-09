# KMVPy

> **简体中文版：[README.zh-CN.md](README.zh-CN.md)**

<p align="center">
  <img src="https://raw.githubusercontent.com/kmvdata/kmvpy/main/assets/kmvpy-logo.svg" alt="KMVPy logo" width="128" />
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/kmvdata/kmvpy/main/assets/kmvpy-header.svg" alt="KMVPy header" width="640" />
</p>

A **FastAPI**-based server-side foundation library: YAML-driven configuration, async SQLAlchemy domain layer, unified response and exception handling, JWT, APScheduler scheduling, Socket.IO, and an **engineering scaffold** (Python + frontend sub-projects, YAML smoke-test skeletons). Default dependencies already include Web, async SQLite/PostgreSQL, Redis, Cassandra drivers, PyJWT, OpenAI SDK and more; **MySQL** requires an extra optional dependency.

## Core Modules (Framework Capabilities)

| Module | Responsibility |
|------|------|
| **`kmvpy.core.main`** | ASGI entry: `init_asgi_app` aggregates routers, logging, i18n, Socket.IO and global exceptions; `lifespan` initializes/releases DB·Redis resources; `get_config_path` resolves the config path. The docstring contains integration notes for "create/evolve tables from ORMs at startup" (`init_tables_by_orms` + async driver constraints). |
| **`kmvpy.common.conf`** | `BaseConfig` (YAML → Pydantic): DB table connections, Redis, logging, service/CORS, Socket.IO, auth (JWT, splittable by user type), optional first admin, `SnowflakeConfig` and KSnowflake, etc. |
| **`kmvpy.common.infra`** | `KOrmStorage` + `KOrmBase`: async sessions, pagination and safe sorting, cache cooperation and other ORM semantics; Snowflake IDs (`KSnowflake`). |
| **`kmvpy.common.response`** | `ApiResponse` / `SocketioResponse`: unified JSON success and error shapes, integrated with `KmvException` and error-code conventions. |
| **`kmvpy.common.exception`** | `KmvException`, `KmvError`: business error codes and message conventions. |
| **`kmvpy.common.schedule`** | APScheduler-based async scheduling: `ScheduleManager`, `schedule_task` decorator, global scheduler lifecycle (hooked to ASGI startup). |
| **`kmvpy.common.kmv`** | `kosmos`: in-process config, Socket.IO and other existing runtime mount points; Storage is explicitly held by the app and passed to `init_asgi_app`. |
| **`kmvpy.common.st`** | Smoke-test skeleton: `StBasePyTest`, `StTestCase`, YAML steps and expectations (used by the generated project's `st_test`). |
| **`kmvpy.core.main.service`** | JWT (multiple algorithms, user-info payload, etc.; see the module). |
| **`kmvpy.core.main.router`** | Socket.IO and FastAPI app binding. |
| **`kmvpy.generator`** | CLI: `kmvpy create` / `kmvpy update` / `kmvpy rotate-jwt-keys`; generates projects and supports JWT key rotation; see `kmvpy/generator/README.md`. |

## Default Dependencies and Optional Extras

- **Declared in:** `pyproject.toml` (PEP 517 / PEP 621, setuptools build backend).
- **Optional:** `[project.optional-dependencies]` currently provides **`mysql`** (`mysqlclient`, `aiomysql`, etc.); the rest of Web/Redis/SocketIO etc. live in the default `dependencies`.

## Tech Stack (excerpt)

FastAPI · Uvicorn · Pydantic v2 · SQLAlchemy 2 (async) · Redis · APScheduler · python-i18n · PyYAML · PyJWT · fastapi-socketio · asyncpg / aiosqlite · cassandra-driver · OpenAI SDK

## Typical Use Cases

REST/realtime hybrid APIs, microservice foundations with unified config and error contracts, and teams that want to scaffold frontend/backend directories and smoke-test templates with one command.

---

## Installation and Usage

**Environment:** Python ≥ 3.11

> **Release status (2026-09-08):** The PyPI project index currently does not list `kmvpy`, but this repository has not shipped its first release yet. Until the first version is actually published, please use the local installation methods below. Maintainer actions: see the [PyPI first-release guide](https://github.com/kmvdata/kmvpy/blob/main/docs/PUBLISHING.md).

**Local install:** `pip install .` · Development: `pip install -e .` · With MySQL: `pip install ".[mysql]"`

**PyPI install (after first release):** `pip install kmvpy` · With MySQL: `pip install "kmvpy[mysql]"`

**Build:** `python -m pip install -U build twine && python -m build && python -m twine check --strict dist/*` → artifacts land in `dist/`; prefer the **wheel** for distribution/install. Offline install from `tar.gz` only, while avoiding build dependencies: `pip install --no-build-isolation --no-deps dist/kmvpy-0.2.3.tar.gz`.

**Scaffold and ops commands:** `kmvpy create <name> [-d parent-dir]` · `kmvpy update …` · `kmvpy rotate-jwt-keys path/to/config.yaml`

**Quick check:**

```bash
python -c "from kmvpy.core.main.service.jwt_service import JwtUserInfo; print(JwtUserInfo)"
```

**Example:**

```python
import kmvpy
from kmvpy.common.tool.logger import logger, init_logger

init_logger(debug=True)
logger.info("ok")

# from kmvpy.common.conf import BaseConfig
# config = BaseConfig.load_config("path/to/config.yaml")

# from kmvpy.core.main import init_asgi_app, get_config_path
# app = init_asgi_app(BaseConfig.load_config(get_config_path()), routers=[...])
```

### Redis ACL Configuration

All Redis configurations (`default_storage.redis`, the top-level `redis` used by legacy projects, `auth_config.user.redis`, `auth_config.admin.redis`) support an optional `username`:

```yaml
redis:
  host: localhost
  port: 6379
  db: 0
  username: app_user
  password: "your-redis-password"
  decode_responses: true
```

Place this snippet under the corresponding config layer. When `username` is configured, authentication uses the ACL username and password; when `username` is omitted, set to `null`, or left as an empty string, the existing password-only authentication is kept and no legacy config change is needed. The Socket.IO Redis clients and distributed message-forwarding connections generated by the scaffold support ACL as well.

### Packaging and Local Installation (detailed)

The commands below run from the repository root (the directory containing `pyproject.toml`); the build is driven by setuptools via PEP 517 and artifacts are written to `dist/`. The first build needs network access for build-tool dependencies (`setuptools`, `wheel`); subsequent builds hit the local cache.

**① Prepare build and validation tools (one-time)**

```bash
python -m pip install -U pip build twine
```

**② Clean stale artifacts and build**

```bash
rm -rf build dist *.egg-info
python -m build
python -m twine check --strict dist/*
```

Artifacts (the version comes solely from `kmvpy/__init__.py`'s `__version__`; currently `0.2.3`; bump it before a new release):

| Artifact | Description | Recommended Use |
|------|------|----------|
| `dist/kmvpy-0.2.3-py3-none-any.whl` | wheel, pure Python, no platform limits | **Preferred**: install, deliver, offline distribution |
| `dist/kmvpy-0.2.3.tar.gz` | sdist source package | source audit, repackaging |

The wheel ships the scaffold templates and nginx templates (collected via `MANIFEST.in` + `include-package-data`), so after installation `kmvpy create / update` can generate or update projects directly without manually copying templates from the repository.

**③ Local install (pick one)**

Option A: install directly from the source directory (builds on site, then installs into the current environment)

```bash
pip install .
# when MySQL drivers (mysqlclient / aiomysql) are needed:
pip install ".[mysql]"
```

Option B: editable install (recommended for development and debugging; code changes take effect immediately without reinstalling)

```bash
pip install -e .
pip install -e ".[mysql]"
```

Option C: install a built wheel (recommended for delivery / CI / offline distribution)

```bash
pip install dist/kmvpy-0.2.3-py3-none-any.whl
```

Option D: offline install from sdist (when the environment already has all runtime dependencies and you want to skip pulling build dependencies; bypasses build isolation and dependency resolution)

```bash
pip install --no-build-isolation --no-deps dist/kmvpy-0.2.3.tar.gz
```

> Note: Option D's `--no-deps` will not auto-install any runtime dependencies; if the environment is missing dependencies, use Option A/C (or install the missing dependencies first).

It is recommended to create a virtual environment first to avoid polluting the global Python:

```bash
python -m venv .venv
source .venv/bin/activate    # Windows: .venv\Scripts\activate
```

**④ Verify after install**

```bash
python -c "from kmvpy.core.main.service.jwt_service import JwtUserInfo; print(JwtUserInfo)"
kmvpy --help
```

Uninstall: `pip uninstall kmvpy`; before reinstalling, uninstall first and then run any of the install commands above.

## JWT Key Configuration

JWT supports only a whitelist of asymmetric algorithms (default `RS256`). Config files are forbidden from storing PEM content; they may only reference read-only key file paths injected by the deployment system. At startup kmvpy validates the paths, PEM legitimacy, `kid` uniqueness, and that the active private key matches the active public key.

```yaml
auth_config:
  user:
    jwt:
      algorithm: "RS256"
      active_kid: "user-20050607"
      private_key_path: "/run/secrets/signal-tracker/jwt-private-user-20050607.pem"
      public_keys:
        - kid: "user-20050607"
          public_key_path: "/run/secrets/signal-tracker/jwt-public-user-20050607.pem"
        - kid: "user-20050301"
          public_key_path: "/run/secrets/signal-tracker/jwt-public-user-20050301.pem"
      issuer: "kmvpy"
      audience: "kmvpy-user-api"
      access_token_lifetime_hours: 0.25
```

Rotation: configure the new private key path as `private_key_path`, switch `active_kid` to the new `kid`, and keep both old and new public keys in `public_keys`. After the old tokens expire, remove the old public key; tokens with the old `kid` will automatically fail verification.

You can also complete one user/admin key rotation automatically with the kmvpy CLI:

```bash
kmvpy rotate-jwt-keys app/etc/release/config.yaml
```

The command reads the directory containing the current `private_key_path` and the active public key's `public_key_path`, generates new private/public PEM files and a random `active_kid`, inserts the new public key into `public_keys`, and backs up the original config file. Up to 1 extra old public-key pair is kept for transitional verification when the old public key file exists; when the old public key file is missing, it is removed from config and only the newly generated public key is used. If the config lacks `auth_config` or the user/admin JWT fragments, they are completed per RS256 and the default issuer/audience/lifetime/session/redis specs, with keys generated into `./secrets` next to the config file.

Production mount recommendations:

- Ubuntu bare metal: place keys at `/etc/<app>/secrets/jwt-private-user-20050607.pem` or `/run/secrets/<app>/jwt-private-user-20050607.pem`; for the private key, `0400` is recommended, owned by the service user, and the config references paths only.
- Docker: mount via Docker secrets or a read-only bind mount to flat-file paths like `/run/secrets/<app>/jwt-private-user-20050607.pem`; reference the mounted path from the container config.
- K8s: mount read-only via a Secret projected volume or CSI Secret Store to flat-file paths like `/run/secrets/<app>/jwt-private-user-20050607.pem`; K8s default file modes may be too permissive — kmvpy warns, and production startup is refused when group/other write permission or execute bits are present.

Details and generated-project conventions: see `kmvpy/generator/README.md` and the docstrings inside each package.