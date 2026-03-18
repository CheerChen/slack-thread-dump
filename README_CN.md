# slack-thread-dump

一个用 `curl` + `jq` 组合完成的轻量 CLI，用来把指定的 Slack Thread 导出为文本或 Markdown，设计思路类似 `pr-dump`。

## 功能
- 支持新版 `app.slack.com/client/.../thread/...` 链接和归档 `/archives/.../p...` 链接。
- 输出 text / markdown，可展开 @用户、#频道、链接，必要时把 mrkdwn 转为标准 Markdown。
- 输出参与者列表，默认过滤 bot（`--include-bots` 可取消）。
- 附件列表展示，`--download-files` 可下载到本地 `./attachments`。
- Token 来源：命令行 > `SLACK_TOKEN` 环境变量 > `~/.slack-thread-dump/config`。

## 依赖
- Bash、`curl`、`jq`
- Slack User Token，至少包含：`channels:history`、`groups:history`、`im:history`、`mpim:history`、`users:read`，如果要下载附件还需要 `files:read`

## 安装
### 直接复制
```bash
chmod +x slack-thread-dump.sh
cp slack-thread-dump.sh /usr/local/bin/slack-thread-dump   # 需要的话加 sudo
```

### install.sh
```bash
./install.sh                # 默认安装到 /usr/local/bin
PREFIX=$HOME/.local ./install.sh
```


## 使用方法
```bash
slack-thread-dump [OPTIONS] <THREAD_URL>

Options:
  -o, --output FILE        输出文件名 (默认: {thread_ts}.txt)
  -f, --format FORMAT      text 或 markdown (默认 text)
  -t, --token TOKEN        Slack User Token (或使用 $SLACK_TOKEN)
      --download-files     下载附件到 ./attachments
      --include-bots       包含 bot 消息（默认过滤）
      --raw                保留原始 mrkdwn，不做 Markdown 转换
  -v, --verbose            打印更多日志
  -h, --help               查看帮助
      --version            查看版本
```

示例：
```bash
slack-thread-dump "https://app.slack.com/client/T.../C.../thread/C...-1234567890.123456"
slack-thread-dump -f markdown -o conversation.md "<thread_url>"
SLACK_TOKEN=xoxp-*** slack-thread-dump --include-bots "<thread_url>"
slack-thread-dump --download-files "<thread_url>"
```

## Token 配置
1) 环境变量：`export SLACK_TOKEN="xoxp-your-token"`  
2) 配置文件：`~/.slack-thread-dump/config` 中写 `SLACK_TOKEN=...`（建议 `chmod 600`）  
3) 命令行：`--token` 会覆盖前面两种方式

## 输出说明
- 头部包含频道、Thread ID、开始时间、参与者列表。
- 提及格式会被展开（`<@U…>` -> `@username`，`<#C…>` -> `#channel`）。
- 链接会被转换；如要保留原始 mrkdwn，使用 `--raw`。
- `--download-files` 会把附件存到输出文件同级的 `attachments` 目录。

## 缓存
用户和频道查询结果缓存在 `${XDG_CACHE_HOME:-$HOME/.cache}/slack-thread-dump/`，删除即可强制重新拉取。

## 许可证
MIT
