#!/bin/bash
# hindsight :: capture hook (Stop)
# Writes one lightweight markdown dump per session_id, pointing at the full
# transcript, so the nightly distill can read sessions without an LLM call here.
# Pure shell + jq + git. Never blocks Claude: always exits 0.
set -u

. "$(dirname "$0")/lib.sh" 2>/dev/null || exit 0
SESSIONS="$HINDSIGHT_HOME/sessions"

# Recursion guard: don't capture distill's own headless claude runs.
[ -n "${HINDSIGHT_DISTILL:-}" ] && exit 0

payload=$(cat)

# Only act on the Stop event regardless of how we're wired.
event=$(printf '%s' "$payload" | jq -r '.hook_event_name // empty' 2>/dev/null)
[ -n "$event" ] && [ "$event" != "Stop" ] && exit 0

session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)
[ -n "$session_id" ] || exit 0
cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd="$PWD"
transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty' 2>/dev/null)
last_msg=$(printf '%s' "$payload" | jq -r '.last_assistant_message // empty' 2>/dev/null \
  | tr '\n' ' ' | head -c 500)

project=$(project_for_dir "$cwd")
branch=""; diffstat=""; gitstatus=""
if git -C "$cwd" rev-parse --show-toplevel >/dev/null 2>&1; then
  branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
  diffstat=$(git -C "$cwd" diff --stat 2>/dev/null | tail -40)
  gitstatus=$(git -C "$cwd" status --short 2>/dev/null | head -40)
fi

short=$(printf '%s' "$session_id" | head -c 8)
mkdir -p "$SESSIONS" 2>/dev/null || exit 0

# One dump per session_id — NOT per project. A session that changes git-repo
# context mid-run (cd into another repo) must not fork into a second dump and
# get distilled twice. Reuse the existing dump for this session_id if present.
file=""
for existing in "$SESSIONS"/*__"$short".md; do
  [ -f "$existing" ] || continue
  if grep -q "^session_id: $session_id\$" "$existing"; then file="$existing"; break; fi
done
[ -n "$file" ] || file="$SESSIONS/${project}__${short}.md"

# Preserve the original started timestamp across turns.
now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
started=""
[ -f "$file" ] && started=$(grep -m1 '^started:' "$file" | sed 's/^started: //')
[ -n "$started" ] || started="$now"

{
  echo "---"
  echo "session_id: $session_id"
  echo "project: $project"
  echo "branch: ${branch}"
  echo "cwd: $cwd"
  echo "started: $started"
  echo "updated: $now"
  echo "transcript: $transcript"
  echo "distilled: false"
  echo "tags: [hindsight/session]"
  echo "---"
  echo
  echo "# Session $short — $project"
  echo
  echo "## Last assistant message"
  echo "${last_msg:-(none)}"
  echo
  echo "## Git diff --stat"
  echo '```'
  echo "${diffstat:-(no repo / no changes)}"
  echo '```'
  echo
  echo "## Git status"
  echo '```'
  echo "${gitstatus:-(no repo / clean)}"
  echo '```'
} > "$file.tmp" && mv "$file.tmp" "$file"

exit 0
