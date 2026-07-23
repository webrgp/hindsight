#!/bin/bash
# hindsight :: distill runner (invoked nightly by launchd, or on demand).
# Thin undistilled session transcripts -> one headless claude pass PER PROJECT
# updates the knowledge vault -> mark sessions distilled -> optional git
# commit & push. Sessions are batched by project so each claude pass stays
# scoped to one project's knowledge/proposals instead of mixing projects.
# Skips (costs $0) when fewer than THRESHOLD undistilled sessions.
# bash 3.2 compatible (macOS system bash): no mapfile, no assoc arrays.
set -u

. "$(dirname "$0")/lib.sh"
HERE="$(cd "$(dirname "$0")" && pwd)"
SESSIONS="$HINDSIGHT_HOME/sessions"
STAGE="$HINDSIGHT_HOME/.distill-stage"       # all thinned sessions, before per-project split
SCRATCH="$HINDSIGHT_HOME/.distill-scratch"   # live working dir for one claude pass (path is baked into distill-prompt.md)
LOCK="$HINDSIGHT_HOME/.distill.lock"
LOG="$HINDSIGHT_HOME/logs/distill.log"
THRESHOLD="${HINDSIGHT_DISTILL_THRESHOLD:-1}"
MODEL="${HINDSIGHT_DISTILL_MODEL:-sonnet}"
BUDGET="${HINDSIGHT_DISTILL_BUDGET:-5.00}"
STALE="${HINDSIGHT_DISTILL_STALE_MIN:-30}"

# Flags for manual runs (launchd passes none):
#   --force      ignore the undistilled-count THRESHOLD; run whatever is pending.
#   --no-budget  run the claude pass with no spend cap (manual backfill drains).
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --no-budget) BUDGET="" ;;
  esac
done

mkdir -p "$HINDSIGHT_HOME/logs" "$SESSIONS"
# Log lines always land in $LOG; when run from a terminal they also echo to
# stderr so a manual run shows progress live (launchd runs stay quiet).
log(){
  line="$(date -u '+%Y-%m-%dT%H:%M:%SZ') $*"
  printf '%s\n' "$line" >> "$LOG"
  [ -t 2 ] && printf '%s\n' "$line" >&2
  return 0
}

# Single-run lock (mkdir is atomic). A lock older than 6h means a run died
# hard (SIGKILL, power loss) and the EXIT trap never fired — reclaim it so one
# crash can't disable distill forever.
if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +360 2>/dev/null)" ]; then
  log "warn: reclaiming stale lock"; rm -rf "$LOCK"
fi
if ! mkdir "$LOCK" 2>/dev/null; then log "skip: locked"; exit 0; fi
trap 'rm -rf "$LOCK" "$STAGE" "$SCRATCH"; kill "${TAILPID:-}" 2>/dev/null; pkill -P $$ -x tail 2>/dev/null' EXIT
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
rm -rf "$STAGE" "$SCRATCH"; mkdir -p "$STAGE"
TODO="$STAGE/.todo"
: > "$TODO"
find "$SESSIONS" -name '*.md' -mmin +"$STALE" 2>/dev/null | sort | while read -r f; do
  grep -q '^distilled: false' "$f" && printf '%s\n' "$f" >> "$TODO"
done
COUNT=$(wc -l < "$TODO" | tr -d ' ')
if [ "$COUNT" -eq 0 ]; then log "skip: 0 undistilled"; exit 0; fi
if [ "$FORCE" -ne 1 ] && [ "$COUNT" -lt "$THRESHOLD" ]; then log "skip: $COUNT undistilled (< $THRESHOLD)"; exit 0; fi

# Cap the batch so a huge backlog can't outgrow the per-run budget and wedge
# every subsequent night. The remainder drains on following runs.
MAXSESS="${HINDSIGHT_DISTILL_MAX_SESSIONS:-20}"
if [ "$COUNT" -gt "$MAXSESS" ]; then
  head -n "$MAXSESS" "$TODO" > "$TODO.cap" && mv "$TODO.cap" "$TODO"
  log "cap: processing $MAXSESS of $COUNT; rest deferred to next run"
  COUNT=$MAXSESS
fi
log "start: $COUNT undistilled sessions"

# Thin each session's transcript into the stage dir (fallback: the dump itself).
# .snap records each dump's updated: stamp so we can detect dumps rewritten
# by the capture hook while the (multi-minute) claude pass runs.
SNAP="$STAGE/.snap"
: > "$SNAP"
while read -r f; do
  proj=$(grep -m1 '^project:' "$f" | sed 's/^project: //')
  sid=$(grep -m1 '^session_id:' "$f" | sed 's/^session_id: //')
  tx=$(grep -m1 '^transcript:' "$f" | sed 's/^transcript: //')
  upd=$(grep -m1 '^updated:' "$f" | sed 's/^updated: //')
  short=$(printf '%s' "$sid" | head -c 8)
  out="$STAGE/${proj}__${short}.md"
  log "thin: ${proj}__${short}"
  {
    echo "# session: $sid"
    echo "# project: $proj"
    echo
    if [ -f "$tx" ]; then "$HERE/thin-transcript.sh" "$tx"; else cat "$f"; fi
  } > "$out"
  printf '%s\t%s\t%s\t%s\n' "$f" "$upd" "$out" "$proj" >> "$SNAP"
done < "$TODO"

# One project per line, in the order first seen.
PROJECTS="$STAGE/.projects"
awk -F'\t' '!seen[$4]++{print $4}' "$SNAP" > "$PROJECTS"
NPROJ=$(wc -l < "$PROJECTS" | tr -d ' ')
log "batching: $NPROJ project(s)"

PROMPT=$(cat "$HERE/distill-prompt.md")
cd "$HINDSIGHT_HOME" || { log "no vault at $HINDSIGHT_HOME"; exit 1; }

total_marked=0
overall_rc=0
while read -r proj; do
  [ -z "$proj" ] && continue
  PSNAP="$STAGE/.psnap"
  awk -F'\t' -v p="$proj" '$4==p' "$SNAP" > "$PSNAP"
  pcount=$(wc -l < "$PSNAP" | tr -d ' ')
  log "project $proj: $pcount session(s)"

  rm -rf "$SCRATCH"; mkdir -p "$SCRATCH"
  while IFS=$'\t' read -r f upd out _; do
    cp "$out" "$SCRATCH/$(basename "$out")"
  done < "$PSNAP"

  # Run the distill agent headless. Restrict tools; auto-accept edits; cap spend.
  # stream-json instead of json so an interactive run can watch the agent work:
  # a background tail follows the event stream and prints each tool call to
  # stderr. The final "result" event carries the same cost/duration fields the
  # old json mode returned.
  RESULT="$SCRATCH/.result.json"
  STREAM="$SCRATCH/.stream.jsonl"
  log "claude pass [$proj]: model=$MODEL budget=${BUDGET:-unlimited} — may take several minutes"
  : > "$STREAM"
  TAILPID=""
  if [ -t 2 ]; then
    tail -f "$STREAM" 2>/dev/null | jq --unbuffered -r '
      if .type=="assistant" then
        (.message.content[]? | select(.type=="tool_use")
         | "  agent: \(.name) \(.input.file_path // .input.pattern // "")")
      elif .type=="result" then
        "  agent: finished — \(.num_turns) turns, $\(.total_cost_usd)"
      else empty end' >&2 &
    TAILPID=$!
  fi
  claude -p "$PROMPT" </dev/null \
      --model "$MODEL" \
      --permission-mode acceptEdits \
      --allowedTools "Read Write Edit Glob Grep" \
      --add-dir "$HINDSIGHT_HOME" \
      ${BUDGET:+--max-budget-usd "$BUDGET"} \
      --output-format stream-json --verbose >"$STREAM" 2>>"$LOG"
  rc=$?
  # Kill both halves of the tail|jq pipeline; never `wait` on it — bash waits
  # the whole job and tail -f never exits, which deadlocks the script.
  if [ -n "$TAILPID" ]; then
    sleep 1                          # let the printer flush the final line
    kill "$TAILPID" 2>/dev/null      # the jq printer ($! is the pipeline's last process)
    pkill -P $$ -x tail 2>/dev/null  # its tail -f feeder
  fi
  jq -c 'select(.type=="result")' "$STREAM" 2>/dev/null | tail -n 1 > "$RESULT"
  cat "$RESULT" >> "$LOG" 2>/dev/null

  cost=$(jq -r '.total_cost_usd // 0' "$RESULT" 2>/dev/null); [ -n "$cost" ] || cost=0
  dur=$(jq -r '.duration_ms // 0' "$RESULT" 2>/dev/null); [ -n "$dur" ] || dur=0
  ok=$([ "$rc" -eq 0 ] && echo true || echo false)
  # One structured line per project pass (the dashboard reads this; the prose log is for humans).
  printf '{"date":"%s","project":"%s","sessions":%s,"cost":%s,"duration_ms":%s,"ok":%s}\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$proj" "$pcount" "$cost" "$dur" "$ok" >> "$HINDSIGHT_HOME/logs/runs.jsonl"

  if [ "$rc" -eq 0 ]; then
    log "distill ok [$proj] (cost=\$$cost, $((dur/1000))s)"
  else
    overall_rc=1
    log "distill FAILED [$proj] (rc=$rc); marking only checkpointed sessions"
  fi

  # Mark this project's sessions distilled. On success mark the whole subset; on
  # failure (budget kill etc.) mark only sessions the agent checkpointed to
  # .done, so a mid-run death loses at most the in-flight session instead of
  # the whole project batch. Either way skip any dump the capture hook
  # rewrote mid-run — its new turns weren't in what we distilled, so leave it
  # for the next run to pick up whole.
  # perl, not sed: byte-safe against emoji/UTF-8 in dumps (BSD sed chokes).
  DONE="$SCRATCH/.done"
  NOW=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  while IFS=$'\t' read -r f upd out _; do
    if [ "$rc" -ne 0 ]; then
      grep -qxF "$(basename "$out")" "$DONE" 2>/dev/null || continue
    fi
    cur=$(grep -m1 '^updated:' "$f" | sed 's/^updated: //')
    if [ "$cur" != "$upd" ]; then log "defer: rewritten during run: $f"; continue; fi
    perl -i -pe 's/^distilled: false/distilled: true/' "$f"
    grep -q '^distilled_at:' "$f" || perl -i -pe "s/^(distilled: true)\$/\$1\ndistilled_at: $NOW/" "$f"
    total_marked=$((total_marked+1))
  done < "$PSNAP"
done < "$PROJECTS"

# Drop stage/scratch before committing so neither lands in the vault repo.
rm -rf "$STAGE" "$SCRATCH"

if [ "$in_git" -eq 1 ]; then
  git -C "$HINDSIGHT_HOME" add -A
  if ! git -C "$HINDSIGHT_HOME" diff --cached --quiet; then
    git -C "$HINDSIGHT_HOME" commit -q -m "distill: $total_marked sessions -> knowledge, $NPROJ project(s) ($(date -u '+%Y-%m-%d'))"
    if git -C "$HINDSIGHT_HOME" remote get-url origin >/dev/null 2>&1; then
      git -C "$HINDSIGHT_HOME" push -q 2>>"$LOG" || log "warn: git push failed"
    fi
    log "committed"
  else
    log "nothing changed to commit"
  fi
fi
log "done: $total_marked of $COUNT sessions distilled across $NPROJ project(s)"
[ "$overall_rc" -eq 0 ] || exit 1
