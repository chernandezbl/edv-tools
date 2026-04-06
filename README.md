# edv-tools

General-purpose monorepo for quick tasks and scripts at Edvisor. Uses [npm workspaces](https://docs.npmjs.com/cli/using-npm/workspaces) + [Turborepo](https://turbo.build/) for orchestration.

## Projects

| Project | Description |
|---------|-------------|
| [pr-volume](tools/pr-volume/) | Compares team PR volume, cycle time, and PR size across configurable time windows. |
| [gdrive](tools/gdrive/) | Node CLI — convert CSV/Markdown to Google Sheets, Slides, or Docs. |

## Structure

```
tools/
├── pr-volume/   Bash scripts — PR volume, cycle time, and size analysis
└── gdrive/      Node CLI — convert CSV/Markdown to Google Sheets, Slides, or Docs
```

## Setup

```bash
npm install
```

## Tools

### pr-volume

Compares team performance across PR volume, cycle time, and PR size for 15/30/90-day windows. Pure bash — requires `gh` CLI authenticated to `edvisor-io`.

```bash
# Run via turbo
npm run fetch              # fetch merged PRs
npm run fetch-details      # enrich with cycle time & size (~35 min, supports resume)
npm run analyze            # volume-only report
npm run analyze-details    # full report with cycle time & size

# Or run directly
bash tools/pr-volume/fetch-prs.sh
bash tools/pr-volume/analyze-details.sh
cat tools/pr-volume/report.md
```

### gdrive

Standalone CLI to convert local files into Google Drive documents. Useful for sharing results with the team.

```bash
# Convert CSV to Google Sheets
npx gdrive sheets tools/pr-volume/data/volume-by-team.csv --title "PR Metrics Q1"

# Convert Markdown to Google Slides
npx gdrive slides tools/pr-volume/report.md --title "PR Volume Report"

# Convert Markdown to Google Docs
npx gdrive docs tools/pr-volume/report.md --title "PR Volume Report"
```

#### Google Drive setup (one-time)

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a project and enable **Sheets**, **Slides**, **Docs**, and **Drive** APIs
3. Create an OAuth 2.0 Client ID (Desktop app type)
4. Download the JSON and save as `~/.edv-tools/credentials.json`
5. First `npx gdrive` run will open your browser for authorization

Files are created under your Google account — share with your org as needed.

## Adding a new tool

```bash
mkdir tools/my-tool
cd tools/my-tool
npm init -y
# Add scripts to package.json — automatically picked up by workspaces
```

If the new tool has turbo tasks, add them to `turbo.json` at the root.
