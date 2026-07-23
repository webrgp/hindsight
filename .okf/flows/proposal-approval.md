---
type: data-flow
title: Proposal approval (the gate)
description: The one human-in-the-loop step — a proposal only becomes a real skill when approved.
tags: [pipeline, gate, human-approval]
timestamp: 2026-07-23
---

# Trigger

The user runs `/hindsight:proposals`. Never automatic — this is the deliberate
chokepoint between "the system noticed a pattern" and "the system can now act on it".

# Data in

Every row in `inbox/proposals.md` ([/data/proposal-entry.md](/data/proposal-entry.md))
with `status: proposed`.

# Transformation

The user is walked through each proposal and decides: approve, reject, or defer.
- **Approve** → a real `SKILL.md` is scaffolded at the proposed scope: project-local
  (`<project>/.claude/skills/`) if the pattern was seen in one project, global
  (`~/.claude/skills/`) if seen across two or more.
- **Reject** → the entry's `status` flips to `rejected`. Distill will not re-propose
  the same pattern shape again.
- **Defer** → left as `proposed` for a future pass.

# Data out

- An approved proposal produces a new skill file on disk, at the scope the proposal
  named — this is the only point in the whole system where hindsight's own data
  becomes new Claude Code capability rather than just context.
- `inbox/proposals.md` entries are updated in place with their new status; nothing is
  deleted (distill's history-matching depends on rejected entries staying visible).

# Citations
- README.md § Usage (`/hindsight:proposals`); § Gate
- skills/proposals/SKILL.md
