#!/usr/bin/env bash
#
# kmvpy 历史重建脚本（一次性使用，执行成功后请删除本文件）
#
# 目标：把 main 重写为「当前代码状态 = 首个提交（无父提交）」，版本号 0.2.6，并创建 tag v0.2.6。
# 前置：已应用 0.2.6 的版本号/文档改动，且 `git status` 干净。
#
# 用法：
#   bash scripts/rebuild-history-v026.sh --plan              # 只打印步骤，不做任何修改
#   bash scripts/rebuild-history-v026.sh                     # 本地重建 main + 打 tag（不联网、不 gc）
#   bash scripts/rebuild-history-v026.sh --push              # 另加强推 main、推送 tag、删除远端旧标签与 develop
#   bash scripts/rebuild-history-v026.sh --push --scrub-local # 再清理本地 reflog 与不可达对象
#
# 安全说明：
#   * 第 2 步先把旧历史打包成 bundle；这是唯一回滚点，确认无误前不要删除（注意它含旧密码）。
#   * --push 使用 --force-with-lease，若远端 main 已被他人推进会直接失败，而不是覆盖别人的提交。
#   * 重写后的历史不可逆；所有已克隆该仓库的人都需要重新 clone，不能 git pull。
#   * 本脚本不处理 GitHub Release / Actions 日志 / fork 缓存，也不处理 PyPI，见末尾清单。
#
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

BRANCH="main"
REMOTE="origin"
NEW_TAG="v0.2.6"
NEW_VERSION="0.2.6"
OLD_HEAD="${OLD_HEAD:-7f0fedc60cc135b7d70cded0fc99f636294955a6}"
BACKUP_BUNDLE="${BACKUP_BUNDLE:-$(dirname "$REPO_ROOT")/kmvpy-prehistory-backup-$(date +%Y%m%d-%H%M%S).bundle}"

# 允许出现在「旧 HEAD → 新提交」差异中的文件；出现其它改动时会要求 --yes 确认。
EXPECTED_FILES=" kmvpy/__init__.py CHANGELOG.md README.md README.zh-CN.md docs/PUBLISHING.md "

DO_PLAN=0
DO_PUSH=0
DO_SCRUB=0
ASSUME_YES=0

for arg in "$@"; do
  case "$arg" in
    --plan) DO_PLAN=1 ;;
    --push) DO_PUSH=1 ;;
    --scrub-local) DO_SCRUB=1 ;;
    --yes) ASSUME_YES=1 ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "未知参数：$arg（可用：--plan --push --scrub-local --yes）" >&2; exit 64 ;;
  esac
done

info() { printf '\n==> %s\n' "$*"; }
step() { printf '\n--- 步骤 %s：%s\n' "$1" "$2"; }
die()  { printf '\n[失败] %s\n' "$*" >&2; exit 1; }

info "kmvpy 历史重建（目标版本 ${NEW_VERSION}）"
printf '仓库      : %s\n' "$REPO_ROOT"
printf '分支/远端 : %s / %s\n' "$BRANCH" "$REMOTE"
printf '旧 HEAD   : %s\n' "$OLD_HEAD"
printf '备份路径  : %s\n' "$BACKUP_BUNDLE"
printf '推送远端  : %s    本地清理: %s\n' "$DO_PUSH" "$DO_SCRUB"

if [ "$DO_PLAN" = 1 ]; then
  cat <<'PLAN'

计划步骤：
  1. 环境校验：在 main 分支、工作区干净、旧 HEAD 存在、版本文件已是 0.2.6
  2. 备份：git bundle create <备份>.bundle --all
  3. 差异白名单：确认相对旧 HEAD 的改动只涉及版本号与文档
  4. 重建：git add -A → git write-tree → git commit-tree（无父提交）→ git update-ref（CAS 校验旧值）
  5. 打标签：git tag -a v0.2.6
  6. 校验：提交数为 1、无 parent、tag 指向 HEAD、版本号一致
  7. 仅 --push：强推 main、推送 v0.2.6、删除远端其它标签与其它分支（含 develop）
  8. 仅 --scrub-local：fetch --prune、删除本地旧标签/分支、reflog expire、gc --prune=now
PLAN
  exit 0
fi

step 1 "环境校验"
current_branch="$(git rev-parse --abbrev-ref HEAD)"
[ "$current_branch" = "$BRANCH" ] || die "当前在 ${current_branch}，请先切到 ${BRANCH}"
[ -z "$(git status --porcelain)" ] || die "工作区不干净，请先提交或清理：
$(git status --porcelain)"
git cat-file -e "${OLD_HEAD}^{commit}" 2>/dev/null || die "找不到旧提交 ${OLD_HEAD}（可能已重建过，或不是本仓库）"
version_in_file="$(sed -n 's/^__version__ = "\(.*\)"$/\1/p' kmvpy/__init__.py)"
[ "$version_in_file" = "$NEW_VERSION" ] || die "kmvpy/__init__.py 的版本是 ${version_in_file:-<空>}，期望 ${NEW_VERSION}；请先应用版本号改动"
printf 'OK：分支=%s，工作区干净，旧提交存在，版本=%s\n' "$current_branch" "$version_in_file"

step 2 "备份完整旧历史（含旧标签与 develop）"
git bundle create "$BACKUP_BUNDLE" --all
git bundle verify "$BACKUP_BUNDLE" >/dev/null 2>&1 || die "备份校验失败，终止"
printf '备份已生成并通过校验：%s\n（提醒：该 bundle 含旧密码，收敛后请删除）\n' "$BACKUP_BUNDLE"

step 3 "确认改动范围仅限版本号与文档"
changed=()
while IFS= read -r f; do
  [ -n "$f" ] && changed+=("$f")
done < <(git diff --name-only "$OLD_HEAD" -- .)
unexpected=()
for f in ${changed[@]+"${changed[@]}"}; do
  case "$EXPECTED_FILES" in
    *" $f "*) ;;
    *) unexpected+=("$f") ;;
  esac
done
if [ ${#changed[@]} -eq 0 ]; then
  echo "相对旧 HEAD 无改动（版本号尚未更新？请先应用改动）"
else
  printf '改动文件：\n'; printf '  %s\n' "${changed[@]}"
fi
if [ ${#unexpected[@]} -gt 0 ]; then
  printf '以下文件不在预期白名单内：\n'; printf '  %s\n' "${unexpected[@]}"
  [ "$ASSUME_YES" = 1 ] || die "确认这些改动也要进入首个提交后，加 --yes 重新运行"
fi

step 4 "重建 main 为单提交（内容 = 当前工作树）"
git add --all
tree_id="$(git write-tree)"
new_commit="$(git commit-tree "$tree_id" -m "chore(release): kmvpy ${NEW_VERSION}

以当前代码状态作为本仓库的首个提交重建历史；此前的提交（其中误含密码）不再属于本仓库历史。")"
printf '新提交：%s（tree=%s）\n' "$new_commit" "$tree_id"
git update-ref -m "rebuild history: kmvpy ${NEW_VERSION}" "refs/heads/${BRANCH}" "$new_commit" "$OLD_HEAD"
printf 'main 已从 %s 指向 %s（旧值校验通过）\n' "$OLD_HEAD" "$new_commit"
[ -z "$(git status --porcelain)" ] || die "重建后工作区不干净，请检查：
$(git status --porcelain)"

step 5 "创建 tag ${NEW_TAG}"
if git rev-parse -q --verify "refs/tags/${NEW_TAG}" >/dev/null; then
  die "本地已存在 tag ${NEW_TAG}，请先确认：git tag -d ${NEW_TAG}"
fi
git tag -a "$NEW_TAG" -m "kmvpy ${NEW_VERSION}" "$new_commit"
printf '已创建 %s → %s\n' "$NEW_TAG" "$new_commit"

step 6 "校验重建结果"
git --no-pager log --oneline --decorate -n 3
count="$(git rev-list --count "$BRANCH")"
parents="$(git cat-file -p "$new_commit" | grep -c '^parent' || true)"
points="$(git tag --points-at "$new_commit" | tr '\n' ' ')"
printf '提交数=%s  父提交数=%s  指向该提交的标签=%s\n' "$count" "$parents" "$points"
[ "$count" = "1" ] || die "提交数应为 1，实际 ${count}"
[ "$parents" = "0" ] || die "新提交不应包含父提交"
case " $points " in *" $NEW_TAG "*) ;; *) die "tag ${NEW_TAG} 未指向新提交" ;; esac
printf '版本文件内容：%s（tag 去掉 v 后应与之一致）\n' "$version_in_file"

if [ "$DO_PUSH" = 1 ]; then
  step 7 "推送远端（不可逆）"
  echo "将执行："
  echo "  git push --force-with-lease=refs/heads/${BRANCH}:${OLD_HEAD} ${REMOTE} ${BRANCH}"
  echo "  git push ${REMOTE} refs/tags/${NEW_TAG}"
  echo "  删除远端除 ${NEW_TAG} 之外的标签"
  echo "  删除远端除 ${BRANCH} 之外的分支（当前包括 develop）"
  echo
  echo "前置提醒："
  echo "  * 若 GitHub 对 ${BRANCH} 开启分支保护，需先临时允许 force push"
  echo "  * 先在 GitHub 删除指向旧提交的 Release，再删标签，避免留下悬空 Release"
  if [ "$ASSUME_YES" != 1 ]; then
    printf '确认继续？输入 YES 继续：'
    read -r answer
    [ "$answer" = "YES" ] || die "已取消（本地重建结果保留，可用 bundle 回滚）"
  fi

  remote_tags="$(git ls-remote --tags --refs "$REMOTE" | awk '{print $2}' | sed 's#^refs/tags/##' | grep -v "^${NEW_TAG}$" || true)"
  remote_branches="$(git ls-remote --heads "$REMOTE" | awk '{print $2}' | sed 's#^refs/heads/##' | grep -v "^${BRANCH}$" || true)"

  git push --force-with-lease="refs/heads/${BRANCH}:${OLD_HEAD}" "$REMOTE" "$BRANCH"
  git push "$REMOTE" "refs/tags/${NEW_TAG}"

  for t in $remote_tags; do
    echo "删除远端标签 ${t}"
    git push "$REMOTE" --delete "$t"
  done
  for b in $remote_branches; do
    echo "删除远端分支 ${b}"
    git push "$REMOTE" --delete "$b"
  done
  git fetch --prune "$REMOTE" || true
else
  step 7 "跳过推送（未指定 --push）；此时远端仍是旧历史"
fi

if [ "$DO_SCRUB" = 1 ]; then
  step 8 "清理本地旧对象"
  if [ "$DO_PUSH" != 1 ]; then
    echo "注意：未执行 --push，远端跟踪引用仍指向旧提交，gc 无法彻底移除旧对象。"
  fi
  for t in $(git tag -l | grep -v "^${NEW_TAG}$" || true); do
    echo "删除本地标签 ${t}"; git tag -d "$t"
  done
  for b in $(git for-each-ref --format='%(refname:short)' refs/heads | grep -v "^${BRANCH}$" || true); do
    echo "删除本地分支 ${b}"; git branch -D "$b"
  done
  git reflog expire --expire=now --all
  git gc --prune=now
  echo "本地不可达对象已清理"
else
  step 8 "跳过本地清理（未指定 --scrub-local）；旧对象仍可通过 reflog 恢复"
fi

info "脚本执行结束。还需人工完成："
cat <<'TODO'
  1. GitHub → Releases：删除指向旧提交的 Release / Draft。
  2. GitHub → Actions：删除历史 workflow run 与 artifacts（日志可能含密码）。
  3. GitHub → Tags/Branches：确认只剩 main（与 v0.2.6）。
  4. 仓库公开或有 fork 时：提交 Support 请求清除缓存（Removing sensitive data），或删除仓库后以新历史重建 push。
  5. 通知所有协作者重新 clone（不要 git pull）。
  6. PyPI：`pip download --no-deps --no-binary :all: kmvpy==0.2.4 -d /tmp/kmvpy-024` 后扫描，命中则 yank 并联系 PyPI 删除。
  7. 轮换真正泄露过的数据库 / Redis / 管理员默认密码。
  8. 确认无误后删除本脚本与备份 bundle。
TODO