#!/bin/bash
# 汇总 git 提交，整理成日报/周报（编号+标题+可选正文说明），推送到飞书（默认发给自己）。
#
# 用法：
#   ./daily-git-report.sh                 # 日报：今天
#   ./daily-git-report.sh 2026-07-14      # 日报：指定某天
#   ./daily-git-report.sh week            # 周报：本周（周一至今天）
#   ./daily-git-report.sh week 2026-07-18 # 周报：包含该日期的那一周（周一至该日）
#   DRY_RUN=1 ./daily-git-report.sh ...   # 只打印不发送
#
# 配置全部写在同目录的 config.sh 里（首次使用：cp config.example.sh config.sh 后填写）。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.sh"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ 缺少配置文件：$CONFIG_FILE" >&2
  echo "   请先执行：cp config.example.sh config.sh 然后按注释填写。" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG_FILE"

if [ -z "${LARK_CLI:-}" ] || [ ! -x "$LARK_CLI" ]; then
  LARK_CLI="$(command -v lark-cli 2>/dev/null || true)"
fi
if [ -z "$LARK_CLI" ]; then
  echo "❌ 找不到 lark-cli，请先安装并在 config.sh 里配置 LARK_CLI 绝对路径。" >&2
  exit 1
fi

# lark-cli 是 node 脚本，其 shebang 走 `env node`。定时任务(launchd/任务计划)的 PATH 很干净，
# 常找不到 nvm/npm 装的 node，导致 "env: node: No such file or directory"。
# node 与 lark-cli 通常在同一 bin 目录，把它加进 PATH 即可。
export PATH="$(dirname "$LARK_CLI"):$PATH"

if [ -z "${MY_OPEN_ID:-}" ]; then
  MY_OPEN_ID="$("$LARK_CLI" auth status 2>/dev/null | sed -n 's/.*"openId": *"\(ou_[^"]*\)".*/\1/p' | head -1)"
fi
if [ -z "$MY_OPEN_ID" ]; then
  echo "❌ 拿不到接收人 open_id，请在 config.sh 里填 MY_OPEN_ID（用 lark-cli auth status 查看）。" >&2
  exit 1
fi

SEND_AS="${SEND_AS:-bot}"

# ==================== 跨平台日期工具 ====================
date_add() {  # $1=YYYY-MM-DD  $2=天数偏移(可负)  ->  YYYY-MM-DD
  local base="$1" off="$2"
  if date -d "$base +0 days" +%Y-%m-%d >/dev/null 2>&1; then
    date -d "$base $off days" +%Y-%m-%d
  else
    local sign="+" n="$off"
    case "$off" in -*) sign="-"; n="${off#-}";; esac
    date -j -v"${sign}${n}d" -f "%Y-%m-%d" "$base" +%Y-%m-%d
  fi
}
weekday() {  # 1=周一 ... 7=周日
  local base="$1"
  if date -d "$base +0 days" +%u >/dev/null 2>&1; then
    date -d "$base" +%u
  else
    date -j -f "%Y-%m-%d" "$base" +%u
  fi
}

# ==================== 解析参数：日报 / 周报 ====================
MODE="day"; DATE_ARG=""
if [ "${1:-}" = "week" ]; then
  MODE="week"; DATE_ARG="${2:-}"
else
  DATE_ARG="${1:-}"
fi
BASE_DATE="${DATE_ARG:-$(date +%Y-%m-%d)}"

if [ "$MODE" = "week" ]; then
  U="$(weekday "$BASE_DATE")"
  START="$(date_add "$BASE_DATE" "-$((U - 1))")"
  END="$BASE_DATE"
  TITLE="📅 ${START} ~ ${END} 本周周报"
  EMPTY_TXT="本周没有检索到 git 提交记录。"
else
  START="$BASE_DATE"; END="$BASE_DATE"
  TITLE="📅 ${BASE_DATE} 工作日报"
  EMPTY_TXT="今天没有检索到 git 提交记录。"
fi

# ==================== 采集提交（标题 + 正文），按标题去重 ====================
SEEN="$(mktemp)"; trap 'rm -f "$SEEN"' EXIT
TITLES=(); BODIES=()

clean_subject() {
  # 去掉 gitee MR 前缀(!174 )与约定式前缀(feat:/fix(scope): 等)
  printf '%s' "$1" \
    | sed -E 's/^![0-9]+[[:space:]]+//' \
    | sed -E 's/^[a-zA-Z]+(\([^)]*\))?:[[:space:]]*//'
}

for repo in "${REPOS[@]}"; do
  git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "跳过(非git仓库): $repo" >&2; continue; }
  author_args=(); [ -n "${AUTHOR:-}" ] && author_args=(--author="$AUTHOR")

  shas="$(git -C "$repo" log --all --no-merges \
    --since="$START 00:00:00" --until="$END 23:59:59" \
    "${author_args[@]}" --pretty=format:'%H' 2>/dev/null)"

  while IFS= read -r sha; do
    [ -z "$sha" ] && continue
    subj="$(git -C "$repo" show -s --format='%s' "$sha")"
    title="$(clean_subject "$subj")"
    [ -z "$title" ] && continue
    grep -qxF -- "$title" "$SEEN" && continue   # 按标题去重（含跨分支的同一改动）
    printf '%s\n' "$title" >> "$SEEN"
    # 正文：去掉 Co-authored-by / Signed-off-by 等 trailer 与空行
    body="$(git -C "$repo" show -s --format='%b' "$sha" \
      | grep -viE '^(Co-authored-by|Signed-off-by|Co-Authored-By):' \
      | sed '/^[[:space:]]*$/d')"
    TITLES+=("$title")
    BODIES+=("$body")
  done <<< "$shas"
done

TOTAL="${#TITLES[@]}"

# ==================== 组装文本（编号 + 标题 + 可选正文）====================
MSG="**${TITLE}**"$'\n'

if [ "$TOTAL" -eq 0 ]; then
  MSG+=$'\n'"$EMPTY_TXT"
else
  n=0
  for i in "${!TITLES[@]}"; do
    n=$((n + 1))
    MSG+=$'\n'"**${n}. ${TITLES[$i]}**"$'\n'
    if [ -n "${BODIES[$i]}" ]; then
      while IFS= read -r bl; do
        [ -z "$bl" ] && continue
        MSG+="${bl}"$'\n'
      done <<< "${BODIES[$i]}"
    fi
  done
  MSG+=$'\n'"—— 共 ${TOTAL} 项"
fi

# ==================== 发送到飞书 ====================
if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "===== DRY RUN（不发送）====="
  printf '%s\n' "$MSG"
  exit 0
fi

"$LARK_CLI" im +messages-send \
  --as "$SEND_AS" \
  --user-id "$MY_OPEN_ID" \
  --markdown "$MSG"
