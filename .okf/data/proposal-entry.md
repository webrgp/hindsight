---
type: data-object
title: Proposal entry
description: One detected repeated-task pattern, waiting on a human decision.
tags: [storage, distill, proposals]
timestamp: 2026-07-23
---

# Where

One entry per pattern, appended to `inbox/proposals.md` in
[/data/vault.md](/data/vault.md) — a single running file, not one file per proposal.

# Shape

`seen` (count + which projects), `what` (the repeated task in one line), `proposed
skill` (name + description), `scope` (`project:<name>` if seen in one project,
`global` if seen in two or more), `automation` (`manual-skill` | `on-demand-skill` |
`local-cron` | `remote-routine`, based on whether it needs local files/secrets vs. is
self-contained), `confidence` (`low` | `med` | `high`), `status`
(`proposed` | `rejected` — approved entries become a skill and the entry is left as a
record, not deleted).

# Lifecycle

Created or updated by [/flows/distill.md](/flows/distill.md) when a task shape recurs
across sessions (never on a single observation). A `rejected` entry blocks the same
pattern from being re-proposed. Consumed by
[/flows/proposal-approval.md](/flows/proposal-approval.md), the only flow allowed to
turn a `proposed` entry into an actual skill file — distill itself never creates
skills, crons, or routines.

# Citations
- scripts/distill-prompt.md (proposal format, rules)
- skills/proposals/SKILL.md
