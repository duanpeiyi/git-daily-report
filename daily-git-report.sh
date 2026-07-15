#!/bin/bash
# 每天定时：汇总当天 git 提交，整理成日报，推送到飞书（默认发给自己）。
#
# 用法：
#   ./daily-git-report.sh            # 汇总今天
#   ./daily-git-report.sh 2026-07-14 # 汇总指定日期
#   DRY_RUN=1 ./daily-git-report.sh  # 只打印不发送
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

# lark-cli 路径：配置里没写就自动探测（launchd 场景建议在 config.sh 写绝对路径）
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
DATE_STR="${1:-$(date +%Y-%m-%d)}"

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

# 把 commit 前缀归一到 CAT_KEYS 里的某一类
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
    --since="$DATE_STR 00:00:00" --until="$DATE_STR 23:59:59" \
    "${author_args[@]}" \
    --pretty=format:'%s' 2>/dev/null)"

  while IFS= read -r subj; do
    [ -z "$subj" ] && continue
    # 去掉 gitee MR 前缀，如 "!174 fix: xxx"
    subj="$(printf '%s' "$subj" | sed -E 's/^![0-9]+[[:space:]]+//')"
    # 解析 type(scope): desc
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

# ==================== 组装日报文本 ====================
MSG="**📅 $DATE_STR 工作日报**"$'\n'

if [ "$TOTAL" -eq 0 ]; then
  MSG+=$'\n'"今天没有检索到 git 提交记录。"
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
