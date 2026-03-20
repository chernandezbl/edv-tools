#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AUTHORS_CSV="$SCRIPT_DIR/authors.csv"
DETAILS_CSV="$SCRIPT_DIR/data/pr-details.csv"
REPORT="$SCRIPT_DIR/report.md"
VOLUME_CSV="$SCRIPT_DIR/data/volume-by-team.csv"

if [ ! -f "$DETAILS_CSV" ]; then
  echo "Error: $DETAILS_CSV not found. Run fetch-pr-details.sh first."
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

echo "Analyzing PR details..."
echo "  Cutoffs: 15d=$DATE_15, 30d=$DATE_30, 90d=$DATE_90"

# Build team map
TEAM_MAP=$(mktemp)
while IFS=$'\t' read -r login name team; do
  team_lower=$(echo "$team" | tr '[:upper:]' '[:lower:]')
  if [ -n "$team_lower" ]; then
    printf '%s\t%s\n' "$login" "$team_lower"
  fi
done < <(tail -n +2 "$AUTHORS_CSV") > "$TEAM_MAP"

# pr-details.csv: repo,pr_number,author,created_at,merged_at,additions,deletions,changed_files,commits,title
LC_NUMERIC=C awk \
    -v date15="$DATE_15" -v date30="$DATE_30" -v date90="$DATE_90" -v today="$TODAY" \
    -v team_map="$TEAM_MAP" \
    -v volume_csv="$VOLUME_CSV" \
    -v report="$REPORT" \
'
function csv_field(line, n,    i, c, in_quote, field, nf) {
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

function iso_to_epoch(ts,    cmd, epoch) {
  # Convert ISO 8601 to epoch seconds using date command
  # ts format: 2026-03-13T17:11:44Z
  cmd = "date -j -f \"%Y-%m-%dT%H:%M:%SZ\" \"" ts "\" +%s 2>/dev/null"
  cmd | getline epoch
  close(cmd)
  return epoch + 0
}

function fmt_hours(h) {
  if (h < 1) return sprintf("%.0fm", h * 60)
  if (h < 24) return sprintf("%.1fh", h)
  return sprintf("%.1fd", h / 24)
}

function median(arr, n,    i, j, tmp) {
  # Simple bubble sort then pick middle
  for (i = 1; i <= n; i++)
    for (j = i + 1; j <= n; j++)
      if (arr[i] > arr[j]) { tmp = arr[i]; arr[i] = arr[j]; arr[j] = tmp }
  if (n % 2 == 1) return arr[int(n/2) + 1]
  return (arr[n/2] + arr[n/2 + 1]) / 2
}

BEGIN {
  while ((getline line < team_map) > 0) {
    split(line, parts, "\t")
    teams[parts[1]] = parts[2]
    team_exists[parts[2]] = 1
    team_members[parts[2]]++
  }
  close(team_map)
}

NR == 1 { next }

{
  author = csv_field($0, 3)
  created_at = csv_field($0, 4)
  merged_at = csv_field($0, 5)
  additions = csv_field($0, 6) + 0
  deletions = csv_field($0, 7) + 0
  changed_files = csv_field($0, 8) + 0
  commits = csv_field($0, 9) + 0

  merged_date = substr(merged_at, 1, 10)
  team = teams[author]
  if (team == "") next

  lines_changed = additions + deletions

  # Cycle time in hours
  created_epoch = iso_to_epoch(created_at)
  merged_epoch = iso_to_epoch(merged_at)
  cycle_hours = (created_epoch > 0 && merged_epoch > 0) ? (merged_epoch - created_epoch) / 3600 : 0

  # Accumulate per period
  if (merged_date >= date90) {
    count90[team]++
    seen["90" SUBSEP team SUBSEP author] = 1
    add90[team] += additions
    del90[team] += deletions
    files90[team] += changed_files
    ct90_n[team]++
    ct90_sum[team] += cycle_hours
    ct90_vals[team, ct90_n[team]] = cycle_hours
    lines90_sum[team] += lines_changed
    lines90_n[team]++
    lines90_vals[team, lines90_n[team]] = lines_changed
  }
  if (merged_date >= date30) {
    count30[team]++
    seen["30" SUBSEP team SUBSEP author] = 1
    add30[team] += additions
    del30[team] += deletions
    files30[team] += changed_files
    ct30_n[team]++
    ct30_sum[team] += cycle_hours
    ct30_vals[team, ct30_n[team]] = cycle_hours
    lines30_sum[team] += lines_changed
    lines30_n[team]++
    lines30_vals[team, lines30_n[team]] = lines_changed
  }
  if (merged_date >= date15) {
    count15[team]++
    seen["15" SUBSEP team SUBSEP author] = 1
    add15[team] += additions
    del15[team] += deletions
    files15[team] += changed_files
    ct15_n[team]++
    ct15_sum[team] += cycle_hours
    ct15_vals[team, ct15_n[team]] = cycle_hours
    lines15_sum[team] += lines_changed
    lines15_n[team]++
    lines15_vals[team, lines15_n[team]] = lines_changed
  }
}

END {
  # Sort teams
  n = 0
  for (t in team_exists) sorted_teams[++n] = t
  for (i = 1; i <= n; i++)
    for (j = i+1; j <= n; j++)
      if (sorted_teams[i] > sorted_teams[j]) {
        tmp = sorted_teams[i]; sorted_teams[i] = sorted_teams[j]; sorted_teams[j] = tmp
      }

  # --- Volume CSV ---
  print "team,period,pr_count,authors_active,total_members,avg_per_active_author,additions,deletions,avg_lines_changed,median_lines_changed,avg_cycle_hours,median_cycle_hours" > volume_csv

  for (i = 1; i <= n; i++) {
    t = sorted_teams[i]; m = team_members[t]

    # 15d
    c = count15[t]+0; a = count_keys("15", t)
    avg_pr = (a > 0) ? sprintf("%.1f", c/a) : "0.0"
    avg_lines = (c > 0) ? sprintf("%.0f", lines15_sum[t]/c) : "0"
    avg_ct = (ct15_n[t] > 0) ? sprintf("%.1f", ct15_sum[t]/ct15_n[t]) : "0.0"
    # median lines
    delete tmp_arr; for (k = 1; k <= lines15_n[t]; k++) tmp_arr[k] = lines15_vals[t, k]
    med_lines = (lines15_n[t] > 0) ? sprintf("%.0f", median(tmp_arr, lines15_n[t])) : "0"
    # median cycle time
    delete tmp_arr; for (k = 1; k <= ct15_n[t]; k++) tmp_arr[k] = ct15_vals[t, k]
    med_ct = (ct15_n[t] > 0) ? sprintf("%.1f", median(tmp_arr, ct15_n[t])) : "0.0"
    printf "%s,15d,%d,%d,%d,%s,%d,%d,%s,%s,%s,%s\n", t, c, a, m, avg_pr, add15[t]+0, del15[t]+0, avg_lines, med_lines, avg_ct, med_ct >> volume_csv

    # 30d
    c = count30[t]+0; a = count_keys("30", t)
    avg_pr = (a > 0) ? sprintf("%.1f", c/a) : "0.0"
    avg_lines = (c > 0) ? sprintf("%.0f", lines30_sum[t]/c) : "0"
    avg_ct = (ct30_n[t] > 0) ? sprintf("%.1f", ct30_sum[t]/ct30_n[t]) : "0.0"
    delete tmp_arr; for (k = 1; k <= lines30_n[t]; k++) tmp_arr[k] = lines30_vals[t, k]
    med_lines = (lines30_n[t] > 0) ? sprintf("%.0f", median(tmp_arr, lines30_n[t])) : "0"
    delete tmp_arr; for (k = 1; k <= ct30_n[t]; k++) tmp_arr[k] = ct30_vals[t, k]
    med_ct = (ct30_n[t] > 0) ? sprintf("%.1f", median(tmp_arr, ct30_n[t])) : "0.0"
    printf "%s,30d,%d,%d,%d,%s,%d,%d,%s,%s,%s,%s\n", t, c, a, m, avg_pr, add30[t]+0, del30[t]+0, avg_lines, med_lines, avg_ct, med_ct >> volume_csv

    # 90d
    c = count90[t]+0; a = count_keys("90", t)
    avg_pr = (a > 0) ? sprintf("%.1f", c/a) : "0.0"
    avg_lines = (c > 0) ? sprintf("%.0f", lines90_sum[t]/c) : "0"
    avg_ct = (ct90_n[t] > 0) ? sprintf("%.1f", ct90_sum[t]/ct90_n[t]) : "0.0"
    delete tmp_arr; for (k = 1; k <= lines90_n[t]; k++) tmp_arr[k] = lines90_vals[t, k]
    med_lines = (lines90_n[t] > 0) ? sprintf("%.0f", median(tmp_arr, lines90_n[t])) : "0"
    delete tmp_arr; for (k = 1; k <= ct90_n[t]; k++) tmp_arr[k] = ct90_vals[t, k]
    med_ct = (ct90_n[t] > 0) ? sprintf("%.1f", median(tmp_arr, ct90_n[t])) : "0.0"
    printf "%s,90d,%d,%d,%d,%s,%d,%d,%s,%s,%s,%s\n", t, c, a, m, avg_pr, add90[t]+0, del90[t]+0, avg_lines, med_lines, avg_ct, med_ct >> volume_csv
  }
  close(volume_csv)

  # --- Report ---
  print "# PR Volume & Cycle Time by Team" > report
  print "" >> report
  printf "Report generated: %s\n", today >> report
  print "Organization: edvisor-io" >> report
  print "" >> report

  periods[1] = "15d"; periods[2] = "30d"; periods[3] = "90d"
  dates[1] = date15; dates[2] = date30; dates[3] = date90

  for (p = 1; p <= 3; p++) {
    period = periods[p]
    printf "## Last %s (since %s)\n\n", period, dates[p] >> report

    printf "| Team | PRs | Active | Avg PRs/Author | +Lines | -Lines | Avg Size | Median Size | Avg Cycle | Median Cycle |\n" >> report
    printf "|------|-----|--------|----------------|--------|--------|----------|-------------|-----------|-------------|\n" >> report

    for (i = 1; i <= n; i++) {
      t = sorted_teams[i]; m = team_members[t]

      if (period == "15d") {
        c = count15[t]+0; a = count_keys("15", t)
        adds = add15[t]+0; dels = del15[t]+0
        ln = lines15_sum[t]+0; ln_n = lines15_n[t]+0
        ct_s = ct15_sum[t]+0; ct_n_val = ct15_n[t]+0
        # median lines
        delete tmp_arr; for (k = 1; k <= ln_n; k++) tmp_arr[k] = lines15_vals[t, k]
        med_l = (ln_n > 0) ? median(tmp_arr, ln_n) : 0
        # median ct
        delete tmp_arr; for (k = 1; k <= ct_n_val; k++) tmp_arr[k] = ct15_vals[t, k]
        med_c = (ct_n_val > 0) ? median(tmp_arr, ct_n_val) : 0
      } else if (period == "30d") {
        c = count30[t]+0; a = count_keys("30", t)
        adds = add30[t]+0; dels = del30[t]+0
        ln = lines30_sum[t]+0; ln_n = lines30_n[t]+0
        ct_s = ct30_sum[t]+0; ct_n_val = ct30_n[t]+0
        delete tmp_arr; for (k = 1; k <= ln_n; k++) tmp_arr[k] = lines30_vals[t, k]
        med_l = (ln_n > 0) ? median(tmp_arr, ln_n) : 0
        delete tmp_arr; for (k = 1; k <= ct_n_val; k++) tmp_arr[k] = ct30_vals[t, k]
        med_c = (ct_n_val > 0) ? median(tmp_arr, ct_n_val) : 0
      } else {
        c = count90[t]+0; a = count_keys("90", t)
        adds = add90[t]+0; dels = del90[t]+0
        ln = lines90_sum[t]+0; ln_n = lines90_n[t]+0
        ct_s = ct90_sum[t]+0; ct_n_val = ct90_n[t]+0
        delete tmp_arr; for (k = 1; k <= ln_n; k++) tmp_arr[k] = lines90_vals[t, k]
        med_l = (ln_n > 0) ? median(tmp_arr, ln_n) : 0
        delete tmp_arr; for (k = 1; k <= ct_n_val; k++) tmp_arr[k] = ct90_vals[t, k]
        med_c = (ct_n_val > 0) ? median(tmp_arr, ct_n_val) : 0
      }

      avg_pr = (a > 0) ? sprintf("%.1f", c/a) : "0.0"
      avg_size = (c > 0) ? sprintf("%.0f", ln/c) : "0"
      med_size = sprintf("%.0f", med_l)
      avg_ct = (ct_n_val > 0) ? fmt_hours(ct_s/ct_n_val) : "-"
      med_ct = (ct_n_val > 0) ? fmt_hours(med_c) : "-"

      printf "| %s | %d | %d/%d | %s | +%d | -%d | %s | %s | %s | %s |\n", \
        t, c, a, m, avg_pr, adds, dels, avg_size, med_size, avg_ct, med_ct >> report
    }
    print "" >> report
  }

  # Summary
  print "## Summary" >> report
  print "" >> report

  for (i = 1; i <= n; i++) {
    t = sorted_teams[i]
    avg_ct90 = (ct90_n[t] > 0) ? fmt_hours(ct90_sum[t]/ct90_n[t]) : "-"
    avg_size90 = (count90[t] > 0) ? sprintf("%.0f", lines90_sum[t]/count90[t]) : "0"
    printf "- **%s**: %d PRs (90d) | avg size %s lines | avg cycle %s\n", \
      t, count90[t]+0, avg_size90, avg_ct90 >> report
  }
  print "" >> report

  # Comparison
  if (n >= 2) {
    t1 = sorted_teams[1]; t2 = sorted_teams[2]
    c1 = count90[t1]+0; c2 = count90[t2]+0
    if (c1 > 0 && c2 > 0) {
      if (c1 > c2) { hi = t1; lo = t2; ch = c1; cl = c2 }
      else { hi = t2; lo = t1; ch = c2; cl = c1 }
      printf "**%s** merged %.1fx more PRs than **%s** over 90 days (%d vs %d).\n\n", hi, ch/cl, lo, ch, cl >> report
    }

    # Cycle time comparison
    ct1 = (ct90_n[t1] > 0) ? ct90_sum[t1]/ct90_n[t1] : 0
    ct2 = (ct90_n[t2] > 0) ? ct90_sum[t2]/ct90_n[t2] : 0
    if (ct1 > 0 && ct2 > 0) {
      if (ct1 < ct2) { fast = t1; slow = t2; cf = ct1; cs = ct2 }
      else { fast = t2; slow = t1; cf = ct2; cs = ct1 }
      printf "**%s** has faster cycle time: %s avg vs %s for **%s** (90d).\n", fast, fmt_hours(cf), fmt_hours(cs), slow >> report
    }
  }

  close(report)
}
' "$DETAILS_CSV"

rm -f "$TEAM_MAP"

echo "Done."
echo "  Volume CSV: $VOLUME_CSV"
echo "  Report:     $REPORT"
