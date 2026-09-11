#!/usr/bin/env bash
#
# ---------- conda 环境名 CONDA_ENV ----------
# 走 conda 激活分支时必填，不设默认值；由 biu deploy / biu 远程执行时 export，或手动 export 后再运行。
# 若已设置 PYTHON，则不会读取 CONDA_ENV。
#
# __PROJECT_NAME__ 发布目录一键重启脚本
#
# 同目录约定文件
# ----------------
# - config.yaml              服务配置（含 logging.path、service.host/port 等）
# - __PROJECT_NAME__-*.whl         至少一个 wheel；若存在多个，取修改时间最新的
# - __PROJECT_NAME__.pid           运行中写入的 PID，用于下次优雅停止（脚本自动生成）
# - nohup.out                本脚本将进程标准输出/错误追加到此文件（与 config 中业务日志路径无关）
#
# 行为概述
# --------
# 1. 启动后先判断是否可用 conda：有则 eval hook 并 conda activate CONDA_ENV（使用 conda 时须已设置 CONDA_ENV，由 biu 或手动 export），
#    再使用该环境中的 python / pip；无 conda 则用系统默认 python / pip。若已设置 PYTHON 则
#    只认该解释器。若最终仍无可用「python -m pip」，则报错退出。
# 2. 始终使用 pip install -U --no-deps --force-reinstall <wheel> 安装当前应用，不随 wheel 安装依赖
# 3. 安装应用后，默认执行 pip install -U --force-reinstall kmvpy，强制安装最新的 kmvpy 框架版本
#    （如需跳过可设置 KMVPY_SKIP_UPGRADE=1）
# 4. 安装成功后，若 ROTATE_JWT_KEYS=1，则在当前 Python/conda 环境中轮换 config.yaml 的 JWT 密钥对
# 5. 若存在 __PROJECT_NAME__.pid 且进程仍存活，则 SIGTERM 停止，必要时 SIGKILL
# 6. 以已安装包内的 __PROJECT_NAME__.core.app.run 为入口启动（等价于安装树中的
#    __PROJECT_NAME__/core/app/run.py），并把同目录 config.yaml 的绝对路径作为唯一参数传入，
#    同时设置 __CONFIG_ENV_VAR__ / __PROJECT_NAME___CONFIG_PATH，并把本脚本路径写入
#    __PROJECT_NAME_UPPER___DEPLOY_SH，保证进程内管理端重启功能能显式定位本脚本。
#
# 用法
# ----
#   chmod +x deploy.sh && ./deploy.sh
#
# 可选环境变量
# ------------
#   PYTHON              解释器；一旦设置则优先使用（不再走 conda / 系统探测）
#   CONDA_ENV           conda 环境名；不设默认值，走 conda 分支时若为空则报错；biu deploy 会注入，亦可手动 export
#   WHEEL               指定 wheel 路径；未设置则在脚本目录下自动挑选最新的 __PROJECT_NAME__-*.whl
#   ROTATE_JWT_KEYS     设为 1: 安装 wheel 后、启动服务前执行 kmvpy rotate-jwt-keys config.yaml
#   KMVPY_SKIP_UPGRADE  设为 1: 跳过默认的 kmvpy 强制升级；否则每次部署都会执行
#                        pip install -U --force-reinstall kmvpy 以安装最新版
#   __PROJECT_NAME_UPPER___DEPLOY_SH
#                       当前 deploy.sh 的绝对路径；由脚本启动服务前自动 export，通常无需手动设置
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CONFIG="${SCRIPT_DIR}/config.yaml"
PIDFILE="${SCRIPT_DIR}/__PROJECT_NAME__.pid"

die() {
  echo "error: $*" >&2
  exit 1
}

python_has_pip() {
  local py="$1"
  command -v "$py" >/dev/null 2>&1 || return 1
  "$py" -m pip --version >/dev/null 2>&1
}

# 未设置 PYTHON：先检查 PATH 中是否有 conda → conda activate；否则在系统上探测「python -m pip」
resolve_python() {
  local c
  if [[ -n "${PYTHON:-}" ]]; then
    if python_has_pip "$PYTHON"; then
      PYTHON="$(command -v "$PYTHON")"
      return 0
    fi
    die "环境变量 PYTHON=$PYTHON 不可用或不带 pip（需要 python -m pip）。请 unset PYTHON 以自动探测，或改为带 pip 的解释器路径。"
  fi

  # 非交互 / ssh「bash -lc」等环境往往未读 ~/.bashrc，PATH 里还没有 conda，但本机已安装
  # miniconda/anaconda。与下方 python 候选目录一致，在此显式 source conda.sh。
  if ! command -v conda >/dev/null 2>&1; then
    local -a conda_bases=(
      "${HOME}/miniconda3"
      "${HOME}/miniforge3"
      "${HOME}/mambaforge"
      "${HOME}/anaconda3"
    )
    for base in "${conda_bases[@]}"; do
      if [[ -f "${base}/etc/profile.d/conda.sh" ]]; then
        # shellcheck source=/dev/null
        . "${base}/etc/profile.d/conda.sh"
        break
      fi
    done
  fi

  if command -v conda >/dev/null 2>&1; then
    [[ -n "${CONDA_ENV:-}" ]] ||
      die "CONDA_ENV 未设置。使用 conda 时须指定环境名：请通过 biu deploy py / biu push py 后的 biu 流程注入，或手动执行 export CONDA_ENV=环境名 后再运行本脚本。"
    echo "==> 检测到 conda，正在 conda activate: ${CONDA_ENV}"
    eval "$(conda shell.bash hook)"
    conda activate "$CONDA_ENV"
    for c in python python3; do
      if python_has_pip "$c"; then
        PYTHON="$(command -v "$c")"
        echo "==> 已激活 conda 环境，使用解释器: $PYTHON"
        return 0
      fi
    done
    die "conda 环境「${CONDA_ENV}」中未找到带 pip 的解释器（已尝试 python、python3）。请在该环境中安装 pip 或修正 CONDA_ENV。"
  fi

  echo "==> 未检测到 conda（PATH 中无 conda），使用系统 Python 探测" >&2
  local -a candidates=(
    python3
    python
    "${HOME}/miniconda3/bin/python"
    "${HOME}/anaconda3/bin/python"
    "${HOME}/miniforge3/bin/python"
    "${HOME}/mambaforge/bin/python"
  )
  for c in 12 11 10 9; do
    candidates+=("python3.${c}")
  done
  for c in "${candidates[@]}"; do
    [[ -n "$c" ]] || continue
    if python_has_pip "$c"; then
      PYTHON="$(command -v "$c")"
      echo "==> 使用系统（或非 conda PATH）解释器: $PYTHON"
      return 0
    fi
  done
  die "未找到 conda，且系统中无带 pip 的 Python（已尝试 python3、python 及常见路径）。请安装 python3-pip 或安装 conda 并配置 PATH。"
}

resolve_python
echo "==> Python 可执行文件: $PYTHON"

[[ -f "$CONFIG" ]] || die "缺少配置文件: $CONFIG"

pick_wheel() {
  local f latest="" best=-1 ts
  shopt -s nullglob
  for f in "$SCRIPT_DIR"/__PROJECT_NAME__-*.whl; do
    if [[ "$(uname -s)" == "Darwin" ]]; then
      ts="$(stat -f%m "$f" 2>/dev/null || echo 0)"
    else
      ts="$(stat -c%Y "$f" 2>/dev/null || echo 0)"
    fi
    if (( ts > best )); then
      best="$ts"
      latest="$f"
    fi
  done
  shopt -u nullglob
  printf '%s' "$latest"
}

if [[ -n "${WHEEL:-}" ]]; then
  [[ -f "$WHEEL" ]] || die "指定的 WHEEL 不存在: $WHEEL"
else
  WHEEL="$(pick_wheel)"
  [[ -n "$WHEEL" ]] || die "在 $SCRIPT_DIR 下未找到 __PROJECT_NAME__-*.whl"
fi

echo "==> pip install -U --no-deps --force-reinstall $WHEEL"
"$PYTHON" -m pip install -U --no-deps --force-reinstall "$WHEEL"

# 默认强制安装最新的 kmvpy（“一定 reinstall”）：每次发布都对 kmvpy 执行
# pip install -U --force-reinstall，确保线上框架与最新版一致；
# 需要跳过时可设置 KMVPY_SKIP_UPGRADE=1。
if [[ "${KMVPY_SKIP_UPGRADE:-}" != "1" ]]; then
  echo "==> 强制安装最新 kmvpy: pip install -U --force-reinstall kmvpy"
  "$PYTHON" -m pip install -U --force-reinstall "kmvpy"
fi

if [[ "${ROTATE_JWT_KEYS:-}" == "1" ]]; then
  echo "==> 轮换 JWT 密钥对: $CONFIG"
  "$PYTHON" -m kmvpy.generator.cli rotate-jwt-keys "$CONFIG"
fi

stop_old() {
  [[ -f "$PIDFILE" ]] || return 0
  local old_pid
  old_pid="$(tr -d '[:space:]' <"$PIDFILE" || true)"
  [[ -n "$old_pid" ]] || { rm -f "$PIDFILE"; return 0; }
  [[ "$old_pid" =~ ^[0-9]+$ ]] || { rm -f "$PIDFILE"; return 0; }
  if kill -0 "$old_pid" 2>/dev/null; then
    echo "==> 停止旧进程 pid=$old_pid"
    kill "$old_pid" 2>/dev/null || true
    local i
    for ((i = 0; i < 30; i++)); do
      kill -0 "$old_pid" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "$old_pid" 2>/dev/null; then
      echo "==> 旧进程未退出，发送 SIGKILL pid=$old_pid"
      kill -9 "$old_pid" 2>/dev/null || true
      sleep 1
    fi
  fi
  rm -f "$PIDFILE"
}

stop_old

ENTRY="$("$PYTHON" -c "import os, __PROJECT_NAME__.core.app.run as m; print(os.path.abspath(m.__file__))")"
[[ -f "$ENTRY" ]] || die "无法定位已安装入口: $ENTRY"

export __CONFIG_ENV_VAR__="$CONFIG"
export __PROJECT_NAME___CONFIG_PATH="$CONFIG"
export __PROJECT_NAME_UPPER___DEPLOY_SH="${SCRIPT_DIR}/deploy.sh"

echo "==> 启动服务: $PYTHON $ENTRY $CONFIG"
nohup "$PYTHON" "$ENTRY" "$CONFIG" >>"${SCRIPT_DIR}/nohup.out" 2>&1 &
new_pid=$!
echo "$new_pid" >"$PIDFILE"
echo "==> 已启动 pid=$new_pid，PID 文件: $PIDFILE"
echo "==> 标准输出/错误追加: ${SCRIPT_DIR}/nohup.out"
echo "==> 业务日志目录以 config.yaml 的 logging.path 为准"
