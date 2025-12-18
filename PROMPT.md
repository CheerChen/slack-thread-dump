# Slack Thread Dump 工具设计方案

## 项目概述

仿照 `pr-dump` 工具的设计思路，创建一个导出 Slack Thread 对话内容的命令行工具。

**项目名称**: `slack-thread-dump`

**核心功能**: 根据 Slack Thread URL，获取完整对话内容、参与者信息，格式化输出到本地文件。

---

## 参考项目: pr-dump

`pr-dump` 的核心设计思路：
1. **依赖外部工具**: 使用 `gh` CLI + `jq` 处理 JSON
2. **配置管理**: 通过命令行参数配置输出选项
3. **认证**: 依赖 `gh auth login` 管理认证
4. **数据获取**: 调用 API 获取 metadata、comments、diff
5. **格式化输出**: 支持 text/markdown 格式，输出到文件
6. **安装方式**: 支持 Homebrew、直接下载、install.sh

---

## 依赖工具

- `curl`: 调用 Slack API
- `jq`: JSON 处理
- Slack User Token: 配置文件或环境变量

---

## Slack Thread URL 格式

```
# 格式1: 新版 Slack URL
https://app.slack.com/client/T12345678/C12345678/thread/C12345678-1234567890.123456
                            ^workspace  ^channel    ^thread    ^channel-thread_ts

# 格式2: 归档链接格式
https://your-workspace.slack.com/archives/C12345678/p1234567890123456?thread_ts=1234567890.123456
                                          ^channel   ^message_ts       ^parent_ts
```

---

## 配置方式

1. 环境变量: `SLACK_TOKEN`
2. 配置文件: `~/.slack-thread-dump/config`
3. 命令行参数: `--token`

---

## 需要的 Slack API

- `conversations.replies` - 获取 thread 所有回复
- `users.info` - 获取用户详情（用于将 user_id 转换为用户名）

---

## Slack 消息格式处理

### Slack mrkdwn vs 标准 Markdown

| 内容类型 | Slack mrkdwn | 标准 Markdown |
|---------|-------------|---------------|
| 粗体 | `*bold*` | `**bold**` |
| 斜体 | `_italic_` | `*italic*` |
| 删除线 | `~strikethrough~` | `~~strikethrough~~` |
| 代码 | `` `code` `` | `` `code` `` |
| 代码块 | ` ```code``` ` | ` ```code``` ` |
| 引用 | `>quote` | `>quote` |
| 链接 | `<https://url\|显示文字>` | `[显示文字](url)` |
| @用户 | `<@U12345678>` | 需要转换为用户名 |
| #频道 | `<#C12345678>` | 需要转换为频道名 |
| @here/@channel | `<!here>` `<!channel>` | 保留原样 |

### 处理函数设计

#### A. 用户/频道引用处理

```bash
# API 返回的原始格式
"text": "Hey <@U0123456789>, please check <#C9876543210|general>"

# 处理后
"Hey @john.doe, please check #general"
```

处理逻辑：
```bash
convert_user_mentions() {
    local text="$1"
    # 提取所有用户ID
    local user_ids=$(echo "$text" | grep -oE '<@U[A-Z0-9]+>' | sed 's/<@//g;s/>//g' | sort -u)
    
    for uid in $user_ids; do
        # 从缓存或API获取用户名
        local username=$(get_username "$uid")
        text=$(echo "$text" | sed "s/<@${uid}>/@${username}/g")
    done
    echo "$text"
}
```

#### B. 链接处理

```bash
# Slack 链接格式
"Check this: <https://github.com/repo|GitHub Repo>"
"Direct link: <https://example.com>"

# 转换为可读格式 (text模式)
"Check this: GitHub Repo (https://github.com/repo)"
"Direct link: https://example.com"

# 转换为 Markdown 格式
"Check this: [GitHub Repo](https://github.com/repo)"
"Direct link: https://example.com"
```

处理逻辑：
```bash
convert_links() {
    local text="$1"
    local format="$2"  # text 或 markdown
    
    if [ "$format" = "markdown" ]; then
        # <url|text> -> [text](url)
        text=$(echo "$text" | sed -E 's/<(https?:\/\/[^|>]+)\|([^>]+)>/[\2](\1)/g')
    else
        # <url|text> -> text (url)
        text=$(echo "$text" | sed -E 's/<(https?:\/\/[^|>]+)\|([^>]+)>/\2 (\1)/g')
    fi
    # <url> -> url (无显示文字的情况)
    text=$(echo "$text" | sed -E 's/<(https?:\/\/[^>]+)>/\1/g')
    echo "$text"
}
```

#### C. 图片/文件处理

Slack 消息中的文件附件在 API 返回中是单独的 `files` 数组：

```json
{
  "text": "Here's the screenshot",
  "files": [
    {
      "id": "F12345678",
      "name": "screenshot.png",
      "mimetype": "image/png",
      "url_private": "https://files.slack.com/files-pri/...",
      "permalink": "https://workspace.slack.com/files/..."
    }
  ]
}
```

处理方案：

```bash
# 方案1: 仅显示文件信息 (默认)
format_files_info() {
    local files_json="$1"
    echo "$files_json" | jq -r '.[] | "  📎 [\(.name)] (\(.mimetype)) - \(.permalink)"'
}

# 输出示例:
# 📎 [screenshot.png] (image/png) - https://workspace.slack.com/files/...
# 📎 [document.pdf] (application/pdf) - https://workspace.slack.com/files/...
```

```bash
# 方案2: 下载文件到本地 (可选参数 --download-files)
download_files() {
    local files_json="$1"
    local output_dir="$2"
    
    mkdir -p "$output_dir/attachments"
    
    echo "$files_json" | jq -c '.[]' | while read -r file; do
        local filename=$(echo "$file" | jq -r '.name')
        local url=$(echo "$file" | jq -r '.url_private')
        
        curl -sL -H "Authorization: Bearer $SLACK_TOKEN" \
             -o "$output_dir/attachments/$filename" "$url"
        echo "  📥 Downloaded: $filename"
    done
}
```

#### D. 特殊提及处理

```bash
convert_special_mentions() {
    local text="$1"
    text=$(echo "$text" | sed 's/<!here>/@here/g')
    text=$(echo "$text" | sed 's/<!channel>/@channel/g')
    text=$(echo "$text" | sed 's/<!everyone>/@everyone/g')
    echo "$text"
}
```

#### E. 完整消息处理流程

```bash
process_message() {
    local message_json="$1"
    local format="$2"
    
    # 1. 提取基础信息
    local user_id=$(echo "$message_json" | jq -r '.user')
    local text=$(echo "$message_json" | jq -r '.text // ""')
    local ts=$(echo "$message_json" | jq -r '.ts')
    local files=$(echo "$message_json" | jq '.files // []')
    
    # 2. 转换时间戳
    local datetime=$(date -r "${ts%.*}" "+%Y-%m-%d %H:%M:%S")
    
    # 3. 获取用户名
    local username=$(get_username "$user_id")
    
    # 4. 处理消息文本
    text=$(convert_user_mentions "$text")
    text=$(convert_channel_mentions "$text")
    text=$(convert_links "$text" "$format")
    text=$(convert_special_mentions "$text")
    
    # 5. 可选: 转换 mrkdwn 到标准 Markdown
    if [ "$format" = "markdown" ]; then
        text=$(convert_mrkdwn_to_markdown "$text")
    fi
    
    # 6. 输出格式化消息
    printf "[@%s] %s\n%s\n" "$username" "$datetime" "$text"
    
    # 7. 处理附件文件
    if [ "$(echo "$files" | jq 'length')" -gt 0 ]; then
        printf "\n  Attachments:\n"
        format_files_info "$files"
    fi
    
    printf "\n"
}
```

---

## 命令行参数设计

```bash
slack-thread-dump [OPTIONS] <THREAD_URL>

OPTIONS:
    -o, --output FILE        输出文件名 (默认: {thread_ts}.txt)
    -f, --format FORMAT      输出格式: text, markdown (默认: text)
    -t, --token TOKEN        Slack User Token (或使用 $SLACK_TOKEN)
    --download-files         下载附件文件到本地
    
    --raw                    保留原始 mrkdwn 格式不转换
    -v, --verbose            显示详细进度
    -h, --help               显示帮助
    --version                显示版本
```

---

## 输出格式示例

### Text 格式 (默认)

```
################################################################################
# SLACK THREAD: C0123456789-1702800000.000000
################################################################################
Channel: #engineering (C0123456789)
Thread Started: 2025-12-15 10:00:00

--- PARTICIPANTS (3) ---
- @john.doe (John Doe)
- @jane.smith (Jane Smith)  
- @bot.assistant (Bot Assistant) [BOT]

--- CONVERSATION ---

[@john.doe] 2025-12-15 10:00:00
Hey @jane.smith, can you review this PR?
Link: GitHub PR #123 (https://github.com/org/repo/pull/123)

  Attachments:
  📎 [screenshot.png] (image/png) - https://files.slack.com/...

---

[@jane.smith] 2025-12-15 10:05:00
> can you review this PR?
Sure! Looking at it now. Here's my initial feedback:

```python
# This could be simplified
def process(data):
    return [x for x in data if x.valid]
```

---

[@john.doe] 2025-12-15 10:10:00
Thanks! 👍 I'll update the code.
```

### Markdown 格式

```markdown
# Slack Thread: C0123456789-1702800000.000000

**Channel:** #engineering (C0123456789)  
**Thread Started:** 2025-12-15 10:00:00

## 👥 Participants (3)
- @john.doe (John Doe)
- @jane.smith (Jane Smith)
- @bot.assistant (Bot Assistant) 🤖

## 💬 Conversation

### [@john.doe] 2025-12-15 10:00:00
Hey @jane.smith, can you review this PR?
Link: [GitHub PR #123](https://github.com/org/repo/pull/123)

**Attachments:**
- 📎 [screenshot.png](https://files.slack.com/...) (image/png)

---

### [@jane.smith] 2025-12-15 10:05:00
> can you review this PR?

Sure! Looking at it now. Here's my initial feedback:

```python
# This could be simplified  
def process(data):
    return [x for x in data if x.valid]
```
```

---

## 文件结构

```
slack-thread-dump/
├── slack-thread-dump.sh    # 主脚本
├── install.sh              # 安装脚本  
├── README.md               # 英文文档
├── README_CN.md            # 中文文档
├── CHANGELOG.md            # 更新日志
├── LICENSE                 # MIT 许可证
└── homebrew/
    └── slack-thread-dump.rb  # Homebrew formula
```

---

## 用户认证说明

### 获取 Slack User Token

1. 访问 https://api.slack.com/apps
2. 创建新 App 或使用现有 App
3. 在 OAuth & Permissions 中添加以下 User Token Scopes:
   - `channels:history` - 读取公开频道消息
   - `groups:history` - 读取私有频道消息
   - `im:history` - 读取私信消息
   - `mpim:history` - 读取群私信消息
   - `users:read` - 读取用户信息
   - `files:read` - 读取文件信息（如需下载附件）
4. 安装 App 到 Workspace
5. 复制 User OAuth Token (以 `xoxp-` 开头)

### Token 配置方式

```bash
# 方式1: 环境变量
export SLACK_TOKEN="xoxp-your-token-here"
slack-thread-dump <url>

# 方式2: 配置文件
mkdir -p ~/.slack-thread-dump
echo "SLACK_TOKEN=xoxp-your-token-here" > ~/.slack-thread-dump/config
chmod 600 ~/.slack-thread-dump/config
slack-thread-dump <url>

# 方式3: 命令行参数
slack-thread-dump --token "xoxp-your-token-here" <url>
```

---

## 实现优先级

1. ✅ 基础框架：参数解析、帮助信息、版本信息
2. ✅ Token 认证：环境变量 + 配置文件 + 命令行参数
3. ✅ URL 解析：支持两种 Slack URL 格式
4. ✅ API 调用：conversations.replies + users.info
5. ✅ 消息格式化：用户引用、链接、特殊提及
6. ✅ 文件附件：显示文件信息
7. ✅ 输出格式：text + markdown
8. ⬜ 可选功能：--download-files 下载附件
9. ⬜ 安装脚本：install.sh + Homebrew formula

---

## 使用示例

```bash
# 基本用法
slack-thread-dump "https://app.slack.com/client/T.../C.../thread/C...-1234567890.123456"

# 指定输出文件和格式
slack-thread-dump -o conversation.md -f markdown "<thread_url>"

# 详细模式
slack-thread-dump -v "<thread_url>"

# 包含 bot 消息
slack-thread-dump "<thread_url>"

# 下载附件
slack-thread-dump --download-files "<thread_url>"
```
