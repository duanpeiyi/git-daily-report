#!/bin/bash
# 配置模板。首次使用请复制为 config.sh 再填写你自己的值：
#   cp config.example.sh config.sh
# config.sh 已被 .gitignore 忽略，不会上传到 GitHub，放心填个人信息。

# 要统计的 git 仓库，可以写多个，一行一个（用你本机的实际路径）
REPOS=(
  "/absolute/path/to/your/repo"
  # "/absolute/path/to/another/repo"
)

# 只统计谁的提交：填你的 git 作者邮箱。留空 "" 表示统计所有人。
# 查看自己的邮箱：git config user.email
AUTHOR=""

# 飞书接收人 open_id。留空则自动发给「当前登录 lark-cli 的用户」自己。
# 查看自己的 open_id：lark-cli auth status  （返回里的 openId 字段）
MY_OPEN_ID=""

# lark-cli 绝对路径。留空会自动探测；但 launchd 定时运行时 PATH 很干净，
# 强烈建议这里填绝对路径（用 `which lark-cli` 查看）。
LARK_CLI=""

# 发送身份：bot（机器人发给你，推荐）或 user（以你本人身份发）
SEND_AS="bot"
