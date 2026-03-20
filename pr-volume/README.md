# pr-volume

Measures merged PR volume by team across multiple time windows (15, 30, 90 days).

## Usage

```bash
# 1. Fetch merged PRs (requires gh CLI authenticated to edvisor-io)
bash pr-volume/fetch-prs.sh

# 2. Generate report
bash pr-volume/analyze.sh

# 3. Review
cat pr-volume/report.md
```

## Files

| File | Description |
|------|-------------|
| `authors.csv` | Team-to-author mapping (tab-separated) |
| `fetch-prs.sh` | Fetches merged PRs via `gh search prs` |
| `analyze.sh` | Aggregates counts and generates report |
| `data/prs.csv` | Raw PR data (generated) |
| `data/volume-by-team.csv` | Aggregated counts (generated) |
| `report.md` | Markdown summary (generated) |

### Requirements

- [GitHub CLI (`gh`)](https://cli.github.com/) authenticated with access to `edvisor-io`
- Bash, awk (macOS/Linux standard tools)
