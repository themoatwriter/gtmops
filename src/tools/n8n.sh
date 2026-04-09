#!/usr/bin/env bash
# GTMOps: n8n REST API wrapper (supports VPS + Cloud instances)
# Usage: N8N.sh <command> [options]
#
# Commands:
#   list-workflows    List all workflows
#   get-workflow       Get workflow definition
#   create-workflow    Create a new workflow from JSON
#   export-workflow    Export workflow to portable JSON file
#   activate           Activate a workflow
#   deactivate         Deactivate a workflow
#   update-workflow    Update a workflow (PUT)
#   executions         List recent executions for a workflow
#   execution-detail   Get full node-by-node output for an execution
#   trigger            Trigger a webhook workflow
#
# Instances:
#   --instance vps     VPS at YOUR_VPS_IP:5678 (default)
#   --instance cloud   n8n Cloud at YOUR_ORG.app.n8n.cloud
#
# GOTCHAS BAKED IN:
#   - VPS requires network access to your self-hosted instance
#   - settings field is REQUIRED on update. Min: {"executionOrder": "v1"}
#   - Extra settings fields (availableInMCP, binaryMode, callerPolicy) cause validation errors
#   - Auth header is X-N8N-API-KEY, not Authorization: Bearer
#   - n8n Cloud uses different API key than VPS
#   - Cloud credentials API returns empty array (can't read credential values via API)
#   - PUT requires "name" field in body or returns 400

set -euo pipefail

# Show help without requiring API keys
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n '2,/^[^#]/{ /^#/s/^# \{0,1\}//p; }' "$0"
  exit 0
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GTMOPS_DIR="${GTMOPS_DIR:-$(dirname "$(dirname "$SCRIPT_DIR")")}"

if [[ -f "$GTMOPS_DIR/.env" ]]; then
  N8N_API_KEY="${N8N_API_KEY:-$(grep '^N8N_API_KEY=' "$GTMOPS_DIR/.env" | cut -d'=' -f2-)}"
  N8N_CLOUD_API_KEY="${N8N_CLOUD_API_KEY:-$(grep '^N8N_CLOUD_API_KEY=' "$GTMOPS_DIR/.env" | cut -d'=' -f2-)}"
  N8N_VPS_URL="${N8N_VPS_URL:-$(grep '^N8N_VPS_URL=' "$GTMOPS_DIR/.env" | cut -d'=' -f2-)}"
  N8N_CLOUD_URL="${N8N_CLOUD_URL:-$(grep '^N8N_CLOUD_URL=' "$GTMOPS_DIR/.env" | cut -d'=' -f2-)}"
fi

# Defaults
INSTANCE="vps"
DRY_RUN=false

# Parse global flags first
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --help|-h) COMMAND="help" ;;
    *) ARGS+=("$arg") ;;
  esac
done

# Extract --instance before command parsing
FILTERED_ARGS=()
i=0
while [[ $i -lt ${#ARGS[@]} ]]; do
  if [[ "${ARGS[$i]}" == "--instance" ]]; then
    i=$((i + 1))
    INSTANCE="${ARGS[$i]:-vps}"
  else
    FILTERED_ARGS+=("${ARGS[$i]}")
  fi
  i=$((i + 1))
done
ARGS=("${FILTERED_ARGS[@]}")

COMMAND="${COMMAND:-${ARGS[0]:-help}}"
if [[ ${#ARGS[@]} -gt 1 ]]; then
  ARGS=("${ARGS[@]:1}")
else
  ARGS=()
fi

# Set base URL and API key based on instance
if [[ "$INSTANCE" == "cloud" ]]; then
  BASE_URL="${N8N_CLOUD_URL}/api/v1"
  API_KEY="${N8N_CLOUD_API_KEY:-}"
  if [[ -z "$API_KEY" ]]; then
    echo "Error: N8N_CLOUD_API_KEY not set" >&2
    exit 1
  fi
else
  BASE_URL="${N8N_VPS_URL:-http://localhost:5678}/api/v1"
  API_KEY="${N8N_API_KEY:-}"
  if [[ -z "$API_KEY" ]]; then
    echo "Error: N8N_API_KEY not set" >&2
    exit 1
  fi
fi

api_call() {
  local method="$1" endpoint="$2" data="${3:-}"
  local url="${BASE_URL}${endpoint}"
  local cmd=(curl -sS -X "$method" "$url" -H "X-N8N-API-KEY: $API_KEY" -H "Content-Type: application/json")

  if [[ -n "$data" ]]; then
    cmd+=(-d "$data")
  fi

  # Add timeout for VPS (Wireguard might be down)
  if [[ "$INSTANCE" == "vps" ]]; then
    cmd+=(--connect-timeout 5)
  fi

  if $DRY_RUN; then
    echo "${cmd[@]}"
    return 0
  fi

  local response
  response=$("${cmd[@]}" 2>&1)
  local exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    if [[ "$INSTANCE" == "vps" ]]; then
      echo "API call failed. Is your VPS accessible? Check network/VPN." >&2
    fi
    echo "Error: $response" >&2
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
  list-workflows)
    api_call GET "/workflows" | jq '[.data[] | {id, name, active, updatedAt}]'
    ;;

  get-workflow)
    parse_kv_args "${ARGS[@]}"
    id="${ARG_id:?--id required}"
    api_call GET "/workflows/$id"
    ;;

  activate)
    parse_kv_args "${ARGS[@]}"
    id="${ARG_id:?--id required}"
    api_call PATCH "/workflows/$id" '{"active": true}'
    ;;

  deactivate)
    parse_kv_args "${ARGS[@]}"
    id="${ARG_id:?--id required}"
    api_call PATCH "/workflows/$id" '{"active": false}'
    ;;

  create-workflow)
    # Create a new workflow from JSON file or inline JSON
    parse_kv_args "${ARGS[@]}"
    json="${ARG_json:-}"
    file="${ARG_file:-}"

    if [[ -n "$file" ]]; then
      json=$(cat "$file")
    fi

    if [[ -z "$json" ]]; then
      echo "Error: --json or --file required" >&2
      exit 1
    fi

    # Ensure settings has executionOrder
    json=$(echo "$json" | jq 'if .settings == null then .settings = {"executionOrder": "v1"} else . end')

    response=$(api_call POST "/workflows" "$json")
    echo "$response" | jq '{id, name, active, createdAt}'
    ;;

  export-workflow)
    # Export a workflow to a local JSON file (portable, can be re-imported)
    parse_kv_args "${ARGS[@]}"
    id="${ARG_id:?--id required}"
    file="${ARG_file:?--file required (output path)}"

    response=$(api_call GET "/workflows/$id")
    # Strip server-only fields, keep portable structure
    echo "$response" | jq '{name, nodes, connections, settings: {executionOrder: (.settings.executionOrder // "v1")}}' > "$file"
    echo "Exported to $file ($(echo "$response" | jq '.nodes | length') nodes)"
    ;;

  update-workflow)
    # GOTCHA: settings is REQUIRED. Strip non-standard fields.
    parse_kv_args "${ARGS[@]}"
    id="${ARG_id:?--id required}"
    json="${ARG_json:-}"
    file="${ARG_file:-}"

    if [[ -n "$file" ]]; then
      json=$(cat "$file")
    fi

    if [[ -z "$json" ]]; then
      echo "Error: --json or --file required" >&2
      exit 1
    fi

    # Ensure settings has executionOrder
    json=$(echo "$json" | jq 'if .settings == null then .settings = {"executionOrder": "v1"} else . end')

    api_call PUT "/workflows/$id" "$json"
    ;;

  executions)
    parse_kv_args "${ARGS[@]}"
    id="${ARG_id:-}"
    limit="${ARG_limit:-10}"
    status="${ARG_status:-}" # success, error, waiting

    endpoint="/executions?limit=$limit"
    [[ -n "$id" ]] && endpoint="$endpoint&workflowId=$id"
    [[ -n "$status" ]] && endpoint="$endpoint&status=$status"

    api_call GET "$endpoint" | jq '[.data[] | {id, workflowId, status, startedAt, stoppedAt, mode}]'
    ;;

  execution-detail)
    parse_kv_args "${ARGS[@]}"
    id="${ARG_id:?--id required (execution ID)}"

    response=$(api_call GET "/executions/$id")

    # Extract node-by-node results for debugging
    echo "$response" | jq '{
      id: .id,
      status: .status,
      startedAt: .startedAt,
      stoppedAt: .stoppedAt,
      workflow: .workflowData.name,
      nodes: [.data.resultData.runData | to_entries[] | {
        node: .key,
        runs: [.value[] | {
          status: (if .error then "error" else "success" end),
          error: (.error.message // null),
          items_in: (.data.main[0] // [] | length),
          items_out: (.data.main[0] // [] | length),
          first_item: (.data.main[0][0].json // null)
        }]
      }]
    }'
    ;;

  trigger)
    parse_kv_args "${ARGS[@]}"
    url="${ARG_url:?--url required (webhook URL)}"
    data="${ARG_data:-{}}"

    if $DRY_RUN; then
      echo "curl -sS -X POST '$url' -H 'Content-Type: application/json' -d '$data'"
      exit 0
    fi

    curl -sS -X POST "$url" -H "Content-Type: application/json" -d "$data"
    ;;

  help|*)
    cat <<'USAGE'
n8n REST API wrapper (GTMOps)

Usage: N8N.sh <command> [--instance vps|cloud] [--dry-run] [options]

Instances:
  --instance vps     Self-hosted VPS (default)
  --instance cloud   n8n Cloud

Commands:
  list-workflows                          List all workflows (id, name, active)
  get-workflow       --id WORKFLOW_ID      Get full workflow definition
  create-workflow    --file path OR --json '{}'   Create new workflow from JSON
  export-workflow    --id WORKFLOW_ID --file path  Export workflow to portable JSON
  activate           --id WORKFLOW_ID      Activate workflow
  deactivate         --id WORKFLOW_ID      Deactivate workflow
  update-workflow    --id ID --json '{}' OR --file path   Update workflow
  executions         [--id WORKFLOW_ID] [--limit N] [--status success|error]
  execution-detail   --id EXECUTION_ID     Node-by-node debug output
  trigger            --url WEBHOOK_URL [--data '{}']

Flags:
  --dry-run    Print curl command without executing
  --help       Show this help

GOTCHAS:
  - VPS requires network access (check VPN if using one)
  - Auth is X-N8N-API-KEY header, not Bearer
  - settings field REQUIRED on update: {"executionOrder": "v1"}
  - Extra settings fields (availableInMCP, binaryMode, callerPolicy) cause validation errors
  - Cloud and VPS use different API keys
  - Cloud credentials API returns empty array (can't read credential values)
  - PUT requires "name" field in body or returns 400
USAGE
    ;;
esac
