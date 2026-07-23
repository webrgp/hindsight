---
type: data-flow
title: Backfill
description: Recovers Claude Code sessions that predate hindsight's installation.
tags: [pipeline, backfill]
timestamp: 2026-07-23
---

# Trigger

The user runs `/hindsight:backfill`, typically once, right after installing the
plugin, to avoid losing pre-install history.

# Data in

Raw session transcripts already on disk under `~/.claude/projects/`, from before the
capture hook existed — the user picks a window (last 30 days, last 90, or all
history).

# Transformation

Same shape as [/flows/capture.md](/flows/capture.md) — one dump written per
transcript — but sourced from existing files instead of a live `Stop` event. Feeds
straight into [/flows/distill.md](/flows/distill.md) afterward, so a large window can
cost real money and take several distill runs. The skill offers a `--drain` loop
that empties the backlog in one go; each batch stays bounded by
`HINDSIGHT_DISTILL_MAX_SESSIONS`, but drain drops the `HINDSIGHT_DISTILL_BUDGET`
cap, so the total spend on a wide window is uncapped.

# Data out

New entries in `sessions/` ([/data/session-dump.md](/data/session-dump.md)),
`distilled: false`, indistinguishable afterward from dumps produced by the live
capture hook.

# Citations
- README.md § Usage (`/hindsight:backfill`)
- skills/backfill/SKILL.md, scripts/backfill.sh
