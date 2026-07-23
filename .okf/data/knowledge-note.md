---
type: data-object
title: Knowledge note
description: A durable, distilled fact — the reusable output of the whole pipeline.
tags: [storage, distill, knowledge]
timestamp: 2026-07-23
---

# Where

`knowledge/global/<topic>.md` (cross-project) or
`knowledge/projects/<project>/<topic>.md` (single-project), inside
[/data/vault.md](/data/vault.md). Scope is deliberate: a note starts project-local and
only moves to global once the same knowledge is seen recurring across projects — it
never generalizes on a single observation.

# Shape

Short frontmatter (`tags`, `updated`) plus tight bullets: conventions, gotchas,
decisions with their rationale, reusable command sequences, stated preferences. Notes
cross-link each other with `[[note-name]]`.

# Indexes

Each scope has one `INDEX.md` — a flat list of `[[note-name]] — one-line summary`
covering only notes in that scope. Indexes are the only part of `knowledge/` that
[/flows/inject.md](/flows/inject.md) reads; kept deliberately small (target: well
under 200 lines / 25KB) because every line costs tokens on every session start.

# Lifecycle

Written and updated (never deleted) by [/flows/distill.md](/flows/distill.md), which
reads existing notes first so a topic accumulates in place instead of duplicating.
Read by [/flows/inject.md](/flows/inject.md) (indexes only) at the start of every new
session, and by a human on request when they follow an index entry to the full note.

# Citations
- README.md § How it works, step 2
- scripts/distill-prompt.md
