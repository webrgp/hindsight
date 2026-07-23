---
type: data-flow
title: Dashboard
description: Renders the whole vault's state as a single self-contained HTML page.
tags: [pipeline, dashboard, reporting]
timestamp: 2026-07-23
---

# Trigger

The user runs `/hindsight:dashboard`. Read-only, no LLM cost — pure reporting.

# Data in

The entire vault: session dump counts and status, distill run history/logs, knowledge
note counts per scope, pending proposal counts.

# Transformation

Computed into one JSON blob and substituted into a static HTML template — no server,
no build step.

# Data out

`dashboard.html` in [/data/vault.md](/data/vault.md), opened directly in the browser.
Self-contained: no other flow reads it back in.

# Citations
- README.md § Usage (`/hindsight:dashboard`); § Vault layout
- skills/dashboard/SKILL.md, scripts/build-dashboard.sh
