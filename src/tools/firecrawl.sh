#!/usr/bin/env bash
# GTMOps: Firecrawl API wrapper (web scraping + search)
# Usage: firecrawl.sh <command> [options]
#
# Commands:
#   scrape            Scrape a single URL (returns markdown)
#   search            Search the web (returns markdown + URLs)
#   crawl             Crawl a site (async, returns job ID)
#   crawl-status      Check crawl job status
#   map               Get sitemap/URLs for a domain
#
# GOTCHAS BAKED IN:
#   - Auth is Authorization: Bearer, standard pattern
#   - scrape returns markdown by default (most useful for LLM consumption)
#   - search returns web results with markdown content (1 credit per result)
#   - crawl is ASYNC - returns job ID, poll with crawl-status
#   - map is fast sitemap extraction, no content (good for discovery)
#   - Cloudflare-protected sites may need waitFor param (milliseconds)

set -euo pipefail

# Show help without requiring API keys
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n '2,/^[^#]/{ /^#/s/^# \{0,1\}//p; }' "$0"
  exit 0
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GTMOPS_DIR="${GTMOPS_DIR:-$(dirname "$(dirname "$SCRIPT_DIR")")}"

if [[ -f "$GTMOPS_DIR/.env" ]]; then
  FIRECRAWL_API_KEY="${FIRECRAWL_API_KEY:-$(grep '^FIRECRAWL_API_KEY=' "$GTMOPS_DIR/.env" | cut -d'=' -f2-)}"
fi

if [[ -z "${FIRECRAWL_API_KEY:-}" ]]; then
  echo "Error: FIRECRAWL_API_KEY not set in environment or $GTMOPS_DIR/.env" >&2
  exit 1
fi

BASE_URL="https://api.firecrawl.dev/v1"
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
  local cmd=(curl -sS -X "$method" "$url" -H "Authorization: Bearer $FIRECRAWL_API_KEY" -H "Content-Type: application/json")

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
  scrape)
    parse_kv_args "${ARGS[@]}"
    url="${ARG_url:?--url required}"
    wait_for="${ARG_wait_for:-}" # milliseconds for JS-heavy sites
    formats="${ARG_formats:-markdown}"

    json=$(jq -n \
      --arg url "$url" \
      --arg formats "$formats" \
      --arg wait "$wait_for" \
      '{url: $url, formats: ($formats | split(","))} +
       (if $wait != "" then {waitFor: ($wait | tonumber)} else {} end)')

    api_call POST "/scrape" "$json"
    ;;

  search)
    # Returns web results with markdown content
    parse_kv_args "${ARGS[@]}"
    query="${ARG_q:?--q required (search query)}"
    limit="${ARG_limit:-5}"

    json=$(jq -n \
      --arg q "$query" \
      --argjson limit "$limit" \
      '{query: $q, limit: $limit}')

    api_call POST "/search" "$json"
    ;;

  crawl)
    # ASYNC - returns job ID, use crawl-status to poll
    parse_kv_args "${ARGS[@]}"
    url="${ARG_url:?--url required (starting URL)}"
    limit="${ARG_limit:-10}"

    json=$(jq -n \
      --arg url "$url" \
      --argjson limit "$limit" \
      '{url: $url, limit: $limit}')

    api_call POST "/crawl" "$json"
    ;;

  crawl-status)
    parse_kv_args "${ARGS[@]}"
    id="${ARG_id:?--id required (crawl job ID)}"

    api_call GET "/crawl/$id"
    ;;

  map)
    # Fast sitemap extraction, no content
    parse_kv_args "${ARGS[@]}"
    url="${ARG_url:?--url required}"

    json=$(jq -n --arg url "$url" '{url: $url}')
    api_call POST "/map" "$json"
    ;;

  help|*)
    cat <<'USAGE'
Firecrawl API wrapper (GTMOps)

Usage: firecrawl.sh <command> [--dry-run] [options]

Commands:
  scrape          --url URL [--wait-for MS] [--formats markdown,html]
  search          --q "query" [--limit N]
  crawl           --url URL [--limit N]  (async, returns job ID)
  crawl-status    --id JOB_ID
  map             --url URL  (fast sitemap extraction)

Flags:
  --dry-run    Print curl command without executing
  --help       Show this help

GOTCHAS:
  - scrape returns markdown by default (best for LLM consumption)
  - crawl is ASYNC - poll with crawl-status until status is "completed"
  - Cloudflare sites may need --wait-for 3000 (milliseconds)
  - search costs 1 credit per result returned
  - map is the cheapest way to discover URLs before scraping
  - Use Serper for search/discovery (cheaper), Firecrawl for deep page reads
USAGE
    ;;
esac
