# Update Log

## 2026-07-23
* **Creation**: Scaffolded the Hindsight bundle with `okf_init.py` — see [getting started](getting-started.md).
* **Data flows documented**: added `flows/` (core-pipeline, capture, distill, inject, proposal-approval, backfill, dashboard, reset) and `data/` (vault, session-dump, knowledge-note, proposal-entry), covering how data moves through the plugin end to end. Source: README.md and the scripts it describes.
* **Distill trigger updated**: on-demand `/hindsight:distill` now passes `--force` to bypass `HINDSIGHT_DISTILL_THRESHOLD`; refreshed `flows/distill.md`. Source: scripts/distill.sh.
* **Drain mode added**: `distill.sh --drain` (force + no budget cap, exits `3` on empty queue) lets backfill loop bounded batches until the queue is empty; refreshed `flows/distill.md` and `flows/backfill.md`. Source: scripts/distill.sh, skills/backfill/SKILL.md.
