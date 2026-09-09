# Docker 依赖服务（PostgreSQL / Redis）

项目本身不跑 Docker。Docker Compose 只负责启动两个基础服务，后端和前端仍按 README 方式本地运行：

- PostgreSQL：业务数据库，默认 `localhost:5432`
- Redis：缓存、会话、Socket.IO，默认 `localhost:6379`

## 快速启动

```bash
# 开发环境
cd __PY_PROJECT_NAME__/app/etc/develop
docker compose up -d

# 发布环境（服务器）
cd __PY_PROJECT_NAME__/app/etc/release
docker compose up -d
```

验证：

```bash
docker compose ps
docker exec -it postgres pg_isready -U dbuser -d __PROJECT_NAME__
docker exec -it redis redis-cli -a 'cgd3nf4fs1PnYfKDgA3gCxk47zFNT9L5' ping   # 返回 PONG
```

## 配置文件

| 用途 | 路径 |
| --- | --- |
| 开发 Compose | `__PY_PROJECT_NAME__/app/etc/develop/docker-compose.yaml` |
| 发布 Compose | `__PY_PROJECT_NAME__/app/etc/release/docker-compose.yaml` |
| 开发配置 | `__PY_PROJECT_NAME__/app/etc/develop/config.yaml` |
| 发布配置 | `__PY_PROJECT_NAME__/app/etc/release/config.yaml` |

## ⚠️ 配置必须对齐（最常见的坑）

config.yaml 与 Compose 的用户名、密码、数据库名必须一致，否则后端启动后连不上库。

脚手架默认固定值：

| 项 | 值 |
| --- | --- |
| POSTGRES_USER | `dbuser` |
| POSTGRES_PASSWORD | `3PVtuInMCcYwOa9Xye7akWQr0RTfTFp3` |
| Redis 密码 | `cgd3nf4fs1PnYfKDgA3gCxk47zFNT9L5` |
| 端口 | PG `5432` / Redis `6379` |

已知不一致：release 下 Compose 的 `POSTGRES_DB` 是 `__PROJECT_NAME__`，而 `release/config.yaml` 的数据库 URL 指向 `stock_chat_db`。**发布前必须二选一对齐**（改 Compose 的 `POSTGRES_DB`，或改 config 的 `url`）。开发环境两者均为 `__PROJECT_NAME__`，无需处理。

## 数据卷（Linux 服务器必改）

Compose 默认挂载 `/Volumes/dbs/...`（macOS 路径）。Linux 上改成服务器目录：

```yaml
volumes:
  - /data/__PROJECT_NAME__/postgres:/var/lib/postgresql
  - /data/__PROJECT_NAME__/redis:/data
```

```bash
sudo mkdir -p /data/__PROJECT_NAME__/postgres /data/__PROJECT_NAME__/redis
sudo chmod -R 755 /data/__PROJECT_NAME__
```

PostgreSQL 18+ 要求挂父目录，所以挂到 `/var/lib/postgresql` 而非 `.../data`，保持现状即可。

## 常用维护

```bash
docker compose down                                  # 停止
docker exec -it postgres psql -U dbuser -d __PROJECT_NAME__  # 进 PG
docker exec -it redis redis-cli -a '<Redis 密码>'     # 进 Redis
docker exec postgres pg_dump -U dbuser -d __PROJECT_NAME__ > __PROJECT_NAME__.sql     # 备份
cat __PROJECT_NAME__.sql | docker exec -i postgres psql -U dbuser -d __PROJECT_NAME__ # 恢复
```

## 排障

- 容器起不来：`docker compose logs postgres` / `docker compose logs redis`
- 端口被占：`lsof -i :5432` / `lsof -i :6379`
- 后端连不上：按"配置必须对齐"逐项核对
- 数据卷问题：确认目录存在且 Docker 可写
