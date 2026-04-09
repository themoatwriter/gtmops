#!/usr/bin/env bash
# GTMOps: Bigin (Zoho) CRM API wrapper
# Usage: Bigin.sh <command> [options]
#
# Commands:
#   list-deals        List deals (with optional pipeline/stage filter)
#   get-deal          Get a single deal
#   create-deal       Create a new deal
#   update-deal       Update deal fields
#   update-stage      Move deal to a new stage
#   list-contacts     List contacts
#   get-contact       Get a single contact
#   create-contact    Create a new contact
#   search            Search records by criteria
#   token-refresh     Refresh the OAuth access token
#
# GOTCHAS BAKED IN:
#   - Bigin uses OAuth2 with refresh tokens. Access token expires every hour.
#   - First call: use grant token to get refresh + access tokens, then use refresh token going forward
#   - Module names are case-sensitive: "Deals", "Contacts", "Pipelines"
#   - Stage updates use the same update-deal endpoint, just set Pipeline_Stage
#   - Rate limit: 100 requests per minute per org

set -euo pipefail

# Show help without requiring API keys
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n '2,/^[^#]/{ /^#/s/^# \{0,1\}//p; }' "$0"
  exit 0
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GTMOPS_DIR="${GTMOPS_DIR:-$(dirname "$(dirname "$SCRIPT_DIR")")}"

if [[ -f "$GTMOPS_DIR/.env" ]]; then
  BIGIN_CLIENT_ID="${BIGIN_CLIENT_ID:-$(grep '^BIGIN_CLIENT_ID=' "$GTMOPS_DIR/.env" | cut -d'=' -f2-)}"
  BIGIN_CLIENT_SECRET="${BIGIN_CLIENT_SECRET:-$(grep '^BIGIN_CLIENT_SECRET=' "$GTMOPS_DIR/.env" | cut -d'=' -f2-)}"
  BIGIN_REFRESH_TOKEN="${BIGIN_REFRESH_TOKEN:-$(grep '^BIGIN_REFRESH_TOKEN=' "$GTMOPS_DIR/.env" | cut -d'=' -f2-)}"
  BIGIN_ACCESS_TOKEN="${BIGIN_ACCESS_TOKEN:-$(grep '^BIGIN_ACCESS_TOKEN=' "$GTMOPS_DIR/.env" | cut -d'=' -f2-)}"
fi

if [[ -z "${BIGIN_CLIENT_ID:-}" ]]; then
  echo "Error: BIGIN_CLIENT_ID not set in environment or $GTMOPS_DIR/.env" >&2
  exit 1
fi

BASE_URL="https://www.zohoapis.com/bigin/v2"
TOKEN_URL="https://accounts.zoho.com/oauth/v2/token"
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

refresh_token() {
  local response
  response=$(curl -sS -X POST "$TOKEN_URL" \
    -d "refresh_token=$BIGIN_REFRESH_TOKEN" \
    -d "client_id=$BIGIN_CLIENT_ID" \
    -d "client_secret=$BIGIN_CLIENT_SECRET" \
    -d "grant_type=refresh_token" 2>&1)

  local token
  token=$(echo "$response" | jq -r '.access_token // empty')

  if [[ -z "$token" ]]; then
    echo "Token refresh failed: $response" >&2
    return 1
  fi

  BIGIN_ACCESS_TOKEN="$token"
  echo "$response"
}

api_call() {
  local method="$1" endpoint="$2" data="${3:-}"

  # Auto-refresh if no access token
  if [[ -z "${BIGIN_ACCESS_TOKEN:-}" ]]; then
    refresh_token >/dev/null || return 1
  fi

  local url="${BASE_URL}${endpoint}"
  local cmd=(curl -sS -X "$method" "$url" -H "Authorization: Zoho-oauthtoken $BIGIN_ACCESS_TOKEN" -H "Content-Type: application/json")

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

  # Check for INVALID_TOKEN and auto-refresh
  local code
  code=$(echo "$response" | jq -r '.code // empty')
  if [[ "$code" == "INVALID_TOKEN" ]]; then
    refresh_token >/dev/null || return 1
    cmd[7]="Authorization: Zoho-oauthtoken $BIGIN_ACCESS_TOKEN"
    response=$("${cmd[@]}" 2>&1)
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
  list-deals)
    parse_kv_args "${ARGS[@]}"
    fields="${ARG_fields:-Deal_Name,Stage,Amount,Contact_Name}"
    limit="${ARG_limit:-20}"

    endpoint="/Deals?fields=$fields&per_page=$limit"
    api_call GET "$endpoint"
    ;;

  get-deal)
    parse_kv_args "${ARGS[@]}"
    id="${ARG_id:?--id required}"

    api_call GET "/Deals/$id"
    ;;

  create-deal)
    parse_kv_args "${ARGS[@]}"
    json="${ARG_json:?--json required (deal record JSON)}"

    api_call POST "/Deals" "{\"data\": [$json]}"
    ;;

  update-deal)
    parse_kv_args "${ARGS[@]}"
    id="${ARG_id:?--id required}"
    json="${ARG_json:?--json required (fields to update)}"

    api_call PUT "/Deals" "{\"data\": [{\"id\": \"$id\", $json}]}"
    ;;

  update-stage)
    parse_kv_args "${ARGS[@]}"
    id="${ARG_id:?--id required}"
    stage="${ARG_stage:?--stage required}"

    json=$(jq -n --arg id "$id" --arg stage "$stage" '{data: [{id: $id, Pipeline_Stage: $stage}]}')
    api_call PUT "/Deals" "$json"
    ;;

  list-contacts)
    parse_kv_args "${ARGS[@]}"
    fields="${ARG_fields:-First_Name,Last_Name,Email,Phone,Company_Name}"
    limit="${ARG_limit:-20}"

    api_call GET "/Contacts?fields=$fields&per_page=$limit"
    ;;

  get-contact)
    parse_kv_args "${ARGS[@]}"
    id="${ARG_id:?--id required}"

    api_call GET "/Contacts/$id"
    ;;

  create-contact)
    parse_kv_args "${ARGS[@]}"
    json="${ARG_json:?--json required (contact record JSON)}"

    api_call POST "/Contacts" "{\"data\": [$json]}"
    ;;

  search)
    parse_kv_args "${ARGS[@]}"
    module="${ARG_module:?--module required (Deals, Contacts)}"
    criteria="${ARG_criteria:?--criteria required (e.g. 'Email:equals:john@acme.com')}"

    api_call GET "/$module/search?criteria=$criteria"
    ;;

  token-refresh)
    refresh_token
    ;;

  help|*)
    cat <<'USAGE'
Bigin (Zoho CRM) API wrapper (GTMOps)

Usage: Bigin.sh <command> [--dry-run] [options]

Commands:
  list-deals        [--fields F1,F2] [--limit N]
  get-deal          --id DEAL_ID
  create-deal       --json '{"Deal_Name": "...", ...}'
  update-deal       --id DEAL_ID --json '"Field": "value", ...'
  update-stage      --id DEAL_ID --stage "Connected"
  list-contacts     [--fields F1,F2] [--limit N]
  get-contact       --id CONTACT_ID
  create-contact    --json '{"First_Name": "...", ...}'
  search            --module Deals|Contacts --criteria "Field:equals:value"
  token-refresh     (refresh OAuth access token)

Flags:
  --dry-run    Print curl command without executing
  --help       Show this help

GOTCHAS:
  - OAuth2 with refresh tokens. Access token expires every hour.
  - Auto-refreshes on INVALID_TOKEN response.
  - Module names are case-sensitive: "Deals", "Contacts"
  - Stage updates use update-deal with Pipeline_Stage field
  - Rate limit: 100 req/min per org
  - Search criteria format: "Field:operator:value" (equals, contains, starts_with)
USAGE
    ;;
esac
