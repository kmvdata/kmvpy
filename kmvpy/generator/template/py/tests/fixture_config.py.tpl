"""Ephemeral keys and loopback-only Redis. Never loads repository deployment configuration."""
import tempfile
from pathlib import Path
from types import SimpleNamespace
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from kmvpy.common.conf import AuthConfig
from kmvpy.common.kmv import kosmos
from __PROJECT_NAME__.common.conf import RealtimeProtectionConfig


def install_fixture_config(redis_port=16389):
    directory = Path(tempfile.mkdtemp(prefix='__PROJECT_NAME__-auth-test-'))
    roles = {}
    for domain in ('user', 'admin'):
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        private, public = directory / (domain + '.key'), directory / (domain + '.pub')
        private.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
        private.chmod(0o600)
        public.write_bytes(key.public_key().public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo))
        roles[domain] = {'jwt': {'active_kid': 'test-' + domain, 'private_key_path': str(private),
            'public_keys': [{'kid': 'test-' + domain, 'public_key_path': str(public)}], 'audience': 'test-' + domain,
            'access_token_lifetime_hours': .01}, 'redis': {'host': '127.0.0.1', 'port': redis_port, 'db': 0}}
    kosmos.config = SimpleNamespace(auth_config=AuthConfig(**roles), realtime_protection=RealtimeProtectionConfig(),
                                    general=SimpleNamespace(env='develop', debug=True))
    return directory
