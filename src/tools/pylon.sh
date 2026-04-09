#!/usr/bin/env bash
# GTMOps: Pylon API wrapper
# Usage: Pylon.sh <command> [options]
#
# Commands:
#   list-accounts     List Pylon accounts
#   get-account       Get account details
#   link-channel      Link a Slack channel to a Pylon account
#   list-issues       List issues (optionally filtered by account)
#   get-issue         Get issue details
#   list-conversations List conversations
#
# GOTCHAS BAKED IN:
#   - Pylon does NOT create Slack channels (only links existing ones)
#   - Pylon is source of truth for channel existence
#   - Issues undercount engagement; Slack conversations.history is better signal
#   - Account may not exist yet for new signups

set -euo pipefail

# Show help without requiring API keys
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n '2,/^[^#]/{ /^#/s/^# \{0,1\}//p; }' "$0"
  exit 0
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GTMOPS_DIR="${GTMOPS_DIR:-$(dirname "$(dirname "$SCRIPT_DIR")")}"

if [[ -f "$GTMOPS_DIR/.env" ]]; then
  PYLON_API_KEY="${PYLON_API_KEY:-$(grep '^PYLON_API_KEY=' "$GTMOPS_DIR/.env" | cut -d'=' -f2-)}"
fi

if [[ -z "${PYLON_API_KEY:-}" ]]; then
  echo "Error: PYLON_API_KEY not set in environment or $GTMOPS_DIR/.env" >&2
  exit 1
fi

BASE_URL="https://api.usepylon.com"
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
  local url="${BASE_URL}${endpoint}"
  local cmd=(curl -sS -X "$method" "$url" -H "Authorization: Bearer $PYLON_API_KEY" -H "Content-Type: application/json")

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
  list-accounts)
    parse_kv_args "${ARGS[@]}"
    api_call GET "/accounts"
    ;;

  get-account)
    parse_kv_args "${ARGS[@]}"
    id="${ARG_id:?--id required}"
    api_call GET "/accounts/$id"
    ;;

  link-channel)
    # GOTCHA: Pylon does NOT create channels. Channel must already exist in Slack.
    parse_kv_args "${ARGS[@]}"
    account_id="${ARG_account_id:?--account-id required}"
    channel_id="${ARG_channel_id:?--channel-id required (Slack channel ID)}"

    json=$(jq -n \
      --arg account "$account_id" \
      --arg channel "$channel_id" \
      '{account_id: $account, slack_channel_id: $channel}')

    api_call POST "/accounts/$account_id/channels" "$json"
    ;;

  list-issues)
    parse_kv_args "${ARGS[@]}"
    endpoint="/issues"
    [[ -n "${ARG_account_id:-}" ]] && endpoint="/accounts/${ARG_account_id}/issues"
    api_call GET "$endpoint"
    ;;

  get-issue)
    parse_kv_args "${ARGS[@]}"
    id="${ARG_id:?--id required}"
    api_call GET "/issues/$id"
    ;;

  list-conversations)
    parse_kv_args "${ARGS[@]}"
    endpoint="/conversations"
    [[ -n "${ARG_account_id:-}" ]] && endpoint="/accounts/${ARG_account_id}/conversations"
    api_call GET "$endpoint"
    ;;

  help|*)
    cat <<'USAGE'
Pylon API wrapper (GTMOps)

Usage: Pylon.sh <command> [--dry-run] [options]

Commands:
  list-accounts
  get-account       --id ACCOUNT_ID
  link-channel      --account-id ID --channel-id SLACK_CHANNEL_ID
  list-issues       [--account-id ID]
  get-issue         --id ISSUE_ID
  list-conversations [--account-id ID]

Flags:
  --dry-run    Print curl command without executing
  --help       Show this help

GOTCHAS:
  - Pylon does NOT create Slack channels (only links existing channel IDs)
  - Pylon is source of truth for channel existence
  - Issues undercount engagement; use Slack conversations.history for better signal
  - Account may not exist yet for new signups
USAGE
    ;;
esac
