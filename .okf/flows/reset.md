---
type: data-flow
title: Reset
description: Deletes or re-queues vault data on explicit request. The only flow that removes data.
tags: [pipeline, reset, destructive]
timestamp: 2026-07-23
---

# Trigger

The user runs `/hindsight:reset` and picks a scope. Every destructive option confirms
before touching anything.

# Data in / out, by scope

- **Re-queue** — flips selected [/data/session-dump.md](/data/session-dump.md)
  entries' `distilled` flag back to `false`, so the next distill run reprocesses them.
  Nothing is deleted.
- **Wipe knowledge** — deletes `knowledge/` (and its `INDEX.md` files); `sessions/`
  and `inbox/proposals.md` are untouched, so a subsequent distill run can rebuild
  knowledge from the same source dumps.
- **Factory reset** — deletes the entire vault, including the launchd schedule.
  Equivalent to never having run `/hindsight:setup`.

# Citations
- README.md § Usage (`/hindsight:reset`)
- skills/reset/SKILL.md
