#!/usr/bin/env bash
# GTMOps: Attio v2 API wrapper
# Usage: Attio.sh <command> [options]
#
# Commands:
#   upsert-person     Upsert a person record (by email)
#   upsert-company    Upsert a company record (by domain)
#   list-records      List records from an object
#   get-record        Get a single record
#   update-field      Update a specific field on a record
#   list-objects      List all objects (for discovering IDs)
#   list-attributes   List attributes for an object
#   list-members      List workspace members (id, name, email)
#   create-task       Create a task assigned to a workspace member
#
# Multi-workspace support:
#   Set ATTIO_API_KEY_<NAME> in .env for additional workspaces
#   Use --workspace <name> to switch (e.g. --workspace team)
#
# GOTCHAS BAKED IN:
#   - Use PUT (upsert) not find+patch. Records may not exist yet for new signups.
#   - Person matching is by email_addresses, company by domains
#   - Custom fields use attribute slug, not display name
#   - Attio returns nested value objects: {attribute_type, values: [{value}]}
#   - Tasks API requires is_completed, assignees, and linked_records fields (all mandatory)
#   - Domain upsert can match wrong company if domain is shared across records

set -euo pipefail

# Show help without requiring API keys
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n '2,/^[^#]/{ /^#/s/^# \{0,1\}//p; }' "$0"
  exit 0
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GTMOPS_DIR="${GTMOPS_DIR:-$(dirname "$(dirname "$SCRIPT_DIR")")}"

if [[ -f "$GTMOPS_DIR/.env" ]]; then
  ATTIO_API_KEY="${ATTIO_API_KEY:-$(grep '^ATTIO_API_KEY=' "$GTMOPS_DIR/.env" | cut -d'=' -f2-)}"
fi

BASE_URL="https://api.attio.com/v2"
DRY_RUN=false
WORKSPACE="default"

ARGS=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --help|-h) COMMAND="help" ;;
    *) ARGS+=("$arg") ;;
  esac
done

# Extract --workspace before command parsing
FILTERED_ARGS=()
i=0
while [[ $i -lt ${#ARGS[@]} ]]; do
  if [[ "${ARGS[$i]}" == "--workspace" ]]; then
    i=$((i + 1))
    WORKSPACE="${ARGS[$i]:-default}"
  else
    FILTERED_ARGS+=("${ARGS[$i]}")
  fi
  i=$((i + 1))
done
ARGS=("${FILTERED_ARGS[@]}")

# Select API key based on workspace
if [[ "$WORKSPACE" != "default" ]]; then
  ws_upper=$(echo "$WORKSPACE" | tr '[:lower:]' '[:upper:]')
  ws_key="ATTIO_API_KEY_${ws_upper}"
  if [[ -f "$GTMOPS_DIR/.env" ]]; then
    ATTIO_API_KEY="${!ws_key:-$(grep "^${ws_key}=" "$GTMOPS_DIR/.env" | cut -d'=' -f2-)}"
  else
    ATTIO_API_KEY="${!ws_key:-}"
  fi
  if [[ -z "${ATTIO_API_KEY:-}" ]]; then
    echo "Error: ${ws_key} not set for workspace '$WORKSPACE'" >&2
    exit 1
  fi
else
  if [[ -z "${ATTIO_API_KEY:-}" ]]; then
    echo "Error: ATTIO_API_KEY not set in environment or $GTMOPS_DIR/.env" >&2
    exit 1
  fi
fi

COMMAND="${COMMAND:-${ARGS[0]:-help}}"
if [[ ${#ARGS[@]} -gt 1 ]]; then
  ARGS=("${ARGS[@]:1}")
else
  ARGS=()
fi

api_call() {
  local method="$1" endpoint="$2" data="${3:-}"
  local url="${BASE_URL}${endpoint}"
  local cmd=(curl -sS -X "$method" "$url" -H "Authorization: Bearer $ATTIO_API_KEY" -H "Content-Type: application/json")

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

# Collect multiple --field key=value pairs
parse_fields() {
  FIELDS=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --field)
        shift
        FIELDS+=("${1:-}")
        shift
        ;;
      *) shift ;;
    esac
  done
}

build_field_json() {
  # Convert key=value pairs into Attio attribute format
  local json="{}"
  for field in "${FIELDS[@]}"; do
    local key="${field%%=*}"
    local value="${field#*=}"
    json=$(echo "$json" | jq --arg k "$key" --arg v "$value" '. + {($k): [{value: $v}]}')
  done
  echo "$json"
}

case "$COMMAND" in
  upsert-person)
    # GOTCHA: Use PUT (assert), not find+patch. Record may not exist.
    # Matching attribute: email_addresses
    parse_kv_args "${ARGS[@]}"
    parse_fields "$@"
    email="${ARG_email:?--email required}"

    field_json=$(build_field_json)

    json=$(jq -n \
      --arg email "$email" \
      --argjson attrs "$field_json" \
      '{
        data: {
          values: ({
            email_addresses: [{email_address: $email}]
          } + $attrs)
        }
      }')

    api_call PUT "/objects/people/records?matching_attribute=email_addresses" "$json"
    ;;

  upsert-company)
    # Matching attribute: domains
    parse_kv_args "${ARGS[@]}"
    parse_fields "$@"
    domain="${ARG_domain:?--domain required}"

    field_json=$(build_field_json)

    json=$(jq -n \
      --arg domain "$domain" \
      --argjson attrs "$field_json" \
      '{
        data: {
          values: ({
            domains: [{domain: $domain}]
          } + $attrs)
        }
      }')

    api_call PUT "/objects/companies/records?matching_attribute=domains" "$json"
    ;;

  list-records)
    parse_kv_args "${ARGS[@]}"
    object="${ARG_object:?--object required (e.g. people, companies)}"
    limit="${ARG_limit:-20}"

    # Attio uses POST for list queries
    json=$(jq -n --argjson limit "$limit" '{limit: $limit}')
    api_call POST "/objects/$object/records/query" "$json"
    ;;

  get-record)
    parse_kv_args "${ARGS[@]}"
    object="${ARG_object:?--object required}"
    record_id="${ARG_record_id:?--record-id required}"

    api_call GET "/objects/$object/records/$record_id"
    ;;

  update-field)
    # Update specific fields on an existing record
    parse_kv_args "${ARGS[@]}"
    parse_fields "$@"
    object="${ARG_object:?--object required}"
    record_id="${ARG_record_id:?--record-id required}"

    field_json=$(build_field_json)
    json=$(jq -n --argjson attrs "$field_json" '{data: {values: $attrs}}')

    api_call PATCH "/objects/$object/records/$record_id" "$json"
    ;;

  list-objects)
    api_call GET "/objects"
    ;;

  list-attributes)
    parse_kv_args "${ARGS[@]}"
    object="${ARG_object:?--object required}"
    api_call GET "/objects/$object/attributes"
    ;;

  list-members)
    api_call GET "/workspace_members" | jq '.data[] | {id: .id.workspace_member_id, name: (.first_name + " " + .last_name), email: .email_address}'
    ;;

  create-task)
    # GOTCHA: is_completed, assignees, and linked_records are ALL required
    parse_kv_args "${ARGS[@]}"
    content="${ARG_content:?--content required}"
    assignee="${ARG_assignee:?--assignee required (workspace member ID)}"

    json=$(jq -n \
      --arg content "$content" \
      --arg assignee "$assignee" \
      '{
        data: {
          content: $content,
          format: "plaintext",
          deadline_at: null,
          is_completed: false,
          assignees: [{
            referenced_actor_type: "workspace-member",
            referenced_actor_id: $assignee
          }],
          linked_records: []
        }
      }')

    api_call POST "/tasks" "$json"
    ;;

  help|*)
    cat <<'USAGE'
Attio v2 API wrapper (GTMOps)

Usage: Attio.sh <command> [--workspace NAME] [--dry-run] [options]

Workspaces:
  --workspace default   Uses ATTIO_API_KEY (default)
  --workspace team      Uses ATTIO_API_KEY_TEAM (set in .env)

Commands:
  upsert-person     --email EMAIL [--field key=value ...]
  upsert-company    --domain DOMAIN [--field key=value ...]
  list-records      --object OBJECT [--limit N]
  get-record        --object OBJECT --record-id ID
  update-field      --object OBJECT --record-id ID --field key=value [...]
  list-objects       (discover object IDs)
  list-attributes   --object OBJECT (discover field slugs)
  list-members       List workspace members (id, name, email)
  create-task       --content "Task text" --assignee MEMBER_ID

Flags:
  --dry-run    Print curl command without executing
  --help       Show this help

GOTCHAS:
  - Use upsert (PUT), not find+patch. Records may not exist for new signups.
  - Person matching is by email_addresses, company by domains
  - Custom fields use attribute slug, not display name
  - list-records uses POST (not GET) - Attio's query endpoint
  - Tasks API requires is_completed, assignees, and linked_records (all mandatory)
  - Domain upsert can match wrong company if domain is shared across records
USAGE
    ;;
esac
