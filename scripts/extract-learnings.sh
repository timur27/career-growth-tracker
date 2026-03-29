#!/usr/bin/env bash
set -euo pipefail

TRACKER_DIR="$HOME/.career-tracker"
EVENTS_FILE="$TRACKER_DIR/logs/events.jsonl"
LOG_FILE="$TRACKER_DIR/logs/automation.log"
CLAUDE_PROJECTS_DIR="$HOME/.claude/projects"
MAX_CHARS=32000
DRY_RUN=false
TARGET_DATE=""

# Parse args: [DATE] [--dry-run] in any order
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) TARGET_DATE="$arg" ;;
    *) echo "Usage: extract-learnings.sh [YYYY-MM-DD] [--dry-run]" >&2; exit 1 ;;
  esac
done
TARGET_DATE="${TARGET_DATE:-$(date +%Y-%m-%d)}"

EXTRACTION_PROMPT='You are a learning extraction engine. Analyze the following conversation between a developer (USER) and an AI assistant (ASSISTANT).

Extract moments where the DEVELOPER genuinely learned something. You are looking for evidence of understanding, not mere exposure.

INCLUDE moments where the developer:
- Drove the reasoning: asked "why", proposed a hypothesis, directed investigation (signal: developer-drove-reasoning)
- Chose between options: evaluated approaches against criteria, picked one with rationale (signal: developer-chose-tradeoff)
- Applied a concept to a new context: used something learned earlier in a different part of code (signal: developer-applied-concept)
- Asked to understand: "why does this work?", "explain the reasoning" — seeking understanding, not just a fix (signal: developer-asked-why)
- First encounter + engagement: new concept introduced AND developer engaged with it via questions, restating, or applying (signal: first-encounter)
- Corrected the AI: spotted a mistake, explained why, guided toward the right answer (signal: developer-corrected-ai)

EXCLUDE these patterns:
- AI explained something, developer said "ok" or "thanks" — passive consumption
- AI wrote code, developer accepted unchanged without discussion — delegation
- Developer said "just do it" or "fix this" — no engagement
- Pattern applied only in the exact context AI suggested — following instructions
- "Cool, didn'\''t know that" with no follow-up — surface awareness

CALIBRATION:
- When in doubt, do NOT include. False negatives are better than false positives.
- Zero learning moments is a normal, common result. Do not pad the output.
- Never attribute learning for things the AI figured out. The developer watching the AI solve a problem is NOT the developer learning to solve it.
- Evidence must reference specific things from the conversation.

DIMENSIONS (use exactly one per event):
- analytical-thinking: debugging by reasoning, root cause analysis, breaking down problems
- software-patterns: design patterns, architecture decisions, abstractions
- tradeoffs: evaluating options, understanding costs/benefits, choosing approaches
- dev-practices: tools, workflows, testing, deployment, code organization

OUTPUT FORMAT:
Return ONLY newline-delimited JSON. One JSON object per line. No markdown fencing, no commentary, no explanation.
Each object must have exactly these fields:
{"concept":"<2-8 word label>","dimension":"<one of the 4 keys>","signal":"<signal key>","evidence":"<1-2 sentences referencing specific conversation details>","confidence":"<high|medium|low>"}

If there are zero learning moments, return nothing (empty output).

CONVERSATION:
'

validate_env() {
  local missing=()
  command -v jq &>/dev/null || missing+=("jq")
  command -v claude &>/dev/null || missing+=("claude")
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Error: Missing required tools: ${missing[*]}" >&2
    exit 1
  fi
  if [[ ! -d "$CLAUDE_PROJECTS_DIR" ]]; then
    echo "Error: Claude projects directory not found at $CLAUDE_PROJECTS_DIR" >&2
    exit 1
  fi
  mkdir -p "$TRACKER_DIR/logs"
  touch "$EVENTS_FILE"
}

log_msg() {
  local status="$1"; shift
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$status] $*" >> "$LOG_FILE"
}

find_sessions() {
  local day_start day_end
  day_start=$(date -j -f '%Y-%m-%d %H:%M:%S' "${TARGET_DATE} 00:00:00" '+%s')
  day_end=$(( day_start + 86400 ))

  for f in "$CLAUDE_PROJECTS_DIR"/*/*.jsonl; do
    [[ -f "$f" ]] || continue
    local mtime
    mtime=$(stat -f '%m' "$f")
    if (( mtime >= day_start && mtime < day_end )); then
      echo "$f"
    fi
  done
}

extract_repo_context() {
  local session_file="$1"
  local cwd
  cwd=$(jq -r 'select(.type == "user") | .cwd // empty' "$session_file" | head -1)

  if [[ -z "$cwd" ]]; then
    echo "unknown|unknown"
    return
  fi

  local repo_path
  repo_path=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")
  local repo
  repo=$(basename "$repo_path")
  echo "${repo_path}|${repo}"
}

get_commit_for_date() {
  local repo_path="$1"
  if [[ ! -d "$repo_path/.git" ]]; then
    echo "unknown"
    return
  fi
  local next_day
  next_day=$(date -j -v+1d -f '%Y-%m-%d' "$TARGET_DATE" '+%Y-%m-%d')
  # Latest commit on or before target date
  git -C "$repo_path" log --oneline -1 \
    --before="${next_day}T00:00:00" \
    --format='%h' 2>/dev/null || echo "unknown"
}

serialize_conversation() {
  local session_file="$1"
  local full_text
  full_text=$(jq -r '
    if .type == "user" then
      if (.message.content | type) == "string" then
        "USER: " + .message.content
      elif (.message.content | type) == "array" then
        [.message.content[] | select(.type == "text") | .text] |
        if length > 0 then "USER: " + join("\n") else empty end
      else empty end
    elif .type == "assistant" then
      if (.message.content | type) == "array" then
        [.message.content[] | select(.type == "text") | .text] |
        if length > 0 then "ASSISTANT: " + join("\n") else empty end
      else empty end
    else empty end
  ' "$session_file")
  printf '%s' "${full_text:0:$MAX_CHARS}"
}

run_extraction() {
  local conversation_text="$1"
  printf '%s%s' "$EXTRACTION_PROMPT" "$conversation_text" | \
    claude -p \
      --model sonnet \
      --tools "" \
      --no-session-persistence \
      --max-budget-usd 0.25 \
      2>/dev/null || true
}

enrich_events() {
  local raw_events="$1"
  local repo="$2"
  local repo_path="$3"
  local commit="$4"
  local base_ts
  base_ts=$(date -u +%s)
  local counter=0

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Must be valid JSON with all required fields
    if ! echo "$line" | jq -e '.concept and .dimension and .signal and .evidence and .confidence' &>/dev/null; then
      continue
    fi
    # Validate dimension
    local dim
    dim=$(echo "$line" | jq -r '.dimension')
    case "$dim" in
      analytical-thinking|software-patterns|tradeoffs|dev-practices) ;;
      *) continue ;;
    esac

    local unix_ts=$(( base_ts + counter ))
    local hex
    hex=$(printf '%04x' $((RANDOM % 65536)))
    local id="evt_${unix_ts}_${hex}"
    local ts
    ts=$(date -u -r "$unix_ts" '+%Y-%m-%dT%H:%M:%SZ')

    echo "$line" | jq -c \
      --arg id "$id" \
      --arg ts "$ts" \
      --arg repo "$repo" \
      --arg repo_path "$repo_path" \
      --arg commit "$commit" \
      '. + {id: $id, ts: $ts, repo: $repo, repo_path: $repo_path, commit: $commit, source: "extraction"}'

    counter=$((counter + 1))
  done <<< "$raw_events"
}

dedup_events() {
  local enriched_events="$1"
  local existing
  existing=$(jq -r "select(.ts | startswith(\"$TARGET_DATE\")) | .repo + \"|\" + .concept" "$EVENTS_FILE" 2>/dev/null || true)

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local key
    key=$(echo "$line" | jq -r '.repo + "|" + .concept')
    if echo "$existing" | grep -qxF "$key" 2>/dev/null; then
      continue
    fi
    echo "$line"
  done <<< "$enriched_events"
}

append_events() {
  local final_events="$1"
  local count=0

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$DRY_RUN" == true ]]; then
      echo "[DRY RUN] $line" >&2
    else
      echo "$line" >> "$EVENTS_FILE"
    fi
    count=$((count + 1))
  done <<< "$final_events"

  echo "$count"
}

main() {
  validate_env

  local sessions
  sessions=$(find_sessions)

  if [[ -z "$sessions" ]]; then
    echo "No sessions found for $TARGET_DATE"
    log_msg "SKIP" "target_date=$TARGET_DATE sessions=0 events=0"
    exit 0
  fi

  local session_count=0
  local total_events=0
  local repos_seen=()

  while IFS= read -r session_file; do
    [[ -z "$session_file" ]] && continue
    session_count=$((session_count + 1))

    local context
    context=$(extract_repo_context "$session_file")
    local repo_path="${context%%|*}"
    local repo="${context##*|}"

    local commit
    commit=$(get_commit_for_date "$repo_path")

    local conversation
    conversation=$(serialize_conversation "$session_file")

    if [[ ${#conversation} -lt 200 ]]; then
      continue
    fi

    echo "Processing session: $repo ($(basename "$session_file"))..."

    local raw_events
    raw_events=$(run_extraction "$conversation")

    if [[ -z "$raw_events" ]]; then
      continue
    fi

    local enriched
    enriched=$(enrich_events "$raw_events" "$repo" "$repo_path" "$commit")

    if [[ -z "$enriched" ]]; then
      continue
    fi

    local deduped
    deduped=$(dedup_events "$enriched")

    if [[ -n "$deduped" ]]; then
      local count
      count=$(append_events "$deduped")
      total_events=$((total_events + count))

      if [[ ! " ${repos_seen[*]:-} " =~ " ${repo} " ]]; then
        repos_seen+=("$repo")
      fi
    fi
  done <<< "$sessions"

  local repo_count=${#repos_seen[@]}

  if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY RUN] Would have written $total_events events from $session_count sessions across $repo_count repos"
    log_msg "DRY_RUN" "target_date=$TARGET_DATE sessions=$session_count events=$total_events repos=$repo_count"
  elif [[ $total_events -gt 0 ]]; then
    echo "Extracted $total_events events from $session_count sessions across $repo_count repos"
    log_msg "SUCCESS" "target_date=$TARGET_DATE sessions=$session_count events=$total_events repos=$repo_count"
  else
    echo "No learning moments found in $session_count sessions for $TARGET_DATE"
    log_msg "SKIP" "target_date=$TARGET_DATE sessions=$session_count events=0"
  fi
}

main
