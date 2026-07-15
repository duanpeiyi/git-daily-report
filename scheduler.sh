#!/bin/bash
# 常驻调度器：自己每分钟看表，到点触发日报/周报。
# 为什么要它：部分 macOS（如 darwin 25 / macOS 26）上 launchd 的 StartCalendarInterval
# 定时不触发，cron 又受 TCC 权限限制。此脚本只依赖"登录时被拉起"（RunAtLoad，可靠），
# 之后自行循环判断时间，并能在睡眠唤醒后补发当天错过的那次。
#
# 触发时间可用环境变量覆盖（也方便测试）：
#   DAILY_HHMM=1830   每天几点几分发日报（默认 18:30）
#   WEEKLY_HHMM=1830  周报时间（默认 18:30）
#   WEEKLY_DOW=5      周几发周报（1=周一 ... 5=周五，默认周五）
#   TICK=50           轮询间隔秒数（默认 50）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$SCRIPT_DIR/.state"
mkdir -p "$STATE_DIR"

DAILY_HHMM="${DAILY_HHMM:-1830}"
WEEKLY_HHMM="${WEEKLY_HHMM:-1830}"
WEEKLY_DOW="${WEEKLY_DOW:-5}"
TICK="${TICK:-50}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$SCRIPT_DIR/run.log"; }

log "调度器启动 (pid $$)  日报=$DAILY_HHMM 周报=周$WEEKLY_DOW@$WEEKLY_HHMM"

while true; do
  now_hhmm="$(date +%H%M)"
  today="$(date +%Y-%m-%d)"
  dow="$(date +%u)"

  # 日报：当天已过触发点且今天还没发过（10#前缀避免 0830 被当八进制）
  if [ "$((10#$now_hhmm))" -ge "$((10#$DAILY_HHMM))" ] && \
     [ "$(cat "$STATE_DIR/daily" 2>/dev/null)" != "$today" ]; then
    log "触发日报 $today"
    if bash "$SCRIPT_DIR/daily-git-report.sh" >> "$SCRIPT_DIR/run.log" 2>&1; then
      echo "$today" > "$STATE_DIR/daily"
      log "日报发送成功"
    else
      log "日报发送失败（下轮重试）"
    fi
  fi

  # 周报：到了指定星期几且已过触发点，本周还没发过
  if [ "$dow" = "$WEEKLY_DOW" ] && \
     [ "$((10#$now_hhmm))" -ge "$((10#$WEEKLY_HHMM))" ] && \
     [ "$(cat "$STATE_DIR/weekly" 2>/dev/null)" != "$today" ]; then
    log "触发周报 $today"
    if bash "$SCRIPT_DIR/daily-git-report.sh" week >> "$SCRIPT_DIR/run.log" 2>&1; then
      echo "$today" > "$STATE_DIR/weekly"
      log "周报发送成功"
    else
      log "周报发送失败（下轮重试）"
    fi
  fi

  sleep "$TICK"
done
