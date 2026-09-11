#!/usr/bin/env bash

# BIU_DEPLOY_HOST：发布主机。若留空或不是合法 IPv4，将在后续推算中使用 BIU_SPA_HOST 解析出的主机值。
# 不要写 user@ 或远程目录。
# -----------------------------------------------------------------------------
BIU_DEPLOY_HOST=""
# BIU_DEPLOY_USER：远程 SSH 用户名，只写用户名，不要写 @host。
BIU_DEPLOY_USER="__PROJECT_NAME__"
# BIU_DEPLOY_DIST：远程基础目录，只写服务器上的绝对目录，不要写 user@host: 前缀。
# biu 会在该目录下创建 / 使用 spa/、py/、backup/ 等子目录。
# 示例: "/home/__PROJECT_NAME__/__PROJECT_NAME___dist"
BIU_DEPLOY_DIST="/home/__PROJECT_NAME__/__PROJECT_NAME___dist"

# BIU_DEPLOY_CONDA_ENV：发布时使用的 conda 环境名（与 deploy.sh 走 conda 分支时 biu 注入的 CONDA_ENV 一致；deploy.sh 内不设默认值）。
# - biu deploy py 在远程执行前会 export CONDA_ENV 为本值（本机已 export CONDA_ENV 则优先）；
# - biu deploy py --rotate-jwt-keys 会由 deploy.sh 在本环境中安装 wheel 后、启动服务前执行 JWT 密钥对轮换；
# - biu conda create <仅 Python 版本> 时创建的 -n 环境名也是本值。
# -----------------------------------------------------------------------------
BIU_DEPLOY_CONDA_ENV='kmvpy'

# BIU_API_HOST / BIU_SPA_HOST：用于 `biu nginx` 生成 nginx 配置。
# - 推荐写完整来源: https://api.example.com / https://www.example.com
# - 也支持 http://...；若只写裸域名，则按 https 处理。
# - 生成文件位于执行 biu 命令时的当前目录: nginx.conf.d/<host>.conf。
# - SPA root 使用 BIU_DEPLOY 或脚本顶部 HOST/USER/DIST 推导出的远程基础目录 + /spa。
# 也可临时覆盖: BIU_API_HOST=https://api.example.com BIU_SPA_HOST=https://www.example.com biu nginx
# -----------------------------------------------------------------------------
BIU_API_HOST=""
BIU_SPA_HOST=""
# Multipart 请求还包含边界和头部，网关需比业务文件上限多预留少量空间。
BIU_API_CLIENT_MAX_BODY_SIZE="51m"

# =============================================================================
# 服务器部署配置（biu deploy / biu nginx）
# -----------------------------------------------------------------------------
# BIU_DEPLOY_DEFAULT 是内部推导值，格式为 user@host:/远程基础目录。
# 通常不要手动改它；请改脚本顶部的 BIU_DEPLOY_HOST / BIU_DEPLOY_USER / BIU_DEPLOY_DIST。
# 注意：BIU_DEPLOY_DIST 只能是远程目录，例如 /home/__PROJECT_NAME__/__PROJECT_NAME___dist；
# 只有临时环境变量 BIU_DEPLOY 才需要写完整 user@host:/path。
# 若已设置非空的 BIU_DEPLOY（export 或命令行前缀），则优先于脚本顶部 HOST/USER/DIST。
# -----------------------------------------------------------------------------
BIU_DEPLOY_HOST_DEFAULT=""
if [[ "${BIU_DEPLOY_HOST}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  IFS=. read -r _biu_ip_a _biu_ip_b _biu_ip_c _biu_ip_d <<<"${BIU_DEPLOY_HOST}"
  if (( 10#${_biu_ip_a} <= 255 && 10#${_biu_ip_b} <= 255 && 10#${_biu_ip_c} <= 255 && 10#${_biu_ip_d} <= 255 )); then
    BIU_DEPLOY_HOST_DEFAULT="${BIU_DEPLOY_HOST}"
  fi
fi
if [[ -z "${BIU_DEPLOY_HOST_DEFAULT}" ]]; then
  BIU_DEPLOY_HOST_DEFAULT="${BIU_SPA_HOST#http://}"
  BIU_DEPLOY_HOST_DEFAULT="${BIU_DEPLOY_HOST_DEFAULT#https://}"
  BIU_DEPLOY_HOST_DEFAULT="${BIU_DEPLOY_HOST_DEFAULT%%/*}"
fi
unset _biu_ip_a _biu_ip_b _biu_ip_c _biu_ip_d
BIU_DEPLOY_DEFAULT="${BIU_DEPLOY_USER}@${BIU_DEPLOY_HOST_DEFAULT}:${BIU_DEPLOY_DIST}"


#
# biu — __PROJECT_NAME__ 前端（SPA）与后端（Python）一键部署
#
# =============================================================================
# 子命令一览（与 biu -h 一致）
# =============================================================================
#   biu                         只在本地构建 py、spa，不上传、不远程部署
#   biu --rotate-jwt-keys       轮换本地 develop/config.yaml 的 user/admin JWT 密钥对
#   biu deploy                  先构建 py、spa；全部构建成功后部署 spa，再部署 py
#                               可选 --no-deps / --update-config / --rotate-jwt-keys
#   biu deploy spa              构建 SPA，再上传并替换远端 spa
#   biu deploy py               构建 Python wheel，再上传并远端安装/重启服务
#
#   biu -h | --help             显示本说明
#
#   biu conda create <Python版本>
#                               环境名固定为脚本顶部 BIU_DEPLOY_CONDA_ENV（与 deploy 一致）；远程：有 conda 则用；无则装 Miniconda3；
#                               若未在 ~/.bashrc 初始化过则 conda init bash；非交互需先 conda tos accept（默认渠道）；
#                               再 conda create -y -n <BIU_DEPLOY_CONDA_ENV> python=…；版本可写 3.11 或 python=3.11
#                               兼容旧写法：biu conda create <环境名> <Python版本>（两个参数时仍按「名 + 版本」）
#
#   biu deploy py               构建 Python wheel，上传本地 .whl 与 release/deploy.sh 到远程并执行（重新部署/装 wheel 后重启服务）
#                               可选 --no-deps / --update-config / --rotate-jwt-keys
#   biu deploy py --update-config
#                               先用本地 __PY_PROJECT_NAME__/app/etc/release/config.yaml 覆盖远程 <部署目标>/py/config.yaml
#   biu deploy py --rotate-jwt-keys
#                               deploy.sh 激活 conda 并安装 wheel 后、启动服务前轮换 JWT 密钥对
#
#   biu nginx                   调用 kmvpy nginx api/spa 读取模板，并按 BIU_API_HOST / BIU_SPA_HOST 的协议与域名
#                               生成当前目录 nginx.conf.d/<host>.conf；SPA root 使用 BIU_DEPLOY 的远程基础目录 + /spa
#
# =============================================================================
# 典型流程
# =============================================================================
#   ./biu                       只构建 py、spa
#   ./biu --rotate-jwt-keys     轮换本地 develop/config.yaml JWT 密钥对
#   ./biu deploy                构建 py、spa，随后部署 spa 与 py
#   ./biu deploy spa            仅部署前端
#   ./biu deploy py             仅部署后端
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIU_SCRIPT_PATH="${SCRIPT_DIR}/$(basename "${BASH_SOURCE[0]}")"
# 所有路径以 biu 所在目录为基准（本仓库中即仓库根）
SPA_DIR="${SCRIPT_DIR}/__SPA_PROJECT_NAME__"
PY_DIR="${SCRIPT_DIR}/__PY_PROJECT_NAME__"
SPA_DIST="${SPA_DIR}/dist/spa"
PY_DIST="${PY_DIR}/dist"
PY_DEVELOP_CONFIG="${PY_DIR}/app/etc/develop/config.yaml"
PY_RELEASE_CONFIG="${PY_DIR}/app/etc/release/config.yaml"
PY_RELEASE_DEPLOY="${PY_DIR}/app/etc/release/deploy.sh"

usage() {
  cat <<'EOF'
biu — 本地构建并部署

命令（与脚本头部注释一致）:
  biu
                        只构建 Python wheel 与 SPA，不上传、不远程部署，用于本地构建/语法检查
  biu --rotate-jwt-keys
                        轮换本地 __PY_PROJECT_NAME__/app/etc/develop/config.yaml 的 user/admin JWT 密钥对

  biu -h | --help
                        显示本说明

  biu deploy
                        构建 Python wheel 与 SPA；全部构建成功后先部署 SPA，再部署 Python 服务
  biu deploy --no-deps
                        构建并部署 SPA 与 Python；Python 远程 pip 使用 install -U --no-deps <wheel>
  biu deploy --update-config
                        构建并部署 SPA 与 Python；执行 Python 部署前覆盖远程 <部署目标>/py/config.yaml
  biu deploy --rotate-jwt-keys
                        构建并部署 SPA 与 Python；Python 服务启动前自动轮换 user/admin JWT 密钥对
  biu deploy --update-config --rotate-jwt-keys --no-deps
                        全量部署时，上述 Python 部署选项可同时使用，参数顺序不限

  biu conda create <Python版本>
                        环境名使用 biu 顶部 BIU_DEPLOY_CONDA_ENV（与 deploy.sh 所用环境统一）；远程：检测 conda（PATH 或 ~/miniconda3 等）；
                        若无则静默安装 Miniconda3 至 ~/miniconda3；仅当 ~/.bashrc 中尚无 conda 初始化块时再 conda init bash（不重复写）；
                        接受默认 channels 的 TOS（Conda 24+ 非交互所必需）后，conda create -y -n <该环境名> python=<版本>；
                        版本可写 3.11 或 python=3.11。兼容旧写法：biu conda create <环境名> <Python版本>

  biu deploy py
                        构建 Python wheel，上传 dist/*.whl 与 app/etc/release/deploy.sh 到远程后执行，重新部署 Python 服务；pip 为 install -U <wheel>（会装依赖）
  biu deploy py --no-deps
                        同上，pip 为 install -U --no-deps <wheel>（不随 wheel 装依赖）
  biu deploy py --update-config
                        同上，但执行部署前先用本地 __PY_PROJECT_NAME__/app/etc/release/config.yaml 覆盖远程 <部署目标>/py/config.yaml
  biu deploy py --rotate-jwt-keys
                        同上，但 deploy.sh 激活 conda 并安装 wheel 后、启动服务前自动轮换 user/admin JWT 密钥对
  biu deploy py --update-config --rotate-jwt-keys --no-deps
                        更新配置、JWT 密钥轮换与 --no-deps 可同时使用，参数顺序不限
  biu deploy spa
                        构建 SPA，将 __SPA_PROJECT_NAME__/dist/spa 打包上传，远端备份原 spa 后解压替换

  biu nginx
                        调用 kmvpy nginx api/spa 输出模板，并按脚本顶部 BIU_API_HOST / BIU_SPA_HOST 的协议与域名
                        生成到当前目录 nginx.conf.d/<API域名>.conf、nginx.conf.d/<SPA域名>.conf；
                        SPA root 使用 BIU_DEPLOY 的远程基础目录 + /spa

部署目标:
  脚本顶部配置        BIU_DEPLOY_HOST / BIU_DEPLOY_USER / BIU_DEPLOY_DIST
                       其中 BIU_DEPLOY_DIST 只写服务器上的远程目录，例如 /home/app/app_dist
  BIU_DEPLOY           可选环境变量覆盖，形如 user@host:/远程基础目录

远程 Python / conda:
  BIU_DEPLOY_CONDA_ENV  见 biu 顶部；biu conda create <版本> 的环境名；biu deploy / biu deploy py 会向远程 export CONDA_ENV（本机已 export CONDA_ENV 则优先）。
                       JWT 密钥对轮换由 deploy.sh 在该环境安装 wheel 后、启动服务前执行；deploy.sh 内不设默认，走 conda 时未设置会报错

依赖:
  spa 构建: Node（与 package.json engines 一致为佳）；有 bun.lock 时优先 bun，否则 pnpm / npm
  部署: ssh、scp、tar（SPA 在本地打包 tar.gz；不在远程使用 git）

示例:
  biu
  biu --rotate-jwt-keys
  biu deploy
  biu deploy --no-deps
  biu deploy --update-config
  biu deploy --rotate-jwt-keys
  biu deploy spa
  BIU_DEPLOY=deploy@server:/opt/dist biu deploy py
  biu deploy py --no-deps
  biu deploy py --update-config
  biu deploy py --rotate-jwt-keys
  BIU_API_HOST=https://api.example.com BIU_SPA_HOST=https://www.example.com biu nginx
  biu conda create 3.11
  biu conda create python=3.11
  biu conda create otherenv 3.11
EOF
  echo "脚本路径: ${BIU_SCRIPT_PATH}"
}

log() {
  printf '\033[1;36m[biu]\033[0m %s\n' "$*"
}

# 输出仓库内 release/deploy.sh 内容供上传（deploy.sh 要求 CONDA_ENV 由 biu 远程 export，不在脚本内写默认）。
# 若业务工程里的 deploy.sh 仍是旧版，上传前自动给副本补齐 ROTATE_JWT_KEYS 支持，避免 --rotate-jwt-keys 被远端静默忽略。
biu_render_release_deploy_sh() {
  local require_rotate_support="${1:-0}"
  local rendered=""
  [[ -f "${PY_RELEASE_DEPLOY}" ]] || die "未找到 release/deploy.sh: ${PY_RELEASE_DEPLOY}"
  if grep -q 'ROTATE_JWT_KEYS' "${PY_RELEASE_DEPLOY}" && grep -q 'rotate-jwt-keys' "${PY_RELEASE_DEPLOY}"; then
    cat "${PY_RELEASE_DEPLOY}"
    return 0
  fi

  if rendered="$(awk '
    BEGIN { pending = 0; inserted = 0 }
    {
      print
      if (index($0, "\"$PYTHON\" -m pip install -U --force-reinstall \"$WHEEL\"") > 0) {
        pending = 1
        next
      }
      if (pending && $0 == "fi") {
        print ""
        print "if [[ \"${ROTATE_JWT_KEYS:-}\" == \"1\" ]]; then"
        print "  echo \"==> 轮换 JWT 密钥对: $CONFIG\""
        print "  \"$PYTHON\" -m kmvpy.generator.cli rotate-jwt-keys \"$CONFIG\""
        print "fi"
        inserted = 1
        pending = 0
      }
    }
    END {
      if (!inserted) {
        exit 42
      }
    }
  ' "${PY_RELEASE_DEPLOY}")"; then
    printf '\033[1;33m[biu]\033[0m 本仓库 release/deploy.sh 缺少 ROTATE_JWT_KEYS 支持，已在上传副本中自动补齐。建议执行: kmvpy update .\n' >&2
    printf '%s\n' "${rendered}"
    return 0
  fi

  if [[ "${require_rotate_support}" == "1" ]]; then
    die "当前 release/deploy.sh 太旧，无法自动补齐 JWT 密钥轮换逻辑。请执行: kmvpy update ."
  fi
  cat "${PY_RELEASE_DEPLOY}"
}

die() {
  printf '\033[1;31m[biu]\033[0m %s\n' "$*" >&2
  exit 1
}

# 引导用户修正脚本顶部配置或环境变量（未配置 / ssh、scp 失败时调用）
hint_deploy_fix() {
  local reason="${1:-部署步骤失败}"
  printf '\n\033[1;31m[biu]\033[0m %s\n' "${reason}" >&2
  printf '\033[1;33m[biu]\033[0m 请用编辑器打开下列文件，在「最上方」检查 BIU_DEPLOY_HOST / BIU_DEPLOY_USER / BIU_DEPLOY_DIST。\n' >&2
  printf '\033[1;33m[biu]\033[0m   %s\n' "${BIU_SCRIPT_PATH}" >&2
  printf '\033[1;33m[biu]\033[0m 注意: BIU_DEPLOY_DIST 只写服务器上的目录，例如 /home/app/app_dist，不要写 user@host: 前缀。\n' >&2
  printf '\033[1;33m[biu]\033[0m 也可不改脚本，在命令前临时指定完整部署目标，例如:\n' >&2
  printf '\033[1;33m[biu]\033[0m   BIU_DEPLOY=user@host:/path biu deploy spa\n' >&2
  printf '\033[1;33m[biu]\033[0m 若地址已正确，请检查: ssh 密钥、~/.ssh/config、用户名、主机名、端口与网络。\n' >&2
}

# scp 已成功但「远程执行 ssh 命令」失败时（例如 chmod），不宜误导为部署地址填错
hint_remote_chmod_failed() {
  local remote_deploy="${1:-}"
  printf '\n\033[1;31m[biu]\033[0m ssh 无法为远程重新部署脚本（py/deploy.sh）设置可执行权限。\n' >&2
  printf '\033[1;33m[biu]\033[0m 当前目标: %s\n' "${BIU_DEPLOY}" >&2
  printf '\033[1;33m[biu]\033[0m 若 wheel / config 已能 scp 上传，多为: 该用户对 %s 无写权限、磁盘只读、或 authorized_keys 限制了「仅 sftp/scp」禁止执行远程 shell 命令。\n' "${remote_deploy}" >&2
  printf '\033[1;33m[biu]\033[0m 可在服务器上手动执行: chmod +x %s\n' "${remote_deploy}" >&2
}

# 未设置 BIU_DEPLOY 时，用脚本顶部的默认值补全
resolve_biudeploy_from_defaults() {
  if [[ -z "${BIU_DEPLOY:-}" ]]; then
    BIU_DEPLOY="${BIU_DEPLOY_DEFAULT:-}"
  fi
}

sync_spa_production_api_base_url() {
  [[ -n "${BIU_API_HOST}" ]] || return 0
  if ! parse_nginx_origin "BIU_API_HOST" "${BIU_API_HOST}"; then
    log "BIU_API_HOST 非法，保持 SPA .env.production 不变。"
    return 0
  fi

  local production_env api_base_url tmp_env
  production_env="${SPA_DIR}/.env.production"
  [[ -f "${production_env}" ]] || die "未找到 SPA 生产环境配置: ${production_env}"
  api_base_url="${PARSED_NGINX_ORIGIN}"
  tmp_env="$(mktemp)"
  awk -v value="${api_base_url}" '
    BEGIN { updated = 0 }
    /^VITE_API_BASE_URL=/ {
      print "VITE_API_BASE_URL=" value
      updated = 1
      next
    }
    { print }
    END {
      if (!updated) {
        print "VITE_API_BASE_URL=" value
      }
    }
  ' "${production_env}" >"${tmp_env}"
  mv "${tmp_env}" "${production_env}"
  log "已同步 SPA .env.production: VITE_API_BASE_URL=${api_base_url}"
}

run_spa_build() {
  [[ -d "${SPA_DIR}" ]] || die "未找到 SPA 目录: ${SPA_DIR}"
  sync_spa_production_api_base_url
  cd "${SPA_DIR}"
  if command -v bun >/dev/null 2>&1 && [[ -f bun.lock ]]; then
    log "使用 bun run build"
    bun run build
  elif command -v pnpm >/dev/null 2>&1 && [[ -f pnpm-lock.yaml ]]; then
    log "使用 pnpm run build"
    pnpm run build
  else
    log "使用 npm run build"
    npm run build
  fi
  [[ -d "${SPA_DIST}" ]] || die "构建完成但未找到输出目录: ${SPA_DIST}"
  log "SPA 构建完成: ${SPA_DIST}"
}

run_py_build() {
  [[ -d "${PY_DIR}" ]] || die "未找到 Python 工程目录: ${PY_DIR}"
  local py_dir
  py_dir="$(cd "${PY_DIR}" && pwd)"
  cd "${py_dir}"
  command -v python >/dev/null 2>&1 || die "未找到 python 命令"
  if ! python -c "import build" >/dev/null 2>&1; then
    die "需要 Python 的 build 模块。请执行: pip install build"
  fi
  log "在 ${py_dir} 执行 python -m build"
  python -m build
  log "Python 构建完成，产物位于 ${py_dir}/dist/"
}

run_local_rotate_jwt_keys() {
  [[ -f "${PY_DEVELOP_CONFIG}" ]] || die "未找到本地开发配置: ${PY_DEVELOP_CONFIG}"
  command -v python >/dev/null 2>&1 || die "未找到 python 命令"
  local config_dir config_file
  config_dir="$(cd "$(dirname "${PY_DEVELOP_CONFIG}")" && pwd)"
  config_file="$(basename "${PY_DEVELOP_CONFIG}")"
  log "轮换本地 develop config.yaml JWT 密钥对: ${PY_DEVELOP_CONFIG}"
  (
    cd "${config_dir}"
    python -m kmvpy.generator.cli rotate-jwt-keys "${config_file}"
  )
  log "本地 develop config.yaml JWT 密钥对已轮换"
}

# 解析 BIU_DEPLOY=user@host:/remote/path → DEPLOY_SSH、DEPLOY_PATH
parse_biudeploy() {
  resolve_biudeploy_from_defaults
  if [[ -z "${BIU_DEPLOY:-}" ]]; then
    hint_deploy_fix "尚未配置部署服务器：请在 biu 脚本最上方填写 BIU_DEPLOY_HOST / BIU_DEPLOY_USER / BIU_DEPLOY_DIST，或设置环境变量 BIU_DEPLOY。"
    exit 1
  fi
  if [[ "${BIU_DEPLOY}" != *:* ]]; then
    hint_deploy_fix "BIU_DEPLOY 格式无效（缺少主机与路径的分隔）: ${BIU_DEPLOY}"
    exit 1
  fi
  DEPLOY_SSH="${BIU_DEPLOY%%:*}"
  DEPLOY_PATH="${BIU_DEPLOY#*:}"
  if [[ -z "${DEPLOY_SSH}" || -z "${DEPLOY_PATH}" ]]; then
    hint_deploy_fix "BIU_DEPLOY 解析失败，请检查 user@host:/path 格式: ${BIU_DEPLOY}"
    exit 1
  fi
  if [[ "${DEPLOY_SSH}" == *@ ]]; then
    hint_deploy_fix "部署主机为空：请填写 BIU_DEPLOY_HOST，或设置 BIU_SPA_HOST 让脚本推算主机。"
    exit 1
  fi
}

parse_nginx_origin() {
  local label="${1}"
  local raw="${2}"
  local lower scheme rest host

  PARSED_NGINX_SCHEME=""
  PARSED_NGINX_HOST=""
  PARSED_NGINX_ORIGIN=""

  if [[ -z "${raw}" ]]; then
    log "${label} 为空，跳过对应 nginx 配置。"
    return 1
  fi
  if [[ "${raw}" == *[[:space:]]* ]]; then
    log "${label} 不能包含空白字符，已跳过: ${raw}"
    return 1
  fi

  lower="$(printf '%s' "${raw}" | tr '[:upper:]' '[:lower:]')"
  case "${lower}" in
    http://*)
      scheme="http"
      rest="${raw:7}"
      ;;
    https://*)
      scheme="https"
      rest="${raw:8}"
      ;;
    *://*)
      log "${label} 仅支持 http 或 https，已跳过: ${raw}"
      return 1
      ;;
    *)
      scheme="https"
      rest="${raw}"
      ;;
  esac

  if [[ -z "${rest}" || "${rest}" == */* || "${rest}" == *\?* || "${rest}" == *#* || "${rest}" == *:* ]]; then
    log "${label} 只支持域名，不支持路径、查询参数、片段或端口，已跳过: ${raw}"
    return 1
  fi
  if [[ "${rest}" == .* || "${rest}" == *. || "${rest}" == *..* ]]; then
    log "${label} 域名格式无效，已跳过: ${raw}"
    return 1
  fi
  if ! [[ "${rest}" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]; then
    log "${label} 域名格式无效，已跳过: ${raw}"
    return 1
  fi

  host="$(printf '%s' "${rest}" | tr '[:upper:]' '[:lower:]')"
  PARSED_NGINX_SCHEME="${scheme}"
  PARSED_NGINX_HOST="${host}"
  PARSED_NGINX_ORIGIN="${scheme}://${host}"
}

render_kmvpy_nginx_template() {
  local kind="${1}"
  local output=""
  if command -v kmvpy >/dev/null 2>&1 && output="$(kmvpy nginx "${kind}" 2>/dev/null)"; then
    printf '%s\n' "${output}"
    return 0
  fi
  if command -v python >/dev/null 2>&1 && output="$(python -m kmvpy.generator.cli nginx "${kind}" 2>/dev/null)"; then
    printf '%s\n' "${output}"
    return 0
  fi
  die "无法读取 nginx 模板。请确认当前环境的 kmvpy 支持: kmvpy nginx ${kind}"
}

write_api_nginx_conf() {
  local output_file="${1}"
  local api_scheme="${2}"
  local api_host="${3}"
  local spa_origin="${4}"
  local content listen ssl_directives redirect_server cors_origin_line

  content="$(render_kmvpy_nginx_template api)" || die "执行 kmvpy nginx api 失败"
  listen="80"
  ssl_directives=""
  redirect_server=""
  if [[ "${api_scheme}" == "https" ]]; then
    listen="443 ssl"
    ssl_directives=$'\n'"    ssl_certificate /etc/letsencrypt/live/${api_host}/fullchain.pem;"$'\n'"    ssl_certificate_key /etc/letsencrypt/live/${api_host}/privkey.pem;"$'\n'"    include /etc/letsencrypt/options-ssl-nginx.conf;"$'\n'"    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;"$'\n'
    redirect_server=$'\n''server {'$'\n''    listen 80;'$'\n'"    server_name ${api_host};"$'\n''    return 301 https://$host$request_uri;'$'\n''}'
  fi
  cors_origin_line="    \"${spa_origin}\" \$http_origin;"

  content="${content//__API_LISTEN__/${listen}}"
  content="${content//__API_HOST__/${api_host}}"
  content="${content//__API_SSL_DIRECTIVES__/${ssl_directives}}"
  content="${content//__API_HTTP_REDIRECT_SERVER__/${redirect_server}}"
  content="${content//__CORS_SPA_ORIGIN_LINE__/${cors_origin_line}}"
  if [[ "${content}" != *"client_max_body_size"* ]]; then
    content="$(printf '%s\n' "${content}" | awk -v body_size="${BIU_API_CLIENT_MAX_BODY_SIZE}" '
      BEGIN { inserted = 0 }
      {
        print
        if (!inserted && $0 ~ /^[[:space:]]*server_name[[:space:]]+/) {
          print ""
          print "    client_max_body_size " body_size ";"
          inserted = 1
        }
      }
    ')"
  fi
  printf '%s\n' "${content}" >"${output_file}"
}

write_spa_nginx_conf() {
  local output_file="${1}"
  local spa_scheme="${2}"
  local spa_host="${3}"
  local spa_root="${4}"
  local content listen ssl_directives redirect_server

  content="$(render_kmvpy_nginx_template spa)" || die "执行 kmvpy nginx spa 失败"
  listen="80"
  ssl_directives=""
  redirect_server=""
  if [[ "${spa_scheme}" == "https" ]]; then
    listen="443 ssl"
    ssl_directives=$'\n'"    ssl_certificate /etc/letsencrypt/live/${spa_host}/fullchain.pem;"$'\n'"    ssl_certificate_key /etc/letsencrypt/live/${spa_host}/privkey.pem;"$'\n'"    include /etc/letsencrypt/options-ssl-nginx.conf;"$'\n'"    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;"$'\n'
    redirect_server=$'\n''server {'$'\n''    listen 80;'$'\n'"    server_name ${spa_host};"$'\n''    return 301 https://$host$request_uri;'$'\n''}'
  fi

  content="${content//__SPA_LISTEN__/${listen}}"
  content="${content//__SPA_HOST__/${spa_host}}"
  content="${content//__SPA_ROOT__/${spa_root}}"
  content="${content//__SPA_SSL_DIRECTIVES__/${ssl_directives}}"
  content="${content//__SPA_HTTP_REDIRECT_SERVER__/${redirect_server}}"
  printf '%s\n' "${content}" >"${output_file}"
}

run_nginx_render() {
  local api_valid=0 spa_valid=0 generated=0
  local api_scheme="" api_host="" spa_scheme="" spa_host="" spa_origin=""
  local output_dir spa_root api_conf spa_conf

  if parse_nginx_origin "BIU_API_HOST" "${BIU_API_HOST}"; then
    api_valid=1
    api_scheme="${PARSED_NGINX_SCHEME}"
    api_host="${PARSED_NGINX_HOST}"
  fi
  if parse_nginx_origin "BIU_SPA_HOST" "${BIU_SPA_HOST}"; then
    spa_valid=1
    spa_scheme="${PARSED_NGINX_SCHEME}"
    spa_host="${PARSED_NGINX_HOST}"
    spa_origin="${PARSED_NGINX_ORIGIN}"
  fi

  output_dir="${PWD}/nginx.conf.d"
  mkdir -p "${output_dir}"

  if (( spa_valid )); then
    parse_biudeploy
    spa_root="${DEPLOY_PATH}/spa"
    spa_conf="${output_dir}/${spa_host}.conf"
    write_spa_nginx_conf "${spa_conf}" "${spa_scheme}" "${spa_host}" "${spa_root}"
    generated=1
    log "已生成 SPA nginx 配置: ${spa_conf}"
  fi

  if (( api_valid )); then
    if (( spa_valid )); then
      api_conf="${output_dir}/${api_host}.conf"
      write_api_nginx_conf "${api_conf}" "${api_scheme}" "${api_host}" "${spa_origin}"
      generated=1
      log "已生成 API nginx 配置: ${api_conf}"
    else
      log "BIU_SPA_HOST 不合法，无法生成 API 配置所需的 CORS 来源，已跳过 API nginx 配置。"
    fi
  fi

  (( generated )) || die "没有生成任何 nginx 配置。请检查 BIU_API_HOST / BIU_SPA_HOST。"
  log "建议检查配置: nginx -t；确认无误后 reload nginx。"
}

SSH_PUSH_OPTS=(-o ConnectTimeout=20)
PY_WHEEL_ARTIFACTS=()

run_spa_scp() {
  command -v scp >/dev/null 2>&1 || die "未找到 scp 命令"
  command -v ssh >/dev/null 2>&1 || die "未找到 ssh 命令"
  command -v tar >/dev/null 2>&1 || die "未找到 tar 命令"
  parse_biudeploy
  [[ -d "${SPA_DIST}" ]] || die "未找到 ${SPA_DIST}，请检查 SPA 构建是否成功。"

  local ts remote_tar local_tar spa_path backup_dir
  ts="$(date '+%Y%m%d_%H%M%S')"
  spa_path="${DEPLOY_PATH}/spa"
  backup_dir="${DEPLOY_PATH}/backup"
  remote_tar="${DEPLOY_PATH}/spa.${ts}.tar.gz"
  local_tar="${TMPDIR:-/tmp}/biu_spa.${ts}.$$"
  trap 'rm -f "${local_tar}"' EXIT

  log "本地打包 SPA: ${SPA_DIST} → ${local_tar}"
  (
    cd "${SPA_DIST}"
    tar czf "${local_tar}" .
  )
  [[ -f "${local_tar}" ]] || die "打包失败: ${local_tar}"

  log "在远程创建目录并上传压缩包 → ${DEPLOY_SSH}:${remote_tar}"
  if ! ssh "${SSH_PUSH_OPTS[@]}" "${DEPLOY_SSH}" "mkdir -p '${DEPLOY_PATH}' '${backup_dir}'"; then
    hint_deploy_fix "ssh 无法登录或无法在远程创建目录（mkdir）。当前目标: ${BIU_DEPLOY}"
    exit 1
  fi
  if ! scp "${SSH_PUSH_OPTS[@]}" "${local_tar}" "${DEPLOY_SSH}:${remote_tar}"; then
    hint_deploy_fix "scp 上传 SPA 压缩包失败。当前目标: ${BIU_DEPLOY}"
    exit 1
  fi

  log "远端备份原 spa（若存在）并解压替换 → ${spa_path}"
  # shellcheck disable=SC2029
  if ! ssh "${SSH_PUSH_OPTS[@]}" "${DEPLOY_SSH}" "set -euo pipefail
    if [[ -d '${spa_path}' ]]; then
      cp -R '${spa_path}' '${backup_dir}/spa.${ts}.bak'
    fi
    rm -rf '${spa_path}'
    mkdir -p '${spa_path}'
    tar xzf '${remote_tar}' -C '${spa_path}'
    rm -f '${remote_tar}'
    chmod -R u=rwX,go=rX '${spa_path}'"; then
    hint_deploy_fix "ssh 远端解压或替换 SPA 失败。当前目标: ${BIU_DEPLOY}"
    exit 1
  fi
  trap - EXIT
  rm -f "${local_tar}"
  log "SPA 已上传并完成远端解压替换（备份目录: ${backup_dir}）"
}

collect_py_wheel_artifacts() {
  [[ -d "${PY_DIST}" ]] || die "未找到 ${PY_DIST}，请检查 Python wheel 构建是否成功。"
  local f
  PY_WHEEL_ARTIFACTS=()
  shopt -s nullglob
  for f in "${PY_DIST}"/*.whl; do
    PY_WHEEL_ARTIFACTS+=("$f")
  done
  shopt -u nullglob
  ((${#PY_WHEEL_ARTIFACTS[@]})) || die "在 ${PY_DIST} 未找到 .whl，请检查 Python wheel 构建是否成功（sdist .tar.gz 不参与上传）"
}

sync_py_wheels_to_remote() {
  local py_dir="${1}"
  local backup_dir="${2}"
  local f ts remote_backup_script
  collect_py_wheel_artifacts
  ts="$(date '+%Y%m%d_%H%M%S')"
  remote_backup_script=""
  for f in "${PY_WHEEL_ARTIFACTS[@]}"; do
    remote_backup_script+="if [[ -f '${py_dir}/$(basename "$f")' ]]; then cp '${py_dir}/$(basename "$f")' '${backup_dir}/$(basename "$f").${ts}.bak'; fi"$'\n'
  done

  log "在远程创建目录并备份已有 whl（若存在）→ ${DEPLOY_SSH}:${py_dir}/"
  if ! ssh "${SSH_PUSH_OPTS[@]}" "${DEPLOY_SSH}" "mkdir -p '${py_dir}' '${backup_dir}'"; then
    hint_deploy_fix "ssh 无法登录或无法在远程创建目录（mkdir）。当前目标: ${BIU_DEPLOY}"
    exit 1
  fi
  # shellcheck disable=SC2029
  if ! ssh "${SSH_PUSH_OPTS[@]}" "${DEPLOY_SSH}" "set -euo pipefail
${remote_backup_script}"; then
    hint_deploy_fix "ssh 远端备份已有 whl 失败。当前目标: ${BIU_DEPLOY}"
    exit 1
  fi

  log "上传 Python wheel → ${DEPLOY_SSH}:${py_dir}/"
  if ! scp "${SSH_PUSH_OPTS[@]}" "${PY_WHEEL_ARTIFACTS[@]}" "${DEPLOY_SSH}:${py_dir}/"; then
    hint_deploy_fix "scp 上传 Python 产物失败。当前目标: ${BIU_DEPLOY}"
    exit 1
  fi
}

run_py_scp() {
  command -v scp >/dev/null 2>&1 || die "未找到 scp 命令"
  command -v ssh >/dev/null 2>&1 || die "未找到 ssh 命令"
  parse_biudeploy
  local py_dir backup_dir
  py_dir="${DEPLOY_PATH}/py"
  backup_dir="${py_dir}/backup"
  sync_py_wheels_to_remote "${py_dir}" "${backup_dir}"
  [[ -f "${PY_RELEASE_CONFIG}" ]] || die "未找到 release 配置: ${PY_RELEASE_CONFIG}"
  [[ -f "${PY_RELEASE_DEPLOY}" ]] || die "未找到 release 部署脚本: ${PY_RELEASE_DEPLOY}"
  chmod +x "${PY_RELEASE_DEPLOY}" 2>/dev/null || true
  local _deploy_tmp
  _deploy_tmp="$(mktemp)"
  biu_render_release_deploy_sh 0 >"${_deploy_tmp}"
  chmod +x "${_deploy_tmp}"
  if ! scp "${SSH_PUSH_OPTS[@]}" "${PY_RELEASE_CONFIG}" "${DEPLOY_SSH}:${py_dir}/"; then
    rm -f "${_deploy_tmp}"
    hint_deploy_fix "scp 上传 config.yaml 失败。当前目标: ${BIU_DEPLOY}"
    exit 1
  fi
  if ! scp "${SSH_PUSH_OPTS[@]}" "${_deploy_tmp}" "${DEPLOY_SSH}:${py_dir}/deploy.sh"; then
    rm -f "${_deploy_tmp}"
    hint_deploy_fix "scp 上传 deploy.sh 失败。当前目标: ${BIU_DEPLOY}"
    exit 1
  fi
  rm -f "${_deploy_tmp}"
  if ! ssh "${SSH_PUSH_OPTS[@]}" "${DEPLOY_SSH}" "chmod +x '${py_dir}/deploy.sh'"; then
    hint_remote_chmod_failed "${py_dir}/deploy.sh"
    exit 1
  fi
  log "Python .whl、config.yaml、deploy.sh 已通过 scp 上传完成（deploy.sh 已 chmod +x；已有 whl 已备份至 ${backup_dir}）"
}

run_py_deploy() {
  command -v scp >/dev/null 2>&1 || die "未找到 scp 命令"
  command -v ssh >/dev/null 2>&1 || die "未找到 ssh 命令"
  parse_biudeploy
  local no_deps_flag="${1:-0}"
  local rotate_jwt_keys_flag="${2:-0}"
  local update_config_flag="${3:-0}"
  local py_dir remote_deploy_sh lc_cmd lc_quoted rotate_jwt_env rotate_jwt_log
  py_dir="${DEPLOY_PATH}/py"
  remote_deploy_sh="${py_dir}/deploy.sh"
  local backup_dir
  backup_dir="${py_dir}/backup"
  [[ -f "${PY_RELEASE_DEPLOY}" ]] || die "未找到 release/deploy.sh: ${PY_RELEASE_DEPLOY}"
  chmod +x "${PY_RELEASE_DEPLOY}" 2>/dev/null || true

  # deploy py 是完整部署：先上传 wheel，再同步脚本，最后执行远程安装/重启。
  sync_py_wheels_to_remote "${py_dir}" "${backup_dir}"

  # 每次 deploy 都同步本仓库脚本，避免远端仍是旧逻辑
  log "同步本仓库 deploy.sh 至远程 → ${DEPLOY_SSH}:${remote_deploy_sh}"
  if ! ssh "${SSH_PUSH_OPTS[@]}" "${DEPLOY_SSH}" "mkdir -p '${py_dir}'"; then
    hint_deploy_fix "ssh 无法在远程创建 ${py_dir}。当前目标: ${BIU_DEPLOY}"
    exit 1
  fi
  local _deploy_tmp
  _deploy_tmp="$(mktemp)"
  biu_render_release_deploy_sh "${rotate_jwt_keys_flag}" >"${_deploy_tmp}"
  chmod +x "${_deploy_tmp}"
  if ! scp "${SSH_PUSH_OPTS[@]}" "${_deploy_tmp}" "${DEPLOY_SSH}:${remote_deploy_sh}"; then
    rm -f "${_deploy_tmp}"
    hint_deploy_fix "scp 上传 deploy.sh 失败。当前目标: ${BIU_DEPLOY}"
    exit 1
  fi
  rm -f "${_deploy_tmp}"
  if ! ssh "${SSH_PUSH_OPTS[@]}" "${DEPLOY_SSH}" "chmod +x '${py_dir}/deploy.sh'"; then
    hint_remote_chmod_failed "${py_dir}/deploy.sh"
    exit 1
  fi
  if [[ "${update_config_flag}" == "1" ]]; then
    [[ -f "${PY_RELEASE_CONFIG}" ]] || die "未找到 release 配置: ${PY_RELEASE_CONFIG}"
    log "更新远程 config.yaml → ${DEPLOY_SSH}:${py_dir}/config.yaml"
    if ! scp "${SSH_PUSH_OPTS[@]}" "${PY_RELEASE_CONFIG}" "${DEPLOY_SSH}:${py_dir}/config.yaml"; then
      hint_deploy_fix "scp 上传 config.yaml 失败。当前目标: ${BIU_DEPLOY}"
      exit 1
    fi
  fi

  local conda_env_for_remote
  conda_env_for_remote="${CONDA_ENV:-${BIU_DEPLOY_CONDA_ENV}}"
  rotate_jwt_env=""
  rotate_jwt_log=""
  if [[ "${rotate_jwt_keys_flag}" == "1" ]]; then
    rotate_jwt_env="export ROTATE_JWT_KEYS=1; "
    rotate_jwt_log="，ROTATE_JWT_KEYS=1，安装 wheel 后、启动服务前轮换 JWT 密钥对"
  fi

  # 非交互 ssh 不读 .bashrc，conda 常未进 PATH；用 login shell 尽量与「手动 ssh 登录后」一致
  if [[ "${no_deps_flag}" == "1" ]]; then
    lc_cmd="export CONDA_ENV=$(printf '%q' "${conda_env_for_remote}"); ${rotate_jwt_env}export RESTART_PIP_NO_DEPS=1; $(printf 'exec %q' "$remote_deploy_sh")"
    log "在远程执行重新部署: ${DEPLOY_SSH}:${remote_deploy_sh}（CONDA_ENV=${conda_env_for_remote}，RESTART_PIP_NO_DEPS=1，pip --no-deps${rotate_jwt_log}）"
  else
    lc_cmd="export CONDA_ENV=$(printf '%q' "${conda_env_for_remote}"); ${rotate_jwt_env}$(printf 'exec %q' "$remote_deploy_sh")"
    log "在远程执行重新部署: ${DEPLOY_SSH}:${remote_deploy_sh}（CONDA_ENV=${conda_env_for_remote}，bash -lc，pip 将随 wheel 安装声明的依赖${rotate_jwt_log}）"
  fi
  lc_quoted="$(printf '%q' "$lc_cmd")"
  if ! ssh "${SSH_PUSH_OPTS[@]}" "${DEPLOY_SSH}" "bash -lc ${lc_quoted}"; then
    printf '\n\033[1;31m[biu]\033[0m ssh 远程重新部署（py/deploy.sh）失败。当前目标: %s\n' "${BIU_DEPLOY}" >&2
    printf '\033[1;33m[biu]\033[0m 此前 scp 上传与 ssh 连接均已成功，通常是远端脚本/环境问题，而不是部署地址问题。\n' >&2
    printf '\033[1;33m[biu]\033[0m 若错误包含 EnvironmentNameNotFound，说明远端缺少 conda 环境 %s，请先创建: biu conda create 3.11（或手动: conda create -n %s python=3.11），再重新执行部署。\n' "${conda_env_for_remote}" "${conda_env_for_remote}" >&2
    printf '\033[1;33m[biu]\033[0m 或改用已存在的环境: CONDA_ENV=<真实环境名> biu deploy py\n' >&2
    exit 1
  fi
  log "远程重新部署已结束"
}

# 远程：确保存在 conda（否则安装 Miniconda3），再创建指定环境
run_remote_conda_create() {
  command -v ssh >/dev/null 2>&1 || die "未找到 ssh 命令"
  parse_biudeploy
  local env_name="${1:-}"
  local py_ver_raw="${2:-}"
  # 支持 "3.11" 或 "python=3.11"；否则远端会变成 python=python=3.11
  local py_ver="${py_ver_raw#python=}"
  while [[ "${py_ver}" == python=* ]]; do
    py_ver="${py_ver#python=}"
  done
  [[ -n "${env_name}" && -n "${py_ver}" ]] ||
    die "用法: biu conda create <Python版本>  示例: biu conda create 3.11  或: biu conda create python=3.11（环境名为 BIU_DEPLOY_CONDA_ENV）；兼容: biu conda create <环境名> <Python版本>"

  local q_env q_py
  q_env="$(printf '%q' "${env_name}")"
  q_py="$(printf '%q' "${py_ver}")"

  log "在远程 ${DEPLOY_SSH} 上准备 conda 环境: -n ${env_name} python=${py_ver}"
  if ! ssh "${SSH_PUSH_OPTS[@]}" "${DEPLOY_SSH}" bash -s "${q_env}" "${q_py}" <<'REMOTE'
set -euo pipefail
ENV_NAME="$1"
PY_VER="${2#python=}"
while [[ "${PY_VER}" == python=* ]]; do
  PY_VER="${PY_VER#python=}"
done

log_r() { printf '[biu-remote] %s\n' "$*"; }

# 若 ~/.bashrc 中已有 conda init 块则不再执行 conda init bash
need_conda_init_bash() {
  local f="${HOME}/.bashrc"
  [[ -f "${f}" ]] && grep -qF '>>> conda initialize >>>' "${f}" 2>/dev/null && return 1
  return 0
}

ensure_conda_init_bash() {
  if ! need_conda_init_bash; then
    log_r "已检测到 ~/.bashrc 中 conda 初始化，跳过 conda init bash"
    return
  fi
  log_r "在 ~/.bashrc 中未检测到 conda 初始化，正在 conda init bash …"
  "${CONDA_BASE}/bin/conda" init bash
}

# Conda 24+ 在 CI/非交互 下对默认 pkgs 渠道需先接受 TOS，否则 create 会报 CondaToSNonInteractiveError
accept_conda_default_channel_tos() {
  local c="${CONDA_BASE}/bin/conda"
  if ! "${c}" tos --help &>/dev/null; then
    return 0
  fi
  # 有 tos 子命令时再试 accept
  if ! "${c}" tos accept --help &>/dev/null; then
    return 0
  fi
  log_r "接受 Anaconda 默认渠道服务条款（非交互/自动化所必需）…"
  "${c}" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main
  "${c}" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r
}

CONDA_BASE=""
if command -v conda >/dev/null 2>&1; then
  CONDA_BASE="$(conda info --base 2>/dev/null || true)"
fi
if [[ -z "${CONDA_BASE}" || ! -d "${CONDA_BASE}" ]]; then
  for cand in "${HOME}/miniconda3" "${HOME}/Miniconda3" "${HOME}/anaconda3" "${HOME}/Anaconda3"; do
    if [[ -x "${cand}/bin/conda" ]]; then
      CONDA_BASE="${cand}"
      break
    fi
  done
fi

if [[ -z "${CONDA_BASE}" || ! -x "${CONDA_BASE}/bin/conda" ]]; then
  log_r "未检测到可用的 conda，正在安装最新 Miniconda3 到 ${HOME}/miniconda3 …"
  ARCH="$(uname -m)"
  case "${ARCH}" in
    x86_64) MC_SUFFIX="Linux-x86_64" ;;
    aarch64|arm64) MC_SUFFIX="Linux-aarch64" ;;
    *)
      printf '[biu-remote] 不支持的机器架构: %s（需要 x86_64 或 aarch64）\n' "${ARCH}" >&2
      exit 1
      ;;
  esac
  URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-${MC_SUFFIX}.sh"
  TMP="$(mktemp "${TMPDIR:-/tmp}/miniconda3.XXXXXX.sh")"
  trap 'rm -f "${TMP}"' EXIT
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "${URL}" -o "${TMP}"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "${TMP}" "${URL}"
  else
    printf '[biu-remote] 需要 curl 或 wget 以下载 Miniconda 安装包\n' >&2
    exit 1
  fi
  bash "${TMP}" -b -p "${HOME}/miniconda3"
  trap - EXIT
  rm -f "${TMP}"
  CONDA_BASE="${HOME}/miniconda3"
  log_r "Miniconda 安装完成: ${CONDA_BASE}"
  ensure_conda_init_bash
else
  log_r "已检测到 conda，使用: ${CONDA_BASE}"
  ensure_conda_init_bash
fi

if [[ -f "${CONDA_BASE}/etc/profile.d/conda.sh" ]]; then
  # shellcheck source=/dev/null
  source "${CONDA_BASE}/etc/profile.d/conda.sh"
else
  eval "$("${CONDA_BASE}/bin/conda" shell.bash hook)"
fi

accept_conda_default_channel_tos

exec "${CONDA_BASE}/bin/conda" create -y -n "${ENV_NAME}" "python=${PY_VER}"
REMOTE
  then
    hint_deploy_fix "ssh 远程 conda create 失败。当前目标: ${BIU_DEPLOY}"
    exit 1
  fi
  log "远程 conda 环境已创建: ${env_name}（python=${py_ver}）"
}

parse_py_deploy_flags() {
  PARSED_PY_DEPLOY_NO_DEPS=0
  PARSED_PY_DEPLOY_ROTATE_JWT_KEYS=0
  PARSED_PY_DEPLOY_UPDATE_CONFIG=0
  local arg
  for arg in "$@"; do
    case "${arg}" in
      --no-deps)
        PARSED_PY_DEPLOY_NO_DEPS=1
        ;;
      --update-config)
        PARSED_PY_DEPLOY_UPDATE_CONFIG=1
        ;;
      --rotate-jwt-keys)
        PARSED_PY_DEPLOY_ROTATE_JWT_KEYS=1
        ;;
      *)
        usage
        die "未知参数: deploy py 仅支持 --no-deps / --update-config / --rotate-jwt-keys，收到: ${arg}"
        ;;
    esac
  done
}

parse_spa_deploy_flags() {
  local arg
  for arg in "$@"; do
    usage
    die "未知参数: deploy spa 不支持额外参数，收到: ${arg}"
  done
}

parse_all_deploy_flags() {
  PARSED_ALL_DEPLOY_NO_DEPS=0
  PARSED_ALL_DEPLOY_ROTATE_JWT_KEYS=0
  PARSED_ALL_DEPLOY_UPDATE_CONFIG=0
  local arg
  for arg in "$@"; do
    case "${arg}" in
      --no-deps)
        PARSED_ALL_DEPLOY_NO_DEPS=1
        ;;
      --update-config)
        PARSED_ALL_DEPLOY_UPDATE_CONFIG=1
        ;;
      --rotate-jwt-keys)
        PARSED_ALL_DEPLOY_ROTATE_JWT_KEYS=1
        ;;
      *)
        usage
        die "未知参数: deploy 全量发布仅支持 --no-deps / --update-config / --rotate-jwt-keys；单独发布请用 deploy py 或 deploy spa，收到: ${arg}"
        ;;
    esac
  done
}

run_deploy_py() {
  local no_deps_flag="${1:-0}"
  local rotate_jwt_keys_flag="${2:-0}"
  local update_config_flag="${3:-0}"
  run_py_build
  run_py_deploy "${no_deps_flag}" "${rotate_jwt_keys_flag}" "${update_config_flag}"
}

run_deploy_spa() {
  run_spa_build
  run_spa_scp
}

run_build_all() {
  run_py_build
  run_spa_build
  log "本地构建完成，跳过上传与远程部署。"
}

run_deploy_all() {
  local no_deps_flag="${1:-0}"
  local rotate_jwt_keys_flag="${2:-0}"
  local update_config_flag="${3:-0}"
  run_py_build
  run_spa_build
  run_spa_scp
  run_py_deploy "${no_deps_flag}" "${rotate_jwt_keys_flag}" "${update_config_flag}"
}

main() {
  local target="${1:-}"
  local action="${2:-}"

  if [[ "${target}" == "-h" || "${target}" == "--help" ]]; then
    usage
    exit 0
  fi

  if [[ -z "${target}" ]]; then
    run_build_all
    exit 0
  fi

  if [[ "${target}" == "--rotate-jwt-keys" ]]; then
    if [[ -n "${action}" ]]; then
      usage
      die "未知参数: --rotate-jwt-keys ${action}"
    fi
    run_local_rotate_jwt_keys
    exit 0
  fi

  if [[ "${target}" == "conda" && "${action}" == "create" ]]; then
    local arg_a="${3:-}"
    local arg_b="${4:-}"
    if [[ -n "${5:-}" ]]; then
      usage
      die "未知参数: conda create 仅需 Python 版本（或兼容：环境名 + 版本），多余参数: ${5}"
    fi
    if [[ -z "${arg_a}" ]]; then
      usage
      die "用法: biu conda create <Python版本>  示例: biu conda create 3.11（环境名: ${BIU_DEPLOY_CONDA_ENV}）；兼容: biu conda create <环境名> <Python版本>"
    fi
    if [[ -z "${arg_b}" ]]; then
      run_remote_conda_create "${BIU_DEPLOY_CONDA_ENV}" "${arg_a}"
    else
      run_remote_conda_create "${arg_a}" "${arg_b}"
    fi
    exit 0
  fi

  if [[ "${target}" == "deploy" ]]; then
    if [[ "${action}" == "spa" ]]; then
      parse_spa_deploy_flags "${@:3}"
      run_deploy_spa
      exit 0
    fi
    if [[ "${action}" == "py" ]]; then
      parse_py_deploy_flags "${@:3}"
      run_deploy_py "${PARSED_PY_DEPLOY_NO_DEPS}" "${PARSED_PY_DEPLOY_ROTATE_JWT_KEYS}" "${PARSED_PY_DEPLOY_UPDATE_CONFIG}"
      exit 0
    fi
    parse_all_deploy_flags "${@:2}"
    run_deploy_all "${PARSED_ALL_DEPLOY_NO_DEPS}" "${PARSED_ALL_DEPLOY_ROTATE_JWT_KEYS}" "${PARSED_ALL_DEPLOY_UPDATE_CONFIG}"
    exit 0
  fi

  if [[ "${target}" == "restart" ]]; then
    usage
    die "restart 已移除。请使用: biu deploy py"
  fi

  if [[ "${target}" == "py" || "${target}" == "spa" || "${target}" == "push" ]]; then
    usage
    die "已移除中间命令。请使用: biu deploy、biu deploy py、biu deploy spa，或直接 biu 做本地构建检查。"
  fi

  if [[ "${action}" == "push" || "${action}" == "deploy" || "${action}" == "restart" ]]; then
    usage
    die "已移除旧写法。请使用: biu deploy、biu deploy py、biu deploy spa，或直接 biu 做本地构建检查。"
  fi

  if [[ "${target}" == "build" ]]; then
    usage
    die "已移除单独构建命令。请使用: biu deploy py、biu deploy spa，或直接 biu 做本地构建检查。"
  fi

  if [[ "${target}" == "nginx" ]]; then
    if [[ -n "${action}" ]]; then
      usage
      die "未知参数: nginx ${action}（用法: biu nginx）"
    fi
    run_nginx_render
    exit 0
  fi

  if [[ "${target}" == "conda" ]]; then
    usage
    die "请指定子命令: biu conda create <Python版本>（环境名见 BIU_DEPLOY_CONDA_ENV）"
  fi

  usage
  die "未知参数: ${target} ${action}"
}

main "$@"
