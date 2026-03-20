#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUTHORS_CSV="$SCRIPT_DIR/authors.csv"
OUTPUT="$SCRIPT_DIR/data/prs.csv"
ORG="edvisor-io"
SINCE_DAYS=90

# Calculate the date 90 days ago
if date -v-1d &>/dev/null; then
  # macOS
  SINCE_DATE=$(date -v-${SINCE_DAYS}d +%Y-%m-%d)
else
  # Linux
  SINCE_DATE=$(date -d "-${SINCE_DAYS} days" +%Y-%m-%d)
fi

echo "Fetching merged PRs since $SINCE_DATE for org $ORG"

# Write CSV header
echo "repo,pr_number,author,merged_at,title" > "$OUTPUT"

# Extract authors that have a team (skip header, skip empty teams)
# authors.csv is tab-separated: login\tname\tteam
AUTHORS=$(awk -F'\t' 'NR>1 && $3 != "" { print $1 }' "$AUTHORS_CSV")

for AUTHOR in $AUTHORS; do
  echo "  Fetching PRs for $AUTHOR..."

  # gh search prs returns JSON; we parse out what we need
  # --limit 200 should be enough for 90 days per author
  gh search prs \
    --merged \
    --author="$AUTHOR" \
    --closed=">=${SINCE_DATE}" \
    --limit=200 \
    --json repository,number,author,closedAt,title \
    --jq '.[] | [.repository.name, .number, .author.login, .closedAt, .title] | @csv' \
    -- "org:${ORG}" \
    >> "$OUTPUT" 2>/dev/null || echo "    Warning: failed for $AUTHOR"

  # Small delay to avoid rate limiting
  sleep 1
done

TOTAL=$(tail -n +2 "$OUTPUT" | wc -l | tr -d ' ')
echo "Done. $TOTAL PRs written to $OUTPUT"
