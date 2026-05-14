# Claude Code Usage

A Noctalia bar widget and panel for tracking Claude Code session limits and API cost in real time.

## Features

- **Bar widget** — shows current session usage percentage (e.g. `32%`)
- **Panel** — CodexBar-style layout with:
  - **Session** progress bar — 5-hour rolling window with animated fill and reset countdown
  - **Weekly** progress bar — 7-day window with day-accurate reset time
  - **Cost** — today's spend + token count, monthly total and session count

## Requirements

- [Claude Code](https://claude.ai/code) CLI installed and authenticated (`~/.claude/.credentials.json` must exist)
- `python3` available in PATH
- The helper script installed at `~/.local/bin/claude-usage-stats` (included in this plugin — copy it manually)

## Setup

1. Copy `claude-usage-stats` to `~/.local/bin/` and make it executable:
   ```bash
   cp claude-usage-stats ~/.local/bin/claude-usage-stats
   chmod +x ~/.local/bin/claude-usage-stats
   ```
2. Enable the plugin in Noctalia settings and add it to your bar.

## How it works

**Usage limits** are fetched from the Anthropic OAuth API:
```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <token from ~/.claude/.credentials.json>
anthropic-beta: oauth-2025-04-20
```
Results are cached to `~/.cache/claude-usage-limits.json` so the panel stays populated during API rate-limit windows.

**Cost** is computed locally by parsing `~/.claude/projects/**/*.jsonl` and summing token usage against current model pricing (Sonnet 4.6, Opus 4.7, Haiku 4.5).

## Settings

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `displayMode` | `"alwaysShow"` \| `"alwaysHide"` | `"alwaysShow"` | Whether to always show the bar pill |
| `pollInterval` | number (ms) | `60000` | How often to refresh data |

## Colour coding

Progress bars use the Noctalia theme colours:
- **Primary** (blue) — 0–50%
- **Tertiary** (amber) — 50–80%
- **Error** (red) — 80–100%
