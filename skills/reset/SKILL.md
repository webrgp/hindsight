---
name: reset
description: Reset hindsight state — re-queue sessions for distill, wipe knowledge, or factory-reset the whole vault and schedule. Destructive options confirm first.
disable-model-invocation: true
---

# hindsight reset

Reset part or all of the hindsight system. Always ask what to reset, always confirm
before deleting anything.

Vault: `HINDSIGHT_HOME` env var if set, else `~/.hindsight`. Call it `$VAULT`.
If `$VAULT` doesn't exist, say there is nothing to reset and stop.

## Steps

1. **Ask the scope** with AskUserQuestion:
   - **Re-distill** — mark every session undistilled so the next distill run
     re-processes all of them. Nothing is deleted.
   - **Wipe knowledge** — delete all knowledge notes and pending proposals; keep
     session dumps so a later distill can rebuild from them.
   - **Factory reset** — unload the launchd job and delete the entire vault.

2. **Confirm destructive scopes.** For wipe/factory, show what will be lost
   (note counts, session count) and get an explicit yes. If `$VAULT` is a git repo
   with uncommitted changes, offer to commit first; if it has no remote, warn that
   deletion is unrecoverable.

3. **Execute:**

   Re-distill:
   ```bash
   # perl, not sed -i: BSD sed corrupts multibyte chars in dumps
   perl -pi -e 's/^distilled: true$/distilled: false/' "$VAULT"/sessions/*.md
   ```

   Wipe knowledge:
   ```bash
   rm -rf "$VAULT/knowledge/global" "$VAULT/knowledge/projects"
   mkdir -p "$VAULT/knowledge/global" "$VAULT/knowledge/projects"
   printf '# hindsight proposals\n\nSkill/automation candidates detected by distill. You approve via /hindsight:proposals.\n' > "$VAULT/inbox/proposals.md"
   ```

   Factory reset:
   ```bash
   launchctl unload ~/Library/LaunchAgents/com.hindsight.distill.plist 2>/dev/null
   rm -f ~/Library/LaunchAgents/com.hindsight.distill.plist
   rm -rf "$VAULT"
   ```

4. **Report** what was reset. After re-distill or wipe, suggest `/hindsight:distill`
   to rebuild; after factory reset, note that capture hooks will recreate `sessions/`
   automatically but the schedule needs `/hindsight:setup` again.
