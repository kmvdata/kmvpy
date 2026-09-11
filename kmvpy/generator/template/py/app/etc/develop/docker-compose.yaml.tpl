# 顶层指定 Docker Desktop 显示的名称
name: __PROJECT_NAME__

services:
  postgres:
    image: postgres:alpine
    container_name: postgres
    restart: always
    cpus: 0.8
    mem_limit: 1536m
    environment:
      POSTGRES_USER: dbuser
      POSTGRES_PASSWORD: 3PVtuInMCcYwOa9Xye7akWQr0RTfTFp3
      POSTGRES_DB: __PROJECT_NAME__
      TZ: Asia/Shanghai
    volumes:
      # Postgres 18+：挂父目录，不要挂 .../data
      - /Volumes/dbs/pg_data:/var/lib/postgresql
    ports:
      - "5432:5432"
    healthcheck:
      test: [ "CMD-SHELL", "pg_isready -U dbuser -d __PROJECT_NAME__" ]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:alpine
    container_name: redis
    restart: always
    cpus: 0.5
    mem_limit: 1024m
    command:
      - redis-server
      - --requirepass cgd3nf4fs1PnYfKDgA3gCxk47zFNT9L5
      - --maxmemory 800mb
      - --maxmemory-policy allkeys-lru
      - --appendonly yes
    volumes:
      - /Volumes/dbs/redis_data:/data
    ports:
      - "6379:6379"
    environment:
      TZ: Asia/Shanghai
