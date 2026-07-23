---
name: status
description: Show hindsight health — undistilled session queue, last distill runs, knowledge note counts per scope, and pending proposals. Read-only.
disable-model-invocation: true
---

# hindsight status

Report the current state of the hindsight system. Read-only — do not modify anything.

Vault: `HINDSIGHT_HOME` env var if set, else `~/.hindsight`. Call it `$VAULT`.
If `$VAULT` doesn't exist, say so and suggest `/hindsight:setup`.

Gather (one bash call is fine):

```bash
VAULT="${HINDSIGHT_HOME:-$HOME/.hindsight}"
echo "== queue =="
grep -rl '^distilled: false' "$VAULT/sessions" 2>/dev/null | wc -l   # undistilled
ls "$VAULT/sessions" 2>/dev/null | wc -l                             # total sessions
echo "== last distill runs =="
tail -20 "$VAULT/logs/distill.log" 2>/dev/null
echo "== knowledge =="
ls "$VAULT/knowledge/global" 2>/dev/null | grep -v INDEX | wc -l     # global notes
ls "$VAULT/knowledge/projects" 2>/dev/null                            # projects with notes
echo "== proposals =="
grep -c '^- status: proposed' "$VAULT/inbox/proposals.md" 2>/dev/null
echo "== schedule =="
launchctl list 2>/dev/null | grep hindsight || echo "(launchd job not loaded)"
```

Then summarize in a few lines: queue depth, when distill last ran and whether it
succeeded, note counts, pending proposal count (suggest `/hindsight:proposals` if > 0),
and whether the nightly job is loaded (suggest `/hindsight:setup` if not).
