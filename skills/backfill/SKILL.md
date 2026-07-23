---
name: backfill
description: Capture old, pre-plugin Claude Code sessions from ~/.claude/projects transcripts into the hindsight vault, then distill them into knowledge. Use when hindsight was just installed and history should not be lost.
---

# hindsight backfill

Pull sessions that predate the plugin into the vault, then distill them.

1. **Ask how far back** (AskUserQuestion): last 30 days (default), last 90, or all
   history. Warn on "all": one distill run costs up to `HINDSIGHT_DISTILL_BUDGET`
   (default $5.00) per batch of `HINDSIGHT_DISTILL_MAX_SESSIONS` (default 20)
   sessions, so a big history takes several runs or several nights.

2. **Run the backfill** (pass days as the argument; 0 = all):
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/backfill.sh" 30
   ```
   It is idempotent — already-captured sessions are skipped, so re-running is safe.
   Report the added/skipped counts.

3. **Ask how to distill** the new backlog:
   - **Nightly drain** — do nothing; the scheduled job processes up to 20 sessions
     per night until done.
   - **Distill now** — run `"${CLAUDE_PLUGIN_ROOT}/scripts/distill.sh"` in the
     background (Bash `run_in_background`), repeatedly if the user wants the whole
     backlog done: each run processes one batch, so loop until the log shows
     `skip: 0 undistilled` — checking the remaining count between runs with
     `grep -rl '^distilled: false' "${HINDSIGHT_HOME:-$HOME/.hindsight}/sessions" | wc -l`.
     Stop looping if a run logs `distill FAILED` and show the log tail instead.

4. **Wrap up** with `tail -20` of the distill log and a pointer to
   `/hindsight:status`.
