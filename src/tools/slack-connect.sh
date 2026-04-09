#!/usr/bin/env bash
# GTMOps: Slack Connect API wrapper
# Usage: SlackConnect.sh <command> [options]
#
# Commands:
#   create-channel    Create a new channel
#   invite-shared     Send Slack Connect invite to external email
#   rename-channel    Rename an existing channel
#   list-channels     List workspace channels
#   get-channel       Get channel info
#
# GOTCHAS BAKED IN:
#   - invite-shared works on EXISTING channels (not just new ones)
#   - Invite lands in whatever workspace owns the target email
#   - Single Channel Guests require Enterprise Grid for API access
#   - conversations.inviteShared requires Pro+ plan
#   - Bot needs: channels:manage, groups:write, conversations.connect:write scopes

set -euo pipefail

# Show help without requiring API keys
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n '2,/^[^#]/{ /^#/s/^# \{0,1\}//p; }' "$0"
  exit 0
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GTMOPS_DIR="${GTMOPS_DIR:-$(dirname "$(dirname "$SCRIPT_DIR")")}"

# Load API key
if [[ -f "$GTMOPS_DIR/.env" ]]; then
  SLACK_BOT_TOKEN="${SLACK_BOT_TOKEN:-$(grep '^SLACK_BOT_TOKEN=' "$GTMOPS_DIR/.env" | cut -d'=' -f2-)}"
fi

if [[ -z "${SLACK_BOT_TOKEN:-}" ]]; then
  echo "Error: SLACK_BOT_TOKEN not set in environment or $GTMOPS_DIR/.env" >&2
  exit 1
fi

BASE_URL="https://slack.com/api"
DRY_RUN=false

ARGS=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --help|-h) COMMAND="help" ;;
    *) ARGS+=("$arg") ;;
  esac
done

COMMAND="${COMMAND:-${ARGS[0]:-help}}"
if [[ ${#ARGS[@]} -gt 1 ]]; then
  ARGS=("${ARGS[@]:1}")
else
  ARGS=()
fi

api_call() {
  local method="$1" endpoint="$2" data="${3:-}"
  local url="${BASE_URL}/${endpoint}"
  local cmd=(curl -sS -X "$method" "$url" -H "Authorization: Bearer $SLACK_BOT_TOKEN" -H "Content-Type: application/json; charset=utf-8")

  if [[ -n "$data" ]]; then
    cmd+=(-d "$data")
  fi

  if $DRY_RUN; then
    echo "${cmd[@]}"
    return 0
  fi

  local response
  response=$("${cmd[@]}" 2>&1)
  local exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    echo "API call failed: $response" >&2
    return 1
  fi

  # Check Slack API ok field
  local ok
  ok=$(echo "$response" | jq -r '.ok // "false"')
  if [[ "$ok" != "true" ]]; then
    local error
    error=$(echo "$response" | jq -r '.error // "unknown error"')
    echo "Slack API error: $error" >&2
    echo "$response" >&2
    return 1
  fi

  echo "$response"
}

parse_kv_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --*)
        local key="${1#--}"
        key="${key//-/_}"
        shift
        eval "ARG_${key}=\"${1:-}\""
        shift
        ;;
      *) shift ;;
    esac
  done
}

case "$COMMAND" in
  create-channel)
    parse_kv_args "${ARGS[@]}"
    name="${ARG_name:?--name required (e.g. user-acmecorp)}"
    is_private="${ARG_private:-false}"

    json=$(jq -n \
      --arg name "$name" \
      --argjson private "$is_private" \
      '{name: $name, is_private: $private}')

    api_call POST "conversations.create" "$json"
    ;;

  invite-shared)
    # Send Slack Connect invite to external email
    # Works on existing channels
    # Requires: conversations.connect:write scope
    parse_kv_args "${ARGS[@]}"
    channel="${ARG_channel:?--channel required (channel ID)}"
    email="${ARG_email:?--email required (external email to invite)}"

    json=$(jq -n \
      --arg channel "$channel" \
      --arg email "$email" \
      '{channel: $channel, emails: [$email]}')

    api_call POST "conversations.inviteShared" "$json"
    ;;

  rename-channel)
    parse_kv_args "${ARGS[@]}"
    channel="${ARG_channel:?--channel required}"
    name="${ARG_name:?--name required}"

    json=$(jq -n \
      --arg channel "$channel" \
      --arg name "$name" \
      '{channel: $channel, name: $name}')

    api_call POST "conversations.rename" "$json"
    ;;

  list-channels)
    parse_kv_args "${ARGS[@]}"
    limit="${ARG_limit:-100}"
    types="${ARG_types:-public_channel,private_channel}"

    api_call GET "conversations.list?limit=$limit&types=$types"
    ;;

  get-channel)
    parse_kv_args "${ARGS[@]}"
    channel="${ARG_channel:?--channel required}"

    api_call GET "conversations.info?channel=$channel"
    ;;

  help|*)
    cat <<'USAGE'
Slack Connect API wrapper (GTMOps)

Usage: SlackConnect.sh <command> [--dry-run] [options]

Commands:
  create-channel    --name NAME [--private true/false]
  invite-shared     --channel CHANNEL_ID --email EMAIL
  rename-channel    --channel CHANNEL_ID --name NEW_NAME
  list-channels     [--limit N] [--types "public_channel,private_channel"]
  get-channel       --channel CHANNEL_ID

Flags:
  --dry-run    Print curl command without executing
  --help       Show this help

GOTCHAS:
  - invite-shared works on existing channels (not just new ones)
  - Invite lands in whatever workspace owns the target email
  - Single Channel Guests require Enterprise Grid (not automatable on Pro)
  - Requires scopes: channels:manage, groups:write, conversations.connect:write
USAGE
    ;;
esac
