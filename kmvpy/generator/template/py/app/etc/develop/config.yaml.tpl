general:
  debug: false
  env: dev
  timezone: Asia/Shanghai
logging:
  level: INFO
  max_bytes: 1MB
  backup_count: 5
  path: ./logs
service:
  host: 127.0.0.1
  port: 15000
  workers: 1
  reload: false
i18n:
  path: locales
  locale: zh_CN
snowflake:
  worker_id: 1
  max_backwards_ms: 5
  epoch_year: 2020
  epoch_month: 1
  epoch_day: 1
auth_config:
  user:
    jwt:
      algorithm: RS256
      active_kid: k-28f7d5abf5953d37ce1d0bf9
      private_key_path: ./secrets/jwt-private-user-k-28f7d5abf5953d37ce1d0bf9.pem
      public_keys:
      - kid: k-28f7d5abf5953d37ce1d0bf9
        public_key_path: ./secrets/jwt-public-user-k-28f7d5abf5953d37ce1d0bf9.pem
      issuer: kmvpy
      audience: kmvpy-user-api
      access_token_lifetime_hours: 48.0
    session:
      idle_timeout_hours: 72.0
      absolute_timeout_hours: 720.0
      max_sessions_per_user: null
    redis:
      host: localhost
      port: 6379
      db: 1
      username: kmvuser
      password: www.kmvdata.com
      decode_responses: true
  admin:
    jwt:
      algorithm: RS256
      active_kid: k-b4d8515f6e0eb131dc692351
      private_key_path: ./secrets/jwt-private-admin-k-b4d8515f6e0eb131dc692351.pem
      public_keys:
      - kid: k-b4d8515f6e0eb131dc692351
        public_key_path: ./secrets/jwt-public-admin-k-b4d8515f6e0eb131dc692351.pem
      issuer: kmvpy
      audience: kmvpy-admin-api
      access_token_lifetime_hours: 48.0
    session:
      idle_timeout_hours: 72.0
      absolute_timeout_hours: 720.0
      max_sessions_per_user: 3
    redis:
      host: localhost
      port: 6379
      db: 10
      username: kmvuser
      password: www.kmvdata.com
      decode_responses: true
default_admin:
  username: admin
  password: Abc123456
default_storage:
  database:
    url: postgresql+asyncpg://kmvuser:www.kmvdata.com@localhost:5432/kmvdata
    pool_size: 10
    max_overflow: 5
    pool_recycle: 3600
    echo: false
    timeout: 60
    pool_pre_ping: true
    ssl: false
    options: -c timezone=Asia/Shanghai
  redis:
    host: localhost
    port: 6379
    db: 0
    username: kmvuser
    password: www.kmvdata.com
    decode_responses: true
