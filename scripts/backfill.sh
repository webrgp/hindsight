#!/bin/bash
# hindsight :: backfill — capture pre-plugin Claude Code sessions.
# Scans ~/.claude/projects/*/<session>.jsonl transcripts and writes an
# undistilled dump for every session the vault doesn't already know, so the
# normal distill runs (batch-capped) drain them into knowledge.
# Usage: backfill.sh [days]   (only sessions from the last N days; default 30; 0 = all)
set -u

. "$(dirname "$0")/lib.sh"
SESSIONS="$HINDSIGHT_HOME/sessions"
PROJECTS_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
DAYS="${1:-30}"

[ -d "$PROJECTS_DIR" ] || { echo "backfill: no transcripts at $PROJECTS_DIR"; exit 0; }
mkdir -p "$SESSIONS"

case "$DAYS" in (*[!0-9]*|'') echo "backfill: days must be a number" >&2; exit 1;; esac
if [ "$DAYS" -gt 0 ]; then set -- -mtime -"$DAYS"; else set --; fi

added=0; skipped=0
while read -r tx; do
  sid=$(basename "$tx" .jsonl)
  # Only real session transcripts (uuid names) — not agent sidechains etc.
  case "$sid" in
    ([0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]-*-*-*-*) ;;
    (*) skipped=$((skipped+1)); continue ;;
  esac

  # Already captured (live or by an earlier backfill)?
  if grep -rql "^session_id: $sid\$" "$SESSIONS" 2>/dev/null; then
    skipped=$((skipped+1)); continue
  fi

  # ponytail: crude noise filter — a session with <10 transcript lines has
  # nothing worth distilling. Raise/parse properly if it proves too blunt.
  if [ "$(wc -l < "$tx" | tr -d ' ')" -lt 10 ]; then
    skipped=$((skipped+1)); continue
  fi

  cwd=$(head -50 "$tx" | jq -r 'select(.cwd != null) | .cwd' 2>/dev/null | head -1)
  [ -n "$cwd" ] || cwd="(unknown)"
  project=$(project_for_dir "$cwd")
  started=$(head -20 "$tx" | jq -r 'select(.timestamp != null) | .timestamp' 2>/dev/null | head -1)
  updated=$(tail -20 "$tx" | jq -r 'select(.timestamp != null) | .timestamp' 2>/dev/null | tail -1)
  [ -n "$started" ] || started=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  [ -n "$updated" ] || updated="$started"
  last_msg=$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' \
    "$tx" 2>/dev/null | tail -1 | tr '\n' ' ' | perl -CS -pe '$_ = substr($_, 0, 500)' 2>/dev/null)

  short=$(printf '%s' "$sid" | head -c 8)
  file="$SESSIONS/${project}__${short}.md"
  # Same collision rule as capture.sh: never clobber another session's dump.
  [ -f "$file" ] && file="$SESSIONS/${project}__${sid}.md"

  {
    echo "---"
    echo "session_id: $sid"
    echo "project: $project"
    echo "branch: "
    echo "cwd: $cwd"
    echo "started: $started"
    echo "updated: $updated"
    echo "transcript: $tx"
    echo "distilled: false"
    echo "tags: [hindsight/session, hindsight/backfill]"
    echo "---"
    echo
    echo "# Session $short — $project (backfilled)"
    echo
    echo "## Last assistant message"
    echo "${last_msg:-(none)}"
    echo
    echo "## Git diff --stat"
    echo '```'
    echo "(backfilled — not captured at session time)"
    echo '```'
    echo
    echo "## Git status"
    echo '```'
    echo "(backfilled — not captured at session time)"
    echo '```'
  } > "$file.tmp" && mv "$file.tmp" "$file"

  # Match the dump's mtime to the transcript so distill's stale-window filter
  # (which reads file mtime) sees these as old sessions, eligible immediately.
  touch -r "$tx" "$file" 2>/dev/null
  added=$((added+1))
done < <(find "$PROJECTS_DIR" -name '*.jsonl' "$@" -mmin +30 2>/dev/null | sort)

echo "backfill: $added sessions added, $skipped skipped (already captured / too small / not a session)"
