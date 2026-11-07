import ast
import json
import os
import re
import shutil
import stat
import subprocess
import tomllib
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
    backend = project_root / "demo_project_py"
    frontend = project_root / "demo_project_spa"
    expected_files = (
        ".vscode/settings.json", ".vscode/launch.json", ".gitignore", "biu",
        "demo_project_py/pyproject.toml", "demo_project_py/app/run.py",
        "demo_project_py/app/etc/develop/config.yaml",
        "demo_project_py/app/etc/release/config.yaml",
        "demo_project_py/app/etc/release/deploy.sh",
        "demo_project_py/tests/test_realtime.py", "demo_project_py/tests/realtime_fixture.py",
        "demo_project_py/demo_project/core/app/run.py",
        "demo_project_py/demo_project/core/main/__init__.py",
        "demo_project_py/demo_project/core/main/schedule/__init__.py",
        "demo_project_py/demo_project/common/infra/storage/default_storage.py",
        "demo_project_spa/package.json", "demo_project_spa/src/router/routes.ts",
        "demo_project_spa/src/pages/home/AuthPage.vue",
        "demo_project_spa/src/pages/app/personal/PersonalProfilePage.vue",
        "demo_project_spa/src/pages/admin/system/AdminSystemSettingsPage.vue",
        "demo_project_spa/src/network/realtime/manager.ts",
    )
    for relative_path in expected_files:
        assert (project_root / relative_path).is_file(), relative_path
    assert not (backend / "demo_project/demo_project").exists()
    assert not list(project_root.rglob("*.tpl"))

    for source in backend.rglob("*.py"):
        text = source.read_text(encoding="utf-8")
        tree = ast.parse(text, filename=str(source))
        assert "__PROJECT_NAME__" not in text, source
        # Every generated absolute project import must resolve to a generated module.
        for node in ast.walk(tree):
            if isinstance(node, ast.ImportFrom) and node.module:
                module_names = [node.module] if not node.level else []
            elif isinstance(node, ast.Import):
                module_names = [alias.name for alias in node.names]
            else:
                continue
            for module_name in module_names:
                if not module_name.startswith("demo_project."):
                    continue
                module_path = backend.joinpath(*module_name.split("."))
                assert module_path.with_suffix(".py").is_file() or (
                    module_path / "__init__.py"
                ).is_file(), (source, module_name)

    package = json.loads((frontend / "package.json").read_text(encoding="utf-8"))
    assert package["name"] == "demo_project_spa"
    assert "socket.io-client" in package["dependencies"]
    assert "quasar" in package["dependencies"]
    routes_path = frontend / "src/router/routes.ts"
    routes = routes_path.read_text(encoding="utf-8")
    route_targets = re.findall(r'import\(["\']([^"\']+)["\']\)', routes)
    assert route_targets
    for target in route_targets:
        assert (routes_path.parent / target).is_file(), target
    assert "VITE_API_BASE_URL=http://localhost:15000" in (
        frontend / ".env.development"
    ).read_text(encoding="utf-8")
    assert "VITE_API_BASE_URL=https://api.kmvdata.com" in (
        frontend / ".env.production"
    ).read_text(encoding="utf-8")
    assert (frontend / "public/app-logo.svg").read_bytes() == (
        Path(__file__).with_name("template") / "spa/public/app-logo.svg.tpl"
    ).read_bytes()


def test_generated_dependency_contract(tmp_path: Path) -> None:
    project_root = create_project("dependency_project", tmp_path)
    backend = project_root / "dependency_project_py"
    metadata = tomllib.loads((backend / "pyproject.toml").read_text(encoding="utf-8"))
    assert metadata["build-system"]["requires"] == ["setuptools>=77.0.3"]
    assert metadata["project"]["requires-python"] == ">=3.11"
    # The generated application receives all runtime drivers from the framework's extras.
    assert metadata["project"]["dependencies"] == ["kmvpy[mysql]>=0.2.3,<0.3"]
    assert metadata["project"]["optional-dependencies"] == {
        "test": ["kmvpy[test]>=0.2.3,<0.3"]
    }
    for filename in ("README.md", "README.en.md"):
        readme = (project_root / filename).read_text(encoding="utf-8")
        assert 'pip install -e ".[test]"' in readme
        assert "OpenAI SDK" not in readme
        assert "Cassandra driver" not in readme


def test_generated_socketio_mount_is_owned_by_framework(tmp_path: Path) -> None:
    project_root = create_project("socket_project", tmp_path)
    entry = project_root / "socket_project_py/socket_project/core/main/__init__.py"
    tree = ast.parse(entry.read_text(encoding="utf-8"))
    assert any(isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
               and node.func.id == "init_asgi_app" for node in ast.walk(tree))
    assert not any(isinstance(node, ast.Attribute) and node.attr == "engineio_path"
                   for node in ast.walk(tree))
    for role in ("user", "admin"):
        source = project_root / f"socket_project_py/socket_project/core/main/service/{role}/socket/__init__.py"
        assert 'getattr(socket_manager, "server", socket_manager)' in source.read_text(encoding="utf-8")


def test_create_project_biu_is_executable(tmp_path: Path) -> None:
    project_root = create_project("demo_project", tmp_path)
    biu = project_root / "biu"
    assert biu.is_file()
    if os.name != "nt":
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
    assert "run_build_all" in content
    assert 'BIU_DEPLOY_HOST="10.0.0.8"' in content
    assert 'BIU_DEPLOY_USER="deploy"' in content
    assert 'BIU_DEPLOY_DIST="/opt/demo_dist"' in content
    assert "BIU_DEPLOY_CONDA_ENV='signal'" in content
    assert 'BIU_API_HOST="https://api.example.com"' in content
    assert 'BIU_SPA_HOST="https://www.example.com"' in content
    if os.name != "nt":
        assert biu.stat().st_mode & stat.S_IXUSR

    deploy_content = deploy_sh.read_text(encoding="utf-8")
    install = '"$PYTHON" -m pip install -U --no-deps --force-reinstall "$WHEEL"'
    framework = '"$PYTHON" -m pip install --force-reinstall "kmvpy[mysql]==${KMVPY_VERSION}"'
    rotate = '"$PYTHON" -m kmvpy.generator.cli rotate-jwt-keys "$CONFIG"'
    start_service = 'echo "==> 启动服务: $PYTHON $ENTRY $CONFIG"'
    assert deploy_content.index(install) < deploy_content.index(framework)
    assert deploy_content.index(framework) < deploy_content.index(rotate)
    assert deploy_content.index(rotate) < deploy_content.index(start_service)
    if os.name != "nt":
        assert deploy_sh.stat().st_mode & stat.S_IXUSR
    if bash := shutil.which("bash"):
        subprocess.run([bash, "-n", str(biu)], check=True, capture_output=True)
        subprocess.run([bash, "-n", str(deploy_sh)], check=True, capture_output=True)

    update_project(str(project_root))
    assert biu.read_text(encoding="utf-8") == content
    assert deploy_sh.read_text(encoding="utf-8") == deploy_content


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

    missing_py_file = project_root / f"{inner}/tests/test_realtime.py"
    missing_spa_file = project_root / f"{spa}/src/router/routes.ts"
    missing_static_file = project_root / f"{spa}/public/app-logo.svg"
    existing_code_file = project_root / f"{inner}/demo_project/core/main/service/user/user_op.py"
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
        ".agents/skills/py-dev/SKILL.md",
        ".agents/skills/py-dev/references/persistence.md",
        ".agents/skills/py-dev/references/verification.md",
        ".agents/skills/spa-dev/SKILL.md",
        ".agents/skills/spa-dev/references/sockets.md",
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
    assert "`demo_project_py`" in readme_content
    assert "`demo_project_spa`" in readme_content

    py_dev_content = (agents_root / "skills/py-dev/SKILL.md").read_text(
        encoding="utf-8"
    )
    assert "name: py-dev" in py_dev_content
    assert "demo_project_py/demo_project" in py_dev_content
    assert "`demo_project_py/demo_project`" in py_dev_content
    assert "references/verification.md" in py_dev_content

    spa_dev_content = (agents_root / "skills/spa-dev/SKILL.md").read_text(
        encoding="utf-8"
    )
    assert "name: spa-dev" in spa_dev_content
    assert "demo_project_spa" in spa_dev_content
    assert "references/sockets.md" in spa_dev_content


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
    (spa_src / "assets").mkdir(exist_ok=True)
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
    missing_py_file = project_root / "demo_project_py/tests/test_realtime.py"
    missing_py_file.unlink()
    monkeypatch.chdir(project_root)

    args = type("Args", (), {"name": None, "directory": tmp_path / "unused"})()

    assert handle_update(args) == 0
    assert missing_py_file.is_file()


def test_update_cli_dot_updates_current_project_directory(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    project_root = create_project("demo_project", tmp_path)
    missing_py_file = project_root / "demo_project_py/tests/test_realtime.py"
    missing_py_file.unlink()
    monkeypatch.chdir(project_root)

    args = type("Args", (), {"name": ".", "directory": tmp_path / "unused"})()

    assert handle_update(args) == 0
    assert missing_py_file.is_file()
