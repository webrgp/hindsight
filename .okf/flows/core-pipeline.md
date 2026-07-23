---
type: pipeline
title: Core data pipeline (capture → distill → inject → gate)
description: How a Claude Code session turns into durable knowledge and, eventually, proposed automations.
tags: [pipeline, overview]
timestamp: 2026-07-23
---

# Summary

Four stages move data from a live Claude Code session into a persistent, self-improving
knowledge vault, and back out again as context for future sessions. Three stages are
automatic (hooked to Claude Code lifecycle events or a nightly schedule); the fourth is
a human decision point.

<img src="./resources/flow.png" />

```
[Claude Code session]
        │  Stop event
        ▼
   CAPTURE ──────────▶ [/data/session-dump.md] in sessions/
        │
        │ (nightly, or on demand)
        ▼
   DISTILL ──────────▶ [/data/knowledge-note.md] in knowledge/
        │                    + [/data/proposal-entry.md] in inbox/proposals.md
        │
        ├──▶ INJECT ──▶ back into the next session's context (SessionStart event)
        │
        └──▶ GATE ────▶ human approves a proposal ──▶ a new skill/automation exists
```

# Stages

- [/flows/capture.md](/flows/capture.md) — session transcript → raw dump
- [/flows/distill.md](/flows/distill.md) — raw dumps → knowledge notes + proposals
- [/flows/inject.md](/flows/inject.md) — knowledge notes → live session context
- [/flows/proposal-approval.md](/flows/proposal-approval.md) — proposal → scaffolded skill

# Data at rest

All stage output lands in one place: [/data/vault.md](/data/vault.md), at
`$HINDSIGHT_HOME` (default `~/.hindsight`) — separate from any project repo.

# Side flows

Three flows touch the same vault outside the nightly cadence:

- [/flows/backfill.md](/flows/backfill.md) — pulls in sessions that predate the plugin
- [/flows/dashboard.md](/flows/dashboard.md) — renders the vault as an HTML report
- [/flows/reset.md](/flows/reset.md) — deletes or re-queues vault data on request

# Invariant: no data crosses without agreement on "project"

Capture and inject both derive a project name from the working directory (git root
name, else directory name) independently, at different times. If they ever disagree,
knowledge written for a session lands in the wrong project's scope and never gets
surfaced back to it. Every stage that reads or writes `knowledge/projects/<project>/`
depends on this staying consistent.

# Invariant: distill's own activity is invisible to capture/inject

Distill's headless Claude pass is itself a Claude Code run. Without a guard it would
capture itself (feeding its own output back in as a new raw dump) and read injected
context from prior distill runs (drifting away from the user's real sessions). Both
capture and inject skip any run flagged as a distill pass.

# Citations
- README.md (pipeline diagram, stage descriptions, configuration table)
