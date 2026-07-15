#!/bin/bash
# 一键安装 macOS 定时任务：每天定点运行 daily-git-report.sh。
# 用法：
#   ./setup-launchd.sh          # 默认每天 18:30
#   ./setup-launchd.sh 19 0     # 每天 19:00（参数：小时 分钟）
#   ./setup-launchd.sh remove   # 卸载定时任务

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="com.maiya.daily-git-report"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ "${1:-}" = "remove" ]; then
  launchctl unload "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  echo "✅ 已卸载定时任务。"
  exit 0
fi

HOUR="${1:-18}"
MINUTE="${2:-30}"

mkdir -p "$HOME/Library/LaunchAgents"

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
        <string>$SCRIPT_DIR/daily-git-report.sh</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$SCRIPT_DIR</string>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>$HOUR</integer>
        <key>Minute</key>
        <integer>$MINUTE</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>$SCRIPT_DIR/run.log</string>
    <key>StandardErrorPath</key>
    <string>$SCRIPT_DIR/run.log</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load -w "$PLIST"

printf '✅ 已安装：每天 %02d:%02d 自动运行。\n' "$HOUR" "$MINUTE"
echo "   查看状态：launchctl list | grep $LABEL"
echo "   卸载：./setup-launchd.sh remove"
