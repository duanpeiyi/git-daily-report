#!/bin/bash
# 一键安装 macOS 定时任务：
#   - 日报：每天 18:30
#   - 周报：每周五 18:30（汇总本周）
# 用法：
#   ./setup-launchd.sh          # 安装/更新
#   ./setup-launchd.sh remove   # 卸载

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LA="$HOME/Library/LaunchAgents"
DAILY_LABEL="com.maiya.daily-git-report"
WEEKLY_LABEL="com.maiya.weekly-git-report"

if [ "${1:-}" = "remove" ]; then
  for L in "$DAILY_LABEL" "$WEEKLY_LABEL"; do
    launchctl unload "$LA/$L.plist" 2>/dev/null || true
    rm -f "$LA/$L.plist"
  done
  echo "✅ 已卸载日报和周报定时任务。"
  exit 0
fi

mkdir -p "$LA"

# 日报：每天 18:30
cat > "$LA/$DAILY_LABEL.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$DAILY_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT_DIR/daily-git-report.sh</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$SCRIPT_DIR</string>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key><integer>18</integer>
        <key>Minute</key><integer>30</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>$SCRIPT_DIR/run.log</string>
    <key>StandardErrorPath</key>
    <string>$SCRIPT_DIR/run.log</string>
</dict>
</plist>
EOF

# 周报：每周五(Weekday=5) 18:30
cat > "$LA/$WEEKLY_LABEL.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$WEEKLY_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT_DIR/daily-git-report.sh</string>
        <string>week</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$SCRIPT_DIR</string>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Weekday</key><integer>5</integer>
        <key>Hour</key><integer>18</integer>
        <key>Minute</key><integer>30</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>$SCRIPT_DIR/run.log</string>
    <key>StandardErrorPath</key>
    <string>$SCRIPT_DIR/run.log</string>
</dict>
</plist>
EOF

for L in "$DAILY_LABEL" "$WEEKLY_LABEL"; do
  launchctl unload "$LA/$L.plist" 2>/dev/null || true
  launchctl load -w "$LA/$L.plist"
done

echo "✅ 已安装：日报每天 18:30，周报每周五 18:30。"
echo "   查看：launchctl list | grep git-report"
echo "   卸载：./setup-launchd.sh remove"
