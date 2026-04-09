#!/usr/bin/env bash
# GTMOps: Serper.dev API wrapper (Google Search, Maps, Reviews)
# Usage: serper.sh <command> [options]
#
# Commands:
#   search            Google web search
#   maps              Google Maps place lookup
#   reviews           Google Reviews for a place
#   news              Google News search
#   images            Google Image search
#
# GOTCHAS BAKED IN:
#   - Auth is X-API-KEY header, not Authorization: Bearer
#   - Maps returns places[0], not a flat object
#   - Reviews needs a placeId from maps result, not a search query
#   - "num" controls result count (default 10, max 100)
#   - Results include position field for ranking context
#   - 1 credit per search, maps is 4 credits, reviews is 10 credits

set -euo pipefail

# Show help without requiring API keys
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n '2,/^[^#]/{ /^#/s/^# \{0,1\}//p; }' "$0"
  exit 0
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GTMOPS_DIR="${GTMOPS_DIR:-$(dirname "$(dirname "$SCRIPT_DIR")")}"

if [[ -f "$GTMOPS_DIR/.env" ]]; then
  SERPER_API_KEY="${SERPER_API_KEY:-$(grep '^SERPER_API_KEY=' "$GTMOPS_DIR/.env" | cut -d'=' -f2-)}"
fi

if [[ -z "${SERPER_API_KEY:-}" ]]; then
  echo "Error: SERPER_API_KEY not set in environment or $GTMOPS_DIR/.env" >&2
  exit 1
fi

BASE_URL="https://google.serper.dev"
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
  local endpoint="$1" data="$2"
  local url="${BASE_URL}/${endpoint}"
  local cmd=(curl -sS -X POST "$url" -H "X-API-KEY: $SERPER_API_KEY" -H "Content-Type: application/json" -d "$data")

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
  search)
    parse_kv_args "${ARGS[@]}"
    query="${ARG_q:?--q required (search query)}"
    num="${ARG_num:-10}"
    gl="${ARG_gl:-}" # country code: us, uk, etc.

    json=$(jq -n \
      --arg q "$query" \
      --argjson num "$num" \
      --arg gl "$gl" \
      '{q: $q, num: $num} + (if $gl != "" then {gl: $gl} else {} end)')

    api_call "search" "$json"
    ;;

  maps)
    # GOTCHA: Returns places array, you usually want places[0]
    parse_kv_args "${ARGS[@]}"
    query="${ARG_q:?--q required (place search query)}"
    num="${ARG_num:-1}"

    json=$(jq -n --arg q "$query" --argjson num "$num" '{q: $q, num: $num}')
    api_call "maps" "$json"
    ;;

  reviews)
    # GOTCHA: Needs placeId from maps result, not a search query
    parse_kv_args "${ARGS[@]}"
    place_id="${ARG_place_id:?--place-id required (from maps result)}"
    num="${ARG_num:-10}"

    json=$(jq -n --arg pid "$place_id" --argjson num "$num" '{placeId: $pid, num: $num}')
    api_call "reviews" "$json"
    ;;

  news)
    parse_kv_args "${ARGS[@]}"
    query="${ARG_q:?--q required}"
    num="${ARG_num:-10}"
    gl="${ARG_gl:-}"

    json=$(jq -n \
      --arg q "$query" \
      --argjson num "$num" \
      --arg gl "$gl" \
      '{q: $q, num: $num} + (if $gl != "" then {gl: $gl} else {} end)')

    api_call "news" "$json"
    ;;

  images)
    parse_kv_args "${ARGS[@]}"
    query="${ARG_q:?--q required}"
    num="${ARG_num:-10}"

    json=$(jq -n --arg q "$query" --argjson num "$num" '{q: $q, num: $num}')
    api_call "images" "$json"
    ;;

  help|*)
    cat <<'USAGE'
Serper.dev API wrapper (GTMOps)

Usage: serper.sh <command> [--dry-run] [options]

Commands:
  search      --q "query" [--num N] [--gl COUNTRY_CODE]
  maps        --q "place query" [--num N]
  reviews     --place-id PLACE_ID [--num N]
  news        --q "query" [--num N] [--gl COUNTRY_CODE]
  images      --q "query" [--num N]

Flags:
  --dry-run    Print curl command without executing
  --help       Show this help

Credit costs:
  search: 1 credit    maps: 4 credits    reviews: 10 credits

GOTCHAS:
  - Auth is X-API-KEY header, not Bearer
  - Maps returns places array, use places[0] for single result
  - Reviews needs placeId from maps, not a search query string
  - gl param is ISO country code (us, uk, de, etc.)
  - num max is 100 per request
USAGE
    ;;
esac
