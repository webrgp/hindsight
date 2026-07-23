---
type: data-flow
title: Distill
description: Undistilled session dumps become durable knowledge notes and skill/automation proposals.
tags: [pipeline, distill]
timestamp: 2026-07-23
---

# Trigger

Nightly, on a schedule chosen at setup time. Nightly runs skip entirely (no cost)
when fewer than `HINDSIGHT_DISTILL_THRESHOLD` sessions are undistilled. On-demand
runs (`/hindsight:distill`) pass `--force` to bypass that threshold and distill
whatever is pending; only a truly empty queue skips.

# Data in

- Every dump in `sessions/` with `distilled: false`, batched **by project** — one
  headless Claude pass per project, not per session, so a busy day in one project
  doesn't fragment into many small calls.
- Excluded: sessions touched within `HINDSIGHT_DISTILL_STALE_MIN` minutes (still
  active) and, past `HINDSIGHT_DISTILL_MAX_SESSIONS`, the oldest overflow — which
  rolls into a future run rather than blowing the per-run budget.
- Existing `knowledge/` notes and `inbox/proposals.md` — so the pass updates instead
  of duplicating what's already known.

# Transformation

A headless `claude -p` call (model + per-project USD budget both configurable) reads
the batch and:
1. Pulls out durable knowledge — conventions, gotchas, decisions with rationale,
   reusable command sequences, stated preferences — and discards one-off chatter.
2. Compares the batch's task shapes against each other and against proposal history;
   when a shape repeats, writes or updates a proposal.

Data never generalizes upward silently: a note only leaves `projects/<name>/` for
`global/` when the same knowledge is seen recurring across projects.

# Data out

- New/updated [/data/knowledge-note.md](/data/knowledge-note.md) files, scoped to
  `knowledge/global/` or `knowledge/projects/<project>/`.
- Refreshed `INDEX.md` for every scope touched.
- New/updated [/data/proposal-entry.md](/data/proposal-entry.md) rows appended to
  `inbox/proposals.md` — never a skill itself; see
  [/flows/proposal-approval.md](/flows/proposal-approval.md).
- The source dumps' `distilled` flag flips to `true`.
- If the vault is a git repo: an auto-commit, pushed if `origin` exists.

# Failure behavior

Crash-safe by checkpoint: a session is marked distilled only once its knowledge and
index updates are fully written, so a mid-run failure leaves partially-processed
sessions to retry next time rather than silently marking them done. A stale run lock
self-clears after 6 hours.

# Citations
- README.md § How it works, step 2; § Configuration
- scripts/distill.sh, scripts/distill-prompt.md
