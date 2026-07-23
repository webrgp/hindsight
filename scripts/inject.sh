#!/bin/bash
# hindsight :: SessionStart hook — injects the vault's knowledge indexes as
# additional context. Read-only, never touches project files. Fails open: any
# error -> exit 0 silently so a broken vault never blocks session start.
#
# Fires on all SessionStart sources (startup, resume, clear, compact) so the
# context survives /clear and auto-compact too.
set +e  # never die

. "$(dirname "$0")/lib.sh" 2>/dev/null || exit 0
KNOWLEDGE="$HINDSIGHT_HOME/knowledge"
[ -d "$KNOWLEDGE" ] || exit 0

# Recursion guard: don't inject into distill's own headless claude run — it
# would burn distill budget and hand it context about a nonexistent project.
[ -n "${HINDSIGHT_DISTILL:-}" ] && exit 0

# Project identity comes from lib.sh so it always matches capture.sh.
cwd="$PWD"
project=$(project_for_dir "$cwd")
if repo=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null); then
  skills_dir="$repo/.claude/skills"
else
  skills_dir="$cwd/.claude/skills"
fi

# Compose the context block. Tagged so Claude recognizes it as background.
ctx=$(
  echo "<hindsight-knowledge>"
  echo "Indexes from your knowledge vault. Read full notes on demand:"
  echo "  $KNOWLEDGE/global/<name>.md  or  $KNOWLEDGE/projects/$project/<name>.md"
  echo

  [ -f "$KNOWLEDGE/global/INDEX.md" ] && { cat "$KNOWLEDGE/global/INDEX.md"; echo; }

  proj_index="$KNOWLEDGE/projects/$project/INDEX.md"
  if [ -f "$proj_index" ]; then
    cat "$proj_index"; echo
  else
    echo "# $project knowledge"
    echo "(no project notes yet — distill will populate as sessions accumulate)"
    echo
  fi

  # Live list of this project's installed skills (from each SKILL.md's
  # frontmatter description), so newly-installed skills appear the same day
  # without waiting on a vault refresh.
  if [ -d "$skills_dir" ]; then
    found=0
    for sk in "$skills_dir"/*/SKILL.md; do
      [ -f "$sk" ] || continue
      [ "$found" -eq 0 ] && { echo "# $project installed skills"; found=1; }
      sk_name=$(basename "$(dirname "$sk")")
      sk_desc=$(awk '/^description:/ {sub(/^description: */,""); print; exit}' "$sk")
      echo "- $sk_name — ${sk_desc:-<no description>}"
    done
    [ "$found" -eq 1 ] && echo
  fi
)

# Injection budget so a large index can't bloat every session's context.
# Mirrors Claude Code's auto-memory cap — first 200 lines OR 25KB, whichever
# comes first. Truncates on whole-line boundaries (keeps valid UTF-8) and
# leaves a visible marker, so nothing is dropped silently.
max_lines="${HINDSIGHT_INJECT_MAX_LINES:-200}"
max_bytes="${HINDSIGHT_INJECT_MAX_BYTES:-25600}"
truncated=0
if [ "$(printf '%s\n' "$ctx" | wc -l | tr -d ' ')" -gt "$max_lines" ]; then
  ctx="$(printf '%s\n' "$ctx" | head -n "$max_lines")"; truncated=1
fi
while [ "$(printf '%s' "$ctx" | wc -c | tr -d ' ')" -gt "$max_bytes" ] \
   && [ "$(printf '%s\n' "$ctx" | wc -l | tr -d ' ')" -gt 1 ]; do
  ctx="$(printf '%s\n' "$ctx" | sed '$d')"; truncated=1
done

# Hook event name from stdin; informational only, default if the parse fails.
stdin_json=$(cat 2>/dev/null)
event=$(printf '%s' "$stdin_json" | jq -r '.hook_event_name // "SessionStart"' 2>/dev/null)
[ -n "$event" ] || event="SessionStart"

# Emit JSON with additionalContext. jq -R -s handles all escaping safely.
{
  printf '%s\n' "$ctx"
  [ "$truncated" -eq 1 ] && printf '… hindsight: knowledge index truncated to the injection budget (%s lines / %s bytes). Read the full indexes under %s\n' "$max_lines" "$max_bytes" "$KNOWLEDGE"
  echo "</hindsight-knowledge>"
} | jq -R -s --arg event "$event" \
  '{hookSpecificOutput: {hookEventName: $event, additionalContext: .}}'

exit 0
