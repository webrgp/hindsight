#!/bin/bash
# hindsight :: self-checks for the hook scripts and the transcript thinner.
# Plain assert-style, no framework. Run: tests/run-tests.sh
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$HERE/../scripts"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HINDSIGHT_HOME="$TMP/vault"

fail=0
assert() { # assert <desc> <condition...>
  local desc="$1"; shift
  if "$@"; then echo "ok: $desc"; else echo "FAIL: $desc"; fail=1; fi
}

# --- capture.sh -------------------------------------------------------------
payload() {
  cat <<EOF
{"hook_event_name":"Stop","session_id":"abcdef12-3456-7890-abcd-ef1234567890",
 "cwd":"$1","transcript_path":"$TMP/transcript.jsonl",
 "last_assistant_message":"did the thing"}
EOF
}

proj="$TMP/myproj"; mkdir -p "$proj"
git -C "$proj" init -q

payload "$proj" | "$SCRIPTS/capture.sh"
dump="$HINDSIGHT_HOME/sessions/myproj__abcdef12.md"
assert "capture writes dump named project__sid8" test -f "$dump"
assert "dump has session_id" grep -q '^session_id: abcdef12-3456-7890-abcd-ef1234567890$' "$dump"
assert "dump has project" grep -q '^project: myproj$' "$dump"
assert "dump marked undistilled" grep -q '^distilled: false$' "$dump"
assert "dump has last message" grep -q 'did the thing' "$dump"

started=$(grep -m1 '^started:' "$dump")
sleep 1
payload "$proj" | "$SCRIPTS/capture.sh"
assert "recapture is idempotent (one dump)" test "$(ls "$HINDSIGHT_HOME/sessions" | wc -l | tr -d ' ')" = "1"
assert "recapture preserves started" grep -q "^$started\$" "$dump"

# Same session_id from a different dir must reuse the dump, not fork a second one.
other="$TMP/otherproj"; mkdir -p "$other"
payload "$other" | "$SCRIPTS/capture.sh"
assert "repo change mid-session doesn't fork dump" test "$(ls "$HINDSIGHT_HOME/sessions" | wc -l | tr -d ' ')" = "1"

# Non-Stop events are ignored.
echo '{"hook_event_name":"SessionStart","session_id":"ffffffff-0000-0000-0000-000000000000"}' \
  | "$SCRIPTS/capture.sh"
assert "non-Stop event ignored" test "$(ls "$HINDSIGHT_HOME/sessions" | wc -l | tr -d ' ')" = "1"

# --- inject.sh --------------------------------------------------------------
mkdir -p "$HINDSIGHT_HOME/knowledge/global" "$HINDSIGHT_HOME/knowledge/projects/myproj"
printf '# global knowledge\n\n- [[note-a]] — a global fact\n' > "$HINDSIGHT_HOME/knowledge/global/INDEX.md"
printf '# myproj knowledge\n\n- [[note-b]] — a project fact\n' > "$HINDSIGHT_HOME/knowledge/projects/myproj/INDEX.md"

out=$(cd "$proj" && echo '{"hook_event_name":"SessionStart"}' | "$SCRIPTS/inject.sh")
assert "inject emits valid JSON" sh -c "printf '%s' '$(printf '%s' "$out" | sed "s/'/'\\\\''/g")' | jq -e . >/dev/null"
ctx=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')
assert "inject includes global index" sh -c "printf '%s' \"\$1\" | grep -q 'a global fact'" _ "$ctx"
assert "inject includes project index" sh -c "printf '%s' \"\$1\" | grep -q 'a project fact'" _ "$ctx"
assert "inject sets hookEventName" test "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName')" = "SessionStart"

# Truncation budget.
big=$(cd "$proj" && echo '{}' | HINDSIGHT_INJECT_MAX_LINES=5 "$SCRIPTS/inject.sh" \
  | jq -r '.hookSpecificOutput.additionalContext')
assert "inject truncates to line budget" sh -c "printf '%s' \"\$1\" | grep -q 'truncated to the injection budget'" _ "$big"

# Missing vault fails open (no output, exit 0).
none=$(cd "$proj" && echo '{}' | HINDSIGHT_HOME="$TMP/nope" "$SCRIPTS/inject.sh")
assert "inject fails open without vault" test -z "$none"

# --- thin-transcript.sh -----------------------------------------------------
cat > "$TMP/transcript.jsonl" <<'EOF'
{"type":"user","message":{"content":"please fix the bug"}}
{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"secret reasoning"},{"type":"text","text":"fixing it now"},{"type":"tool_use","name":"Bash","input":{"command":"make test"}}]}}
{"type":"user","message":{"content":[{"type":"tool_result","content":"huge tool output"}]}}
{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}
EOF
thin=$("$SCRIPTS/thin-transcript.sh" "$TMP/transcript.jsonl")
assert "thin keeps user text" sh -c "printf '%s' \"\$1\" | grep -q 'USER: please fix the bug'" _ "$thin"
assert "thin keeps assistant text" sh -c "printf '%s' \"\$1\" | grep -q 'ASSISTANT: fixing it now'" _ "$thin"
assert "thin keeps tool name+input" sh -c "printf '%s' \"\$1\" | grep -q 'TOOL\[Bash\]: .*make test'" _ "$thin"
assert "thin drops thinking" sh -c "! printf '%s' \"\$1\" | grep -q 'secret reasoning'" _ "$thin"
assert "thin drops tool results" sh -c "! printf '%s' \"\$1\" | grep -q 'huge tool output'" _ "$thin"

# --- capture.sh collision + UTF-8 ---------------------------------------------
# Two session_ids sharing the same first 8 chars must not clobber each other.
mkdir -p "$TMP/vault2"
sidA="deadbeef-aaaa-0000-0000-000000000000"
sidB="deadbeef-bbbb-0000-0000-000000000000"
for sid in "$sidA" "$sidB"; do
  printf '{"hook_event_name":"Stop","session_id":"%s","cwd":"%s"}' "$sid" "$proj" \
    | HINDSIGHT_HOME="$TMP/vault2" "$SCRIPTS/capture.sh"
done
assert "short-id collision keeps both dumps" \
  test "$(ls "$TMP/vault2/sessions" | wc -l | tr -d ' ')" = "2"
assert "collision preserves first session's id" \
  grep -q "^session_id: $sidA\$" "$TMP/vault2/sessions/myproj__deadbeef.md"
# Re-capture of the full-id session must find its own dump again, not fork a third.
printf '{"hook_event_name":"Stop","session_id":"%s","cwd":"%s"}' "$sidB" "$proj" \
  | HINDSIGHT_HOME="$TMP/vault2" "$SCRIPTS/capture.sh"
assert "full-id dump found on recapture" \
  test "$(ls "$TMP/vault2/sessions" | wc -l | tr -d ' ')" = "2"

# Multibyte truncation must not produce invalid UTF-8.
emoji=$(python3 -c "print('🎉' * 300)" 2>/dev/null || perl -CO -e 'print "\x{1F389}" x 300')
printf '{"hook_event_name":"Stop","session_id":"utf8test-0000-0000-0000-000000000000","cwd":"%s","last_assistant_message":"%s"}' "$proj" "$emoji" \
  | HINDSIGHT_HOME="$TMP/vault2" "$SCRIPTS/capture.sh"
assert "truncated last message stays valid UTF-8" \
  sh -c 'iconv -f UTF-8 -t UTF-8 "$1" >/dev/null 2>&1' _ "$TMP/vault2/sessions/myproj__utf8test.md"

# --- inject.sh recursion guard -----------------------------------------------
guarded=$(cd "$proj" && echo '{}' | HINDSIGHT_DISTILL=1 "$SCRIPTS/inject.sh")
assert "inject skips distill's own run" test -z "$guarded"

# --- distill.sh (no-LLM paths only) ------------------------------------------
# Fresh dump is younger than STALE window -> skip, costs nothing.
"$SCRIPTS/distill.sh"
assert "distill skips active sessions" grep -q 'skip: 0 undistilled' "$HINDSIGHT_HOME/logs/distill.log"
assert "distill releases lock" test ! -d "$HINDSIGHT_HOME/.distill.lock"

# A live lock blocks the run; a stale (>6h) lock is reclaimed.
mkdir -p "$HINDSIGHT_HOME/.distill.lock"
"$SCRIPTS/distill.sh"
assert "fresh lock blocks concurrent run" grep -q 'skip: locked' "$HINDSIGHT_HOME/logs/distill.log"
touch -t 202001010000 "$HINDSIGHT_HOME/.distill.lock"
"$SCRIPTS/distill.sh"
assert "stale lock reclaimed" grep -q 'reclaiming stale lock' "$HINDSIGHT_HOME/logs/distill.log"
assert "reclaimed run completes and releases lock" test ! -d "$HINDSIGHT_HOME/.distill.lock"

echo
[ "$fail" -eq 0 ] && echo "all tests passed" || { echo "TESTS FAILED"; exit 1; }
