---
type: data-flow
title: Capture
description: A Claude Code session ending writes one raw dump into the vault.
tags: [pipeline, capture]
timestamp: 2026-07-23
---

# Trigger

The `Stop` lifecycle event of a Claude Code session (fires whenever the session goes
idle, not just on final exit).

# Data in

From the Stop event payload: session ID, current working directory, transcript file
path, last assistant message. From the working directory's git state (if any): branch,
diff stat, short status.

# Transformation

- Working directory → project name (git root basename, else directory basename).
- Session ID → looked up against existing dumps, so a session that changes directory
  mid-run (`cd` into another repo) keeps appending to *one* dump rather than forking a
  second one under a different project.
- Last assistant message → truncated to a fixed length.
- No LLM involved — this stage is pure bookkeeping, so it costs nothing to run on
  every single Stop event.

# Data out

One [/data/session-dump.md](/data/session-dump.md) file per session ID, written to
`sessions/` in [/data/vault.md](/data/vault.md), marked `distilled: false`.

# Failure behavior

Always succeeds from Claude Code's point of view — never blocks or errors the session
it's attached to, even if the vault is unwritable.

# Citations
- README.md § How it works, step 1
- scripts/capture.sh
