general:
  debug: false
  env: main
  timezone: Asia/Shanghai
logging:
  level: INFO
  max_bytes: 100MB
  backup_count: 5
  path: /tmp/__PROJECT_NAME__/logs
service:
  host: 127.0.0.1
  port: 15000
  workers: 1
  reload: false
  cors_allow_origins:
  - https://www.kmvdata.com
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
      active_kid: k-9b4de96e1f8ebcf3167c0f1c
      private_key_path: ./secrets/jwt-private-user-k-9b4de96e1f8ebcf3167c0f1c.pem
      public_keys:
      - kid: k-9b4de96e1f8ebcf3167c0f1c
        public_key_path: ./secrets/jwt-public-user-k-9b4de96e1f8ebcf3167c0f1c.pem
      - kid: k-6c2c05c1896dc377fd289e57
        public_key_path: ./secrets/jwt-public-user-k-6c2c05c1896dc377fd289e57.pem
      issuer: kmvpy
      audience: kmvpy-user-api
      access_token_lifetime_hours: 0.25
    session:
      idle_timeout_hours: 24.0
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
      active_kid: k-4d5a788ce7ced215e5ebdbf6
      private_key_path: ./secrets/jwt-private-admin-k-4d5a788ce7ced215e5ebdbf6.pem
      public_keys:
      - kid: k-4d5a788ce7ced215e5ebdbf6
        public_key_path: ./secrets/jwt-public-admin-k-4d5a788ce7ced215e5ebdbf6.pem
      - kid: k-5abf55bdd6ba0a2596234a7d
        public_key_path: ./secrets/jwt-public-admin-k-5abf55bdd6ba0a2596234a7d.pem
      issuer: kmvpy
      audience: kmvpy-admin-api
      access_token_lifetime_hours: 1.0
    session:
      idle_timeout_hours: 2.0
      absolute_timeout_hours: 8.0
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
    echo: true
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
