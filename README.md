# Git 日报 / 周报自动推送

定点自动汇总 git 提交，按类型整理成日报/周报，通过飞书机器人发给你自己。你只要复制粘贴进公司 OA 的日报里就行。

- **日报**：每天 18:30，汇总当天提交
- **周报**：每周五 18:30，汇总本周（周一至周五）提交

## 效果预览

飞书里会收到这样一条消息：

```
📅 2026-07-14 工作日报

✨ 新功能
- 剧集首页增加积分模型管理入口 + 模型列表表体滚动
- 生图新增模型并扩展 AI 改写模型选择

🐛 问题修复
- 场景/道具删除实体后关闭弹窗并刷新列表
- 生成视频区分已删除引用资产与未报白提示

—— 共 9 条提交
```

它会自动：按 `feat` / `fix` / `perf` / `refactor` 等前缀分类、去掉前缀、合并重复条目。

---

## 前置条件（macOS / Windows 通用）

1. **git**
2. **lark-cli** 并且已登录飞书
   - 安装：`npm install -g @larksuiteoapi/lark-cli`（或团队内部提供的安装方式）
   - 登录：`lark-cli auth login`
   - 机器人需具备发消息权限（scope 如 `im:message`），且与你本人有私聊关系（第一次可在飞书里主动跟机器人发一句话）
3. **Windows 额外需要**：安装 [Git for Windows](https://git-scm.com/download/win)（自带 Git Bash，脚本靠它运行）

> 没有 lark-cli / 飞书机器人环境的话，这个工具跑不起来——它依赖飞书应用能力。

---

## 快速开始（macOS / Linux）

```bash
git clone git@github.com:duanpeiyi/git-daily-report.git
cd git-daily-report

cp config.example.sh config.sh   # 生成个人配置（不会上传，放心填）

# 查一下自己的信息填进 config.sh：
git config user.email            # -> AUTHOR
lark-cli auth status             # -> 返回里的 openId 填 MY_OPEN_ID
which lark-cli                   # -> LARK_CLI（绝对路径）

DRY_RUN=1 bash daily-git-report.sh   # 先干跑看效果（不发送）
bash daily-git-report.sh             # 真发一条测试

bash setup-launchd.sh            # 装定时：日报每天 18:30 + 周报每周五 18:30
```

## 快速开始（Windows）

先装好 Git for Windows。用 **Git Bash** 执行：

```bash
git clone git@github.com:duanpeiyi/git-daily-report.git
cd git-daily-report
cp config.example.sh config.sh
# 编辑 config.sh 填 AUTHOR / MY_OPEN_ID
# LARK_CLI 可留空自动探测；填的话用 Windows 路径，如：
#   LARK_CLI="/c/Users/你的用户名/AppData/Roaming/npm/lark-cli.cmd"

DRY_RUN=1 bash daily-git-report.sh   # 干跑
bash daily-git-report.sh             # 发测试
```

再用 **PowerShell** 注册定时任务：

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-task-scheduler.ps1
```

---

## 配置说明（`config.sh`）

| 变量 | 说明 |
|---|---|
| `REPOS` | 要统计的仓库路径，可写多个，一行一个 |
| `AUTHOR` | 只统计这个邮箱的提交；留空 `""` = 统计所有人 |
| `MY_OPEN_ID` | 飞书接收人 open_id；留空 = 自动发给当前登录用户自己 |
| `LARK_CLI` | lark-cli 绝对路径；留空自动探测，**定时任务建议填绝对路径** |
| `SEND_AS` | `bot`（机器人发给你，推荐）或 `user`（以你本人身份发） |

---

## 手动运行

```bash
DRY_RUN=1 bash daily-git-report.sh              # 只看今天日报、不发送
bash daily-git-report.sh                         # 日报：发今天
bash daily-git-report.sh 2026-07-14              # 日报：补发某天
bash daily-git-report.sh week                    # 周报：本周
bash daily-git-report.sh week 2026-07-18         # 周报：包含该日期的那一周
```

---

## 定时任务

### macOS（常驻调度器）

```bash
bash setup-launchd.sh          # 安装/更新（默认日报每天 18:30 + 周报每周五 18:30）
bash setup-launchd.sh 19 0     # 改成 19:00
bash setup-launchd.sh remove   # 卸载

# 查看是否在跑：
launchctl print gui/$(id -u)/com.maiya.git-report-scheduler | grep -E 'state|pid'
cat run.log                    # 查看运行日志
```

> 说明：部分 macOS（darwin 25 / macOS 26）上 launchd 的 `StartCalendarInterval` 定时不触发。
> 因此这里改用 `scheduler.sh` 常驻方式——登录时由 launchd 拉起（`RunAtLoad`+`KeepAlive`），
> 脚本自己每分钟看表到点触发，并能在睡眠唤醒后补发当天错过的那次。

### Windows（任务计划程序）

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-task-scheduler.ps1          # 安装/更新
powershell -ExecutionPolicy Bypass -File .\setup-task-scheduler.ps1 -Remove  # 卸载
```

改时间：编辑 `setup-task-scheduler.ps1` 里的 `-At 6:30PM`，改完重新执行。

### Linux（cron）

```bash
crontab -e
# 日报：每天 18:30
30 18 * * *   /bin/bash /path/to/git-daily-report/daily-git-report.sh      >> /path/to/git-daily-report/run.log 2>&1
# 周报：每周五 18:30
30 18 * * 5   /bin/bash /path/to/git-daily-report/daily-git-report.sh week >> /path/to/git-daily-report/run.log 2>&1
```

> ⚠️ 定时都是**本地**的：到点时电脑必须开机且已登录才会触发（睡眠错过的，多数会在唤醒后补跑）。想要真正 7×24 稳定，请部署到服务器。

---

## 常见问题

- **收不到消息**：确认 `lark-cli auth status` 正常；确认机器人和你有私聊关系（先在飞书里跟机器人说句话）；看 `run.log` 报错。
- **分类不准**：本工具按约定式提交（Conventional Commits）前缀分类，`feat: xxx` / `fix: xxx` 效果最好；不带前缀的会归到「其他」。
- **Windows 上 bash 找不到**：确认装了 Git for Windows，并用 Git Bash 运行脚本；PowerShell 脚本会自动找 `bash.exe`。

---

## 关于"自动填进 OA"

本工具目前只做到**把整理好的日报/周报推送到飞书**，最后"粘贴进公司 OA 并提交"仍需手动一步。因为多数公司 OA 是嵌在飞书工作台里的独立系统，要真正自动写入必须对接它自己的后端接口（需抓包拿到提交接口、且登录态会过期），成本和稳定性都不划算，故暂不包含。
