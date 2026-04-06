#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUTHORS_CSV="$SCRIPT_DIR/authors.csv"
PRS_CSV="$SCRIPT_DIR/data/prs.csv"
VOLUME_CSV="$SCRIPT_DIR/data/volume-by-team.csv"
REPORT="$SCRIPT_DIR/report.md"

if [ ! -f "$PRS_CSV" ]; then
  echo "Error: $PRS_CSV not found. Run fetch-prs.sh first."
  exit 1
fi

# Calculate cutoff dates
if date -v-1d &>/dev/null; then
  DATE_15=$(date -v-15d +%Y-%m-%d)
  DATE_30=$(date -v-30d +%Y-%m-%d)
  DATE_90=$(date -v-90d +%Y-%m-%d)
  TODAY=$(date +%Y-%m-%d)
else
  DATE_15=$(date -d "-15 days" +%Y-%m-%d)
  DATE_30=$(date -d "-30 days" +%Y-%m-%d)
  DATE_90=$(date -d "-90 days" +%Y-%m-%d)
  TODAY=$(date +%Y-%m-%d)
fi

echo "Analyzing PRs..."
echo "  Cutoffs: 15d=$DATE_15, 30d=$DATE_30, 90d=$DATE_90"

# Create a temp file with author-team mapping
TEAM_MAP=$(mktemp)
while IFS=$'\t' read -r login name team; do
  team_lower=$(echo "$team" | tr '[:upper:]' '[:lower:]')
  if [ -n "$team_lower" ]; then
    printf '%s\t%s\n' "$login" "$team_lower"
  fi
done < <(tail -n +2 "$AUTHORS_CSV") > "$TEAM_MAP"

# Use awk to do the full analysis (compatible with macOS awk — no FPAT, no multi-dim arrays)
LC_NUMERIC=C awk \
    -v date15="$DATE_15" -v date30="$DATE_30" -v date90="$DATE_90" -v today="$TODAY" \
    -v team_map="$TEAM_MAP" \
    -v volume_csv="$VOLUME_CSV" \
    -v report="$REPORT" \
'
function csv_field(line, n,    i, c, in_quote, field, nf) {
  # Simple CSV parser: return the nth field (1-indexed)
  nf = 1; field = ""; in_quote = 0
  for (i = 1; i <= length(line); i++) {
    c = substr(line, i, 1)
    if (c == "\"") { in_quote = !in_quote; continue }
    if (c == "," && !in_quote) {
      nf++
      if (nf > n) break
      if (nf == n) field = ""
      continue
    }
    if (nf == n) field = field c
  }
  return field
}

function count_keys(prefix, team,    k, cnt) {
  cnt = 0
  for (k in seen) {
    if (index(k, prefix SUBSEP team SUBSEP) == 1) cnt++
  }
  return cnt
}

BEGIN {
  # Load team mapping
  while ((getline line < team_map) > 0) {
    split(line, parts, "\t")
    teams[parts[1]] = parts[2]
    team_exists[parts[2]] = 1
    team_members[parts[2]]++
  }
  close(team_map)
}

NR == 1 { next } # skip header

{
  author = csv_field($0, 3)
  merged_at = csv_field($0, 4)
  merged_date = substr(merged_at, 1, 10)

  team = teams[author]
  if (team == "") next

  if (merged_date >= date90) {
    count90[team]++
    seen["90" SUBSEP team SUBSEP author] = 1
  }
  if (merged_date >= date30) {
    count30[team]++
    seen["30" SUBSEP team SUBSEP author] = 1
  }
  if (merged_date >= date15) {
    count15[team]++
    seen["15" SUBSEP team SUBSEP author] = 1
  }
}

END {
  # Write volume CSV
  print "team,period,pr_count,authors_active,total_members,avg_per_active_author" > volume_csv

  # Collect team names sorted
  n = 0
  for (t in team_exists) { sorted_teams[++n] = t }
  for (i = 1; i <= n; i++)
    for (j = i+1; j <= n; j++)
      if (sorted_teams[i] > sorted_teams[j]) {
        tmp = sorted_teams[i]; sorted_teams[i] = sorted_teams[j]; sorted_teams[j] = tmp
      }

  for (i = 1; i <= n; i++) {
    t = sorted_teams[i]
    members = team_members[t]

    c = count15[t]+0; a = count_keys("15", t)
    avg = (a > 0) ? sprintf("%.1f", c/a) : "0.0"
    printf "%s,15d,%d,%d,%d,%s\n", t, c, a, members, avg >> volume_csv

    c = count30[t]+0; a = count_keys("30", t)
    avg = (a > 0) ? sprintf("%.1f", c/a) : "0.0"
    printf "%s,30d,%d,%d,%d,%s\n", t, c, a, members, avg >> volume_csv

    c = count90[t]+0; a = count_keys("90", t)
    avg = (a > 0) ? sprintf("%.1f", c/a) : "0.0"
    printf "%s,90d,%d,%d,%d,%s\n", t, c, a, members, avg >> volume_csv
  }
  close(volume_csv)

  # Write report
  print "# PR Volume by Team" > report
  print "" >> report
  printf "Report generated: %s\n", today >> report
  printf "Organization: edvisor-io\n" >> report
  print "" >> report

  periods[1] = "15d"; periods[2] = "30d"; periods[3] = "90d"
  dates[1] = date15; dates[2] = date30; dates[3] = date90

  for (p = 1; p <= 3; p++) {
    period = periods[p]
    printf "## Last %s (since %s)\n\n", period, dates[p] >> report
    printf "| Team | PRs Merged | Active Authors | Total Members | Avg PRs/Author |\n" >> report
    printf "|------|-----------|----------------|---------------|----------------|\n" >> report

    for (i = 1; i <= n; i++) {
      t = sorted_teams[i]
      members = team_members[t]

      if (period == "15d") { c = count15[t]+0; a = count_keys("15", t) }
      else if (period == "30d") { c = count30[t]+0; a = count_keys("30", t) }
      else { c = count90[t]+0; a = count_keys("90", t) }

      avg = (a > 0) ? sprintf("%.1f", c/a) : "0.0"
      printf "| %s | %d | %d | %d | %s |\n", t, c, a, members, avg >> report
    }
    print "" >> report
  }

  # Summary
  print "## Summary" >> report
  print "" >> report

  for (i = 1; i <= n; i++) {
    t = sorted_teams[i]
    printf "- **%s**: %d PRs (90d), %d PRs (30d), %d PRs (15d) — %d total members\n", \
      t, count90[t]+0, count30[t]+0, count15[t]+0, team_members[t] >> report
  }
  print "" >> report

  # Ratio comparison (90d)
  if (n >= 2) {
    t1 = sorted_teams[1]; t2 = sorted_teams[2]
    c1 = count90[t1]+0; c2 = count90[t2]+0
    if (c1 > 0 && c2 > 0) {
      if (c1 > c2) {
        ratio = c1 / c2
        printf "Over the last 90 days, **%s** merged %.1fx more PRs than **%s** (%d vs %d).\n", t1, ratio, t2, c1, c2 >> report
      } else {
        ratio = c2 / c1
        printf "Over the last 90 days, **%s** merged %.1fx more PRs than **%s** (%d vs %d).\n", t2, ratio, t1, c2, c1 >> report
      }
    }
  }

  close(report)
}
' "$PRS_CSV"

rm -f "$TEAM_MAP"

echo "Done."
echo "  Volume CSV: $VOLUME_CSV"
echo "  Report:     $REPORT"
