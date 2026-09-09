# coding: utf-8
"""管理端系统维护服务。"""

import os
import subprocess
import sys
from pathlib import Path

from kmvpy.common.exception.kmv_exception import KmvException
from kmvpy.common.tool.logger import logger

from __PROJECT_NAME__.common.dto.admin.system import (
    AdminServiceRestartReq,
    AdminServiceRestartRes,
)
from __PROJECT_NAME__.common.exception import system_errors as system_exc


class AdminSystemService:
    """管理端系统维护能力。"""

    _RESTART_CONFIRM_TEXT = "RESTART_SERVICE"
    _DEPLOY_SCRIPT_ENV = "__PROJECT_NAME_UPPER___DEPLOY_SH"
    _CONFIG_ENV_NAMES = ("__CONFIG_ENV_VAR__", "__PROJECT_NAME___CONFIG_PATH")

    @staticmethod
    def _ensure_restart_confirmed(req: AdminServiceRestartReq) -> None:
        if req.confirm_text.strip() != AdminSystemService._RESTART_CONFIRM_TEXT:
            raise KmvException(error=system_exc.SERVICE_RESTART_CONFIRM_MISMATCH_ERROR)

    @staticmethod
    def _runtime_config_path() -> Path | None:
        for env_name in AdminSystemService._CONFIG_ENV_NAMES:
            value = os.getenv(env_name)
            if value and value.strip():
                return Path(value).expanduser().resolve()
        return None

    @staticmethod
    def _resolve_deploy_script() -> tuple[Path, Path | None]:
        override = os.getenv(AdminSystemService._DEPLOY_SCRIPT_ENV)
        if override and override.strip():
            script = Path(override).expanduser().resolve()
            if script.is_file():
                return script, AdminSystemService._runtime_config_path()

        config_path = AdminSystemService._runtime_config_path()
        if config_path is not None:
            script = config_path.parent / "deploy.sh"
            if script.is_file():
                return script.resolve(), config_path

        raise KmvException(error=system_exc.SERVICE_RESTART_SCRIPT_NOT_FOUND_ERROR)

    @staticmethod
    def _build_restart_env(config_path: Path | None) -> dict[str, str]:
        env = os.environ.copy()
        env.setdefault("PYTHON", sys.executable)
        if config_path is not None:
            config_text = str(config_path)
            env["__CONFIG_ENV_VAR__"] = config_text
            env["__PROJECT_NAME___CONFIG_PATH"] = config_text
        return env

    @staticmethod
    async def restart_service(req: AdminServiceRestartReq) -> AdminServiceRestartRes:
        AdminSystemService._ensure_restart_confirmed(req)
        script_path, config_path = AdminSystemService._resolve_deploy_script()
        script_dir = script_path.parent
        log_path = script_dir / "service_restart.out"

        try:
            with log_path.open("ab") as log_file:
                proc = subprocess.Popen(
                    [
                        "bash",
                        "-c",
                        'sleep 2; exec bash "$1"',
                        "signal-tracker-restart",
                        str(script_path),
                    ],
                    cwd=str(script_dir),
                    env=AdminSystemService._build_restart_env(config_path),
                    stdin=subprocess.DEVNULL,
                    stdout=log_file,
                    stderr=subprocess.STDOUT,
                    start_new_session=True,
                    close_fds=True,
                )
        except KmvException:
            raise
        except Exception as exc:  # noqa: BLE001
            logger.warning("触发服务重启失败: %s", exc, exc_info=exc)
            raise KmvException(
                error=system_exc.SERVICE_RESTART_TRIGGER_FAILED_ERROR
            ) from exc

        logger.warning("已触发服务重启脚本 pid=%s path=%s", proc.pid, script_path)
        return AdminServiceRestartRes(accepted=True, restart_pid=proc.pid)
