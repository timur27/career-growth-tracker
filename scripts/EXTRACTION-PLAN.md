# Extraction Script Build Plan

## What we're building

`scripts/extract-learnings.sh` — scans `~/.claude/projects/` for sessions on a target date,
extracts conversation text, runs LLM extraction, appends events to `~/.career-tracker/logs/events.jsonl`.

This is the missing upstream step that `daily-summary.sh` depends on.

---

## Inputs / Outputs

| | |
|---|---|
| **Input** | Target date (default: today via `date +%Y-%m-%d`) |
| **Source** | `~/.claude/projects/*/**.jsonl` filtered by file mtime |
| **Output** | Appended lines in `~/.career-tracker/logs/events.jsonl` |
| **Log** | `~/.career-tracker/logs/automation.log` |

---

## Steps

### 1. Date filtering
- Compute epoch boundaries for `TARGET_DATE` (midnight to midnight local time)
- Use `find ~/.claude/projects/ -name "*.jsonl" -newer <start> ! -newer <end>` to select files
- Skip files with no `"type":"user"` lines (empty/snapshot-only files)

### 2. Repo name extraction
- Parent folder name is the repo path with `/` → `-` (e.g. `-Users-foo-code-myrepo`)
- Strip leading `-`, replace `-` back to `/` using the known prefix `/Users/<username>/`
- Edge case: folder names with legitimate dashes — use `cwd` field from first message as ground truth

### 3. Conversation serialization
- Read each session file, extract lines where `type == "user"` or `type == "assistant"`
- For user: `message.content` is string or `[{type:"text", text:"..."}]`
- For assistant: `message.content` is array, pick blocks with `type == "text"` (skip `thinking`, `tool_use`, `tool_result`)
- Format as plain `USER: ...\nASSISTANT: ...` text, truncated to ~8000 tokens per session

### 4. LLM extraction
- Pipe serialized conversation to `claude -p "<extraction prompt>"`
- Extraction prompt must return **newline-delimited JSON**, one event object per line
- Each event must match the existing schema:
  ```json
  {"concept":"...","dimension":"...","signal":"...","evidence":"...","confidence":"..."}
  ```
- Prompt should enforce attribution rules: only count developer-initiated learning, not AI-executed patterns

### 5. Event enrichment + dedup
- Add `id`, `ts`, `repo`, `repo_path`, `commit`, `source:"extraction"` to each returned event
- Skip events where `concept` already exists in `events.jsonl` for same `repo` + same `date` (exact match)
- Append survivors to `~/.career-tracker/logs/events.jsonl`

---

## Key decisions to make during build

1. **Truncation strategy** — what to do when a session is very long (summarize first? sliding window? just truncate?)
2. **Extraction prompt** — needs careful testing against 2-3 real sessions before locking in
3. **`cwd` vs folder name** — use `cwd` from first user message as the canonical repo path (more reliable than decoding folder name)

---

## Files touched

| File | Change |
|---|---|
| `scripts/extract-learnings.sh` | new — main extraction script |
| `scripts/daily-summary.sh` | no change needed |
| `~/.career-tracker/logs/events.jsonl` | appended to (never mutated) |

---

## Testing approach

```bash
# Dry run against yesterday's sessions
bash scripts/extract-learnings.sh 2026-03-28 --dry-run   # prints events, does not write

# Real run
bash scripts/extract-learnings.sh 2026-03-28

# Then generate summary
bash scripts/daily-summary.sh 2026-03-28
```
