---
name: distill
description: Run a hindsight distill pass right now instead of waiting for the nightly schedule. Thins undistilled session transcripts and folds them into the knowledge vault.
disable-model-invocation: true
---

# hindsight distill (run now)

Run the distill pass immediately.

1. Run it in the background (it spawns a headless `claude` call and can take a few
   minutes). Pass `--force` so a manual run ignores the nightly count threshold
   (`HINDSIGHT_DISTILL_THRESHOLD`) and distills whatever is pending:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/distill.sh" --force
   ```
   Use the Bash tool's `run_in_background` option. Drop `--force` only if the user
   explicitly wants the threshold respected.

2. When it finishes, show the outcome:
   ```bash
   tail -10 "${HINDSIGHT_HOME:-$HOME/.hindsight}/logs/distill.log"
   ```

3. Interpret the log for the user: `skip: 0 undistilled` means nothing stale to
   process (sessions touched in the last 30 min are deliberately skipped as
   still-active — `HINDSIGHT_DISTILL_STALE_MIN` controls this; with `--force` only a
   truly empty queue skips); `skip: locked` means a run is already in progress;
   `distill ok` + `done` means knowledge was updated — mention any new proposals in
   `inbox/proposals.md`.
