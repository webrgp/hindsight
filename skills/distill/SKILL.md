---
name: distill
description: Run a hindsight distill pass right now instead of waiting for the nightly schedule. Thins undistilled session transcripts and folds them into the knowledge vault.
---

# hindsight distill (run now)

Run the distill pass immediately.

1. Run it in the background (it spawns a headless `claude` call and can take a few
   minutes):
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/distill.sh"
   ```
   Use the Bash tool's `run_in_background` option.

2. When it finishes, show the outcome:
   ```bash
   tail -10 "${HINDSIGHT_HOME:-$HOME/.hindsight}/logs/distill.log"
   ```

3. Interpret the log for the user: `skip: N undistilled` means nothing stale to
   process (sessions touched in the last 30 min are deliberately skipped as
   still-active — `HINDSIGHT_DISTILL_STALE_MIN` controls this); `skip: locked` means a
   run is already in progress; `distill ok` + `done` means knowledge was updated —
   mention any new proposals in `inbox/proposals.md`.
