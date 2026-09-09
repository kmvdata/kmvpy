from __future__ import annotations

import re
import shutil
import stat
import sys
from pathlib import Path

from kmvpy.generator.gitignore_matcher import GitignoreMatcher

PROJECT_NAME_PATTERN = re.compile(r"^[A-Za-z][A-Za-z0-9_]*$")
TEMPLATE_DIR = Path(__file__).with_name("template")

_GENTPL_IGNORE_PATTERNS = (
    "node_modules/",
    "__pycache__/",
    ".git/",
    "*.log",
    "*.tmp",
    "bun.lock",
    ".quasar/",
    "**/dist/spa/",
    "nginx.conf.d/",
)

# 与「模板文件名去掉 .tpl 后的扩展名」匹配；此类文件按字节原样写出，不做占位符替换。
_BINARY_SUFFIXES_AFTER_STRIPPING_DOT_TPL = frozenset(
    {
        ".png",
        ".jpg",
        ".jpeg",
        ".gif",
        ".webp",
        ".bmp",
        ".ico",
        ".svg",
        ".icns",
        ".woff",
        ".woff2",
        ".ttf",
        ".eot",
    }
)

_BIU_PRESERVED_ASSIGNMENTS = (
    "BIU_DEPLOY_HOST",
    "BIU_DEPLOY_USER",
    "BIU_DEPLOY_DIST",
    "BIU_DEPLOY_CONDA_ENV",
    "BIU_API_HOST",
    "BIU_SPA_HOST",
)


class GentplFileError(ValueError):
    """gentpl 处理单个文件失败时携带源文件和模板目标文件。"""

    def __init__(
        self,
        stage: str,
        source_path: Path,
        dest_path: Path,
        cause: BaseException,
    ) -> None:
        self.stage = stage
        self.source_path = source_path
        self.dest_path = dest_path
        self.cause = cause
        super().__init__(
            "\n".join(
                [
                    "gentpl 执行失败。",
                    f"执行阶段: {stage}",
                    f"源文件: {source_path}",
                    f"目标文件: {dest_path}",
                    f"原因: {cause}",
                ]
            )
        )


def validate_project_name(project_name: str) -> str:
    normalized_name = project_name.strip()
    if not normalized_name:
        raise ValueError("工程名称不能为空。")
    if not PROJECT_NAME_PATTERN.fullmatch(normalized_name):
        raise ValueError("工程名称仅支持字母开头，可包含字母、数字和下划线。")
    return normalized_name


def _looks_like_filesystem_path_to_project_root(spec: str) -> bool:
    """判断用户输入是否应解释为「工程根目录」路径，而非仅工程名。"""
    s = spec.strip()
    if not s:
        return False
    if Path(s).is_absolute():
        return True
    if "/" in s or "\\" in s:
        return True
    if s.startswith(("./", ".\\", "../", "..\\")):
        return True
    # Windows 盘符路径（未带反斜杠时 Path 可能仍解析为相对路径）
    if sys.platform == "win32" and len(s) >= 2 and s[1] == ":":
        return True
    return False


def resolve_project_root_and_name(
    spec: str,
    base_directory: str | Path | None = None,
) -> tuple[Path, str]:
    """根据「工程名」或「工程根目录路径」解析出 ``(project_root, project_name)``。

    - 若 ``spec`` 为路径形态（含分隔符、绝对路径、``./`` ``../`` 开头等），则
      ``project_root`` 为该路径（展开用户目录并 resolve），工程名为路径
      **最后一级目录名**（须通过 :func:`validate_project_name`）。
    - 否则将 ``spec`` 视为工程名，``project_root = base / name``，其中
      ``base`` 为 ``base_directory`` 或当前工作目录。
    """
    raw = spec.strip()
    if not raw:
        raise ValueError("工程名称或路径不能为空。")

    if _looks_like_filesystem_path_to_project_root(raw):
        project_root = Path(raw).expanduser().resolve()
        name = project_root.name
        if not name or name in (".", ".."):
            raise ValueError(f"无法从路径解析工程名称: {project_root}")
        try:
            normalized_name = validate_project_name(name)
        except ValueError as exc:
            raise ValueError(
                f"工程根路径最后一级目录名「{name}」不是合法的工程名称"
                f"（须字母开头，仅含字母、数字与下划线）。"
            ) from exc
        return project_root, normalized_name

    normalized_name = validate_project_name(raw)
    base = Path(base_directory or Path.cwd()).expanduser().resolve()
    return base / normalized_name, normalized_name


def _ensure_project_root_directory(project_root: Path, *, for_create: bool) -> None:
    """若 ``project_root`` 不存在则递归创建；存在时校验为目录。

    ``for_create=True`` 时若目录已存在则报错（避免覆盖已有工程）。
    """
    if project_root.exists():
        if not project_root.is_dir():
            raise NotADirectoryError(f"目标路径已存在但不是目录: {project_root}")
        if for_create:
            raise FileExistsError(f"目标目录已存在: {project_root}")
        return
    try:
        project_root.mkdir(parents=True, exist_ok=False)
    except OSError as exc:
        raise OSError(
            f"无法创建工程目录「{project_root}」。请检查上级路径是否存在、是否有写权限，"
            f"或磁盘是否已满。\n系统详情: {exc}"
        ) from exc


def create_project(project_spec: str, base_directory: str | Path | None = None) -> Path:
    project_root, normalized_name = resolve_project_root_and_name(
        project_spec, base_directory
    )
    _ensure_project_root_directory(project_root, for_create=True)

    _materialize_project(
        project_root,
        normalized_name,
        create_missing_only=False,
    )

    return project_root


def update_project(project_spec: str, base_directory: str | Path | None = None) -> Path:
    project_root, normalized_name = resolve_project_root_and_name(
        project_spec, base_directory
    )
    _ensure_project_root_directory(project_root, for_create=False)

    _materialize_project(
        project_root,
        normalized_name,
        create_missing_only=True,
    )

    return project_root


def _render_template_text(template_path: Path, project_name: str, output_rel: str) -> str:
    text = template_path.read_text(encoding="utf-8")
    return _apply_template_replacements(text, project_name, output_rel)


def _extract_biu_assignment_lines(text: str) -> dict[str, str]:
    preserved: dict[str, str] = {}
    for line in text.splitlines():
        for name in _BIU_PRESERVED_ASSIGNMENTS:
            if line.startswith(f"{name}="):
                preserved[name] = line
    return preserved


def _merge_biu_preserved_assignments(template_text: str, existing_text: str) -> str:
    preserved = _extract_biu_assignment_lines(existing_text)
    if not preserved:
        return template_text

    merged_lines: list[str] = []
    for line in template_text.splitlines():
        replaced = False
        for name, preserved_line in preserved.items():
            if line.startswith(f"{name}="):
                merged_lines.append(preserved_line)
                replaced = True
                break
        if not replaced:
            merged_lines.append(line)
    suffix = "\n" if template_text.endswith("\n") else ""
    return "\n".join(merged_lines) + suffix


def _maybe_upgrade_existing_biu(
    dest: Path,
    template_path: Path,
    project_name: str,
    output_rel: str,
) -> bool:
    existing_text = dest.read_text(encoding="utf-8")
    if (
        "--rotate-jwt-keys" in existing_text
        and "parse_py_deploy_flags" in existing_text
    ):
        return False

    template_text = _render_template_text(template_path, project_name, output_rel)
    updated_text = _merge_biu_preserved_assignments(template_text, existing_text)
    dest.write_text(updated_text, encoding="utf-8")
    mode = dest.stat().st_mode
    dest.chmod(mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return True


def _maybe_upgrade_existing_release_deploy_sh(
    dest: Path,
    template_path: Path,
    project_name: str,
    output_rel: str,
) -> bool:
    existing_text = dest.read_text(encoding="utf-8")
    if (
        "ROTATE_JWT_KEYS" in existing_text
        and "rotate-jwt-keys" in existing_text
    ):
        return False

    dest.write_text(
        _render_template_text(template_path, project_name, output_rel),
        encoding="utf-8",
    )
    mode = dest.stat().st_mode
    dest.chmod(mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return True


def generate_template_from_project(
    project_spec: str,
    base_directory: str | Path | None = None,
    template_parent_directory: str | Path | None = None,
) -> Path:
    """将已生成工程反向同步回 ``template/`` 目录。

    该命令用于维护 generator 自身的模板：它会把工程名相关内容恢复为占位符，
    但不会删除模板中已有而工程中不存在的文件。模板目录固定生成到
    ``template_parent_directory/template``，未指定时使用当前工作目录。
    """
    project_root, normalized_name = resolve_project_root_and_name(
        project_spec, base_directory
    )
    template_root = _resolve_generated_template_root(template_parent_directory)
    if not project_root.exists():
        raise FileNotFoundError(f"工程目录不存在: {project_root}")
    if not project_root.is_dir():
        raise NotADirectoryError(f"工程路径不是目录: {project_root}")

    _remove_legacy_py_template_root(template_root)

    for source_path in _iter_project_files_for_template(project_root):
        project_rel = source_path.relative_to(project_root).as_posix()
        template_rel = project_relative_path_to_template_path(
            project_rel, normalized_name
        )
        dest = template_root / template_rel
        dest.parent.mkdir(parents=True, exist_ok=True)

        if _is_binary_template_file(dest):
            try:
                content = source_path.read_bytes()
            except OSError as exc:
                raise GentplFileError(
                    "读取二进制工程文件", source_path, dest, exc
                ) from exc
            try:
                dest.write_bytes(content)
            except OSError as exc:
                raise GentplFileError(
                    "写入二进制模板文件", source_path, dest, exc
                ) from exc
        else:
            try:
                text = source_path.read_text(encoding="utf-8")
            except UnicodeDecodeError as exc:
                raise GentplFileError(
                    "读取 UTF-8 文本工程文件", source_path, dest, exc
                ) from exc
            except OSError as exc:
                raise GentplFileError(
                    "读取文本工程文件", source_path, dest, exc
                ) from exc
            try:
                dest.write_text(
                    _apply_reverse_template_replacements(
                        text, normalized_name, template_rel
                    ),
                    encoding="utf-8",
                )
            except OSError as exc:
                raise GentplFileError(
                    "写入文本模板文件", source_path, dest, exc
                ) from exc

    return template_root


def _resolve_generated_template_root(
    template_parent_directory: str | Path | None = None,
) -> Path:
    parent = Path(template_parent_directory or Path.cwd()).expanduser().resolve()
    return parent / "template"


def _remove_legacy_py_template_root(template_root: Path) -> None:
    """清理旧版 gentpl 生成的 py/__PY_PROJECT_NAME__ 包装目录。"""
    legacy_py_root = template_root / "py" / "__PY_PROJECT_NAME__"
    if legacy_py_root.is_dir():
        shutil.rmtree(legacy_py_root)
    elif legacy_py_root.exists():
        legacy_py_root.unlink()


def _py_project_name(project_name: str) -> str:
    return f"{project_name}_py"


def _spa_project_name(project_name: str) -> str:
    return f"{project_name}_spa"


def _config_env_var_name(project_name: str) -> str:
    return f"{project_name.upper()}_CONFIG_PATH"


def _spa_api_base_url(env: str) -> str:
    if env == "development":
        return "http://localhost:15000"
    return "https://example.kmvdata.com"


def _normalize_template_filename(filename: str) -> str:
    if filename == "gitignore.tpl":
        return ".gitignore"
    if filename == "env.development.tpl":
        return ".env.development"
    if filename == "env.production.tpl":
        return ".env.production"
    if filename.endswith(".tpl"):
        return filename[: -len(".tpl")]
    return filename


def _map_segment_placeholder(segment: str, project_name: str, py_name: str) -> str:
    return segment.replace("__PY_PROJECT_NAME__", py_name).replace(
        "__PROJECT_NAME__", project_name
    )


def template_relative_path_to_project_path(
    relative_to_template_dir: str, project_name: str
) -> str:
    """将 ``template/`` 下相对路径映射为生成工程内的相对路径。"""
    parts = relative_to_template_dir.split("/")
    py_name = _py_project_name(project_name)
    spa_name = _spa_project_name(project_name)

    if parts[0] == "py":
        # 兼容历史模板布局：旧版模板在 py/ 下额外包了一层
        # __PY_PROJECT_NAME__，新版模板直接把 Python 子项目内容放在 py/ 下。
        if len(parts) >= 2 and parts[1] == "__PY_PROJECT_NAME__":
            mapped = [py_name] + [
                _map_segment_placeholder(p, project_name, py_name) for p in parts[2:]
            ]
        else:
            mapped = [py_name] + [
                _map_segment_placeholder(p, project_name, py_name) for p in parts[1:]
            ]
    elif parts[0] == "spa":
        mapped = [spa_name] + [
            _map_segment_placeholder(p, project_name, py_name) for p in parts[1:]
        ]
    else:
        mapped = [
            _map_segment_placeholder(p, project_name, py_name) for p in parts
        ]

    *parent_parts, filename = mapped
    filename = _normalize_template_filename(filename)
    if not parent_parts:
        return filename
    return "/".join(parent_parts + [filename])


def _denormalize_template_filename(filename: str, parent_parts: list[str]) -> str:
    if filename == ".gitignore" and not parent_parts:
        return "gitignore.tpl"
    return f"{filename}.tpl"


def _unmap_segment_placeholder(segment: str, project_name: str, py_name: str) -> str:
    return segment.replace(py_name, "__PY_PROJECT_NAME__").replace(
        project_name, "__PROJECT_NAME__"
    )


def project_relative_path_to_template_path(
    relative_to_project_root: str, project_name: str
) -> str:
    """将生成工程内相对路径映射回 ``template/`` 下的相对路径。"""
    parts = relative_to_project_root.split("/")
    py_name = _py_project_name(project_name)
    spa_name = _spa_project_name(project_name)

    if parts[0] == py_name:
        mapped = ["py"] + [
            _unmap_segment_placeholder(p, project_name, py_name) for p in parts[1:]
        ]
    elif parts[0] == spa_name:
        mapped = ["spa"] + [
            _unmap_segment_placeholder(p, project_name, py_name) for p in parts[1:]
        ]
    else:
        mapped = [
            _unmap_segment_placeholder(p, project_name, py_name) for p in parts
        ]

    *parent_parts, filename = mapped
    filename = _denormalize_template_filename(filename, parent_parts)
    if not parent_parts:
        return filename
    return "/".join(parent_parts + [filename])


def _is_binary_template_file(template_path: Path) -> bool:
    name = template_path.name
    if not name.endswith(".tpl"):
        return True
    without_tpl = name[: -len(".tpl")]
    suffix = Path(without_tpl).suffix.lower()
    return suffix in _BINARY_SUFFIXES_AFTER_STRIPPING_DOT_TPL


def _replacement_items(project_name: str, output_relative: str) -> list[tuple[str, str]]:
    replacements: dict[str, str] = {
        "PROJECT_NAME": project_name,
        "PY_PROJECT_NAME": _py_project_name(project_name),
        "SPA_PROJECT_NAME": _spa_project_name(project_name),
        "CONFIG_ENV_VAR": _config_env_var_name(project_name),
        "PROJECT_NAME_UPPER": project_name.upper(),
    }
    if output_relative.endswith(".env.development"):
        replacements["API_BASE_URL"] = _spa_api_base_url("development")
    elif output_relative.endswith(".env.production"):
        replacements["API_BASE_URL"] = _spa_api_base_url("production")
    return sorted(replacements.items(), key=lambda kv: len(kv[0]), reverse=True)


def _apply_template_replacements(
    content: str, project_name: str, output_relative: str
) -> str:
    for key, value in _replacement_items(project_name, output_relative):
        content = content.replace(f"__{key}__", str(value))
    return content


def _reverse_replacement_items(
    project_name: str, template_relative: str
) -> list[tuple[str, str]]:
    values = {
        _config_env_var_name(project_name): "__CONFIG_ENV_VAR__",
        _py_project_name(project_name): "__PY_PROJECT_NAME__",
        _spa_project_name(project_name): "__SPA_PROJECT_NAME__",
        project_name.upper(): "__PROJECT_NAME_UPPER__",
        project_name: "__PROJECT_NAME__",
    }
    if template_relative.endswith(".env.development.tpl"):
        values[_spa_api_base_url("development")] = "__API_BASE_URL__"
    elif template_relative.endswith(".env.production.tpl"):
        values[_spa_api_base_url("production")] = "__API_BASE_URL__"
    return sorted(values.items(), key=lambda kv: len(kv[0]), reverse=True)


def _apply_reverse_template_replacements(
    content: str, project_name: str, template_relative: str
) -> str:
    for value, placeholder in _reverse_replacement_items(
        project_name, template_relative
    ):
        content = content.replace(value, placeholder)
    return content


def _iter_template_files() -> list[Path]:
    paths: list[Path] = []
    for path in sorted(TEMPLATE_DIR.rglob("*")):
        if path.is_file():
            paths.append(path)
    return paths


def _iter_project_files_for_template(project_root: Path) -> list[Path]:
    matcher = GitignoreMatcher.from_tree(
        project_root,
        hard_patterns=_GENTPL_IGNORE_PATTERNS,
    )
    return matcher.iter_visible_files()


def _materialize_project(
    project_root: Path,
    project_name: str,
    *,
    create_missing_only: bool,
) -> None:
    for template_path in _iter_template_files():
        rel = template_path.relative_to(TEMPLATE_DIR).as_posix()
        output_rel = template_relative_path_to_project_path(rel, project_name)
        dest = project_root / output_rel

        if create_missing_only and dest.exists():
            if output_rel == "biu":
                _maybe_upgrade_existing_biu(
                    dest,
                    template_path,
                    project_name,
                    output_rel,
                )
            elif output_rel == f"{_py_project_name(project_name)}/app/etc/release/deploy.sh":
                _maybe_upgrade_existing_release_deploy_sh(
                    dest,
                    template_path,
                    project_name,
                    output_rel,
                )
            continue

        dest.parent.mkdir(parents=True, exist_ok=True)

        if _is_binary_template_file(template_path):
            dest.write_bytes(template_path.read_bytes())
        else:
            dest.write_text(
                _render_template_text(template_path, project_name, output_rel),
                encoding="utf-8",
            )

        if output_rel == "biu":
            mode = dest.stat().st_mode
            dest.chmod(mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
