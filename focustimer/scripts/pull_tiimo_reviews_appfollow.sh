#!/usr/bin/env bash
set -euo pipefail

API_URL="https://api.appfollow.io/api/v2/reviews"
DEFAULT_IOS_EXT_ID="1480220328"
DEFAULT_OUTPUT="tiimo-reviews.json"

usage() {
  cat <<'EOF'
Pull Tiimo reviews from AppFollow Reviews API v2.

Usage:
  APPFOLLOW_API_TOKEN=... ./scripts/pull_tiimo_reviews_appfollow.sh [options]

Options:
  --ext-id <id>         App store external id (default: 1480220328, Tiimo iOS)
  --from <YYYY-MM-DD>   Start date (required)
  --to <YYYY-MM-DD>     End date (required)
  --output <file>       Output JSON file (default: tiimo-reviews.json)
  --extra-query <qs>    Extra query parameters without leading '?'
                        Example: "page=2"
  --help                Show this help

Notes:
  - Requires environment variable APPFOLLOW_API_TOKEN.
  - Per AppFollow docs, the endpoint requires ext_id or collection_name.
EOF
}

EXT_ID="$DEFAULT_IOS_EXT_ID"
FROM_DATE=""
TO_DATE=""
OUTPUT="$DEFAULT_OUTPUT"
EXTRA_QUERY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ext-id)
      EXT_ID="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT="${2:-}"
      shift 2
      ;;
    --from)
      FROM_DATE="${2:-}"
      shift 2
      ;;
    --to)
      TO_DATE="${2:-}"
      shift 2
      ;;
    --extra-query)
      EXTRA_QUERY="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${APPFOLLOW_API_TOKEN:-}" ]]; then
  echo "APPFOLLOW_API_TOKEN is required." >&2
  exit 1
fi

if [[ -z "$FROM_DATE" || -z "$TO_DATE" ]]; then
  echo "--from and --to are required (YYYY-MM-DD)." >&2
  exit 1
fi

QUERY="ext_id=${EXT_ID}&from=${FROM_DATE}&to=${TO_DATE}"
if [[ -n "$EXTRA_QUERY" ]]; then
  QUERY="${QUERY}&${EXTRA_QUERY}"
fi

URL="${API_URL}?${QUERY}"

curl --fail --silent --show-error \
  --header "X-AppFollow-API-Token: ${APPFOLLOW_API_TOKEN}" \
  "$URL" \
  > "$OUTPUT"

echo "Saved AppFollow response to ${OUTPUT}"
