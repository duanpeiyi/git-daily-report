# 每日 Git 日报自动推送

每天定点自动汇总当天的 git 提交，按类型整理成日报，通过飞书机器人发给你自己。你只要把内容复制粘贴进公司 OA 的日报里就行。

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

## 前置条件

1. **macOS**（定时用的是 macOS 的 launchd；其他系统见文末）
2. **git**
3. **lark-cli** 并且已登录飞书
   - 安装：`npm install -g @larksuiteoapi/lark-cli`（或团队内部提供的安装方式）
   - 登录：`lark-cli auth login`
   - 需要机器人具备发消息权限（scope：`im:message` 等），并且机器人与你本人有私聊关系（第一次可在飞书里主动跟机器人发一句话）

> 没有 lark-cli / 飞书机器人环境的话，这个工具跑不起来——它依赖飞书应用能力。

---

## 快速开始

```bash
# 1. 克隆
git clone <你的仓库地址> maiya-git-daily-report
cd maiya-git-daily-report

# 2. 生成个人配置（config.sh 不会被上传，放心填）
cp config.example.sh config.sh

# 3. 查一下自己的信息，填进 config.sh
git config user.email       # -> 填 AUTHOR
lark-cli auth status        # -> 返回里的 openId 填 MY_OPEN_ID
which lark-cli              # -> 填 LARK_CLI（绝对路径）

# 4. 先干跑看看效果（不发送）
DRY_RUN=1 bash daily-git-report.sh

# 5. 真发一条测试
bash daily-git-report.sh

# 6. 装上每天定时（默认 18:30）
bash setup-launchd.sh
```

---

## 配置说明（`config.sh`）

| 变量 | 说明 |
|---|---|
| `REPOS` | 要统计的仓库路径，可写多个，一行一个 |
| `AUTHOR` | 只统计这个邮箱的提交；留空 `""` = 统计所有人 |
| `MY_OPEN_ID` | 飞书接收人 open_id；留空 = 自动发给当前登录用户自己 |
| `LARK_CLI` | lark-cli 绝对路径；留空自动探测，但**定时任务建议填绝对路径** |
| `SEND_AS` | `bot`（机器人发给你，推荐）或 `user`（以你本人身份发） |

---

## 手动运行

```bash
DRY_RUN=1 bash daily-git-report.sh            # 只看今天日报、不发送
bash daily-git-report.sh                       # 发今天
bash daily-git-report.sh 2026-07-14            # 补发指定日期
```

---

## 定时任务

```bash
bash setup-launchd.sh          # 每天 18:30
bash setup-launchd.sh 19 0     # 改成每天 19:00（参数：小时 分钟）
bash setup-launchd.sh remove   # 卸载

launchctl list | grep com.maiya.daily-git-report   # 查看是否已加载
cat run.log                                        # 查看运行日志
```

> ⚠️ launchd 是**本地定时**：到点时电脑必须开机且已登录才会触发（睡眠错过的，多数会在唤醒后补跑）。想要真正 7×24 稳定，请部署到服务器并改用 cron。

---

## 常见问题

- **收不到消息**：确认 `lark-cli auth status` 正常；确认机器人和你有私聊关系（先在飞书里跟机器人说句话）；看 `run.log` 报错。
- **分类不准**：本工具按约定式提交（Conventional Commits）前缀分类。提交信息写成 `feat: xxx` / `fix: xxx` 效果最好；不带前缀的会归到「其他」。
- **定时没触发**：到点时电脑是否开着、是否登录；`launchctl list | grep com.maiya` 是否在列。

---

## 关于"自动填进 OA"

本工具目前只做到**把整理好的日报推送到飞书**，最后"粘贴进公司 OA 日报并提交"仍需手动一步。因为多数公司 OA 是嵌在飞书工作台里的独立系统，要真正自动写入必须对接它自己的后端接口（需要抓包拿到提交接口、且登录态会过期），成本和稳定性都不划算，故暂不包含。

---

## 其他系统（Linux / 服务器）

脚本本身跨平台，只是定时那步不同。用 cron：

```bash
crontab -e
# 每天 18:30 运行
30 18 * * * /bin/bash /path/to/maiya-git-daily-report/daily-git-report.sh >> /path/to/maiya-git-daily-report/run.log 2>&1
```
