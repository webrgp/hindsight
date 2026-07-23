#!/bin/bash
# hindsight :: distill runner (invoked nightly by launchd, or on demand).
# Thin undistilled session transcripts -> headless claude pass updates the
# knowledge vault -> mark sessions distilled -> optional git commit & push.
# Skips (costs $0) when fewer than THRESHOLD undistilled sessions.
# bash 3.2 compatible (macOS system bash): no mapfile, no assoc arrays.
set -u

. "$(dirname "$0")/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
SESSIONS="$HINDSIGHT_HOME/sessions"
SCRATCH="$HINDSIGHT_HOME/.distill-scratch"
LOCK="$HINDSIGHT_HOME/.distill.lock"
LOG="$HINDSIGHT_HOME/logs/distill.log"
THRESHOLD="${HINDSIGHT_DISTILL_THRESHOLD:-1}"
MODEL="${HINDSIGHT_DISTILL_MODEL:-sonnet}"
BUDGET="${HINDSIGHT_DISTILL_BUDGET:-1.50}"
STALE="${HINDSIGHT_DISTILL_STALE_MIN:-30}"

mkdir -p "$HINDSIGHT_HOME/logs" "$SESSIONS"
log(){ printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >> "$LOG"; }

# Single-run lock (mkdir is atomic).
if ! mkdir "$LOCK" 2>/dev/null; then log "skip: locked"; exit 0; fi
trap 'rm -rf "$LOCK" "$SCRATCH"' EXIT

export HINDSIGHT_DISTILL=1   # stops the capture hook logging our own claude run

# Git sync is optional: only when the vault dir itself is a git repo.
# ponytail: no support for a vault nested inside a larger repo — add if ever needed.
in_git=0
if [ "$(git -C "$HINDSIGHT_HOME" rev-parse --show-toplevel 2>/dev/null)" = "$HINDSIGHT_HOME" ]; then
  in_git=1
  git -C "$HINDSIGHT_HOME" pull --rebase --autostash -q 2>>"$LOG" || log "warn: git pull failed"
fi

# Collect undistilled sessions, excluding ones touched in the last STALE min
# (the capture hook rewrites the dump each turn, so recent mtime == still active).
rm -rf "$SCRATCH"; mkdir -p "$SCRATCH"
TODO="$SCRATCH/.todo"
: > "$TODO"
find "$SESSIONS" -name '*.md' -mmin +"$STALE" 2>/dev/null | sort | while read -r f; do
  grep -q '^distilled: false' "$f" && printf '%s\n' "$f" >> "$TODO"
done
COUNT=$(wc -l < "$TODO" | tr -d ' ')
if [ "$COUNT" -lt "$THRESHOLD" ]; then log "skip: $COUNT undistilled (< $THRESHOLD)"; exit 0; fi
log "start: $COUNT undistilled sessions"

# Thin each session's transcript into scratch (fallback: the dump itself).
while read -r f; do
  proj=$(grep -m1 '^project:' "$f" | sed 's/^project: //')
  sid=$(grep -m1 '^session_id:' "$f" | sed 's/^session_id: //')
  tx=$(grep -m1 '^transcript:' "$f" | sed 's/^transcript: //')
  short=$(printf '%s' "$sid" | head -c 8)
  out="$SCRATCH/${proj}__${short}.md"
  {
    echo "# session: $sid"
    echo "# project: $proj"
    echo
    if [ -f "$tx" ]; then "$HERE/thin-transcript.sh" "$tx"; else cat "$f"; fi
  } > "$out"
done < "$TODO"

# Run the distill agent headless. Restrict tools; auto-accept edits; cap spend.
PROMPT=$(cat "$HERE/distill-prompt.md")
cd "$HINDSIGHT_HOME" || { log "no vault at $HINDSIGHT_HOME"; exit 1; }
if claude -p "$PROMPT" </dev/null \
    --model "$MODEL" \
    --permission-mode acceptEdits \
    --allowedTools "Read Write Edit Glob Grep" \
    --add-dir "$HINDSIGHT_HOME" \
    --max-budget-usd "$BUDGET" \
    --output-format json >>"$LOG" 2>&1; then
  log "distill ok"
else
  log "distill FAILED (rc=$?); leaving sessions undistilled"; exit 1
fi

# Mark processed sessions distilled (only after success).
# perl, not sed: byte-safe against emoji/UTF-8 in dumps (BSD sed chokes).
NOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
while read -r f; do
  perl -i -pe 's/^distilled: false/distilled: true/' "$f"
  grep -q '^distilled_at:' "$f" || perl -i -pe "s/^(distilled: true)\$/\$1\ndistilled_at: $NOW/" "$f"
done < "$TODO"

# Drop scratch before committing so it never lands in the vault repo.
rm -rf "$SCRATCH"

if [ "$in_git" -eq 1 ]; then
  git -C "$HINDSIGHT_HOME" add -A
  if ! git -C "$HINDSIGHT_HOME" diff --cached --quiet; then
    git -C "$HINDSIGHT_HOME" commit -q -m "distill: $COUNT sessions -> knowledge ($(date -u '+%Y-%m-%d'))"
    if git -C "$HINDSIGHT_HOME" remote get-url origin >/dev/null 2>&1; then
      git -C "$HINDSIGHT_HOME" push -q 2>>"$LOG" || log "warn: git push failed"
    fi
    log "committed"
  else
    log "nothing changed to commit"
  fi
fi
log "done: $COUNT sessions distilled"
