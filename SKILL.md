---
name: career-growth-tracker
description: Track what you actually learn from AI coding sessions. Extracts learning moments from conversations, distinguishes genuine understanding from passive AI assistance, and stores structured events locally as JSONL. Three commands — setup (initialize tracker), capture (extract learning from current session), summary (view learning history). Triggers for "capture learning", "what did I learn", "track my growth", "learning summary", "career tracker", "setup career tracker", "capture session", or requests to review learning history from coding sessions.
---

# Career Growth Tracker

Extract what you **actually learned** from AI coding sessions — not what the AI did for you.

```
setup → capture → summary
```

Three commands. Local JSONL storage at `~/.career-tracker/`. No accounts, no cloud.

---

## Command: `setup`

Initialize the tracker. Run once per machine.

### Steps

1. Check if `~/.career-tracker/` exists.
   - If yes: read `state.json`, print status ("N events captured since {date}"). Offer to run `capture` instead.
   - If no: continue.

2. Create `~/.career-tracker/` and `~/.career-tracker/logs/`.

3. Write `~/.career-tracker/state.json`:
```json
{
  "version": 1,
  "created_at": "<ISO 8601 now>",
  "last_capture": null,
  "total_events": 0,
  "dimensions": ["analytical-thinking", "software-patterns", "tradeoffs", "dev-practices"]
}
```

4. Print welcome:
```
Career tracker initialized at ~/.career-tracker/

Dimensions tracked:
  analytical-thinking  — Debugging by reasoning, root cause analysis, breaking down problems
  software-patterns    — Design patterns, architecture decisions, abstractions
  tradeoffs            — Evaluating options, understanding costs/benefits, choosing approaches
  dev-practices        — Tools, workflows, testing, deployment, code organization

Run /career-growth-tracker:capture after a coding session to extract what you learned.
```

5. Ask: "Want to capture learning from this session now?" If yes, run the capture flow.

---

## Command: `capture`

Extract learning moments from the current conversation.

### Steps

1. **Pre-flight.** Check `~/.career-tracker/state.json` exists. If not, tell user to run `setup`.

2. **Repo context.** Run `git rev-parse --show-toplevel` to get repo name, `git log --oneline -1` for current commit. If not in a git repo, use `"unknown"` for repo.

3. **Extract.** Analyze the conversation that happened BEFORE this capture command using the extraction rules below. Produce 0-N learning candidates.

4. **Zero candidates.** If nothing found:
   - Print: "No clear learning moments detected in this session. Not every session produces them."
   - Offer: "Want to add a manual note about something you learned?"
   - If yes, take freeform text and store with `signal: "manual-note"`, `confidence: "user-reported"`, `source: "manual"`.

5. **Present candidates.** Show numbered list:
```
Found N potential learning moments:

1. [dimension] Concept label
   "Evidence sentence referencing what happened in the session."
   Confidence: high/medium/low

2. [dimension] ...

Accept all, or type numbers to keep (e.g. "1,3"), or "none":
```

6. **Approval.**
   - "all" / "yes" → accept all
   - Comma-separated numbers → accept those only
   - "none" → discard all, offer manual note

7. **Write events.** For each approved candidate, append one JSON line to `~/.career-tracker/logs/events.jsonl`:
```json
{"id":"evt_<unix_ts>_<4hex>","ts":"<ISO 8601>","repo":"<name>","repo_path":"<full path>","commit":"<short sha>","concept":"<2-8 words>","dimension":"<key>","signal":"<key>","evidence":"<1-2 sentences>","confidence":"<high|medium|low>","source":"extraction"}
```

8. **Update state.** Update `last_capture` and increment `total_events` in `state.json`.

9. **Confirm.** Print "Captured N learning moments." with one-line summary of each.

### Extraction Rules

Analyze the conversation for moments where the **developer** (not you) genuinely learned something. Look for evidence of understanding, not just exposure.

#### Signals — INCLUDE moments where the developer:

| Signal | Key | What it looks like |
|--------|-----|-------------------|
| Drove the reasoning | `developer-drove-reasoning` | Asked "why", proposed a hypothesis, directed the investigation |
| Chose between options | `developer-chose-tradeoff` | Evaluated approaches against criteria, picked one with rationale |
| Applied to new context | `developer-applied-concept` | Used a concept from earlier in the session in a different part of the code |
| Asked to understand | `developer-asked-why` | "Why does this work?" or "explain the reasoning" — seeking understanding, not just a fix |
| First encounter + engagement | `first-encounter` | New concept introduced AND developer engaged with it (questions, restating, applying) |
| Corrected the AI | `developer-corrected-ai` | Spotted a mistake in AI's suggestion, explained why, guided toward right answer |

#### Anti-signals — EXCLUDE these:

- AI explained something, developer said "ok" / "thanks" — passive consumption, no evidence of understanding
- AI wrote code, developer accepted unchanged without discussion — delegation, not learning
- Developer said "just do it" / "fix this" — no engagement with the approach
- Pattern applied only in the exact context AI suggested — following instructions, not transferring knowledge
- "Cool, didn't know that" with no follow-up — surface awareness without depth

#### Calibration

- **When in doubt, do NOT include.** False negatives are better than false positives.
- **Zero is normal.** A 30-minute session with zero learning moments is common. Do not pad the list.
- **Never attribute learning for things YOU figured out.** The developer watching you solve a problem is not the developer learning to solve it.
- **"Good question" is not enough.** Did they engage with the answer? Ask follow-ups? Apply it?
- **Evidence must be specific.** Reference what happened in the conversation. "The developer seemed to understand X" is not valid — it must be "the developer asked about X, then applied it to Y."

#### Dimensions

| Key | What qualifies |
|-----|---------------|
| `analytical-thinking` | Breaking down problems, debugging by reasoning (not just trying things), root cause analysis, asking "why" not just "what" |
| `software-patterns` | Recognizing or choosing a design pattern, making architecture decisions, understanding abstractions, seeing when a pattern fits and when it doesn't |
| `tradeoffs` | Evaluating multiple options against criteria, understanding what you gain and lose, choosing an approach and articulating why |
| `dev-practices` | Learning a tool, adopting a workflow, understanding a testing approach, deployment strategy, code organization convention |

---

## Command: `summary`

View learning history grouped by dimension.

### Steps

1. **Pre-flight.** Check `~/.career-tracker/logs/events.jsonl` exists and is non-empty. If not: "No learning events captured yet. Run /career-growth-tracker:capture after a coding session."

2. **Read events.** Parse the JSONL file.

3. **Default view: last 30 days, grouped by dimension.**

```
Career Growth Summary (<start date> - <end date>)

analytical-thinking  ████████░░  7 events
software-patterns    █████░░░░░  4 events
tradeoffs           ███░░░░░░░  2 events
dev-practices       ████░░░░░░  3 events

analytical-thinking (7)
  Mar 20  Debugging race condition in useEffect          my-app
  Mar 15  Root cause analysis for memory leak            my-app
  Mar 08  Breaking down recursive tree traversal         utils
  ...

software-patterns (4)
  Mar 20  Repository pattern for data access             my-app
  ...

tradeoffs (2)
  ...

dev-practices (3)
  ...

Total: 16 learning moments across 4 repos
```

4. **Alternate views** (if user asks):
   - "by repo" — group by repository instead of dimension
   - "by week" — timeline view, week-by-week
   - "last 7 days" / "last 90 days" / "all time" — change time window
   - "detail on {concept}" — show full evidence text for a specific event

5. **Patterns section** (only if 20+ events exist):
```
Patterns
  Strongest dimension: analytical-thinking (44% of events)
  Gap: tradeoffs has 2 events in 30 days (lowest)
  Most active repo: my-app (56% of events)
  Capture frequency: ~3.7 events/week
```

Keep it factual. No motivational language. No "Great job!" — just data.

---

## Data Schema

### Event (one JSONL line per learning moment)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | yes | `evt_{unix_ts}_{4hex}` — unique, sortable |
| `ts` | string | yes | ISO 8601 timestamp |
| `repo` | string | yes | Repository name (basename of git root), or `"unknown"` |
| `repo_path` | string | no | Full path to repo root |
| `commit` | string | no | Short SHA of HEAD at capture time |
| `concept` | string | yes | 2-8 word label of what was learned |
| `dimension` | string | yes | One of the 4 dimension keys |
| `signal` | string | yes | Which signal triggered the extraction |
| `evidence` | string | yes | 1-2 sentence explanation with session-specific detail |
| `confidence` | string | yes | `high` / `medium` / `low` |
| `source` | string | yes | `extraction` or `manual` |

### Storage layout

```
~/.career-tracker/
├── state.json
└── logs/
    └── events.jsonl
```
