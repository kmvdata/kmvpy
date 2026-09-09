from kmvpy.generator.project_generator import create_project


def test_generated_storage_is_explicitly_wired_to_asgi_app(tmp_path) -> None:
    project_root = create_project("demo_project", tmp_path)
    source_root = project_root / "demo_project_py/demo_project"
    storage_module = (source_root / "common/infra/storage/default_storage.py").read_text(
        encoding="utf-8"
    )
    core_main_module = (source_root / "core/main/__init__.py").read_text(encoding="utf-8")
    user_service_module = (
        source_root / "core/main/service/user/user_op.py"
    ).read_text(encoding="utf-8")

    removed_binding = "kosmos." + "domain"
    assert removed_binding not in storage_module
    assert removed_binding not in user_service_module
    assert "default_storage = DefaultStorage.instance(config)" in core_main_module
    assert (
        "app = init_asgi_app(config, routers, storage=default_storage)"
        in core_main_module
    )
    assert "def current(cls) -> DefaultStorage | None:" in storage_module
    assert "storage = DefaultStorage.current()" in user_service_module
    assert "if storage is None or not storage.has_redis_client():" in user_service_module
    assert "return None" in user_service_module
