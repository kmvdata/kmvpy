# KMVPy

> Chinese version: [README.md](README.md)

KMVPy is a FastAPI backend foundation and project scaffold. It is not meant to implement your business system for you. Its goal is to move a backend project from an empty directory to a runnable, configurable, testable, and deployable service foundation.

This repository is a KMVPy-generated reference project that has been further extended: the backend lives in `__PY_PROJECT_NAME__/`, and the landing site plus example SPA live in `__SPA_PROJECT_NAME__/`. The business positioning, capability map, and runtime examples shown on the homepage are synchronized into this document.

## Project Status

- Backend framework: FastAPI
- Python version: `>= 3.11`
- KMVPy version shown on the homepage: `0.2.3`
- Default JWT algorithm: `RS256`
- Maturity: Pre-Alpha, suitable for internal foundations, pilot services, and teams ready to provide fast feedback
- MySQL: optional dependency; PostgreSQL, SQLite, or other storage backends can be wired in as needed

## What KMVPy Solves

When starting a new FastAPI project, teams often rebuild the same foundation repeatedly:

- ASGI application entry, lifespan, router aggregation, global exceptions, logging, and i18n
- YAML loading and validation into Pydantic config models
- Unified configuration for database, Redis, CORS, Socket.IO, JWT, and logging
- SQLAlchemy 2 async storage, pagination, safe sorting, Redis cache, and Snowflake kid generation
- `ApiResponse`, `SocketioResponse`, `KmvException`, and error-code conventions
- Asymmetric JWT, kid, key file paths, Redis sessions, automatic renewal, and key rotation
- APScheduler cron jobs, startup jobs, and unified lifecycle management
- A mixed runtime path for REST APIs and Socket.IO realtime APIs
- pytest, YAML cases, and `StExpect` minimal field assertions
- Generated Python subproject, SPA subproject, editor config, Nginx templates, and deployment config

KMVPy consolidates these conventions into a foundation library, runtime path, and generator so teams can start writing their own routers, ORM models, schedules, and deployment details sooner.

## Use Cases

- Engineering teams that need to bootstrap a microservice foundation quickly
- Backend services that need ordinary HTTP APIs and Socket.IO realtime notifications together
- Teams that want consistent response formats, error codes, config structure, and logging across services
- Projects that need Python backend, SPA, test templates, Nginx, and deployment config generated together
- Backend teams that want new projects to start with Cursor / VS Code debugger config, workspace structure, and runnable examples

KMVPy is not a complete business system to buy or run directly. Business models, workflows, and product rules are still implemented by your team.

## Layered Architecture

The backend code of a KMVPy-generated project strictly follows one-way dependencies:

```text
HTTP / Socket Router ─┐
Schedule ─────────────┴─> Service ─> Hub ─> Infra
                                      ├─> Config
                                      └─> Exception
```

| Layer | Responsibility | May Call |
| --- | --- | --- |
| Router | HTTP/Socket entry, auth, parameter binding, response wrapping | Service |
| Schedule | Time-based triggers, input preparation, task logging | Service |
| Service | Transaction lifecycle, unconditional call order, low-level exception translation, DTO assembly | Hub, DTO, Exception |
| Hub | Business judgment, validation, normalization, aggregation, data access, config reads | Infra, Config, Exception |
| Infra | ORM, Storage, Redis, RPC, AI and other technical resources | nothing above |
| Config | Config models and safe reads | nothing above |
| Exception | Error constants and builders | nothing above |

Core constraints:

- `core/main/hub` is the single owner of business rules and data access; no parallel business-rule layer is created.
- Service only defines transactions and a fixed call order; it never branches on business data with `if`/`match`/conditional loops. Permission, state, existence, and flow decisions all live in Hub.
- Services never call other Services; shared business capabilities are pushed down to Hub.
- Hub does not depend on FastAPI, DTOs, Router, or Service; when it needs database access it explicitly receives the `session` passed in by Service and never creates or commits transactions itself.
- Router / Schedule act only as entry adapters and never carry business logic; all external BIGINT/KID values use strings.

## Quick Start

When using KMVPy to create a new project, the typical flow is:

```bash
pip install kmvpy
# or from the source directory
pip install .

kmvpy create demo_project
cd demo_project/__PY_PROJECT_NAME__
python app/run.py

kmvpy rotate-jwt-keys app/etc/release/config.yaml
```

The generated project includes a Python backend, SPA, editor config, deployment templates, and smoke-test directory. Before release, JWT keys can be rotated while previous public keys remain available for a smooth client transition.

## Running This Repository

### Backend

The backend project lives in `__PY_PROJECT_NAME__/`. Its `pyproject.toml` depends on the KMVPy release published on PyPI:

```toml
kmvpy>=0.2.3
```

If your environment does not have this local path, install an available KMVPy package or adjust the dependency source first.

Run locally:

```bash
cd __PY_PROJECT_NAME__
python -m venv .venv
source .venv/bin/activate
pip install -e ".[test,sqlite]"
python app/run.py
```

The default config is `__PY_PROJECT_NAME__/app/etc/develop/config.yaml`. You can also choose a config through an environment variable:

```bash
__CONFIG_ENV_VAR__=app/etc/release/config.yaml python app/run.py
```

### Frontend

The frontend project lives in `__SPA_PROJECT_NAME__/`. It uses Quasar SPA, Vue 3, TypeScript, and Vite.

```bash
cd __SPA_PROJECT_NAME__
bun install
bun run dev
```

Production build:

```bash
cd __SPA_PROJECT_NAME__
bun run build
```

## Generated Project Structure

A typical KMVPy-generated project contains:

```text
demo_project/
|-- __PY_PROJECT_NAME__/
|   |-- app/etc/develop/config.yaml
|   |-- app/st_test/
|   `-- __PROJECT_NAME__/core/main/
`-- __SPA_PROJECT_NAME__/
```

Key directories in this repository:

```text
__PY_PROJECT_NAME__/
  app/run.py                         # Backend startup entry
  app/etc/develop/config.yaml        # Local development config
  app/etc/release/config.yaml        # Release config
  __PROJECT_NAME__/common/conf/              # AppConfig and config loading
  __PROJECT_NAME__/common/dto/               # user/admin request/response DTOs
  __PROJECT_NAME__/common/dependencies/      # FastAPI auth and audit dependencies
  __PROJECT_NAME__/common/exception/         # Business error constants and builders
  __PROJECT_NAME__/common/infra/orm/         # SQLAlchemy ORM models and central registration
  __PROJECT_NAME__/common/infra/storage/     # Database, Redis and resource lifecycle
  __PROJECT_NAME__/core/main/__init__.py     # ASGI application factory
  __PROJECT_NAME__/core/main/router/         # user/admin router aggregation
  __PROJECT_NAME__/core/main/service/        # user/admin business services (transaction coordination)
  __PROJECT_NAME__/core/main/hub/            # business rules and data access (single owner)
  __PROJECT_NAME__/core/main/schedule/       # APScheduler job registration

__SPA_PROJECT_NAME__/
  src/pages/home/IndexPage.vue       # KMVPy homepage
  src/layouts/HomeLayout.vue         # Homepage layout
  src/i18n/zh-CN/landing.ts          # Chinese landing copy
  src/i18n/en-US/landing.ts          # English landing copy
  src/network/                       # API, DTO, and Socket wrappers
```

## ASGI Application Entry

The current project uses `gen_asgi_app()` to compose config, routers, database initialization, Socket.IO, and scheduled jobs. The core shape is:

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

The real `__PY_PROJECT_NAME__/__PROJECT_NAME__/core/main/__init__.py` also adds default table initialization, default admin initialization, user Socket handler registration, and production Redis checks.

## Config And Security

KMVPy puts security and operational defaults into the project foundation from day one:

- JWT defaults to asymmetric algorithms such as `RS256`, with `kid` identifying active keys
- Config files reference key file paths instead of embedding PEM content directly
- Separate user/admin JWT config isolates issuer, audience, session lifetime, and Redis DBs
- JWT key rotation keeps previous public keys available during client transition
- Redis sessions, HttpOnly cookies, and CORS restrictions provide runtime boundaries for auth
- Nginx templates plus release/develop configs support deployment and local integration

JWT config example:

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

## Smoke Tests

KMVPy-generated projects include an `app/st_test/` smoke-test directory by default. The test flow is:

- pytest executes the tests
- `StBasePyTest.data_driven` turns same-name YAML cases into parameterized tests
- `TestClient` calls the FastAPI app directly, so the service does not need to be started manually
- `StExpect` validates only the required fields, which fits API smoke tests well

Run all smoke tests in a generated project:

```bash
cd __PY_PROJECT_NAME__
source .venv/bin/activate
pip install -e ".[test,sqlite]"
pytest app/st_test
```

> Note: this reference repository does not include the `app/st_test/` directory yet; add cases following the KMVPy generator template when needed.

YAML case example:

```yaml
test_send_email_verify_code:
  comment: user email verification smoke test
  case_list:
    - comment: send registration verification code
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

## Scheduled Jobs

This project keeps the KMVPy schedule registration entry:

- `__PY_PROJECT_NAME__/__PROJECT_NAME__/core/main/schedule/__init__.py`

No scheduled job is registered by default for the current business scope. To add one, create `schedule_<topic>.py` under `__PROJECT_NAME__/core/main/schedule/` and register it centrally in `register_app_schedule_jobs()`.

## Tech Stack

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

## Development Flow

A generated project is usually extended through this path:

1. Create Project
2. Configure YAML
3. Add Routers / ORM / Schedules
4. Run Smoke Tests
5. Deploy
6. Rotate JWT Keys

In this repository, backend business code generally expands along `router -> service -> hub -> infra`; frontend pages generally expand along `route -> page -> network/api -> network/dto`.

## FAQ

### Is KMVPy a complete business system?

No. KMVPy is a backend foundation library and project generator. It helps teams generate the service base; business models, workflows, and product rules are still yours to build.

### What Python version does it require?

Python `>= 3.11`. Generated projects are organized around modern typing, async I/O, and Pydantic v2.

### How mature is it?

The homepage currently shows version `0.2.3`, and the Development Status is Beta. It fits internal foundations, pilot services, and teams ready to provide fast feedback.

### Is MySQL required?

No. MySQL is optional. Projects can use PostgreSQL, SQLite, or another configured storage path as needed.
