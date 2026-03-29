#!/usr/bin/env bash
set -euo pipefail

TRACKER_DIR="$HOME/.career-tracker"
EVENTS_FILE="$TRACKER_DIR/logs/events.jsonl"
SUMMARIES_DIR="$TRACKER_DIR/summaries"
LOG_FILE="$TRACKER_DIR/logs/automation.log"
TARGET_DATE="${1:-$(date +%Y-%m-%d)}"
ALL_DIMENSIONS=("analytical-thinking" "software-patterns" "tradeoffs" "dev-practices")

validate_env() {
  if ! command -v jq &>/dev/null; then
    echo "Error: jq is required. Install with: brew install jq" >&2
    exit 1
  fi
  if [[ ! -f "$EVENTS_FILE" ]]; then
    echo "Error: Events file not found at $EVENTS_FILE" >&2
    exit 1
  fi
  mkdir -p "$SUMMARIES_DIR"
}

filter_events() {
  jq -s --arg date "$TARGET_DATE" \
    '[.[] | select(.ts | startswith($date))]' \
    "$EVENTS_FILE"
}

generate_markdown() {
  local events="$1"
  local output_file="$SUMMARIES_DIR/daily-${TARGET_DATE}.md"
  local all_dims
  all_dims=$(printf '%s\n' "${ALL_DIMENSIONS[@]}" | jq -R -s 'split("\n") | map(select(. != ""))')

  echo "$events" | jq -rs --arg date "$TARGET_DATE" --argjson all_dims "$all_dims" '
    .[0] as $events |
    if ($events | length) == 0 then empty
    else
      ($events | group_by(.repo)) as $by_repo |
      ($events | length) as $total |
      ($by_repo | length) as $project_count |

      # Per-dimension counts
      ($events | group_by(.dimension) | map({key: .[0].dimension, value: length}) | from_entries) as $dim_counts |

      # Strongest dimension
      ($dim_counts | to_entries | sort_by(-.value) | .[0]) as $strongest |

      # Missing dimensions
      ($all_dims - ($dim_counts | keys)) as $missing |

      "# Learning Summary — \($date)\n\n" +

      # Per-project sections
      ($by_repo | map(
        .[0].repo as $repo |
        .[0].repo_path as $repo_path |
        (map(.commit) | unique | first) as $commit |
        group_by(.dimension) as $by_dim |

        "## \($repo)\n*Repo path: \($repo_path) | Last commit: \($commit)*\n\n" +

        ($by_dim | sort_by(.[0].dimension) | map(
          .[0].dimension as $dim |
          length as $count |
          "### \($dim) (\($count) \(if $count == 1 then "event" else "events" end))\n" +
          (map(
            "- **\(.concept)** — \(.evidence)\n  - Dimension: \(.dimension) | Signal: \(.signal) | Confidence: \(.confidence)\n"
          ) | join(""))
        ) | join("\n"))
      ) | join("\n---\n\n")) +

      "\n---\n\n## Daily Aggregate\n" +
      "- Total learning moments: \($total)\n" +
      "- Projects active: \($project_count)\n" +
      "- Strongest dimension: \($strongest.key) (\($strongest.value * 100 / $total | floor)%)\n" +
      "- Dimensions with no events: \(if ($missing | length) == 0 then "none" else ($missing | join(", ")) end)\n"
    end
  ' > "$output_file"

  echo "$output_file"
}

update_index() {
  local index_file="$SUMMARIES_DIR/INDEX.md"
  {
    echo "# Daily Summary Index"
    echo ""
    for f in $(ls -1r "$SUMMARIES_DIR"/daily-*.md 2>/dev/null | head -7); do
      local basename
      basename=$(basename "$f")
      local date_part="${basename#daily-}"
      date_part="${date_part%.md}"
      local count
      count=$(grep -c '^\- \*\*' "$f" 2>/dev/null || echo "0")
      echo "- [$date_part]($basename) — $count events"
    done
  } > "$index_file"
}

log_result() {
  local status="$1"
  local events="${2:-0}"
  local projects="${3:-0}"
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [$status] target_date=$TARGET_DATE events=$events projects=$projects" >> "$LOG_FILE"
}

main() {
  validate_env

  local events
  events=$(filter_events)

  local count
  count=$(echo "$events" | jq 'length')

  if [[ "$count" -eq 0 ]]; then
    echo "No events for $TARGET_DATE"
    log_result "SKIP"
    exit 0
  fi

  local project_count
  project_count=$(echo "$events" | jq '[.[].repo] | unique | length')

  local output_file
  output_file=$(generate_markdown "$events")

  update_index

  log_result "SUCCESS" "$count" "$project_count"
  echo "Generated $output_file ($count events, $project_count projects)"
}

main
