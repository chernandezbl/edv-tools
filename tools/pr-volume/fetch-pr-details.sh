#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRS_CSV="$SCRIPT_DIR/data/prs.csv"
DETAILS_CSV="$SCRIPT_DIR/data/pr-details.csv"

if [ ! -f "$PRS_CSV" ]; then
  echo "Error: $PRS_CSV not found. Run fetch-prs.sh first."
  exit 1
fi

# Resume support: if pr-details.csv exists, skip already-fetched PRs
declare -A FETCHED
if [ -f "$DETAILS_CSV" ]; then
  while IFS=, read -r repo pr_number _rest; do
    # Strip quotes
    repo="${repo//\"/}"
    pr_number="${pr_number//\"/}"
    FETCHED["${repo}/${pr_number}"]=1
  done < <(tail -n +2 "$DETAILS_CSV")
  ALREADY=${#FETCHED[@]}
  echo "Resuming: $ALREADY PRs already fetched"
else
  echo "repo,pr_number,author,created_at,merged_at,additions,deletions,changed_files,commits,title" > "$DETAILS_CSV"
  ALREADY=0
fi

TOTAL=$(tail -n +2 "$PRS_CSV" | wc -l | tr -d ' ')
echo "Fetching details for $TOTAL PRs (skipping $ALREADY already done)..."

COUNT=0
SKIPPED=0
ERRORS=0

# Parse prs.csv: repo,pr_number,author,merged_at,title
while IFS= read -r line; do
  # CSV fields may be quoted — extract with simple parameter expansion
  repo=$(echo "$line" | awk -F',' '{gsub(/"/, "", $1); print $1}')
  pr_number=$(echo "$line" | awk -F',' '{gsub(/"/, "", $2); print $2}')

  KEY="${repo}/${pr_number}"

  # Skip if already fetched
  if [ "${FETCHED[$KEY]:-}" = "1" ]; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  COUNT=$((COUNT + 1))

  # Progress every 25 PRs
  if [ $((COUNT % 25)) -eq 1 ]; then
    echo "  [$COUNT / $((TOTAL - ALREADY))] Fetching ${KEY}..."
  fi

  # Fetch PR details
  RESULT=$(gh pr view "$pr_number" \
    --repo "edvisor-io/${repo}" \
    --json additions,deletions,changedFiles,createdAt,mergedAt,commits,author \
    --jq '[
      .author.login,
      .createdAt,
      .mergedAt,
      .additions,
      .deletions,
      .changedFiles,
      (.commits | length)
    ] | @csv' 2>/dev/null) || {
    ERRORS=$((ERRORS + 1))
    continue
  }

  # Get title from original CSV (last field, may contain commas)
  title=$(echo "$line" | awk -v FPAT='([^,]*)|("[^"]*")' '{print $5}' 2>/dev/null || \
    echo "$line" | sed 's/^[^,]*,[^,]*,[^,]*,[^,]*//' | sed 's/^,//')

  echo "\"${repo}\",\"${pr_number}\",${RESULT},${title}" >> "$DETAILS_CSV"

  # Rate limit: ~30 requests/min to stay safe
  sleep 2
done < <(tail -n +2 "$PRS_CSV")

FINAL=$(tail -n +2 "$DETAILS_CSV" | wc -l | tr -d ' ')
echo "Done. $FINAL PRs with details in $DETAILS_CSV ($ERRORS errors)"
