# edv-tools

Quick analysis tools for the `edvisor-io` GitHub org.

## pr-volume/

Compares **apollo** and **artemis** teams across PR volume, cycle time, and PR size for 15, 30, and 90-day windows.

### Metrics

| Metric | Source | Description |
|--------|--------|-------------|
| PR count | `gh search prs` | Merged PRs per team |
| Cycle time | `createdAt` → `mergedAt` | Time from PR open to merge (avg + median) |
| PR size | `additions` + `deletions` | Lines changed per PR (avg + median) |
| Active authors | per-author counts | Team members with at least one merged PR |

### Usage

```bash
# 1. Fetch merged PRs
bash pr-volume/fetch-prs.sh

# 2. Enrich with cycle time & size (~35 min, supports resume)
bash pr-volume/fetch-pr-details.sh

# 3. Generate report
bash pr-volume/analyze-details.sh   # full report (needs step 2)
bash pr-volume/analyze.sh           # volume-only (skip step 2)

# 4. Review
cat pr-volume/report.md
```

### Files

| File | Description |
|------|-------------|
| `authors.csv` | Team-to-author mapping (tab-separated) |
| `fetch-prs.sh` | Fetches merged PRs via `gh search prs` |
| `fetch-pr-details.sh` | Enriches with size & cycle time via `gh pr view` |
| `analyze.sh` | Volume-only analysis (from `prs.csv`) |
| `analyze-details.sh` | Full analysis with cycle time & size (from `pr-details.csv`) |
| `data/prs.csv` | Raw PR list (generated) |
| `data/pr-details.csv` | Enriched PR data (generated) |
| `data/volume-by-team.csv` | Aggregated metrics (generated) |
| `report.md` | Markdown report (generated) |

### Requirements

- [GitHub CLI (`gh`)](https://cli.github.com/) authenticated with access to `edvisor-io`
- Bash, awk (macOS/Linux standard tools)
