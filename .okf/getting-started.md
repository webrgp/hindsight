---
type: reference
title: Getting started — Hindsight
description: What hindsight is, and how to read this bundle.
tags: [getting-started]
timestamp: 2026-07-23
---

# What this is

Hindsight is a Claude Code plugin: a self-improving memory layer that learns from
Claude Code sessions, retains knowledge in a personal vault, and proposes new
skills/automations from recurring patterns. This bundle documents its **data flows** —
what moves where, on what trigger, and why — not its shell-script implementation.

# Where to start

- [/flows/index.md](flows/index.md) — the four pipeline stages (capture, distill,
  inject, gate) plus three on-demand side flows (backfill, dashboard, reset).
- [/data/index.md](data/index.md) — the data objects those flows read and write, and
  the vault that stores them.

Start at [/flows/core-pipeline.md](flows/core-pipeline.md) for the whole picture in
one file, then follow links out to individual stages and data objects as needed.

# Citations
- README.md
