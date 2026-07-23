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

# --- backfill.sh ---------------------------------------------------------------
export CLAUDE_PROJECTS_DIR="$TMP/projects"
pdir="$CLAUDE_PROJECTS_DIR/-tmp-oldproj"
mkdir -p "$pdir"
old_sid="01d5e551-0000-4000-8000-000000000000"
{
  printf '{"type":"user","cwd":"/tmp/oldproj","timestamp":"2026-06-01T10:00:00Z","message":{"content":"old question"}}\n'
  printf '{"type":"assistant","timestamp":"2026-06-01T10:01:00Z","message":{"content":[{"type":"text","text":"old answer"}]}}\n'
  for i in 1 2 3 4 5 6 7 8; do printf '{"type":"user","message":{"content":"filler %s"}}\n' "$i"; done
} > "$pdir/$old_sid.jsonl"
printf '{"type":"user","message":{"content":"hi"}}\n' > "$pdir/aaaaaaaa-1111-4000-8000-000000000000.jsonl"  # too small
printf '{"type":"user","message":{"content":"hi"}}\n' > "$pdir/agent-notes.jsonl"                            # not a session uuid
touch -t 202606011002 "$pdir"/*.jsonl

BF_VAULT="$TMP/vault3"
out=$(HINDSIGHT_HOME="$BF_VAULT" "$SCRIPTS/backfill.sh" 0)
bf_dump="$BF_VAULT/sessions/oldproj__01d5e551.md"
assert "backfill adds old session" test -f "$bf_dump"
assert "backfill reports 1 added" sh -c "printf '%s' \"\$1\" | grep -q '1 sessions added'" _ "$out"
assert "backfill dump undistilled" grep -q '^distilled: false$' "$bf_dump"
assert "backfill keeps transcript timestamps" grep -q '^started: 2026-06-01T10:00:00Z$' "$bf_dump"
assert "backfill tags dump" grep -q 'hindsight/backfill' "$bf_dump"
assert "backfill dump mtime is old (distill-eligible)" \
  sh -c "find \"\$1\" -mmin +30 | grep -q ." _ "$bf_dump"
out2=$(HINDSIGHT_HOME="$BF_VAULT" "$SCRIPTS/backfill.sh" 0)
assert "backfill is idempotent" sh -c "printf '%s' \"\$1\" | grep -q '0 sessions added'" _ "$out2"
assert "backfill skips small + non-session files" \
  test "$(ls "$BF_VAULT/sessions" | wc -l | tr -d ' ')" = "1"
out3=$(HINDSIGHT_HOME="$TMP/vault4" "$SCRIPTS/backfill.sh" 7)
assert "days filter excludes older sessions" sh -c "printf '%s' \"\$1\" | grep -q '0 sessions added'" _ "$out3"
unset CLAUDE_PROJECTS_DIR

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

# --- distill.sh incremental marking (stubbed claude) --------------------------
# A budget-killed run must keep the sessions the agent checkpointed to .done.
V5="$TMP/vault5"; mkdir -p "$V5/sessions" "$V5/logs"
mkdump() { # mkdump <proj> <sid8>
  cat > "$V5/sessions/$1__$2.md" <<EOF
---
session_id: $2-0000-4000-8000-000000000000
project: $1
transcript: $TMP/no-such-transcript.jsonl
updated: 2026-06-01T10:00:00Z
distilled: false
---
stuff
EOF
  touch -t 202606011000 "$V5/sessions/$1__$2.md"
}
mkdump projA 11111111
mkdump projB 22222222

BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/claude" <<'EOF'
#!/bin/bash
# fake claude: checkpoint projA only, then die like a budget kill
basename "$(ls .distill-scratch/projA__*.md | head -1)" > .distill-scratch/.done
echo '{"total_cost_usd":0.1,"duration_ms":5,"type":"result"}'
exit 1
EOF
chmod +x "$BIN/claude"

HINDSIGHT_HOME="$V5" PATH="$BIN:$PATH" "$SCRIPTS/distill.sh"; rc5=$?
assert "killed distill exits nonzero" test "$rc5" = "1"
assert "checkpointed session marked distilled" grep -q '^distilled: true' "$V5/sessions/projA__11111111.md"
assert "checkpointed session gets distilled_at" grep -q '^distilled_at:' "$V5/sessions/projA__11111111.md"
assert "unfinished session stays undistilled" grep -q '^distilled: false' "$V5/sessions/projB__22222222.md"
assert "killed run logs partial marking" grep -q 'marking only checkpointed' "$V5/logs/distill.log"
assert "killed run reports 1 of 2" grep -q 'done: 1 of 2' "$V5/logs/distill.log"
assert "sessions batched into separate per-project passes" \
  test "$(grep -c '"project":"proj[AB]"' "$V5/logs/runs.jsonl")" = "2"

# A successful run still marks the whole batch, .done or not.
cat > "$BIN/claude" <<'EOF'
#!/bin/bash
echo '{"total_cost_usd":0.1,"duration_ms":5,"type":"result"}'
exit 0
EOF
HINDSIGHT_HOME="$V5" PATH="$BIN:$PATH" "$SCRIPTS/distill.sh"; rc6=$?
assert "successful distill exits zero" test "$rc6" = "0"
assert "success marks remaining session" grep -q '^distilled: true' "$V5/sessions/projB__22222222.md"
assert "success reports 1 of 1" grep -q 'done: 1 of 1' "$V5/logs/distill.log"

# --drain on an empty queue exits 3 (the drain loop's stop signal); plain run
# on the same empty queue still exits 0 (nightly launchd contract unchanged).
HINDSIGHT_HOME="$V5" "$SCRIPTS/distill.sh" --drain; rc_drain=$?
assert "drain on empty queue exits 3" test "$rc_drain" = "3"
HINDSIGHT_HOME="$V5" "$SCRIPTS/distill.sh"; rc_plain=$?
assert "plain run on empty queue exits 0" test "$rc_plain" = "0"

# --- build-dashboard.sh --------------------------------------------------------
# Reuse V5: two sessions + a runs.jsonl (3 project-passes: projA+projB killed run, projB-only ok run).
mkdir -p "$V5/knowledge/global" "$V5/knowledge/projects/projA" "$V5/inbox"
printf -- '---\ntags: [x]\n---\n- a fact\n' > "$V5/knowledge/projects/projA/deploys.md"
printf '# projA knowledge\n\n- [[deploys]] — how deploys work\n' > "$V5/knowledge/projects/projA/INDEX.md"
cat > "$V5/inbox/proposals.md" <<'EOF'
# hindsight proposals

## release-notes-ritual
- seen: 3 times — projects: projA
- what: draft release notes from merged PRs
- proposed skill: release-notes — drafts notes from git log
- scope: project:projA
- confidence: med
- status: proposed

## old-idea
- seen: 2 times — projects: projB
- status: rejected
EOF

HINDSIGHT_HOME="$V5" "$SCRIPTS/build-dashboard.sh" >/dev/null
dash="$V5/dashboard.html"
assert "dashboard html written" test -f "$dash"
data=$(awk '/^const DATA =$/{f=1;next} f && /^;$/{exit} f' "$dash")
assert "dashboard DATA is valid JSON" sh -c "printf '%s' \"\$1\" | jq -e . >/dev/null" _ "$data"
assert "dashboard counts sessions" \
  test "$(printf '%s' "$data" | jq '.sessions.total')" = "2"
assert "dashboard carries run history" \
  test "$(printf '%s' "$data" | jq '.runs | length')" = "3"
assert "dashboard run cost preserved" \
  test "$(printf '%s' "$data" | jq '.runs[0].cost')" = "0.1"
assert "dashboard counts knowledge notes" \
  test "$(printf '%s' "$data" | jq '.knowledge.projects[0].notes')" = "1"
assert "dashboard lists pending proposal" \
  test "$(printf '%s' "$data" | jq -r '.proposals.items[] | select(.status=="proposed") | .name')" = "release-notes-ritual"
assert "dashboard carries proposal statuses" \
  test "$(printf '%s' "$data" | jq '[.proposals.items[] | select(.status=="rejected")] | length')" = "1"
assert "dashboard counts rejected" \
  test "$(printf '%s' "$data" | jq '.proposals.rejected')" = "1"

echo
[ "$fail" -eq 0 ] && echo "all tests passed" || { echo "TESTS FAILED"; exit 1; }
