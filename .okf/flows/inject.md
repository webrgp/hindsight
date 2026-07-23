---
type: data-flow
title: Inject
description: Knowledge already in the vault is fed back into a new session as background context.
tags: [pipeline, inject]
timestamp: 2026-07-23
---

# Trigger

The `SessionStart` lifecycle event — fires when a Claude Code session begins, and
again after `/clear` or auto-compact, so distilled knowledge survives context resets.

# Data in

- `knowledge/global/INDEX.md` — always.
- `knowledge/projects/<project>/INDEX.md` — only when the session's working directory
  resolves to that project (same project-name derivation as
  [/flows/capture.md](/flows/capture.md)).

# Transformation

Concatenates the two index files, capped by `HINDSIGHT_INJECT_MAX_LINES` and
`HINDSIGHT_INJECT_MAX_BYTES`. Overflow is truncated with a visible marker rather than
silently dropped, so a session can tell its context was cut. Read-only — this stage
never writes to the vault.

# Data out

The concatenated, capped text, delivered as `additionalContext` on the session.

# Citations
- README.md § How it works, step 3; § Configuration
- scripts/inject.sh
