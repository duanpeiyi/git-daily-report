#!/bin/bash
# 汇总 git 提交，整理成日报/周报，推送到飞书（默认发给自己）。
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

# lark-cli 路径：配置里没写就自动探测（定时任务场景建议在 config.sh 写绝对路径）
if [ -z "${LARK_CLI:-}" ] || [ ! -x "$LARK_CLI" ]; then
  LARK_CLI="$(command -v lark-cli 2>/dev/null || true)"
fi
if [ -z "$LARK_CLI" ]; then
  echo "❌ 找不到 lark-cli，请先安装并在 config.sh 里配置 LARK_CLI 绝对路径。" >&2
  exit 1
fi

# open_id 没填就用当前登录用户自己的（发给自己）
if [ -z "${MY_OPEN_ID:-}" ]; then
  MY_OPEN_ID="$("$LARK_CLI" auth status 2>/dev/null | sed -n 's/.*"openId": *"\(ou_[^"]*\)".*/\1/p' | head -1)"
fi
if [ -z "$MY_OPEN_ID" ]; then
  echo "❌ 拿不到接收人 open_id，请在 config.sh 里填 MY_OPEN_ID（用 lark-cli auth status 查看）。" >&2
  exit 1
fi

SEND_AS="${SEND_AS:-bot}"

# ==================== 跨平台日期工具（macOS BSD date / Linux·Git Bash GNU date）====================
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
MODE="day"
DATE_ARG=""
if [ "${1:-}" = "week" ]; then
  MODE="week"; DATE_ARG="${2:-}"
else
  DATE_ARG="${1:-}"
fi
BASE_DATE="${DATE_ARG:-$(date +%Y-%m-%d)}"

if [ "$MODE" = "week" ]; then
  U="$(weekday "$BASE_DATE")"
  START="$(date_add "$BASE_DATE" "-$((U - 1))")"   # 回退到本周周一
  END="$BASE_DATE"
  TITLE="📅 ${START} ~ ${END} 本周周报"
  EMPTY_TXT="本周没有检索到 git 提交记录。"
else
  START="$BASE_DATE"; END="$BASE_DATE"
  TITLE="📅 ${BASE_DATE} 工作日报"
  EMPTY_TXT="今天没有检索到 git 提交记录。"
fi

# 分类：commit 前缀 -> 中文标题（保持这个顺序输出）
CAT_KEYS=(feat fix perf refactor style docs test chore other)
cat_label() {
  case "$1" in
    feat)     echo "✨ 新功能" ;;
    fix)      echo "🐛 问题修复" ;;
    perf)     echo "⚡ 性能优化" ;;
    refactor) echo "♻️ 重构" ;;
    style)    echo "💄 样式调整" ;;
    docs)     echo "📝 文档" ;;
    test)     echo "✅ 测试" ;;
    chore)    echo "🔧 杂项/构建" ;;
    *)        echo "📌 其他" ;;
  esac
}
normalize_type() {
  case "$1" in
    feat|feature)      echo feat ;;
    fix|bugfix|hotfix) echo fix ;;
    perf)              echo perf ;;
    refactor)          echo refactor ;;
    style)             echo style ;;
    docs|doc)          echo docs ;;
    test|tests)        echo test ;;
    chore|build|ci)    echo chore ;;
    *)                 echo other ;;
  esac
}

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

TOTAL=0

for repo in "${REPOS[@]}"; do
  if ! git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "跳过（不是 git 仓库）: $repo" >&2
    continue
  fi

  author_args=()
  [ -n "${AUTHOR:-}" ] && author_args=(--author="$AUTHOR")

  subjects="$(git -C "$repo" log --all --no-merges \
    --since="$START 00:00:00" --until="$END 23:59:59" \
    "${author_args[@]}" \
    --pretty=format:'%s' 2>/dev/null)"

  while IFS= read -r subj; do
    [ -z "$subj" ] && continue
    subj="$(printf '%s' "$subj" | sed -E 's/^![0-9]+[[:space:]]+//')"
    if printf '%s' "$subj" | grep -qE '^[a-zA-Z]+(\([^)]*\))?:'; then
      rawtype="$(printf '%s' "$subj" | sed -E 's/^([a-zA-Z]+)(\([^)]*\))?:.*/\1/' | tr '[:upper:]' '[:lower:]')"
      desc="$(printf '%s' "$subj" | sed -E 's/^[a-zA-Z]+(\([^)]*\))?:[[:space:]]*//')"
    else
      rawtype="other"
      desc="$subj"
    fi
    cat="$(normalize_type "$rawtype")"
    printf '%s\t%s\n' "$cat" "$desc" >> "$TMP"
    TOTAL=$((TOTAL + 1))
  done <<< "$subjects"
done

# ==================== 组装文本 ====================
MSG="**${TITLE}**"$'\n'

if [ "$TOTAL" -eq 0 ]; then
  MSG+=$'\n'"$EMPTY_TXT"
else
  for key in "${CAT_KEYS[@]}"; do
    lines="$(awk -F'\t' -v k="$key" '$1==k{print $2}' "$TMP")"
    [ -z "$lines" ] && continue
    MSG+=$'\n'"**$(cat_label "$key")**"$'\n'
    while IFS= read -r d; do
      [ -z "$d" ] && continue
      MSG+="- ${d}"$'\n'
    done <<< "$(printf '%s\n' "$lines" | awk '!seen[$0]++')"
  done
  MSG+=$'\n'"—— 共 ${TOTAL} 条提交"
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
