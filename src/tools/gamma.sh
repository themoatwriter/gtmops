#!/usr/bin/env bash
# GTMOps: Gamma API wrapper
# Usage: Gamma.sh <command> [options]
#
# Commands:
#   generate          Create a presentation/document
#   status            Poll generation status
#   themes            List workspace themes
#   folders           List workspace folders
#
# GOTCHAS BAKED IN:
#   - Auth is X-API-KEY header, NOT Authorization: Bearer
#   - User-Agent header REQUIRED or Cloudflare blocks with 403 (error 1010)
#   - Response field is generationId, NOT id
#   - textMode=preserve keeps exact text (use for pipeline reports with numbers)
#   - cardSplit=inputTextBreaks respects \n---\n for manual slide breaks
#   - ~4 credits per slide

set -euo pipefail

# Show help without requiring API keys
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  sed -n '2,/^[^#]/{ /^#/s/^# \{0,1\}//p; }' "$0"
  exit 0
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GTMOPS_DIR="${GTMOPS_DIR:-$(dirname "$(dirname "$SCRIPT_DIR")")}"

if [[ -f "$GTMOPS_DIR/.env" ]]; then
  GAMMA_API_KEY="${GAMMA_API_KEY:-$(grep '^GAMMA_API_KEY=' "$GTMOPS_DIR/.env" | cut -d'=' -f2-)}"
fi

if [[ -z "${GAMMA_API_KEY:-}" ]]; then
  echo "Error: GAMMA_API_KEY not set in environment or $GTMOPS_DIR/.env" >&2
  exit 1
fi

BASE_URL="https://public-api.gamma.app/v1.0"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
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
  local cmd=(curl -sS -X "$method" "$url" -H "X-API-KEY: $GAMMA_API_KEY" -H "User-Agent: $UA" -H "Content-Type: application/json")

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
  generate)
    parse_kv_args "${ARGS[@]}"
    text="${ARG_text:-}"
    file="${ARG_file:-}"
    mode="${ARG_mode:-preserve}"
    format="${ARG_format:-presentation}"
    split="${ARG_split:-inputTextBreaks}"

    if [[ -n "$file" ]]; then
      text=$(cat "$file")
    fi

    if [[ -z "$text" ]]; then
      echo "Error: --text or --file required" >&2
      exit 1
    fi

    json=$(jq -n \
      --arg text "$text" \
      --arg mode "$mode" \
      --arg format "$format" \
      --arg split "$split" \
      '{
        inputText: $text,
        textMode: $mode,
        format: $format,
        cardSplit: $split,
        imageOptions: {
          source: "aiGenerated",
          stylePreset: "custom",
          style: "dark moody tech aesthetic, abstract data visualizations, network nodes, clean geometric shapes, dark backgrounds with accent lighting, no clip art, no cartoons"
        },
        cardOptions: {
          dimensions: "16x9"
        }
      }')

    api_call POST "/generations" "$json"
    ;;

  status)
    parse_kv_args "${ARGS[@]}"
    id="${ARG_id:?--id required (generationId from generate response)}"

    api_call GET "/generations/$id"
    ;;

  themes)
    api_call GET "/themes"
    ;;

  folders)
    api_call GET "/folders"
    ;;

  help|*)
    cat <<'USAGE'
Gamma API wrapper (GTMOps)

Usage: Gamma.sh <command> [--dry-run] [options]

Commands:
  generate    --text "content" OR --file path [--mode preserve|generate|condense] [--format presentation|document] [--split inputTextBreaks|auto]
  status      --id GENERATION_ID
  themes      (list workspace themes)
  folders     (list workspace folders)

Flags:
  --dry-run    Print curl command without executing
  --help       Show this help

GOTCHAS:
  - Auth is X-API-KEY, NOT Bearer token
  - User-Agent header required or Cloudflare blocks (403, error 1010)
  - Response field is generationId, NOT id
  - Use --mode preserve for reports with exact numbers
  - Use \n---\n in text for manual slide breaks with --split inputTextBreaks
  - ~4 credits per slide, check balance in status response
USAGE
    ;;
esac
