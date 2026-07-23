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

# Single-run lock (mkdir is atomic). A lock older than 6h means a run died
# hard (SIGKILL, power loss) and the EXIT trap never fired — reclaim it so one
# crash can't disable distill forever.
if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +360 2>/dev/null)" ]; then
  log "warn: reclaiming stale lock"; rm -rf "$LOCK"
fi
if ! mkdir "$LOCK" 2>/dev/null; then log "skip: locked"; exit 0; fi
trap 'rm -rf "$LOCK" "$SCRATCH"' EXIT
trap 'exit 1' HUP INT TERM   # untrapped signals skip the EXIT trap; route them through it

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

# Cap the batch so a huge backlog can't outgrow the per-run budget and wedge
# every subsequent night. The remainder drains on following runs.
MAXSESS="${HINDSIGHT_DISTILL_MAX_SESSIONS:-20}"
if [ "$COUNT" -gt "$MAXSESS" ]; then
  head -n "$MAXSESS" "$TODO" > "$TODO.cap" && mv "$TODO.cap" "$TODO"
  log "cap: processing $MAXSESS of $COUNT; rest deferred to next run"
  COUNT=$MAXSESS
fi
log "start: $COUNT undistilled sessions"

# Thin each session's transcript into scratch (fallback: the dump itself).
# .snap records each dump's updated: stamp so we can detect dumps rewritten
# by the capture hook while the (multi-minute) claude pass runs.
SNAP="$SCRATCH/.snap"
: > "$SNAP"
while read -r f; do
  proj=$(grep -m1 '^project:' "$f" | sed 's/^project: //')
  sid=$(grep -m1 '^session_id:' "$f" | sed 's/^session_id: //')
  tx=$(grep -m1 '^transcript:' "$f" | sed 's/^transcript: //')
  upd=$(grep -m1 '^updated:' "$f" | sed 's/^updated: //')
  short=$(printf '%s' "$sid" | head -c 8)
  out="$SCRATCH/${proj}__${short}.md"
  {
    echo "# session: $sid"
    echo "# project: $proj"
    echo
    if [ -f "$tx" ]; then "$HERE/thin-transcript.sh" "$tx"; else cat "$f"; fi
  } > "$out"
  printf '%s\t%s\t%s\n' "$f" "$upd" "$out" >> "$SNAP"
done < "$TODO"

# Run the distill agent headless. Restrict tools; auto-accept edits; cap spend.
PROMPT=$(cat "$HERE/distill-prompt.md")
RESULT="$SCRATCH/.result.json"
cd "$HINDSIGHT_HOME" || { log "no vault at $HINDSIGHT_HOME"; exit 1; }
claude -p "$PROMPT" </dev/null \
    --model "$MODEL" \
    --permission-mode acceptEdits \
    --allowedTools "Read Write Edit Glob Grep" \
    --add-dir "$HINDSIGHT_HOME" \
    --max-budget-usd "$BUDGET" \
    --output-format json >"$RESULT" 2>>"$LOG"
rc=$?
cat "$RESULT" >> "$LOG" 2>/dev/null

# One structured line per run (the dashboard reads this; the prose log is for humans).
cost=$(jq -r '.total_cost_usd // 0' "$RESULT" 2>/dev/null); [ -n "$cost" ] || cost=0
dur=$(jq -r '.duration_ms // 0' "$RESULT" 2>/dev/null); [ -n "$dur" ] || dur=0
ok=$([ "$rc" -eq 0 ] && echo true || echo false)
printf '{"date":"%s","sessions":%s,"cost":%s,"duration_ms":%s,"ok":%s}\n' \
  "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$COUNT" "$cost" "$dur" "$ok" >> "$HINDSIGHT_HOME/logs/runs.jsonl"

if [ "$rc" -eq 0 ]; then
  log "distill ok"
else
  log "distill FAILED (rc=$rc); marking only checkpointed sessions"
fi

# Mark processed sessions distilled. On success mark the whole batch; on failure
# (budget kill etc.) mark only sessions the agent checkpointed to .done, so a
# mid-run death loses at most the in-flight session instead of the whole batch.
# Either way skip any dump the capture hook rewrote mid-run — its new turns
# weren't in what we distilled, so leave it for the next run to pick up whole.
# perl, not sed: byte-safe against emoji/UTF-8 in dumps (BSD sed chokes).
DONE="$SCRATCH/.done"
NOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
marked=0
while IFS=$'\t' read -r f upd out; do
  if [ "$rc" -ne 0 ]; then
    grep -qxF "$(basename "$out")" "$DONE" 2>/dev/null || continue
  fi
  cur=$(grep -m1 '^updated:' "$f" | sed 's/^updated: //')
  if [ "$cur" != "$upd" ]; then log "defer: rewritten during run: $f"; continue; fi
  perl -i -pe 's/^distilled: false/distilled: true/' "$f"
  grep -q '^distilled_at:' "$f" || perl -i -pe "s/^(distilled: true)\$/\$1\ndistilled_at: $NOW/" "$f"
  marked=$((marked+1))
done < "$SNAP"

# Drop scratch before committing so it never lands in the vault repo.
rm -rf "$SCRATCH"

if [ "$in_git" -eq 1 ]; then
  git -C "$HINDSIGHT_HOME" add -A
  if ! git -C "$HINDSIGHT_HOME" diff --cached --quiet; then
    git -C "$HINDSIGHT_HOME" commit -q -m "distill: $marked sessions -> knowledge ($(date -u '+%Y-%m-%d'))"
    if git -C "$HINDSIGHT_HOME" remote get-url origin >/dev/null 2>&1; then
      git -C "$HINDSIGHT_HOME" push -q 2>>"$LOG" || log "warn: git push failed"
    fi
    log "committed"
  else
    log "nothing changed to commit"
  fi
fi
log "done: $marked of $COUNT sessions distilled"
[ "$rc" -eq 0 ] || exit 1
