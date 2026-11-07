import subprocess
import sys

import pytest

from kmvpy.generator.project_generator import create_project


@pytest.mark.parametrize("fail_table_initialization", [False, True])
def test_generated_app_owns_and_disposes_business_storage(
    tmp_path, fail_table_initialization
) -> None:
    project_root = create_project("storage_fixture", tmp_path)
    # Isolate generated ORM registrations and process-wide configuration from
    # other generated-project tests; the child uses only an in-memory SQLite DB.
    result = subprocess.run(
        [
            sys.executable,
            "-c",
            r'''
import asyncio
import sys
from pathlib import Path

from sqlalchemy import text

project_root = Path(sys.argv[1])
sys.path.insert(0, str(project_root / "storage_fixture_py"))
import storage_fixture.core.main as core
from storage_fixture.common.conf import AppConfig
from storage_fixture.common.infra.storage.default_storage import DefaultStorage

config = AppConfig.model_validate({
    "general": {"debug": True, "env": "test", "timezone": "UTC"},
    "service": {"workers": 1},
    "logging": {"level": "ERROR"},
    "i18n": {"path": ".", "locale": "en"},
    "default_storage": {"database": {"url": "sqlite+aiosqlite:///:memory:"}},
})
config_path = project_root / "config.yaml"
config_path.write_text("{}", encoding="utf-8")
AppConfig.load_config = classmethod(lambda cls, path: config)
storage = DefaultStorage.instance(config)
assert storage is DefaultStorage.instance()
assert storage.timezone == "UTC"
assert not storage.has_db_session()

events = []
original_init_asgi_app = core.init_asgi_app
def init_asgi_app(config, routers, *, storage):
    assert storage is DefaultStorage.instance()
    return original_init_asgi_app(config, routers, storage=storage)
core.init_asgi_app = init_asgi_app

original_dispose = storage.dispose
async def dispose():
    events.append("dispose")
    await original_dispose()
storage.dispose = dispose

async def init_tables():
    assert storage is DefaultStorage.instance()
    assert storage.has_db_session()
    async with storage.session_scope() as session:
        assert await session.scalar(text("SELECT 1")) == 1
    events.append("tables")
    if sys.argv[2] == "True":
        raise RuntimeError("synthetic table initialization failure")
core.init_tables = init_tables

async def init_default_admin(config):
    assert storage is DefaultStorage.instance()
    events.append("admin")
core.init_default_admin_if_needed = init_default_admin

app = core.gen_asgi_app(str(config_path))
assert not storage.has_db_session()
async def run():
    try:
        async with app.router.lifespan_context(app):
            events.append("body")
            assert storage.has_db_session()
    except RuntimeError as error:
        assert sys.argv[2] == "True"
        assert str(error) == "synthetic table initialization failure"
    else:
        assert sys.argv[2] == "False"
    assert not storage.has_db_session()
    assert not storage.has_redis_client()
asyncio.run(run())
expected = ["tables", "dispose"] if sys.argv[2] == "True" else ["tables", "admin", "body", "dispose"]
assert events == expected, events
''',
            str(project_root),
            str(fail_table_initialization),
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, result.stdout + result.stderr
