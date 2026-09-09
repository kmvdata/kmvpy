# biu 发布指南

`biu` 是仓库根目录的发布脚本，一条命令完成：本地构建 → 上传 → 远程安装 wheel → 重启服务。

## 常用命令

| 命令 | 作用 |
| --- | --- |
| `./biu` | 只本地构建（py wheel + SPA），不上传 |
| `./biu deploy` | 全量发布：先部署 SPA，再部署后端 |
| `./biu deploy spa` | 只发布前端 |
| `./biu deploy py` | 只发布后端 |
| `./biu conda create 3.11` | 在远程创建 conda 环境 |
| `./biu nginx` | 生成 Nginx 配置（见 ops-nginx-and-certificates.md） |
| `./biu --rotate-jwt-keys` | 轮换本地开发配置的 JWT 密钥 |

## 1. 改配置

编辑脚本顶部（前 30 行），必改项：

```bash
BIU_DEPLOY_HOST=""                                  # 服务器 IP/域名；留空则从 BIU_SPA_HOST 推导
BIU_DEPLOY_USER="__PROJECT_NAME__"                          # SSH 用户
BIU_DEPLOY_DIST="/home/__PROJECT_NAME__/__PROJECT_NAME___dist"      # 远程发布目录
BIU_DEPLOY_CONDA_ENV='kmvpy'                       # 远程 conda 环境名
BIU_API_HOST=""                                     # API 域名，如 https://api.example.com
BIU_SPA_HOST=""                                     # SPA 域名，如 https://www.example.com
```

`BIU_API_HOST` / `BIU_SPA_HOST` 用于生成 Nginx 配置，并在构建时自动同步 `VITE_API_BASE_URL`，建议直接填真实域名。不想改脚本时，可用环境变量临时覆盖目标：

```bash
BIU_DEPLOY=deploy@example.com:/home/__PROJECT_NAME__/__PROJECT_NAME___dist ./biu deploy
```

## 2. 准备环境

本地需要：bash、ssh/scp、tar、Python（含 `build` 模块）、bun（无 bun.lock 时才用 pnpm/npm）。

```bash
cd __PY_PROJECT_NAME__ && python -m pip install build
cd ../__SPA_PROJECT_NAME__ && bun install
```

远程需要：SSH 可登录、目录可写、PostgreSQL/Redis 已启动（见 ops-docker-services.md）。首次发布前：

```bash
ssh __PROJECT_NAME__@example.com "mkdir -p /home/__PROJECT_NAME__/__PROJECT_NAME___dist"
BIU_DEPLOY=__PROJECT_NAME__@example.com:/home/__PROJECT_NAME__/__PROJECT_NAME___dist ./biu conda create 3.11
```

## 3. 发布前检查

```bash
sed -n '1,140p' __PY_PROJECT_NAME__/app/etc/release/config.yaml
```

- `service.port` 与 Nginx upstream 一致（默认 `15000`）
- `service.cors_allow_origins` 包含 SPA 域名
- 数据库 / Redis 连接信息与 docker-compose 一致（见 ops-docker-services.md）
- JWT 私钥路径指向发布目录 `py/` 下可写的 `secrets/`

## 4. 发布

```bash
./biu deploy        # 全量
./biu deploy spa    # 仅前端
./biu deploy py     # 仅后端
```

后端发布可选参数（可组合使用）：

| 参数 | 作用 |
| --- | --- |
| `--update-config` | 用本地 release/config.yaml 覆盖远程 `py/config.yaml` |
| `--rotate-jwt-keys` | 安装 wheel 后、启动前轮换 JWT 密钥（已登录用户会掉线） |
| `--no-deps` | 不随 wheel 装依赖（当前 deploy.sh 本就固定 `--no-deps`，此参数主要为表达意图） |

远程 `py/deploy.sh` 会自动：选最新 wheel → 安装 → 停旧进程 → nohup 启动（pid 写入 `py/__PROJECT_NAME__.pid`，日志追加 `py/nohup.out`）。

## 5. 回滚

远程目录约定：

```text
<BIU_DEPLOY_DIST>/
  spa/            # 线上 SPA
  py/             # wheel、config.yaml、deploy.sh、pid、日志
  backup/         # SPA 旧目录备份：backup/spa.<时间戳>.bak
  py/backup/      # 旧 wheel 备份
```

SPA 回滚：

```bash
ssh __PROJECT_NAME__@example.com 'cd /home/__PROJECT_NAME__/__PROJECT_NAME___dist && rm -rf spa && cp -R backup/spa.20260101_120000.bak spa'
```

后端回滚（把旧 wheel 拷回，指定 `WHEEL` 手动跑 deploy.sh）：

```bash
ssh __PROJECT_NAME__@example.com '
cd /home/__PROJECT_NAME__/__PROJECT_NAME___dist/py
cp backup/__PROJECT_NAME__-0.0.1-py3-none-any.whl.20260101_120000.bak ./__PROJECT_NAME__-rollback.whl
CONDA_ENV=kmvpy WHEEL=./__PROJECT_NAME__-rollback.whl ./deploy.sh
'
```

## 6. 排障速查

| 现象 | 处理 |
| --- | --- |
| 报缺少 build 模块 | `python -m pip install build` |
| SSH/SCP 失败 | 检查 `BIU_DEPLOY`、SSH key、`~/.ssh/config`、远程目录权限 |
| conda 激活失败 | 检查 `BIU_DEPLOY_CONDA_ENV` 与远程环境名一致；可重跑 `./biu conda create 3.11` |
| 后端启动后 API 不通 | 看 `py/nohup.out`；确认 PG/Redis 已启动、Nginx upstream 指向 `127.0.0.1:15000` |
| 跨域或登录异常 | 检查 `cors_allow_origins` 与 SPA 实际访问域名是否一致 |
