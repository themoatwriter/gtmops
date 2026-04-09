#!/usr/bin/env bash
# GTMOps: Instantly v2 API wrapper
# Usage: Instantly.sh <command> [options]
#
# Commands:
#   create-lead       Add a lead to a campaign or list
#   list-leads        List leads (filter by campaign or list)
#   get-lead          Get a single lead by UUID
#   update-lead       Update lead custom variables
#   create-campaign   Create a new campaign
#   list-campaigns    List all campaigns
#   get-campaign      Get campaign details
#   create-list       Create a new lead list
#   list-lists        List all lead lists
#   supersearch-count Count leads matching criteria (free)
#   supersearch-preview Preview leads matching criteria (free, no emails)
#   supersearch-enrich Enrich leads into a list (1 credit/lead)
#   list-emails       List sent emails for a campaign
#
# GOTCHAS BAKED IN:
#   - create-lead uses "campaign" param (NOT "campaign_id") for assignment
#   - supersearch keyword_filter.include is a STRING not array
#   - supersearch-preview returns names/titles only, NO emails
#   - supersearch-enrich needs a LEAD LIST ID, resource_type=1
#   - Use level + department instead of title.include (title returns 0)

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
  INSTANTLY_API_KEY="${INSTANTLY_API_KEY:-$(grep '^INSTANTLY_API_KEY=' "$GTMOPS_DIR/.env" | cut -d'=' -f2-)}"
fi

if [[ -z "${INSTANTLY_API_KEY:-}" ]]; then
  echo "Error: INSTANTLY_API_KEY not set in environment or $GTMOPS_DIR/.env" >&2
  exit 1
fi

BASE_URL="https://api.instantly.ai/api/v2"
DRY_RUN=false

# Parse global flags
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
  local cmd=(curl -sS -X "$method" "$url" -H "Authorization: Bearer $INSTANTLY_API_KEY" -H "Content-Type: application/json")

  if [[ -n "$data" ]]; then
    cmd+=(-d "$data")
  fi

  if $DRY_RUN; then
    echo "${cmd[@]}" ${data:+-d "$data"}
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
  # Parse --key value pairs into variables
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
  create-lead)
    # GOTCHA: Use "campaign" not "campaign_id" for assignment
    parse_kv_args "${ARGS[@]}"
    email="${ARG_email:?--email required}"

    json=$(jq -n \
      --arg email "$email" \
      --arg first "${ARG_first_name:-}" \
      --arg last "${ARG_last_name:-}" \
      --arg company "${ARG_company:-}" \
      --arg campaign "${ARG_campaign:-}" \
      --arg list "${ARG_list:-}" \
      '{email: $email} +
       (if $first != "" then {first_name: $first} else {} end) +
       (if $last != "" then {last_name: $last} else {} end) +
       (if $company != "" then {company_name: $company} else {} end) +
       (if $campaign != "" then {campaign: $campaign} else {} end) +
       (if $list != "" then {list_id: $list} else {} end)')

    api_call POST "/leads" "$json"
    ;;

  list-leads)
    parse_kv_args "${ARGS[@]}"
    params=""
    [[ -n "${ARG_campaign_id:-}" ]] && params="campaign_id=${ARG_campaign_id}"
    [[ -n "${ARG_list_id:-}" ]] && params="${params:+$params&}list_id=${ARG_list_id}"
    [[ -n "${ARG_limit:-}" ]] && params="${params:+$params&}limit=${ARG_limit}"

    api_call GET "/leads/list?${params}"
    ;;

  get-lead)
    parse_kv_args "${ARGS[@]}"
    uuid="${ARG_uuid:?--uuid required}"
    api_call GET "/leads/$uuid"
    ;;

  update-lead)
    parse_kv_args "${ARGS[@]}"
    uuid="${ARG_uuid:?--uuid required}"
    # Custom variables go into payload object
    json=$(jq -n --arg cv "${ARG_custom:-{}}" '{custom_variables: ($cv | fromjson)}')
    api_call PATCH "/leads/$uuid" "$json"
    ;;

  create-campaign)
    parse_kv_args "${ARGS[@]}"
    name="${ARG_name:?--name required}"
    tz="${ARG_timezone:-America/Chicago}"

    json=$(jq -n \
      --arg name "$name" \
      --arg tz "$tz" \
      '{name: $name, campaign_schedule: {timezone: $tz}}')

    api_call POST "/campaigns" "$json"
    ;;

  list-campaigns)
    parse_kv_args "${ARGS[@]}"
    limit="${ARG_limit:-20}"
    api_call GET "/campaigns?limit=$limit"
    ;;

  get-campaign)
    parse_kv_args "${ARGS[@]}"
    id="${ARG_id:?--id required}"
    api_call GET "/campaigns/$id"
    ;;

  create-list)
    parse_kv_args "${ARGS[@]}"
    name="${ARG_name:?--name required}"
    json=$(jq -n --arg name "$name" '{name: $name}')
    api_call POST "/lead-lists" "$json"
    ;;

  list-lists)
    api_call GET "/lead-lists"
    ;;

  supersearch-count)
    # Free operation - use as decision gate before spending credits
    parse_kv_args "${ARGS[@]}"
    json="${ARG_json:?--json required (raw SuperSearch filter JSON)}"
    api_call POST "/supersearch-enrichment/count-leads-from-supersearch" "$json"
    ;;

  supersearch-preview)
    # Free - returns names/titles, NO emails
    parse_kv_args "${ARGS[@]}"
    json="${ARG_json:?--json required (raw SuperSearch filter JSON)}"
    api_call POST "/supersearch-enrichment/preview-leads-from-supersearch" "$json"
    ;;

  supersearch-enrich)
    # COSTS 1 CREDIT PER LEAD
    # GOTCHA: resource_id must be a LEAD LIST ID, resource_type must be 1
    parse_kv_args "${ARGS[@]}"
    list_id="${ARG_list_id:?--list-id required (lead list ID, NOT campaign ID)}"
    json="${ARG_json:?--json required (raw SuperSearch filter JSON)}"

    # Inject resource fields into the filter JSON
    enriched=$(echo "$json" | jq --arg rid "$list_id" '. + {resource_id: $rid, resource_type: 1}')
    api_call POST "/supersearch-enrichment/enrich-leads-from-supersearch" "$enriched"
    ;;

  list-emails)
    parse_kv_args "${ARGS[@]}"
    campaign_id="${ARG_campaign_id:?--campaign-id required}"
    api_call GET "/emails?campaign_id=$campaign_id"
    ;;

  help|*)
    cat <<'USAGE'
Instantly v2 API wrapper (GTMOps)

Usage: Instantly.sh <command> [--dry-run] [options]

Commands:
  create-lead         --email EMAIL [--first-name] [--last-name] [--company] [--campaign ID] [--list ID]
  list-leads          [--campaign-id ID] [--list-id ID] [--limit N]
  get-lead            --uuid UUID
  update-lead         --uuid UUID --custom '{"key": "value"}'
  create-campaign     --name NAME [--timezone TZ]
  list-campaigns      [--limit N]
  get-campaign        --id ID
  create-list         --name NAME
  list-lists
  supersearch-count   --json '{"filters": ...}'
  supersearch-preview --json '{"filters": ...}'
  supersearch-enrich  --list-id LIST_ID --json '{"filters": ...}'
  list-emails         --campaign-id ID

Flags:
  --dry-run    Print curl command without executing
  --help       Show this help

GOTCHAS:
  - create-lead uses "campaign" (NOT "campaign_id") for assignment
  - supersearch keyword_filter.include is a STRING not array
  - supersearch-preview returns names only, NO emails
  - supersearch-enrich needs a LEAD LIST ID, resource_type=1
USAGE
    ;;
esac
