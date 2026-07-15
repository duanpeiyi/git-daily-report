#!/bin/bash
# 安装 macOS 常驻调度器（登录时自动启动，自身循环到点触发）。
#   日报：每天 HH:MM（默认 18:30）
#   周报：每周五 HH:MM（默认 18:30）
#
# 为什么不用 launchd 的 StartCalendarInterval：部分 macOS（darwin 25 / macOS 26）上它不触发。
# 这里用 RunAtLoad + KeepAlive 拉起 scheduler.sh，由脚本自己看表，稳定可靠。
#
# 用法：
#   ./setup-launchd.sh          # 安装/更新（默认 18:30）
#   ./setup-launchd.sh 19 0     # 改成 19:00
#   ./setup-launchd.sh remove   # 卸载

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LA="$HOME/Library/LaunchAgents"
UID_NUM="$(id -u)"
LABEL="com.maiya.git-report-scheduler"
PLIST="$LA/$LABEL.plist"

# 兼容清理旧版基于日历定时的任务
OLD_LABELS=(com.maiya.daily-git-report com.maiya.weekly-git-report)

remove_all() {
  launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  for L in "${OLD_LABELS[@]}"; do
    launchctl bootout "gui/$UID_NUM/$L" 2>/dev/null || true
    launchctl unload "$LA/$L.plist" 2>/dev/null || true
    rm -f "$LA/$L.plist"
  done
}

if [ "${1:-}" = "remove" ]; then
  remove_all
  echo "✅ 已卸载调度器（含旧版日报/周报任务）。"
  exit 0
fi

HOUR="${1:-18}"
MINUTE="${2:-30}"
HHMM="$(printf '%02d%02d' "$HOUR" "$MINUTE")"

mkdir -p "$LA"
remove_all   # 先清干净再装，避免重复

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT_DIR/scheduler.sh</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>DAILY_HHMM</key><string>$HHMM</string>
        <key>WEEKLY_HHMM</key><string>$HHMM</string>
        <key>WEEKLY_DOW</key><string>5</string>
    </dict>
    <key>WorkingDirectory</key>
    <string>$SCRIPT_DIR</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$SCRIPT_DIR/run.log</string>
    <key>StandardErrorPath</key>
    <string>$SCRIPT_DIR/run.log</string>
</dict>
</plist>
EOF

launchctl bootstrap "gui/$UID_NUM" "$PLIST"
launchctl enable "gui/$UID_NUM/$LABEL"

echo "✅ 已安装常驻调度器：日报每天 $HOUR:$(printf '%02d' "$MINUTE")，周报每周五同一时间。"
echo "   查看是否在跑：launchctl print gui/$UID_NUM/$LABEL | grep -E 'state|pid'"
echo "   日志：$SCRIPT_DIR/run.log"
echo "   卸载：./setup-launchd.sh remove"
