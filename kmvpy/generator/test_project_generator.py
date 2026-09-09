import shutil
import stat
from pathlib import Path

import pytest

from kmvpy.generator.cli import handle_gentpl, handle_nginx, handle_update
from kmvpy.generator.project_generator import (
    GentplFileError,
    create_project,
    generate_template_from_project,
    project_relative_path_to_template_path,
    resolve_project_root_and_name,
    template_relative_path_to_project_path,
    update_project,
)


def test_create_project_generates_expected_layout(tmp_path: Path) -> None:
    project_root = create_project("demo_project", tmp_path)
    inner = "demo_project_py"
    spa = "demo_project_spa"

    expected_directories = [
        ".vscode",
        f"{inner}/app/etc/develop",
        f"{inner}/app/etc/release",
        f"{inner}/app/st_test",
        f"{inner}/demo_project/common/conf",
        f"{inner}/demo_project/common/dependencies",
        f"{inner}/demo_project/common/infra/storage",
        f"{inner}/demo_project/common/dto",
        f"{inner}/demo_project/common/infra/orm",
        f"{inner}/demo_project/core/app",
        f"{inner}/demo_project/core/main/router",
        f"{inner}/demo_project/core/main/service",
        f"{spa}/public",
        f"{spa}/public/icons",
        f"{spa}/src/assets",
        f"{spa}/src/boot",
        f"{spa}/src/components",
        f"{spa}/src/css",
        f"{spa}/src/layouts",
        f"{spa}/src/network/api",
        f"{spa}/src/network/dto",
        f"{spa}/src/pages",
        f"{spa}/src/pages/admin",
        f"{spa}/src/pages/home",
        f"{spa}/src/pages/user",
        f"{spa}/src/router",
    ]

    for relative_dir in expected_directories:
        assert (project_root /
                relative_dir).is_dir(), f"expected dir: {relative_dir}"

    assert (project_root / ".vscode/settings.json").is_file()
    assert (project_root / ".vscode/launch.json").is_file()
    assert (project_root / ".gitignore").is_file()
    assert "demo_project.db" in (project_root / ".gitignore").read_text(encoding="utf-8")
    assert (project_root / f"{inner}/pyproject.toml").is_file()
    assert not (project_root / f"{inner}/config.yaml").exists()
    assert (project_root / f"{inner}/demo_project").is_dir()
    assert not (project_root / f"{inner}/app/__init__.py").exists()
    assert (project_root / f"{inner}/app/run.py").is_file()
    assert (project_root / f"{inner}/app/st_test/conftest.py").is_file()
    assert (project_root /
            f"{inner}/app/st_test/test_health_router.py").is_file()
    assert (project_root /
            f"{inner}/app/st_test/test_health_router.yaml").is_file()
    assert (project_root /
            f"{inner}/app/st_test/test_user_opt_router.py").is_file()
    assert (project_root /
            f"{inner}/app/st_test/test_user_opt_router.yaml").is_file()
    assert (project_root /
            f"{inner}/demo_project/core/main/router/admin/admin_op.py").is_file()
    assert (project_root /
            f"{inner}/demo_project/core/main/service/admin/admin_op.py").is_file()
    assert (project_root / f"{inner}/demo_project/core/app/run.py").is_file()
    assert (project_root /
            f"{inner}/demo_project/core/main/schedule/__init__.py").is_file()
    assert not (project_root /
                f"{inner}/demo_project/core/main/schedule/schedule_base.py").exists()
    assert (project_root /
            f"{inner}/demo_project/core/main/schedule/schedule_demo.py").is_file()
    assert (project_root /
            f"{inner}/demo_project/core/main/schedule/schedule_ping.py").is_file()
    assert (project_root /
            f"{inner}/demo_project/common/conf/__init__.py").is_file()
    assert (project_root /
            f"{inner}/demo_project/common/dependencies/__init__.py").is_file()
    assert (project_root /
            f"{inner}/demo_project/common/dependencies/auth.py").is_file()
    assert (project_root /
            f"{inner}/demo_project/common/dependencies/client.py").is_file()
    assert (project_root /
            f"{inner}/demo_project/common/dto/user/health.py").is_file()
    assert (project_root /
            f"{inner}/demo_project/common/dto/user/user_op.py").is_file()
    assert (project_root /
            f"{inner}/demo_project/common/infra/storage/__init__.py").is_file()
    assert (project_root /
            f"{inner}/demo_project/common/infra/storage/default_storage.py").is_file()
    assert (project_root /
            f"{inner}/demo_project/common/infra/orm/__init__.py").is_file()
    assert (project_root /
            f"{inner}/demo_project/common/infra/orm/kv_conf.py").is_file()
    assert (project_root /
            f"{inner}/demo_project/common/infra/orm/user_base.py").is_file()
    assert (project_root /
            f"{inner}/demo_project/common/infra/orm/user_tree.py").is_file()
    assert not (project_root /
                f"{inner}/demo_project/core/main/schedule/SKILLS.md").exists()
    assert not list(project_root.rglob("__SKILLS.md"))

    pyproject_content = (
        project_root / f"{inner}/pyproject.toml").read_text(encoding="utf-8")
    assert 'kmvpy>=0.2.1' in pyproject_content
    assert '"pytest"' in pyproject_content
    assert '"aiomysql"' in pyproject_content
    assert '"asyncpg"' in pyproject_content
    assert '"aiosqlite"' in pyproject_content

    readme_content = (
        project_root / f"{inner}/README.md").read_text(encoding="utf-8")
    assert 'pip install -e ".[test,sqlite]"' in readme_content
    assert "pytest app/st_test" in readme_content
    assert "app/etc/develop/config.yaml" in readme_content
    assert "Python: Select Interpreter" in readme_content
    assert "测试面板" in readme_content
    assert "app/st_test/test_health_router.py -q" in readme_content
    assert "pytest app/st_test -vv" in readme_content
    assert "test_user_opt_router.yaml" in readme_content
    assert "step.action" in readme_content
    assert "METHOD /uri" in readme_content
    assert "新增冒烟测试" in readme_content
    assert "本项目由 `kmvpy create` 生成" in readme_content
    assert "## Schedule Demo" in readme_content
    assert "core/main/schedule/__init__.py" in readme_content
    assert "core/main/schedule/schedule_demo.py" in readme_content
    assert "core/main/schedule/schedule_ping.py" in readme_content
    assert "Schedule` / `ScheduleManager" in readme_content
    assert "不依赖 `config.yaml` 驱动" in readme_content
    assert "core/main/__init__.py` 只会调用这里暴露的方法" in readme_content
    assert "每分钟按当前 `service.port`" in readme_content
    assert "http://localhost:{service.port}/api/ping" in readme_content
    assert "schedule_base.py" not in readme_content

    develop_config = (
        project_root / f"{inner}/app/etc/develop/config.yaml"
    ).read_text(encoding="utf-8")
    assert 'env: "dev"' in develop_config
    assert "database:" in develop_config
    assert 'url: "sqlite+aiosqlite:///./demo_project.db"' in develop_config
    assert "auth_config:" in develop_config
    assert "redis:" in develop_config
    assert 'path: "./logs"' in develop_config
    assert 'port: 15000' in develop_config
    assert "schedule:" not in develop_config

    release_config = (
        project_root / f"{inner}/app/etc/release/config.yaml"
    ).read_text(encoding="utf-8")
    assert 'env: "main"' in release_config
    assert 'active_kid: "user-20050607"' in release_config
    assert 'private_key_path: "/run/secrets/demo_project/jwt-private-user-20050607.pem"' in release_config
    assert "# default_storage:" in release_config
    assert '#   redis:' in release_config
    assert 'path: "/tmp/demo_project/logs"' in release_config
    assert "schedule:" not in release_config

    settings_content = (
        project_root / ".vscode/settings.json").read_text(encoding="utf-8")
    assert '"./demo_project_py"' in settings_content
    assert '"cursorpyright.analysis.extraPaths"' in settings_content

    launch_content = (
        project_root / ".vscode/launch.json").read_text(encoding="utf-8")
    assert '"cwd": "${workspaceFolder}/demo_project_py"' in launch_content
    assert '"app.run:create_app"' in launch_content

    app_run_content = (project_root / f"{inner}/app/run.py").read_text(
        encoding="utf-8"
    )
    assert "DEMO_PROJECT_CONFIG_PATH" in app_run_content
    assert "app.run:create_app" in app_run_content

    st_test_support = (project_root / f"{inner}/app/st_test/conftest.py").read_text(
        encoding="utf-8"
    )
    assert "sqlite+aiosqlite:///" in st_test_support
    assert 'Path(__file__).resolve().parents[1] / "etc" / "develop" / "config.yaml"' in st_test_support
    assert "TestClient(app, base_url=base_url)" in st_test_support
    assert "gen_asgi_app" in st_test_support

    st_test_health = (project_root / f"{inner}/app/st_test/test_health_router.py").read_text(
        encoding="utf-8"
    )
    assert "class TestHealthRouter(StBasePyTest):" in st_test_health
    assert "def on_step(" not in st_test_health
    assert "ApiResponse(**resp.json())" in st_test_health

    st_test_health_yaml = (project_root / f"{inner}/app/st_test/test_health_router.yaml").read_text(
        encoding="utf-8"
    )
    assert "test_ping:" in st_test_health_yaml
    assert "GET /api/ping" in st_test_health_yaml
    assert "message: pong" in st_test_health_yaml
    assert "step_kid: STEP_PING" in st_test_health_yaml
    assert "comment: ping returns pong" in st_test_health_yaml

    st_test_user = (project_root / f"{inner}/app/st_test/test_user_opt_router.py").read_text(
        encoding="utf-8"
    )
    assert "def build_request_kwargs(" in st_test_user
    assert "def after_step_hook(" in st_test_user
    assert "def on_step(" not in st_test_user
    assert 'next_step_request.request = {"verify_code": "666666"}' in st_test_user
    assert "_AUTH_RESPONSE_STEP_KIDS" in st_test_user
    assert '_STEP_EMAIL_REGISTER = "STEP_EMAIL_REGISTER"' in st_test_user
    assert '_STEP_EMAIL_LOGIN = "STEP_EMAIL_LOGIN"' in st_test_user
    assert "/api/user/profile" in st_test_user
    assert "/api/user/profile/update" in st_test_user
    assert "user_smoke_client" in st_test_user

    st_test_user_yaml = (project_root / f"{inner}/app/st_test/test_user_opt_router.yaml").read_text(
        encoding="utf-8"
    )
    assert "test_send_email_verify_code:" in st_test_user_yaml
    assert "test_email_register:" in st_test_user_yaml
    assert "test_email_login:" in st_test_user_yaml
    assert "test_get_user_profile:" in st_test_user_yaml
    assert "test_update_user_profile:" in st_test_user_yaml
    assert "POST /api/user/email/verify-code" in st_test_user_yaml
    assert "POST /api/user/email/register" in st_test_user_yaml
    assert "POST /api/user/email/login" in st_test_user_yaml
    assert "POST /api/user/profile" in st_test_user_yaml
    assert "POST /api/user/profile/update" in st_test_user_yaml
    assert "step_kid: STEP_SEND_EMAIL_VERIFY_CODE" in st_test_user_yaml
    assert "step_kid: STEP_EMAIL_REGISTER" in st_test_user_yaml
    assert "step_kid: STEP_EMAIL_LOGIN" in st_test_user_yaml
    assert "step_kid: STEP_GET_USER_PROFILE" in st_test_user_yaml
    assert "step_kid: STEP_UPDATE_USER_PROFILE" in st_test_user_yaml
    assert "request:" in st_test_user_yaml
    assert "inputs:" not in st_test_user_yaml
    assert 'verify_code: "666666"' not in st_test_user_yaml

    core_run_content = (project_root / f"{inner}/demo_project/core/app/run.py").read_text(
        encoding="utf-8"
    )
    assert "DEMO_PROJECT_CONFIG_PATH" in core_run_content
    assert '"app", "etc", "release", "config.yaml"' in core_run_content

    deploy_script_content = (
        project_root / f"{inner}/app/etc/release/deploy.sh"
    ).read_text(encoding="utf-8")
    assert "ROTATE_JWT_KEYS" in deploy_script_content
    assert '"$PYTHON" -m kmvpy.generator.cli rotate-jwt-keys "$CONFIG"' in deploy_script_content
    assert deploy_script_content.index('"$PYTHON" -m pip install -U --force-reinstall "$WHEEL"') < (
        deploy_script_content.index('"$PYTHON" -m kmvpy.generator.cli rotate-jwt-keys "$CONFIG"')
    )
    assert deploy_script_content.index('"$PYTHON" -m kmvpy.generator.cli rotate-jwt-keys "$CONFIG"') < (
        deploy_script_content.index('echo "==> 启动服务: $PYTHON $ENTRY $CONFIG"')
    )

    storage_module = (project_root / f"{inner}/demo_project/common/infra/storage/default_storage.py").read_text(
        encoding="utf-8"
    )
    assert "import threading" in storage_module
    assert "from kmvpy.common.infra.korm_storage import KOrmStorage" in storage_module
    assert "class DefaultStorage(KOrmStorage):" in storage_module
    assert "def __init__(self, *args, **kwargs) -> None:" in storage_module
    assert "self.init_db_session()" in storage_module
    assert "if self.redis_config is not None:" in storage_module
    assert "def has_redis_client(self) -> bool:" in storage_module
    assert "def set_redis_client(self, redis_client) -> None:" in storage_module
    assert "async def dispose(self) -> None:" in storage_module
    assert "self.init_redis_client()" in storage_module
    assert "def current(cls) -> DefaultStorage | None:" in storage_module
    assert "def instance(cls, config: BaseConfig | None = None) -> DefaultStorage:" in storage_module
    assert "app_config = config or kosmos.config" in storage_module
    assert "database_config = app_config.get_default_storage_database_config()" in storage_module
    assert "redis_config = app_config.get_default_storage_redis_config()" in storage_module
    assert "database_config=config.database" not in storage_module
    assert "def init_domain(" not in storage_module
    assert "def get_domain(" not in storage_module

    core_main_content = (project_root / f"{inner}/demo_project/core/main/__init__.py").read_text(
        encoding="utf-8"
    )
    assert (
        "from demo_project.common.infra.orm import init_default_admin_if_needed, init_tables"
        in core_main_content
    )
    assert "from kmvpy.common.schedule import ScheduleManager" not in core_main_content
    assert "from demo_project.core.main.schedule import (" in core_main_content
    assert "register_app_schedule_jobs" in core_main_content
    assert "from demo_project.common.storage.default_storage import DefaultStorage" not in core_main_content
    assert "default_storage = DefaultStorage.instance(config)" in core_main_content
    assert "app = init_asgi_app(config, routers, storage=default_storage)" in core_main_content
    assert "if config.get_default_storage_database_config():" in core_main_content
    assert "await init_tables()" in core_main_content
    assert "await init_default_admin_if_needed(config)" in core_main_content
    assert "await init_tables(default_storage)" not in core_main_content
    assert "_existing_lifespan = app.router.lifespan_context" in core_main_content
    assert "schedule_managers = register_app_schedule_jobs()" not in core_main_content
    assert "for schedule_manager in schedule_managers:" not in core_main_content
    assert "register_app_schedule_jobs()" in core_main_content
    assert "await ScheduleManager.start()" not in core_main_content
    assert "for schedule_manager in reversed(schedule_managers):" not in core_main_content
    assert "await ScheduleManager.shutdown()" not in core_main_content

    schedule_init_content = (
        project_root / f"{inner}/demo_project/core/main/schedule/__init__.py"
    ).read_text(encoding="utf-8")
    assert "from .schedule_base import AppSchedule" not in schedule_init_content
    assert "from .schedule_demo import ScheduleHelloDemo" in schedule_init_content
    assert "from .schedule_ping import ScheduleHealthPing" in schedule_init_content
    assert "_SCHEDULE_REGISTRATIONS" not in schedule_init_content
    assert "def init_app_schedule_manager() -> type[ScheduleManager]:" not in schedule_init_content
    assert "def init_app_schedule_managers() -> tuple[type[ScheduleManager], ...]:" not in schedule_init_content
    assert 'return ScheduleManager' not in schedule_init_content
    assert "def register_app_schedule_jobs() -> None:" in schedule_init_content
    assert "ScheduleHelloDemo" in schedule_init_content
    assert "ScheduleHealthPing" in schedule_init_content
    assert "ScheduleConfig(" in schedule_init_content
    assert 'logger.info("开始注册 demo_project schedule 任务")' in schedule_init_content
    assert "ScheduleManager.register(" in schedule_init_content

    schedule_demo_content = (
        project_root /
        f"{inner}/demo_project/core/main/schedule/schedule_demo.py"
    ).read_text(encoding="utf-8")
    assert "from kmvpy.common.schedule import Schedule" in schedule_demo_content
    assert "class ScheduleHelloDemo(Schedule):" in schedule_demo_content
    assert "build_schedule_config" not in schedule_demo_content
    assert "[schedule-demo] demo_project 心跳任务触发" in schedule_demo_content
    assert "def register_schedule_demo_jobs(" not in schedule_demo_content

    schedule_ping_content = (
        project_root /
        f"{inner}/demo_project/core/main/schedule/schedule_ping.py"
    ).read_text(encoding="utf-8")
    assert "from urllib.request import urlopen" in schedule_ping_content
    assert "from demo_project.common.conf import get_app_config" in schedule_ping_content
    assert "class ScheduleHealthPing(Schedule):" in schedule_ping_content
    assert "build_schedule_config" not in schedule_ping_content
    assert "async def _before(self) -> None:" not in schedule_ping_content
    assert "await super()._before()" not in schedule_ping_content
    assert "async def _after(self) -> None:" not in schedule_ping_content
    assert "await super()._after()" not in schedule_ping_content
    assert "async def _on_error(self, error: Exception) -> None:" in schedule_ping_content
    assert "await super()._on_error(error)" in schedule_ping_content
    assert "[schedule-ping] 准备请求 demo_project ping接口。kid=%s" in schedule_ping_content
    assert "[schedule-ping] demo_project ping接口请求流程结束。kid=%s" in schedule_ping_content
    assert 'url = f"http://localhost:{config.service.port}/api/ping"' in schedule_ping_content
    assert 'logger.info(' in schedule_ping_content
    assert "def register_schedule_ping_jobs(" not in schedule_ping_content

    dependencies_init_content = (
        project_root / f"{inner}/demo_project/common/dependencies/__init__.py"
    ).read_text(encoding="utf-8")
    assert "from demo_project.common.dependencies.auth import auth_user" in dependencies_init_content
    assert "from demo_project.common.dependencies.client import ClientRequestInfo, client_request_info" in dependencies_init_content

    dependencies_auth_content = (
        project_root / f"{inner}/demo_project/common/dependencies/auth.py"
    ).read_text(encoding="utf-8")
    assert "def _authorization_invalid_detail(" in dependencies_auth_content
    assert "from demo_project.core.main.domain.user_op import UserOpDomain" in dependencies_auth_content
    assert "async def auth_user(" in dependencies_auth_content

    dependencies_client_content = (
        project_root / f"{inner}/demo_project/common/dependencies/client.py"
    ).read_text(encoding="utf-8")
    assert "class ClientRequestInfo(" in dependencies_client_content
    assert "def client_request_info(" in dependencies_client_content

    orm_init_content = (
        project_root / f"{inner}/demo_project/common/infra/orm/__init__.py"
    ).read_text(encoding="utf-8")
    assert 'from sqlalchemy import BigInteger, Integer' in orm_init_content
    assert 'from sqlalchemy.dialects.mysql import BIGINT as MYSQL_BIGINT' in orm_init_content
    assert 'BIGINT_TYPE = BigInteger().with_variant(MYSQL_BIGINT(unsigned=True), "mysql")' in orm_init_content
    assert 'AUTO_INCREMENT_PK_TYPE = BIGINT_TYPE.with_variant(Integer, "sqlite")' in orm_init_content

    kv_conf_content = (project_root / f"{inner}/demo_project/common/infra/orm/kv_conf.py").read_text(
        encoding="utf-8"
    )
    assert '__table_args__ = {"sqlite_autoincrement": True}' in kv_conf_content
    assert "from . import BIGINT_TYPE, AUTO_INCREMENT_PK_TYPE" in kv_conf_content
    assert "id = Column(" in kv_conf_content
    assert "AUTO_INCREMENT_PK_TYPE" in kv_conf_content
    assert "autoincrement=True" in kv_conf_content

    user_base_content = (project_root / f"{inner}/demo_project/common/infra/orm/user_base.py").read_text(
        encoding="utf-8"
    )
    assert 'from sqlalchemy import Column, DateTime, Integer, SmallInteger, String, func, text' in user_base_content
    assert "from . import BIGINT_TYPE, AUTO_INCREMENT_PK_TYPE" in user_base_content
    assert '__table_args__ = {"sqlite_autoincrement": True}' in user_base_content
    assert "id = Column(AUTO_INCREMENT_PK_TYPE, primary_key=True, index=True," in user_base_content
    assert "kid = Column(BIGINT_TYPE, nullable=False," in user_base_content

    user_tree_content = (project_root / f"{inner}/demo_project/common/infra/orm/user_tree.py").read_text(
        encoding="utf-8"
    )
    assert 'from sqlalchemy import Column, DateTime, Integer, String, func' in user_tree_content
    assert "from . import BIGINT_TYPE, AUTO_INCREMENT_PK_TYPE" in user_tree_content
    assert '__table_args__ = {"sqlite_autoincrement": True}' in user_tree_content
    assert "id = Column(AUTO_INCREMENT_PK_TYPE, primary_key=True, index=True," in user_tree_content
    assert "p9_kid = Column(BIGINT_TYPE, nullable=True, index=True," in user_tree_content

    assert not (project_root /
                "demo_project_py/demo_project/demo_project").exists()

    router_init = (
        project_root / f"{inner}/demo_project/core/main/router/__init__.py"
    ).read_text(encoding="utf-8")
    assert "user_op_router" in router_init
    assert "from demo_project.core.main.router.user.user_op import router as user_op_router" in router_init
    assert "admin_op_router" in router_init
    assert "from demo_project.core.main.router.admin.admin_op import router as admin_op_router" in router_init

    user_service = (
        project_root / f"{inner}/demo_project/core/main/service/user/user_op.py"
    ).read_text(encoding="utf-8")
    assert "from demo_project.common.dependencies.client import ClientRequestInfo" in user_service
    assert "from demo_project.common.infra.storage.default_storage import DefaultStorage" in user_service
    assert "from demo_project.common.dto.user.user_op import" in user_service
    assert "DefaultStorage.instance()" in user_service
    assert "DEBUG_EMAIL_CAPTCHA_CODE = UserOpDomain.DEBUG_EMAIL_CAPTCHA_CODE" in user_service
    assert "UserOpDomain.build_email_captcha_key" in user_service
    assert "request: Request" not in user_service
    assert "async def email_register(" in user_service

    user_router = (
        project_root / f"{inner}/demo_project/core/main/router/user/user_op.py"
    ).read_text(encoding="utf-8")
    assert "user_info: JwtUserInfo = Depends(auth_user)" in user_router
    assert "auth_res = await UserOpService.email_register(req, client_info)" in user_router
    assert "auth_res = await UserOpService.email_login(req, client_info)" in user_router
    assert "return _user_auth_success_response(auth_res)" in user_router

    admin_service = (
        project_root / f"{inner}/demo_project/core/main/service/admin/admin_op.py"
    ).read_text(encoding="utf-8")
    assert "class AdminOpService:" in admin_service
    assert "后台管理员账号相关能力" in admin_service
    assert "NOT_ADMIN_ERROR = UserOpDomain.NOT_ADMIN_ERROR" in admin_service
    assert "from demo_project.common.dto.user.user_op import" in admin_service

    admin_router = (
        project_root / f"{inner}/demo_project/core/main/router/admin/admin_op.py"
    ).read_text(encoding="utf-8")
    assert 'router = APIRouter(prefix="/api/admin"' in admin_router
    assert "AdminOpService.admin_login" in admin_router
    assert "Depends(auth_admin)" in admin_router

    orm_init = (
        project_root / f"{inner}/demo_project/common/infra/orm/__init__.py"
    ).read_text(encoding="utf-8")
    assert "from .user_base import UserBase" in orm_init
    assert "from .user_tree import UserTree" in orm_init
    assert "async def init_default_admin_if_needed(config: AppConfig)" in orm_init

    spa_package = (
        project_root / f"{spa}/package.json").read_text(encoding="utf-8")
    assert '"name": "demo_project_spa"' in spa_package
    assert '"quasar": "^2.16.0"' in spa_package
    assert '"axios": "^1.2.1"' in spa_package

    spa_env_dev = (
        project_root / f"{spa}/.env.development").read_text(encoding="utf-8")
    assert "VITE_API_BASE_URL=http://localhost:15000" in spa_env_dev
    assert "VITE_AUTH_STORAGE_KEY=demo_project_spa:authorization" in spa_env_dev

    spa_env_prod = (
        project_root / f"{spa}/.env.production").read_text(encoding="utf-8")
    assert "VITE_API_BASE_URL=https://example.kmvdata.com" in spa_env_prod

    spa_index_html = (
        project_root / f"{spa}/index.html").read_text(encoding="utf-8")
    assert "<!-- quasar:entry-point -->" in spa_index_html
    assert "<%= productName %>" in spa_index_html

    spa_quasar_config = (
        project_root / f"{spa}/quasar.config.ts").read_text(encoding="utf-8")
    assert "vueRouterMode: 'history'" in spa_quasar_config
    assert "plugins: ['Notify', 'Dialog']" in spa_quasar_config
    assert "'framework_style'" in spa_quasar_config
    assert "'axios_user'" in spa_quasar_config
    assert "'axios_admin'" in spa_quasar_config

    spa_pinia = (project_root /
                 f"{spa}/src/boot/pinia.ts").read_text(encoding="utf-8")
    assert "createPinia" in spa_pinia

    spa_axios = (project_root /
                 f"{spa}/src/boot/axios.ts").read_text(encoding="utf-8")
    assert 'export const API_BASE_URL = getRequiredEnv("VITE_API_BASE_URL");' in spa_axios
    assert 'const AUTH_STORAGE_KEY = getRequiredEnv("VITE_AUTH_STORAGE_KEY");' in spa_axios
    assert "import packageJson from" in spa_axios
    assert "const CLIENT_HEADER_NAMES = [" in spa_axios
    assert "throw new Error(`Missing required env: ${key}`);" in spa_axios
    assert "createApiClient" in spa_axios
    assert "setStoredAuthorization" in spa_axios

    spa_axios_user = (project_root / f"{spa}/src/boot/axios_user.ts").read_text(
        encoding="utf-8"
    )
    assert "USER_AUTH_STORAGE_KEY" in spa_axios_user
    assert "postUserApi" in spa_axios_user

    spa_axios_admin = (project_root / f"{spa}/src/boot/axios_admin.ts").read_text(
        encoding="utf-8"
    )
    assert "ADMIN_AUTH_STORAGE_KEY" in spa_axios_admin
    assert "postAdminApi" in spa_axios_admin

    spa_routes = (
        project_root / f"{spa}/src/router/routes.ts").read_text(encoding="utf-8")
    assert "component: () => import('../layouts/HomeLayout.vue')" in spa_routes
    assert "component: () => import('../layouts/UserLayout.vue')" in spa_routes
    assert "component: () => import('../layouts/AdminLayout.vue')" in spa_routes
    assert "component: () => import('../pages/home/IndexPage.vue')" in spa_routes
    assert "component: () => import('../pages/user/UsersPage.vue')" in spa_routes
    assert "component: () => import('../pages/admin/AdminHomePage.vue')" in spa_routes

    spa_home_layout = (
        project_root / f"{spa}/src/layouts/HomeLayout.vue").read_text(encoding="utf-8")
    assert "AccountStyleMenu" in spa_home_layout

    spa_user_layout = (
        project_root / f"{spa}/src/layouts/UserLayout.vue").read_text(encoding="utf-8")
    assert "AccountStyleMenu" in spa_user_layout

    spa_admin_layout = (
        project_root / f"{spa}/src/layouts/AdminLayout.vue").read_text(encoding="utf-8")
    assert "AccountStyleMenu" in spa_admin_layout

    spa_index_page = (
        project_root / f"{spa}/src/pages/home/IndexPage.vue").read_text(encoding="utf-8")
    assert '<q-page class="spa-page">' in spa_index_page

    spa_users_page = (project_root / f"{spa}/src/pages/user/UsersPage.vue").read_text(
        encoding="utf-8"
    )
    assert "ApiUserOp.getUserProfile" in spa_users_page

    spa_auth_card = (
        project_root / f"{spa}/src/components/EmailAuthCard.vue"
    ).read_text(encoding="utf-8")
    assert "ApiUserOp.sendEmailVerifyCode" in spa_auth_card
    assert "ApiUserOp.emailRegister" in spa_auth_card
    assert "ApiUserOp.emailLogin" in spa_auth_card

    assert not (project_root / f"{spa}/__SKILLS.md").exists()
    assert not (project_root / f"{spa}/src/components/__SKILLS.md").exists()
    assert not (project_root / f"{spa}/src/layouts/__SKILLS.md").exists()
    assert not (project_root / f"{spa}/src/network/__SKILLS.md").exists()
    assert not (project_root / f"{spa}/src/pages/__SKILLS.md").exists()
    assert sorted(path.name for path in (project_root / f"{spa}/src/components").iterdir()) == [
        "AccountStyleMenu.vue",
        "EmailAuthCard.vue",
    ]

    spa_user_opt_api = (project_root / f"{spa}/src/network/api/user/user_op.ts").read_text(
        encoding="utf-8"
    )
    assert "/api/user/email/register" in spa_user_opt_api

    spa_public_favicon = project_root / f"{spa}/public/favicon.ico"
    assert spa_public_favicon.is_file()
    assert spa_public_favicon.read_bytes() == (
        Path(__file__).with_name("template") / "spa" / "public" / "favicon.ico.tpl"
    ).read_bytes()

    spa_public_icon = project_root / f"{spa}/public/icons/favicon-128x128.png"
    assert spa_public_icon.is_file()
    assert spa_public_icon.read_bytes() == (
        Path(__file__).with_name("template")
        / "spa"
        / "public"
        / "icons"
        / "favicon-128x128.png.tpl"
    ).read_bytes()

    spa_asset_logo = project_root / f"{spa}/src/assets/quasar-logo-vertical.svg"
    assert spa_asset_logo.is_file()
    assert spa_asset_logo.read_text(encoding="utf-8") == (
        Path(__file__).with_name("template")
        / "spa"
        / "src"
        / "assets"
        / "quasar-logo-vertical.svg.tpl"
    ).read_text(encoding="utf-8")


def test_create_project_biu_is_executable(tmp_path: Path) -> None:
    project_root = create_project("demo_project", tmp_path)
    biu = project_root / "biu"
    assert biu.is_file()
    mode = biu.stat().st_mode
    assert mode & stat.S_IXUSR
    assert mode & stat.S_IXGRP
    assert mode & stat.S_IXOTH
    assert "#!/usr/bin/env bash" in biu.read_text(encoding="utf-8")


def test_update_project_upgrades_existing_biu_and_preserves_deploy_config(tmp_path: Path) -> None:
    project_root = create_project("demo_project", tmp_path)
    biu = project_root / "biu"
    deploy_sh = project_root / "demo_project_py/app/etc/release/deploy.sh"
    biu.write_text(
        "\n".join(
            [
                "#!/usr/bin/env bash",
                'BIU_DEPLOY_HOST="10.0.0.8"',
                'BIU_DEPLOY_USER="deploy"',
                'BIU_DEPLOY_DIST="/opt/demo_dist"',
                "BIU_DEPLOY_CONDA_ENV='signal'",
                'BIU_API_HOST="https://api.example.com"',
                'BIU_SPA_HOST="https://www.example.com"',
                'die "未知参数: 仅支持可选 --no-deps，收到: $p3"',
                "",
            ]
        ),
        encoding="utf-8",
    )
    biu.chmod(0o644)
    deploy_sh.write_text(
        "\n".join(
            [
                "#!/usr/bin/env bash",
                'echo "==> pip install -U --force-reinstall $WHEEL"',
                '"$PYTHON" -m pip install -U --force-reinstall "$WHEEL"',
                'echo "==> 启动服务: $PYTHON $ENTRY $CONFIG"',
                "",
            ]
        ),
        encoding="utf-8",
    )
    deploy_sh.chmod(0o644)

    update_project(str(project_root))

    content = biu.read_text(encoding="utf-8")
    assert "--rotate-jwt-keys" in content
    assert "--update-config" in content
    assert "--build-only" in content
    assert "parse_py_deploy_flags" in content
    assert "parse_spa_deploy_flags" in content
    assert "PARSED_PY_DEPLOY_BUILD_ONLY=1" in content
    assert "PARSED_SPA_DEPLOY_BUILD_ONLY=1" in content
    assert "ROTATE_JWT_KEYS=1" in content
    assert "PARSED_PY_DEPLOY_UPDATE_CONFIG=1" in content
    assert "sync_py_wheels_to_remote" in content
    assert "deploy py 是完整部署" in content
    assert "run_deploy_all" in content
    assert "run_deploy_spa" in content
    assert "run_deploy_py" in content
    assert 'if [[ -z "${target}" ]]; then\n    run_deploy_all' in content
    all_deploy_body = content[
        content.index("run_deploy_all() {"):
        content.index("main() {")
    ]
    assert all_deploy_body.index("run_py_build") < all_deploy_body.index("run_spa_build")
    assert all_deploy_body.index("run_spa_build") < all_deploy_body.index("build-only 完成")
    assert all_deploy_body.index("run_spa_build") < all_deploy_body.index("run_spa_scp")
    assert all_deploy_body.index("run_spa_scp") < all_deploy_body.index("run_py_deploy")
    assert 'PY_RELEASE_CONFIG="${PY_DIR}/app/etc/release/config.yaml"' in content
    assert 'scp "${SSH_PUSH_OPTS[@]}" "${PY_RELEASE_CONFIG}" "${DEPLOY_SSH}:${py_dir}/config.yaml"' in content
    assert 'run_deploy_py "${PARSED_PY_DEPLOY_NO_DEPS}" "${PARSED_PY_DEPLOY_ROTATE_JWT_KEYS}" "${PARSED_PY_DEPLOY_UPDATE_CONFIG}" "${PARSED_PY_DEPLOY_BUILD_ONLY}"' in content
    assert 'run_deploy_spa "${PARSED_SPA_DEPLOY_BUILD_ONLY}"' in content
    assert "run_deploy_all 1" in content
    assert 'biu_render_release_deploy_sh "${rotate_jwt_keys_flag}"' in content
    assert "缺少 ROTATE_JWT_KEYS 支持" in content
    assert "run_remote_jwt_key_rotation" not in content
    assert "biu push" not in content
    assert 'BIU_DEPLOY_HOST="10.0.0.8"' in content
    assert 'BIU_DEPLOY_USER="deploy"' in content
    assert 'BIU_DEPLOY_DIST="/opt/demo_dist"' in content
    assert "BIU_DEPLOY_CONDA_ENV='signal'" in content
    assert 'BIU_API_HOST="https://api.example.com"' in content
    assert 'BIU_SPA_HOST="https://www.example.com"' in content
    mode = biu.stat().st_mode
    assert mode & stat.S_IXUSR
    assert mode & stat.S_IXGRP
    assert mode & stat.S_IXOTH

    deploy_content = deploy_sh.read_text(encoding="utf-8")
    assert "ROTATE_JWT_KEYS" in deploy_content
    assert '"$PYTHON" -m kmvpy.generator.cli rotate-jwt-keys "$CONFIG"' in deploy_content
    assert deploy_content.index('"$PYTHON" -m pip install -U --force-reinstall "$WHEEL"') < (
        deploy_content.index('"$PYTHON" -m kmvpy.generator.cli rotate-jwt-keys "$CONFIG"')
    )
    assert deploy_content.index('"$PYTHON" -m kmvpy.generator.cli rotate-jwt-keys "$CONFIG"') < (
        deploy_content.index('echo "==> 启动服务: $PYTHON $ENTRY $CONFIG"')
    )
    deploy_mode = deploy_sh.stat().st_mode
    assert deploy_mode & stat.S_IXUSR
    assert deploy_mode & stat.S_IXGRP
    assert deploy_mode & stat.S_IXOTH


def test_create_project_does_not_materialize_nginx_templates(tmp_path: Path) -> None:
    project_root = create_project("demo_project", tmp_path)

    assert not (project_root / "nginx").exists()
    assert not (project_root / "nginx.conf.d").exists()


def test_nginx_cli_outputs_templates(capsys: pytest.CaptureFixture[str]) -> None:
    handle_nginx(type("Args", (), {"target": "api"})())
    api_output = capsys.readouterr().out
    assert "__API_HOST__" in api_output
    assert "__CORS_SPA_ORIGIN_LINE__" in api_output

    handle_nginx(type("Args", (), {"target": "spa"})())
    spa_output = capsys.readouterr().out
    assert "__SPA_HOST__" in spa_output
    assert "__SPA_ROOT__" in spa_output


def test_create_project_rejects_existing_directory(tmp_path: Path) -> None:
    create_project("demo_project", tmp_path)

    with pytest.raises(FileExistsError):
        create_project("demo_project", tmp_path)


def test_create_project_rejects_invalid_package_name(tmp_path: Path) -> None:
    with pytest.raises(ValueError):
        create_project("demo-project", tmp_path)


def test_update_project_creates_missing_files_and_preserves_existing_files(
    tmp_path: Path,
) -> None:
    project_root = create_project("demo_project", tmp_path)
    inner = "demo_project_py"
    spa = "demo_project_spa"

    missing_py_file = project_root / f"{inner}/app/st_test/test_health_router.py"
    missing_spa_file = project_root / f"{spa}/src/router/routes.ts"
    missing_static_file = project_root / f"{spa}/public/favicon.ico"
    existing_code_file = project_root / f"{inner}/demo_project/core/main/service/user/health.py"
    legacy_skills_file = project_root / f"{inner}/demo_project/core/main/service/__SKILLS.md"

    original_code_content = existing_code_file.read_text(encoding="utf-8")
    missing_py_file.unlink()
    missing_spa_file.unlink()
    missing_static_file.unlink()
    existing_code_file.write_text("# user customized\n", encoding="utf-8")
    legacy_skills_file.write_text("# old skills\n", encoding="utf-8")

    updated_root = update_project("demo_project", tmp_path)

    assert updated_root == project_root
    assert missing_py_file.is_file()
    assert missing_spa_file.is_file()
    assert missing_static_file.is_file()
    assert existing_code_file.read_text(encoding="utf-8") == "# user customized\n"
    assert existing_code_file.read_text(encoding="utf-8") != original_code_content
    assert legacy_skills_file.read_text(encoding="utf-8") == "# old skills\n"


def test_update_project_materializes_agents_templates_with_project_names(
    tmp_path: Path,
) -> None:
    project_root = create_project("demo_project", tmp_path)
    agents_root = project_root / ".agents"
    shutil.rmtree(agents_root)

    update_project("demo_project", tmp_path)

    expected_files = [
        ".agents/README.md",
        ".agents/skills/kmvpy-skill-creator/SKILL.md",
        ".agents/skills/kmvpy-skill-creator/SKILL.zh-CN.md",
        ".agents/skills/py-dev/SKILL.md",
        ".agents/skills/py-dev/SKILL.zh-CN.md",
        ".agents/skills/py-orm/SKILL.md",
        ".agents/skills/py-orm/SKILL.zh-CN.md",
        ".agents/skills/py-schedule/SKILL.md",
        ".agents/skills/py-schedule/SKILL.zh-CN.md",
        ".agents/skills/spa-dev/SKILL.md",
        ".agents/skills/spa-dev/SKILL.zh-CN.md",
    ]
    for relative_file in expected_files:
        assert (project_root / relative_file).is_file(), relative_file

    generated_agents_files = [
        path for path in agents_root.rglob("*") if path.is_file()
    ]
    assert not any(path.name.endswith(".tpl") for path in generated_agents_files)

    all_agents_content = "\n".join(
        path.read_text(encoding="utf-8") for path in generated_agents_files
    )
    assert "__PROJECT_NAME__" not in all_agents_content
    assert "__PY_PROJECT_NAME__" not in all_agents_content
    assert "__SPA_PROJECT_NAME__" not in all_agents_content

    readme_content = (agents_root / "README.md").read_text(encoding="utf-8")
    assert "`demo_project_py` 后端设计" in readme_content
    assert "`demo_project_spa` Quasar/Vue 前端" in readme_content

    py_dev_content = (agents_root / "skills/py-dev/SKILL.md").read_text(
        encoding="utf-8"
    )
    assert "# demo_project_py Backend Development" in py_dev_content
    assert "inside the `demo_project` repository" in py_dev_content
    assert "`demo_project_py/demo_project`" in py_dev_content
    assert "cd demo_project_py" in py_dev_content

    spa_dev_content = (agents_root / "skills/spa-dev/SKILL.md").read_text(
        encoding="utf-8"
    )
    assert "# demo_project_spa Frontend Development" in spa_dev_content
    assert "inside the `demo_project` repository" in spa_dev_content
    assert "under `demo_project_spa`" in spa_dev_content


def test_project_relative_path_to_template_path_round_trips_special_names() -> None:
    assert (
        project_relative_path_to_template_path(
            "demo_project_py/demo_project/core/app/run.py", "demo_project"
        )
        == "py/__PROJECT_NAME__/core/app/run.py.tpl"
    )
    assert (
        project_relative_path_to_template_path(
            "demo_project_spa/.env.development", "demo_project"
        )
        == "spa/.env.development.tpl"
    )
    assert (
        project_relative_path_to_template_path(".gitignore", "demo_project")
        == "gitignore.tpl"
    )


def test_template_relative_path_to_project_path_supports_new_and_legacy_py_layout() -> None:
    assert (
        template_relative_path_to_project_path(
            "py/__PROJECT_NAME__/core/app/run.py.tpl", "demo_project"
        )
        == "demo_project_py/demo_project/core/app/run.py"
    )
    assert (
        template_relative_path_to_project_path(
            "py/__PY_PROJECT_NAME__/__PROJECT_NAME__/core/app/run.py.tpl",
            "demo_project",
        )
        == "demo_project_py/demo_project/core/app/run.py"
    )


def test_generate_template_from_project_reverses_project_names(
    tmp_path: Path,
) -> None:
    project_root = create_project("demo_project", tmp_path)
    template_parent = tmp_path / "gentpl_output"
    legacy_template = template_parent / "template/py/__PY_PROJECT_NAME__/stale.py.tpl"
    legacy_template.parent.mkdir(parents=True)
    legacy_template.write_text("stale legacy template", encoding="utf-8")
    app_run = project_root / "demo_project_py/app/run.py"
    app_run.write_text(
        "\n".join(
            [
                "project = 'demo_project'",
                "py = 'demo_project_py'",
                "spa = 'demo_project_spa'",
                "env = 'DEMO_PROJECT_CONFIG_PATH'",
                "",
            ]
        ),
        encoding="utf-8",
    )

    favicon = project_root / "demo_project_spa/public/favicon.ico"
    favicon_bytes = b"\x00demo_project\x00"
    favicon.write_bytes(favicon_bytes)

    generated_template_root = generate_template_from_project(
        "demo_project",
        base_directory=tmp_path,
        template_parent_directory=template_parent,
    )

    assert generated_template_root == template_parent / "template"
    assert not legacy_template.exists()
    app_run_tpl = generated_template_root / "py/app/run.py.tpl"
    assert app_run_tpl.read_text(encoding="utf-8") == "\n".join(
        [
            "project = '__PROJECT_NAME__'",
            "py = '__PY_PROJECT_NAME__'",
            "spa = '__SPA_PROJECT_NAME__'",
            "env = '__CONFIG_ENV_VAR__'",
            "",
        ]
    )
    assert (
        generated_template_root / "spa/public/favicon.ico.tpl"
    ).read_bytes() == favicon_bytes


def test_generate_template_from_project_reports_bad_text_file_context(
    tmp_path: Path,
) -> None:
    project_root = create_project("demo_project", tmp_path)
    bad_text_file = project_root / "demo_project_py/app/bad_encoding.txt"
    bad_text_file.write_bytes(b"ok\n\xba\n")
    template_parent = tmp_path / "gentpl_output"
    expected_target = template_parent / "template/py/app/bad_encoding.txt.tpl"

    with pytest.raises(GentplFileError) as exc_info:
        generate_template_from_project(
            "demo_project",
            base_directory=tmp_path,
            template_parent_directory=template_parent,
        )

    message = str(exc_info.value)
    assert "执行阶段: 读取 UTF-8 文本工程文件" in message
    assert f"源文件: {bad_text_file}" in message
    assert f"目标文件: {expected_target}" in message
    assert "'utf-8' codec can't decode byte" in message


def test_generate_template_from_project_respects_project_gitignore(
    tmp_path: Path,
) -> None:
    project_root = create_project("demo_project", tmp_path)
    gitignore = project_root / ".gitignore"
    gitignore.write_text(
        gitignore.read_text(encoding="utf-8")
        + "\n".join(
            [
                "",
                ".DS_Store",
                "ignored_dir/",
                "/*.local",
                "*.cache",
                "!keep.cache",
                "",
            ]
        ),
        encoding="utf-8",
    )
    (project_root / ".DS_Store").write_bytes(b"\xba")
    (project_root / "ignored_dir").mkdir()
    (project_root / "ignored_dir/file.txt").write_text("ignored", encoding="utf-8")
    (project_root / "nested/ignored_dir").mkdir(parents=True)
    (project_root / "nested/ignored_dir/file.txt").write_text(
        "ignored", encoding="utf-8"
    )
    (project_root / "secret.local").write_text("ignored", encoding="utf-8")
    (project_root / "nested").mkdir(exist_ok=True)
    (project_root / "nested/secret.local").write_text("kept", encoding="utf-8")
    (project_root / "drop.cache").write_text("ignored", encoding="utf-8")
    (project_root / "keep.cache").write_text("kept", encoding="utf-8")
    template_parent = tmp_path / "gentpl_output"

    generated_template_root = generate_template_from_project(
        "demo_project",
        base_directory=tmp_path,
        template_parent_directory=template_parent,
    )

    assert not (generated_template_root / ".DS_Store.tpl").exists()
    assert not (generated_template_root / "ignored_dir/file.txt.tpl").exists()
    assert not (generated_template_root / "nested/ignored_dir/file.txt.tpl").exists()
    assert not (generated_template_root / "secret.local.tpl").exists()
    assert not (generated_template_root / "drop.cache.tpl").exists()
    assert (generated_template_root / "nested/secret.local.tpl").is_file()
    assert (generated_template_root / "keep.cache.tpl").is_file()
    assert (generated_template_root / "gitignore.tpl").is_file()


def test_generate_template_from_project_respects_nested_gitignore_files(
    tmp_path: Path,
) -> None:
    project_root = create_project("demo_project", tmp_path)
    spa_src = project_root / "demo_project_spa/src"
    nested_gitignore = spa_src / ".gitignore"
    nested_gitignore.write_text(
        "\n".join(
            [
                "secret.js",
                "/anchored-only.txt",
                "pages/*.local",
                "cache/",
                "*.cache",
                "!keep.cache",
                "assets/**",
                "!assets/keep.txt",
                "",
            ]
        ),
        encoding="utf-8",
    )
    (spa_src / "secret.js").write_text("ignored", encoding="utf-8")
    (spa_src / "pages/secret.js").write_text("ignored", encoding="utf-8")
    (spa_src / "anchored-only.txt").write_text("ignored", encoding="utf-8")
    (spa_src / "pages/anchored-only.txt").write_text("kept", encoding="utf-8")
    (spa_src / "pages/user.local").write_text("ignored", encoding="utf-8")
    (spa_src / "components").mkdir(exist_ok=True)
    (spa_src / "components/user.local").write_text("kept", encoding="utf-8")
    (spa_src / "cache").mkdir(exist_ok=True)
    (spa_src / "cache/file.txt").write_text("ignored", encoding="utf-8")
    (spa_src / "pages/cache").mkdir(exist_ok=True)
    (spa_src / "pages/cache/file.txt").write_text("ignored", encoding="utf-8")
    (spa_src / "drop.cache").write_text("ignored", encoding="utf-8")
    (spa_src / "pages/keep.cache").write_text("kept", encoding="utf-8")
    (spa_src / "assets/drop.txt").write_text("ignored", encoding="utf-8")
    (spa_src / "assets/keep.txt").write_text("kept", encoding="utf-8")

    gitignore = project_root / ".gitignore"
    gitignore.write_text(
        gitignore.read_text(encoding="utf-8") + "\nignored_parent/\n",
        encoding="utf-8",
    )
    ignored_parent = project_root / "ignored_parent"
    ignored_parent.mkdir()
    (ignored_parent / ".gitignore").write_text("!keep.txt\n", encoding="utf-8")
    (ignored_parent / "keep.txt").write_text("ignored", encoding="utf-8")

    template_parent = tmp_path / "gentpl_output"
    generated_template_root = generate_template_from_project(
        "demo_project",
        base_directory=tmp_path,
        template_parent_directory=template_parent,
    )

    assert (generated_template_root / "spa/src/.gitignore.tpl").is_file()
    assert not (generated_template_root / "spa/src/secret.js.tpl").exists()
    assert not (generated_template_root / "spa/src/pages/secret.js.tpl").exists()
    assert not (generated_template_root / "spa/src/anchored-only.txt.tpl").exists()
    assert (
        generated_template_root / "spa/src/pages/anchored-only.txt.tpl"
    ).is_file()
    assert not (generated_template_root / "spa/src/pages/user.local.tpl").exists()
    assert (
        generated_template_root / "spa/src/components/user.local.tpl"
    ).is_file()
    assert not (generated_template_root / "spa/src/cache/file.txt.tpl").exists()
    assert not (
        generated_template_root / "spa/src/pages/cache/file.txt.tpl"
    ).exists()
    assert not (generated_template_root / "spa/src/drop.cache.tpl").exists()
    assert (generated_template_root / "spa/src/pages/keep.cache.tpl").is_file()
    assert not (generated_template_root / "spa/src/assets/drop.txt.tpl").exists()
    assert (generated_template_root / "spa/src/assets/keep.txt.tpl").is_file()
    assert not (generated_template_root / "ignored_parent/keep.txt.tpl").exists()


def test_generate_template_from_project_defaults_to_cwd_template(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    create_project("demo_project", tmp_path)
    monkeypatch.chdir(tmp_path)

    generated_template_root = generate_template_from_project("demo_project")

    assert generated_template_root == tmp_path / "template"
    assert (
        generated_template_root / "py/app/run.py.tpl"
    ).is_file()


def test_gentpl_cli_directory_only_controls_template_output(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    create_project("demo_project", tmp_path)
    template_parent = tmp_path / "generated_template_parent"
    monkeypatch.chdir(tmp_path)

    args = type(
        "Args",
        (),
        {
            "name": "demo_project",
            "directory": template_parent,
        },
    )()

    assert handle_gentpl(args) == 0
    assert (
        template_parent / "template/py/app/run.py.tpl"
    ).is_file()
    assert not (template_parent / "demo_project").exists()


def test_generate_template_from_project_ignores_runtime_files(tmp_path: Path) -> None:
    project_root = create_project("demo_project", tmp_path)
    template_parent = tmp_path / "gentpl_output"

    ignored_files = [
        "demo_project_spa/node_modules/pkg/index.js",
        "demo_project_py/__pycache__/run.pyc",
        ".git/config",
        "logs/app.log",
        "logs/app.tmp",
        "demo_project_spa/bun.lock",
        "demo_project_spa/.quasar/dev-spa/app.js",
        "demo_project_spa/dist/spa/index.html",
        "nginx.conf.d/api.example.com.conf",
    ]
    for relative in ignored_files:
        path = project_root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("runtime artifact", encoding="utf-8")

    spa_dist_file = project_root / "demo_project_spa/dist/server/index.html"
    spa_dist_file.parent.mkdir(parents=True, exist_ok=True)
    spa_dist_file.write_text("server artifact", encoding="utf-8")

    generated_template_root = generate_template_from_project(
        "demo_project",
        base_directory=tmp_path,
        template_parent_directory=template_parent,
    )

    assert not (generated_template_root / "spa/node_modules/pkg/index.js.tpl").exists()
    assert not (
        generated_template_root / "py/__pycache__/run.pyc.tpl"
    ).exists()
    assert not (generated_template_root / ".git/config.tpl").exists()
    assert not (generated_template_root / "logs/app.log.tpl").exists()
    assert not (generated_template_root / "logs/app.tmp.tpl").exists()
    assert not (generated_template_root / "spa/bun.lock.tpl").exists()
    assert not (
        generated_template_root / "spa/.quasar/dev-spa/app.js.tpl"
    ).exists()
    assert not (generated_template_root / "spa/dist/spa/index.html.tpl").exists()
    assert not (generated_template_root / "nginx.conf.d/api.example.com.conf.tpl").exists()
    assert not (generated_template_root / "spa/dist/server/index.html.tpl").exists()


def test_resolve_project_root_and_name_plain_name(tmp_path: Path) -> None:
    root, name = resolve_project_root_and_name("demo_project", tmp_path)
    assert name == "demo_project"
    assert root == tmp_path / "demo_project"


def test_resolve_project_root_and_name_path_ignores_base(tmp_path: Path) -> None:
    nested = tmp_path / "nested" / "demo_project"
    spec = str(nested)
    root, name = resolve_project_root_and_name(spec, tmp_path / "other_base")
    assert name == "demo_project"
    assert root == nested


def test_resolve_project_root_rejects_invalid_final_segment(tmp_path: Path) -> None:
    bad = tmp_path / "bad-name"
    with pytest.raises(ValueError, match="最后一级目录名"):
        resolve_project_root_and_name(str(bad), tmp_path)


def test_create_project_accepts_path_and_creates_parents(tmp_path: Path) -> None:
    target = tmp_path / "a" / "b" / "demo_project"
    project_root = create_project(str(target))
    assert project_root == target.resolve()
    assert (project_root / "demo_project_py" / "pyproject.toml").is_file()


def test_update_project_creates_missing_root_then_materializes(tmp_path: Path) -> None:
    missing = tmp_path / "fresh" / "demo_project"
    project_root = update_project(str(missing))
    assert project_root == missing.resolve()
    assert (project_root / "demo_project_py" / "pyproject.toml").is_file()


def test_update_cli_defaults_to_current_project_directory(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project_root = create_project("demo_project", tmp_path)
    missing_py_file = project_root / "demo_project_py/app/st_test/test_health_router.py"
    missing_py_file.unlink()
    monkeypatch.chdir(project_root)

    args = type("Args", (), {"name": None, "directory": tmp_path / "unused"})()

    assert handle_update(args) == 0
    assert missing_py_file.is_file()


def test_update_cli_dot_updates_current_project_directory(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project_root = create_project("demo_project", tmp_path)
    missing_py_file = project_root / "demo_project_py/app/st_test/test_health_router.py"
    missing_py_file.unlink()
    monkeypatch.chdir(project_root)

    args = type("Args", (), {"name": ".", "directory": tmp_path / "unused"})()

    assert handle_update(args) == 0
    assert missing_py_file.is_file()
