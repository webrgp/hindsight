# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Claude Code plugin (`.claude-plugin/plugin.json`) — a self-improving memory layer. No build step, no dependencies beyond shell + `jq`. Everything is bash, markdown skills, and one HTML template.

## Commands

```sh
tests/run-tests.sh        # all self-checks (plain asserts, no framework, one file)
```

There is no lint/build. Tests run against a throwaway vault in `mktemp -d` via `HINDSIGHT_HOME`, so they never touch the real `~/.hindsight`.

## Hard constraints

- **bash 3.2 compatible** (macOS system bash): no `mapfile`, no associative arrays, no `${var,,}`.
- **Hooks must never block Claude**: `capture.sh` and `inject.sh` always exit 0 and fail open on any error.
- **UTF-8 safety**: use `perl` for truncation/in-place edits, not `head -c` or BSD `sed` (both corrupt multibyte chars in dumps).
- Scripts operate on the **vault** (`$HINDSIGHT_HOME`, default `~/.hindsight`), never on this repo. `HINDSIGHT_HOME` is the test seam.

## Architecture

Pipeline: **capture → distill → inject → gate**, all under `scripts/`, sharing `lib.sh`.

- `capture.sh` (Stop hook) — writes one markdown dump per `session_id` to `sessions/` with frontmatter (`project:`, `distilled: false`, `updated:`, transcript pointer). Idempotent per session; pure shell, no LLM.
- `distill.sh` (nightly launchd, or `/hindsight:distill`) — the heart. Thins undistilled transcripts via `thin-transcript.sh`, runs a **headless `claude -p`** (prompt in `distill-prompt.md`, tools restricted to Read/Write/Edit/Glob/Grep, budget-capped via `--max-budget-usd`) that updates `knowledge/` and appends to `inbox/proposals.md`, then flips `distilled: false → true`. Optionally commits/pushes the vault if it's a git repo.
- `inject.sh` (SessionStart hook) — cats the global + per-project `INDEX.md` files into `additionalContext`, capped by line/byte budgets. Read-only.
- `skills/*/SKILL.md` — the user-facing commands; they mostly wrap the scripts. `proposals` is the human approval gate that scaffolds real skills.
- `build-dashboard.sh` — computes a JSON blob from the vault and substitutes it at the `__DATA__` line of `templates/dashboard.html`. Pure shell.

Cross-cutting invariants to preserve when editing:

- **Project identity** comes only from `lib.sh:project_for_dir` (git root basename, else dir basename). capture and inject must always agree on it, or knowledge lands in the wrong scope.
- **Recursion guard**: distill exports `HINDSIGHT_DISTILL=1`; both hooks bail when it's set, so distill's own headless run isn't captured or injected into.
- **Crash safety in distill.sh**: mkdir lock with 6h stale reclaim; `.snap` records each dump's `updated:` stamp to skip dumps rewritten mid-run; on failure only sessions the agent checkpointed to `.done` are marked distilled. Don't simplify these away.
- **Launchd never calls the plugin path directly**: plugin cache paths change on every update, so `templates/run-distill-shim.sh` (installed to `$HINDSIGHT_HOME/bin` by setup) resolves the current install path from `installed_plugins.json` at run time.

## Conventions

- `ponytail:` comments mark deliberate shortcuts, naming the ceiling and upgrade path. Keep the style when taking one.
- Config is env vars with defaults (`HINDSIGHT_*`); the full table lives in README.md — keep it in sync when adding one.
