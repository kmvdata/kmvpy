#!/usr/bin/env bash
# ============================================================
# reinstall.sh
# 构建当前 Python 包并强制重装其 sdist（tar.gz）。
# 包名与版本自动从 pyproject.toml 读取，升级版本号后无需改动本脚本。
#
# 用法：
#   ./reinstall.sh                      # build + 重装 dist/<name>-<version>.tar.gz（不带 extras）
#   ./reinstall.sh mysql                # 同上，URL 附加 extras: [mysql]
#   EXTRAS='mysql' ./reinstall.sh       # 或通过环境变量指定 extras
#   DEP_DIR='/abs/path/to/dependence' ./reinstall.sh   # 先把产物复制到该目录，再从那里安装
#
# 等价的完整命令形态：
#   python -m build && pip install -U --force-reinstall --no-deps \
#       <目录>/<name>-<version>.tar.gz[extras]
#
# 说明：
#   - --no-deps 不会安装任何运行依赖，请确保当前 Python 环境已具备所需依赖。
#   - extras 仅在需要时才传入（示例来源的 california 包 extras 对当前包不适用，
#     且 --no-deps 下 extras 不会触发依赖安装）。
# ============================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

# 可选环境变量（也可用第一个命令行参数指定 extras）：
#   EXTRAS   安装时附加的 extras，如 'fastapi,mysql,redis,captcha,aliyun'
#   DEP_DIR  非空时：构建产物先复制到此目录，再从该目录安装（如业务工程的 dependence/ 目录）
EXTRAS="${1:-${EXTRAS:-}}"
DEP_DIR="${DEP_DIR:-}"

# ---- 1. 从 pyproject.toml 解析包名与版本（自动适配当前版本）----
PYPROJECT="$ROOT_DIR/pyproject.toml"
if [[ ! -f "$PYPROJECT" ]]; then
  echo "错误：未找到 $PYPROJECT，请在 Python 包仓库根目录运行本脚本" >&2
  exit 1
fi

PACKAGE_NAME="$(sed -n 's/^name = "\(.*\)"$/\1/p' "$PYPROJECT" | head -n 1)"

# version 可能是静态（version = "x.y.z"），也可能是动态：
#   dynamic = ["version"] + [tool.setuptools.dynamic] version = {attr = "kmvpy.__version__"}
# 动态时从 attr 指向的源码（如 kmvpy/__init__.py 里的 __version__）读取版本号。
PACKAGE_VERSION="$(sed -n 's/^version = "\(.*\)"$/\1/p' "$PYPROJECT" | head -n 1)"
if [[ -z "$PACKAGE_VERSION" ]]; then
  DYNAMIC_ATTR="$(sed -n 's/^version = {attr = "\(.*\)"}$/\1/p' "$PYPROJECT" | head -n 1)"
  if [[ -n "$DYNAMIC_ATTR" ]]; then
    ATTR_NAME="${DYNAMIC_ATTR##*.}"
    ATTR_DIR="${DYNAMIC_ATTR%.*}"
    ATTR_DIR="${ATTR_DIR//.//}"
    for ATTR_FILE in "$ROOT_DIR/$ATTR_DIR/__init__.py" "$ROOT_DIR/$ATTR_DIR.py"; do
      if [[ -f "$ATTR_FILE" ]]; then
        PACKAGE_VERSION="$(sed -n "s/^${ATTR_NAME} = \"\\(.*\\)\"$/\\1/p" "$ATTR_FILE" | head -n 1)"
        [[ -n "$PACKAGE_VERSION" ]] && break
      fi
    done
  fi
fi
if [[ -z "$PACKAGE_NAME" || -z "$PACKAGE_VERSION" ]]; then
  echo "错误：无法从 pyproject.toml 解析 name / version（静态 version 与 dynamic attr 指向的 __version__ 均解析失败）" >&2
  exit 1
fi
echo "==> 当前包：${PACKAGE_NAME} ${PACKAGE_VERSION}"

# ---- 2. 检查构建工具 ----
if ! python -c 'import build' >/dev/null 2>&1; then
  echo "错误：当前 Python 环境未安装 build，请先执行: python -m pip install -U build" >&2
  exit 1
fi

# ---- 3. 构建 ----
echo "==> python -m build"
python -m build

TARBALL="$ROOT_DIR/dist/${PACKAGE_NAME}-${PACKAGE_VERSION}.tar.gz"
if [[ ! -f "$TARBALL" ]]; then
  echo "错误：构建产物不存在：$TARBALL" >&2
  exit 1
fi

# ---- 4. 可选：同步产物到外部依赖目录后安装 ----
if [[ -n "$DEP_DIR" ]]; then
  mkdir -p "$DEP_DIR"
  DEP_DIR="$(cd "$DEP_DIR" && pwd)"
  cp -f "$TARBALL" "$DEP_DIR/"
  TARBALL="$DEP_DIR/${PACKAGE_NAME}-${PACKAGE_VERSION}.tar.gz"
  echo "==> 已复制产物到 $DEP_DIR"
fi

# ---- 5. 拼装 extras 并强制重装（--no-deps）----
EXTRA_SUFFIX=""
if [[ -n "$EXTRAS" ]]; then
  EXTRA_SUFFIX="[$EXTRAS]"
fi
TARGET="${TARBALL}${EXTRA_SUFFIX}"

echo "==> pip install -U --force-reinstall --no-deps \"$TARGET\""
pip install -U --force-reinstall --no-deps "$TARGET"

echo "==> 完成：${PACKAGE_NAME} ${PACKAGE_VERSION} 已强制重装"
