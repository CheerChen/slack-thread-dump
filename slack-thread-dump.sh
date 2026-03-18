#!/usr/bin/env bash
set -euo pipefail

VERSION="0.1.0"
CONFIG_FILE="${HOME}/.slack-thread-dump/config"
CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/slack-thread-dump"
USER_CACHE="${CACHE_DIR}/users.json"
CHANNEL_CACHE="${CACHE_DIR}/channels.json"

FORMAT="text"
OUTPUT_FILE=""
TOKEN_ARG=""
DOWNLOAD_FILES=0
RAW_MRKDWN=0
VERBOSE=0
THREAD_URL=""

usage() {
  cat <<'EOF'
Usage: slack-thread-dump [OPTIONS] <THREAD_URL>

Options:
  -o, --output FILE        Output file name (default: {thread_ts}.txt)
  -f, --format FORMAT      Output format: text, markdown (default: text)
  -t, --token TOKEN        Slack User Token (or use $SLACK_TOKEN)
      --download-files     Download attachments to ./attachments
      --raw                Keep original Slack mrkdwn (skip Markdown tweaks)
  -v, --verbose            Verbose logging
  -h, --help               Show this help
      --version            Show version
EOF
}

show_version() {
  echo "slack-thread-dump ${VERSION}"
}

log() {
  if [ "${VERBOSE}" -eq 1 ]; then
    echo "[slack-thread-dump] $*" >&2
  fi
}

die() {
  echo "Error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

ensure_cache() {
  mkdir -p "${CACHE_DIR}"
  [ -f "${USER_CACHE}" ] || echo "{}" >"${USER_CACHE}"
  [ -f "${CHANNEL_CACHE}" ] || echo "{}" >"${CHANNEL_CACHE}"
}

load_config() {
  if [ -f "${CONFIG_FILE}" ]; then
    # shellcheck disable=SC1090
    set -a
    . "${CONFIG_FILE}"
    set +a
  fi
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -o|--output)
        OUTPUT_FILE="$2"; shift 2;;
      -f|--format)
        FORMAT="$2"; shift 2;;
      -t|--token)
        TOKEN_ARG="$2"; shift 2;;
      --download-files)
        DOWNLOAD_FILES=1; shift 1;;
      --raw)
        RAW_MRKDWN=1; shift 1;;
      -v|--verbose)
        VERBOSE=1; shift 1;;
      -h|--help)
        usage; exit 0;;
      --version)
        show_version; exit 0;;
      --)
        shift; break;;
      -*)
        die "Unknown option: $1";;
      *)
        THREAD_URL="$1"; shift 1;;
    esac
  done

  if [ -z "${THREAD_URL}" ]; then
    usage
    exit 1
  fi

  if [ "${FORMAT}" != "text" ] && [ "${FORMAT}" != "markdown" ]; then
    die "Invalid format: ${FORMAT}. Use text or markdown."
  fi
}

parse_thread_url() {
  local url="$1"
  CHANNEL_ID=""
  THREAD_TS=""

  if [[ "${url}" =~ /client/[^/]+/([A-Z0-9]+)/thread/[^/-]+-([0-9]+\.[0-9]+) ]]; then
    CHANNEL_ID="${BASH_REMATCH[1]}"
    THREAD_TS="${BASH_REMATCH[2]}"
    return 0
  fi

  if [[ "${url}" =~ /archives/([A-Z0-9]+)/p([0-9]{16,}) ]]; then
    CHANNEL_ID="${BASH_REMATCH[1]}"
    local raw_ts="${BASH_REMATCH[2]}"
    local query_ts
    query_ts=$(echo "${url}" | sed -n 's/.*[?&]thread_ts=\([0-9]\+\.[0-9]\+\).*/\1/p')
    if [ -n "${query_ts}" ]; then
      THREAD_TS="${query_ts}"
    else
      THREAD_TS="${raw_ts:0:10}.${raw_ts:10:6}"
    fi
    return 0
  fi

  die "Unsupported Slack thread URL: ${url}"
}

slack_api() {
  local method="$1"
  local data="$2"
  log "API request: ${method} ${data}"
  local resp
  resp=$(curl -sS -H "Authorization: Bearer ${SLACK_TOKEN}" \
               -H "Content-Type: application/x-www-form-urlencoded" \
               --data "${data}" "https://slack.com/api/${method}" || true)
  [ -z "${resp}" ] && die "Slack API ${method} failed: empty response"
  local ok
  ok=$(echo "${resp}" | jq -r '.ok // false')
  if [ "${ok}" != "true" ]; then
    local err
    err=$(echo "${resp}" | jq -r '.error // "unknown_error"')
    local needed provided
    needed=$(echo "${resp}" | jq -r '.needed // ""')
    provided=$(echo "${resp}" | jq -r '.provided // ""')
    if [ "${VERBOSE}" -eq 1 ]; then
      echo "Slack API ${method} failed (params: ${data})" >&2
      echo "Response: ${resp}" >&2
    fi
    if [ "${err}" = "missing_scope" ]; then
      local channel_param channel_hint=""
      channel_param=$(echo "${data}" | sed -n 's/.*channel=\([^&]*\).*/\1/p')
      if [[ "${channel_param}" =~ ^C ]]; then
        channel_hint="Add channels:history (public channel threads) or groups:history if it is private."
      elif [[ "${channel_param}" =~ ^G ]]; then
        channel_hint="Add groups:history (private channel threads)."
      fi
      local msg="Slack API ${method} failed: ${err}"
      [ -n "${needed}" ] && msg="${msg} (needed: ${needed})"
      [ -n "${provided}" ] && msg="${msg} (provided: ${provided})"
      [ -n "${channel_hint}" ] && msg="${msg}. ${channel_hint}"
      die "${msg}"
    fi
    die "Slack API ${method} failed: ${err}"
  fi
  echo "${resp}"
}

get_user_data() {
  local uid="$1"
  ensure_cache
  local cached
  cached=$(jq -c --arg uid "${uid}" '.[$uid] // empty' "${USER_CACHE}")
  if [ -n "${cached}" ]; then
    echo "${cached}"
    return
  fi

  log "Fetching user info for ${uid}"
  local resp
  resp=$(slack_api "users.info" "user=${uid}") || {
    echo "{\"id\":\"${uid}\",\"name\":\"${uid}\",\"display_name\":\"${uid}\",\"real_name\":\"${uid}\",\"is_bot\":false}"
    return
  }
  local data
  data=$(echo "${resp}" | jq -c '{
    id: .user.id,
    name: (.user.name // ""),
    display_name: (.user.profile.display_name_normalized // .user.profile.real_name_normalized // .user.real_name // .user.name // ""),
    real_name: (.user.profile.real_name_normalized // .user.real_name // ""),
    is_bot: (.user.is_bot // false)
  }')

  local tmp="${USER_CACHE}.tmp"
  jq --arg uid "${uid}" --argjson data "${data}" '. + {($uid): $data}' "${USER_CACHE}" >"${tmp}" && mv "${tmp}" "${USER_CACHE}"
  echo "${data}"
}

get_channel_name() {
  local cid="$1"
  ensure_cache
  local cached
  cached=$(jq -r --arg cid "${cid}" '.[$cid].name // empty' "${CHANNEL_CACHE}")
  if [ -n "${cached}" ]; then
    echo "${cached}"
    return
  fi

  log "Fetching channel info for ${cid}"
  local resp
  resp=$(slack_api "conversations.info" "channel=${cid}") || {
    echo "${cid}"
    return
  }
  local name
  name=$(echo "${resp}" | jq -r '.channel.name // "'${cid}'"')
  local data
  data=$(echo "${resp}" | jq -c '{name: (.channel.name // ""), is_private: (.channel.is_private // false)}')
  local tmp="${CHANNEL_CACHE}.tmp"
  jq --arg cid "${cid}" --argjson data "${data}" '. + {($cid): $data}' "${CHANNEL_CACHE}" >"${tmp}" && mv "${tmp}" "${CHANNEL_CACHE}"
  echo "${name}"
}

convert_special_mentions() {
  echo "$1" | sed -e 's/<!here>/@here/g' \
                  -e 's/<!channel>/@channel/g' \
                  -e 's/<!everyone>/@everyone/g'
}

convert_user_mentions() {
  local text="$1"
  local ids
  ids=$(echo "${text}" | grep -oE '<@U[A-Z0-9]+([|][^>]+)?>' || true)
  ids=$(echo "${ids}" | sed 's/<@//g;s/>//g;s/|.*//g' | sort -u || true)

  for uid in ${ids}; do
    [ -z "${uid}" ] && continue
    local user_json username escaped_username
    user_json=$(get_user_data "${uid}")
    username=$(echo "${user_json}" | jq -r '.display_name // .name // "'${uid}'"')
    escaped_username=$(printf '%s\n' "${username}" | sed 's/[&/]/\\&/g')
    text=$(echo "${text}" | sed -E "s/<@${uid}[^>]*>/@${escaped_username}/g")
  done
  echo "${text}"
}

convert_channel_mentions() {
  local text="$1"
  local matches
  matches=$(echo "${text}" | grep -oE '<#C[A-Z0-9]+\|[^>]+>|<#C[A-Z0-9]+>' || true)
  matches=$(echo "${matches}" | sort -u || true)

  while read -r match; do
    [ -z "${match}" ] && continue
    local inner cid name
    inner="${match#<#}"
    inner="${inner%>}"
    if [[ "${inner}" == *"|"* ]]; then
      cid="${inner%%|*}"
      name="${inner#*|}"
    else
      cid="${inner}"
      name=""
    fi
    [ -z "${name}" ] && name=$(get_channel_name "${cid}")
    text=${text//${match}/#${name}}
    text=${text//<#${cid}>/#${name}}
  done <<< "${matches}"

  echo "${text}"
}

convert_links() {
  local text="$1"
  local fmt="$2"
  if [ "${fmt}" = "markdown" ]; then
    text=$(echo "${text}" | sed -E 's#<(https?://[^|>]+)\|([^>]+)>#[\2](\1)#g')
  else
    text=$(echo "${text}" | sed -E 's#<(https?://[^|>]+)\|([^>]+)>#\2 (\1)#g')
  fi
  text=$(echo "${text}" | sed -E 's#<(https?://[^>]+)>#\1#g')
  echo "${text}"
}

convert_mrkdwn_to_markdown() {
  local text="$1"
  text=$(echo "${text}" | sed -E 's/\*([^*]+)\*/**\1**/g')
  text=$(echo "${text}" | sed -E 's/_([^_]+)_/*\1*/g')
  text=$(echo "${text}" | sed -E 's/~([^~]+)~/~~\1~~/g')
  echo "${text}"
}

format_files_info() {
  local files_json="$1"
  echo "${files_json}" | jq -r '.[] | "  📎 [\(.name)] (\(.mimetype // "unknown")) - \(.permalink // .url_private // "n/a")"'
}

download_files() {
  local files_json="$1"
  local output_dir="$2"
  mkdir -p "${output_dir}/attachments"
  echo "${files_json}" | jq -c '.[]' | while read -r file; do
    local filename url
    filename=$(echo "${file}" | jq -r '.name // "attachment"')
    url=$(echo "${file}" | jq -r '.url_private // empty')
    [ -z "${url}" ] && continue
    log "Downloading ${filename}"
    if curl -sSL -H "Authorization: Bearer ${SLACK_TOKEN}" -o "${output_dir}/attachments/${filename}" "${url}"; then
      echo "  📥 Downloaded: ${filename}" >&2
    else
      echo "  ⚠️ Failed to download: ${filename}" >&2
    fi
  done
}

format_ts() {
  local ts="$1"
  date -r "${ts%.*}" "+%Y-%m-%d %H:%M:%S"
}

fetch_thread_messages() {
  local channel="$1"
  local thread_ts="$2"
  local cursor=""
  local combined="[]"

  while true; do
    local data="channel=${channel}&ts=${thread_ts}&limit=200&inclusive=true"
    [ -n "${cursor}" ] && data="${data}&cursor=${cursor}"
    local resp
    resp=$(slack_api "conversations.replies" "${data}")
    local msgs
    msgs=$(echo "${resp}" | jq '.messages // []')
    combined=$(jq -s 'add' <(echo "${combined}") <(echo "${msgs}"))
    cursor=$(echo "${resp}" | jq -r '.response_metadata.next_cursor // ""')
    [ -z "${cursor}" ] && break
  done

  echo "${combined}"
}

extract_participants() {
  echo "$1" | jq -r 'map(select(.user != null)) | .[].user' | sort -u
}

render_header() {
  local channel_id="$1"
  local channel_name="$2"
  local thread_ts="$3"
  local first_ts="$4"
  local participant_lines="$5"
  local participants_count="$6"

  if [ "${FORMAT}" = "markdown" ]; then
    cat <<EOF
# Slack Thread: ${channel_id}-${thread_ts}

**Channel:** #${channel_name:-${channel_id}} (${channel_id})
**Thread Started:** ${first_ts}

## 👥 Participants (${participants_count})
${participant_lines}

## 💬 Conversation

EOF
  else
    cat <<EOF
################################################################################
# SLACK THREAD: ${channel_id}-${thread_ts}
################################################################################
Channel: #${channel_name:-${channel_id}} (${channel_id})
Thread Started: ${first_ts}

--- PARTICIPANTS (${participants_count}) ---
${participant_lines}

--- CONVERSATION ---

EOF
  fi
}

format_participants_lines() {
  local participants="$1"
  local lines=""
  while read -r uid; do
    [ -z "${uid}" ] && continue
    local user_json username real_name is_bot
    user_json=$(get_user_data "${uid}")
    username=$(echo "${user_json}" | jq -r '.display_name // .name // "'${uid}'"')
    real_name=$(echo "${user_json}" | jq -r '.real_name // ""')
    is_bot=$(echo "${user_json}" | jq -r '.is_bot // false')
    local label="@${username}"
    [ -n "${real_name}" ] && label="${label} (${real_name})"
    [ "${is_bot}" = "true" ] && label="${label} [BOT]"
    lines="${lines}- ${label}\n"
  done <<< "${participants}"
  printf "%b" "${lines}"
}

render_message() {
  local msg_json="$1"
  local channel_name="$2"
  local text ts files user_id bot_name username display_name label

  text=$(echo "${msg_json}" | jq -r '.text // ""')
  ts=$(echo "${msg_json}" | jq -r '.ts')
  files=$(echo "${msg_json}" | jq '.files // []')
  user_id=$(echo "${msg_json}" | jq -r '.user // empty')
  bot_name=$(echo "${msg_json}" | jq -r '.bot_profile.name // .username // empty')

  if [ -n "${user_id}" ]; then
    local user_json
    user_json=$(get_user_data "${user_id}")
    username=$(echo "${user_json}" | jq -r '.display_name // .name // "'${user_id}'"')
    display_name="@${username}"
  elif [ -n "${bot_name}" ]; then
    display_name="@${bot_name} [BOT]"
  else
    display_name="@unknown"
  fi

  local processed="${text}"
  processed=$(convert_special_mentions "${processed}")
  processed=$(convert_user_mentions "${processed}")
  processed=$(convert_channel_mentions "${processed}")
  processed=$(convert_links "${processed}" "${FORMAT}")
  if [ "${RAW_MRKDWN}" -eq 0 ] && [ "${FORMAT}" = "markdown" ]; then
    processed=$(convert_mrkdwn_to_markdown "${processed}")
  fi

  local human_time
  human_time=$(format_ts "${ts}")

  if [ "${FORMAT}" = "markdown" ]; then
    printf "### [%s] %s\n" "${display_name}" "${human_time}"
    printf "%s\n" "${processed}"
  else
    printf "[@%s] %s\n" "${display_name#@}" "${human_time}"
    printf "%s\n" "${processed}"
  fi

  local files_count
  files_count=$(echo "${files}" | jq 'length')
  if [ "${files_count}" -gt 0 ]; then
    if [ "${FORMAT}" = "markdown" ]; then
      echo
      echo "**Attachments:**"
      format_files_info "${files}" | sed 's/^/- /'
    else
      echo
      echo "  Attachments:"
      format_files_info "${files}"
    fi
    if [ "${DOWNLOAD_FILES}" -eq 1 ]; then
      download_files "${files}" "$(dirname "${OUTPUT_FILE}")"
    fi
  fi

  echo -e "\n---\n"
}

main() {
  parse_args "$@"
  load_config
  require_cmd curl
  require_cmd jq

  SLACK_TOKEN="${TOKEN_ARG:-${SLACK_TOKEN:-}}"
  [ -z "${SLACK_TOKEN:-}" ] && die "Slack token not provided. Use --token, \$SLACK_TOKEN, or ${CONFIG_FILE}."

  parse_thread_url "${THREAD_URL}"
  [ -z "${OUTPUT_FILE}" ] && OUTPUT_FILE="${THREAD_TS}.txt"

  log "Channel: ${CHANNEL_ID}, Thread TS: ${THREAD_TS}"
  local messages
  messages=$(fetch_thread_messages "${CHANNEL_ID}" "${THREAD_TS}")

  local first_ts
  first_ts=$(echo "${messages}" | jq -r '.[0].ts // empty')
  [ -z "${first_ts}" ] && die "No messages found in thread."

  local start_time
  start_time=$(format_ts "${first_ts}")
  local channel_name
  channel_name=$(get_channel_name "${CHANNEL_ID}")
  local participants participant_lines
  participants=$(extract_participants "${messages}")
  participant_lines=$(format_participants_lines "${participants}")

  mkdir -p "$(dirname "${OUTPUT_FILE}")"
  : > "${OUTPUT_FILE}"

  render_header "${CHANNEL_ID}" "${channel_name}" "${THREAD_TS}" "${start_time}" "${participant_lines}" "$(echo "${participants}" | grep -c . || true)" >> "${OUTPUT_FILE}"

  echo "${messages}" | jq -c '.[]' | while read -r msg; do
    render_message "${msg}" "${channel_name}" >> "${OUTPUT_FILE}"
  done

  log "Saved to ${OUTPUT_FILE}"
}

main "$@"
