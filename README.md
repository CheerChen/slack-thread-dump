# slack-thread-dump

Command-line helper to export a full Slack thread into text or Markdown. It mirrors the lightweight, pipe-friendly approach of `pr-dump`: rely on `curl` + `jq`, no heavy dependencies.

## Features

- Parse both `app.slack.com/client/.../thread/...` and archived `/archives/.../p...` URLs.
- Text or Markdown output with user/channel mention expansion, link cleanup, and optional mrkdwn-to-Markdown tweaks.
- Participant list with real names (when available).
- Attachment metadata listing, optional `--download-files` to `./attachments`.
- Token sourcing from CLI flag, `SLACK_TOKEN`, or `~/.slack-thread-dump/config`.

## Requirements

- Bash, `curl`, `jq`.
- Slack user token with scopes at least: `channels:history`, `groups:history`, `im:history`, `mpim:history`, `users:read`, `files:read` (for downloads).

## Install

### Quick copy

```bash
chmod +x slack-thread-dump.sh
cp slack-thread-dump.sh /usr/local/bin/slack-thread-dump   # sudo if needed
```

### install.sh helper

```bash
./install.sh                # installs to /usr/local/bin by default
PREFIX=$HOME/.local ./install.sh
```

## Usage

```bash
slack-thread-dump [OPTIONS] <THREAD_URL>

Options:
  -o, --output FILE        Output file name (default: {thread_ts}.txt)
  -f, --format FORMAT      text or markdown (default: text)
  -t, --token TOKEN        Slack user token (or use $SLACK_TOKEN)
      --download-files     Save attachments to ./attachments
      --raw                Keep Slack mrkdwn (skip Markdown tweaks)
  -v, --verbose            Verbose logging
  -h, --help               Show help
      --version            Show version
```

Examples:

```bash
slack-thread-dump "https://app.slack.com/client/T.../C.../thread/C...-1234567890.123456"
slack-thread-dump -f markdown -o conversation.md "<thread_url>"
slack-thread-dump --download-files "<thread_url>"
```

## Token configuration

1) Environment: `export SLACK_TOKEN="xoxp-your-token"`
2) Config file: create `~/.slack-thread-dump/config` with `SLACK_TOKEN=...` (chmod 600 recommended).
3) CLI: `--token xoxp-your-token` overrides the others.

## Output notes

- Headers include channel name, thread id, start time, and participants.
- Mentions become human-friendly (`<@U…>` -> `@username`, `<#C…>` -> `#channel`).
- Links are prettified; use `--raw` to keep Slack mrkdwn untouched.
- `--download-files` writes into `./attachments` beside your output file.

## Cache

User and channel lookups are cached under `${XDG_CACHE_HOME:-$HOME/.cache}/slack-thread-dump/`. Delete those files if you need to refresh names.

## License

MIT
