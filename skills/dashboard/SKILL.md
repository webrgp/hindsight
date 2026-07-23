---
name: dashboard
description: Rebuild the hindsight HTML dashboard from the vault (sessions, distill runs, knowledge, proposals) and open it in the browser. Pure shell, no LLM cost.
---

# hindsight dashboard

Rebuild and open the dashboard.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/build-dashboard.sh" && \
  open "${HINDSIGHT_HOME:-$HOME/.hindsight}/dashboard.html"
```

That's it. The builder is pure shell + jq; data is embedded, so the resulting file
is self-contained and stays valid (if stale) until the next rebuild. If it errors
with "no vault", point the user at `/hindsight:setup`.
