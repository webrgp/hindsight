---
name: backfill
description: Capture old, pre-plugin Claude Code sessions from ~/.claude/projects transcripts into the hindsight vault, then distill them into knowledge. Use when hindsight was just installed and history should not be lost.
disable-model-invocation: true
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
   - **Distill now** — run the drain loop in the background (Bash
     `run_in_background`). Each `--drain` pass processes one batch (up to 20
     sessions) with no spend cap; the loop repeats until the queue is empty:
     ```bash
     while "${CLAUDE_PLUGIN_ROOT}/scripts/distill.sh" --drain; do :; done
     ```
     Exit codes drive the loop: `0` did a batch (keep going), `3` queue empty
     (drained clean), `1` a batch failed (loop stops). Because `--drain` uses
     distill's own eligibility filter as the stop signal, don't recount
     `distilled: false` yourself — that count omits the active-session filter and
     would loop forever. On exit `1`, show the `distill FAILED` line and log tail.

     Note: `--drain` runs uncapped (no `--max-budget-usd`), so a large backlog
     can cost real money. For "all history" this is the total, not per-batch.

4. **Wrap up** with `tail -20` of the distill log and a pointer to
   `/hindsight:status`.
