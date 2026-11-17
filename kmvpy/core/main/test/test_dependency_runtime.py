"""Exercise integrations affected by dependency upgrades without external services."""
import asyncio
import json

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi import HTTPException
import pytest
from sqlalchemy import Column, Integer, String, select
from sqlalchemy.orm import DeclarativeBase

from kmvpy.common.conf import BaseConfig, DatabaseConfig, JwtConfig
from kmvpy.common.infra.korm_storage import KOrmStorage
from kmvpy.core.main import init_asgi_app
from kmvpy.core.main.service.jwt_service import JwtService, JwtUserInfo


def test_async_sqlite_transactions_and_disposal():
    class Base(DeclarativeBase):
        pass

    class Record(Base):
        __tablename__ = "dependency_record"
        id = Column(Integer, primary_key=True)
        value = Column(String, nullable=False)

    async def scenario():
        storage = KOrmStorage(database_config=DatabaseConfig(url="sqlite+aiosqlite:///:memory:"))
        storage.init_db_session()
        try:
            async with storage.engine.begin() as connection:
                await connection.run_sync(Base.metadata.create_all)
            async with storage.db_session() as session:
                session.add(Record(id=1, value="committed"))
                await session.commit()
            async with storage.db_session() as session:
                session.add(Record(id=2, value="rolled back"))
                await session.flush()
                await session.rollback()
            async with storage.db_session() as session:
                assert (await session.execute(select(Record.value))).scalars().all() == ["committed"]
        finally:
            await storage.dispose()
        assert not storage.has_db_session()

    asyncio.run(scenario())


def test_ec_jwt_roundtrip_and_invalid_signature(tmp_path):
    key = ec.generate_private_key(ec.SECP256R1())
    private_path, public_path = tmp_path / "private.pem", tmp_path / "public.pem"
    private_path.write_bytes(key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
    ))
    public_path.write_bytes(key.public_key().public_bytes(
        serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo
    ))
    config = JwtConfig.model_validate({
        "algorithm": "ES256", "active_kid": "ec-key", "private_key_path": str(private_path),
        "public_keys": [{"kid": "ec-key", "public_key_path": str(public_path)}],
        "issuer": "test", "audience": "test-api", "access_token_lifetime_hours": 0.25,
    })
    token = JwtService.encode_token(JwtUserInfo(kid=42, user_type=0), auth_role="user", jwt_config=config)
    assert JwtService.decode_token(token, auth_role="user", jwt_config=config)["sub"] == "42"
    header, payload, signature = token.split(".")
    changed = ("A" if signature[0] != "A" else "B") + signature[1:]
    with pytest.raises(HTTPException) as exc:
        JwtService.decode_token(f"{header}.{payload}.{changed}", auth_role="user", jwt_config=config)
    assert exc.value.status_code == 401


def test_i18n_json_configuration_and_locale_fallback(tmp_path, monkeypatch):
    import i18n
    import kmvpy.core.main as core_main
    from kmvpy.common.kmv import kosmos

    # The legacy translation package has process-global settings/cache.
    monkeypatch.setattr(kosmos, "config", getattr(kosmos, "config", None), raising=False)
    monkeypatch.setattr(kosmos, "socketio", getattr(kosmos, "socketio", None), raising=False)
    monkeypatch.setattr(core_main, "init_logger", lambda **kwargs: None)
    load_path = []
    monkeypatch.setattr(i18n, "load_path", load_path)
    monkeypatch.setattr(i18n.config, "settings", {**i18n.config.settings, "load_path": load_path})
    monkeypatch.setattr(i18n.translations, "container", {})
    translations = {
        "probe.en.json": {"hello": "Hello %{name}"},
        "probe.zh-CN.json": {"hello": "你好 %{name}"},
    }
    for name, content in translations.items():
        (tmp_path / name).write_text(json.dumps(content), encoding="utf-8")
    config = BaseConfig.model_validate({
        "general": {"env": "test", "debug": True}, "logging": {"level": "WARNING"},
        "i18n": {"path": str(tmp_path), "locale": "zh-CN"},
    })
    init_asgi_app(config, routers=[])
    assert i18n.t("probe.hello", name="Ada") == "你好 Ada"
    assert i18n.t("probe.hello", locale="en", name="Ada") == "Hello Ada"
    assert i18n.t("probe.missing", default="fallback") == "fallback"
