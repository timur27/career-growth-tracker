# Career Growth Tracker

Track what you **actually learn** from AI coding sessions — not what the AI did for you.

A Claude Code skill that extracts learning moments from your conversations, distinguishes genuine understanding from passive AI assistance, and stores structured events locally as JSONL.

## Install

```bash
claude skill add /path/to/career-growth-tracker
```

## Usage

### 1. Initialize

```
/career-growth-tracker:setup
```

Creates `~/.career-tracker/` with a JSONL log and state file.

### 2. Capture learning after a session

```
/career-growth-tracker:capture
```

Analyzes your current conversation for moments where **you** learned something (not where the AI just did the work). Shows candidates for your approval before saving.

### 3. View your history

```
/career-growth-tracker:summary
```

Grouped by dimension, filterable by time and repo.

## What counts as learning?

The extraction looks for specific signals:

- **You drove the reasoning** — asked "why", proposed a hypothesis, directed investigation
- **You chose between options** — evaluated tradeoffs and picked an approach with rationale
- **You applied a concept to a new context** — transferred knowledge beyond where it was introduced
- **You asked to understand, not just fix** — sought the mechanism, not just the solution
- **You corrected the AI** — spotted a mistake and explained why

It excludes passive consumption: accepting code unchanged, saying "ok thanks", asking the AI to "just do it."

## Dimensions

| Dimension | What it covers |
|-----------|---------------|
| `analytical-thinking` | Debugging by reasoning, root cause analysis, breaking down problems |
| `software-patterns` | Design patterns, architecture decisions, abstractions |
| `tradeoffs` | Evaluating options, understanding costs/benefits |
| `dev-practices` | Tools, workflows, testing, deployment, code organization |

## Storage

All data is local. No accounts, no cloud.

```
~/.career-tracker/
├── state.json
└── logs/
    └── events.jsonl
```

## License

MIT
