---
type: data-object
title: Session dump
description: The raw, per-session record capture writes — distill's only input.
tags: [storage, capture]
timestamp: 2026-07-23
---

# Where

One file per Claude Code session, in `sessions/` within [/data/vault.md](/data/vault.md).
Named by project and a short session ID.

# Shape

Frontmatter: `project`, `session_id`, `started` (first-seen timestamp, preserved across
turns within the same session), `updated`, `distilled` (`false` until
[/flows/distill.md](/flows/distill.md) processes it), a pointer to the full transcript
file (never copied — the dump stays lightweight).

Body: working directory, git branch, a bounded diff stat and status, and the session's
last assistant message (length-capped).

# Lifecycle

Created or appended to by [/flows/capture.md](/flows/capture.md) (or
[/flows/backfill.md](/flows/backfill.md) for pre-plugin history). One dump per session
ID persists across turns — a session that changes working directory mid-run keeps
appending to the same dump rather than forking a second one.
[/flows/distill.md](/flows/distill.md) flips `distilled: true` once its knowledge is
durably written. [/flows/reset.md](/flows/reset.md) can flip it back to `false` to force
reprocessing.

# Citations
- scripts/capture.sh
