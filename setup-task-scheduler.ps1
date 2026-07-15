# Windows 一键安装定时任务（等价于 macOS 的 setup-launchd.sh）：
#   - 日报：每天 18:30
#   - 周报：每周五 18:30（汇总本周）
# 依赖：已安装 Git for Windows（提供 bash.exe）。
#
# 用法（在 PowerShell 里）：
#   powershell -ExecutionPolicy Bypass -File .\setup-task-scheduler.ps1          # 安装/更新
#   powershell -ExecutionPolicy Bypass -File .\setup-task-scheduler.ps1 -Remove  # 卸载

param([switch]$Remove)

$ErrorActionPreference = "Stop"
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$DailyName  = "MaiyaGitDailyReport"
$WeeklyName = "MaiyaGitWeeklyReport"

if ($Remove) {
  Unregister-ScheduledTask -TaskName $DailyName  -Confirm:$false -ErrorAction SilentlyContinue
  Unregister-ScheduledTask -TaskName $WeeklyName -Confirm:$false -ErrorAction SilentlyContinue
  Write-Host "已卸载日报和周报定时任务。"
  exit 0
}

# 查找 Git Bash 的 bash.exe
$bashCandidates = @(
  "$env:ProgramFiles\Git\bin\bash.exe",
  "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
  "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
)
$bash = $bashCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $bash) {
  Write-Error "找不到 Git Bash（bash.exe）。请先安装 Git for Windows：https://git-scm.com/download/win"
  exit 1
}

# 把 Windows 路径转成 Git Bash 的 POSIX 路径：C:\a\b -> /c/a/b
$drive    = $ScriptDir.Substring(0,1).ToLower()
$rest     = $ScriptDir.Substring(2) -replace '\\','/'
$posixDir = "/$drive$rest"

$dailyCmd  = "'$posixDir/daily-git-report.sh'"
$weeklyCmd = "'$posixDir/daily-git-report.sh' week"

$dailyAction  = New-ScheduledTaskAction -Execute $bash -Argument "-lc `"$dailyCmd`""
$weeklyAction = New-ScheduledTaskAction -Execute $bash -Argument "-lc `"$weeklyCmd`""

$dailyTrigger  = New-ScheduledTaskTrigger -Daily -At 6:30PM
$weeklyTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Friday -At 6:30PM

# 登录时运行；电脑没开机时错过的任务，开机后会补跑
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

Register-ScheduledTask -TaskName $DailyName  -Action $dailyAction  -Trigger $dailyTrigger  -Settings $settings -Force | Out-Null
Register-ScheduledTask -TaskName $WeeklyName -Action $weeklyAction -Trigger $weeklyTrigger -Settings $settings -Force | Out-Null

Write-Host "已安装：日报每天 18:30，周报每周五 18:30。"
Write-Host "查看：任务计划程序 -> 任务计划程序库，找 $DailyName / $WeeklyName"
Write-Host "卸载：powershell -ExecutionPolicy Bypass -File .\setup-task-scheduler.ps1 -Remove"
