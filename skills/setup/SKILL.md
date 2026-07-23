---
name: setup
description: One-time hindsight setup — scaffold the vault at ~/.hindsight (or $HINDSIGHT_HOME), install the nightly launchd distill job, optionally git-init the vault. Run once after installing the plugin; re-run any time to change the distill schedule. macOS only.
disable-model-invocation: true
---

# hindsight setup

Set up the hindsight vault and the nightly distill schedule. Idempotent — safe to
re-run (it unloads and reloads the launchd job).

## Steps

1. **Resolve paths.**
   - Vault: `HINDSIGHT_HOME` env var if set, else `~/.hindsight`. Call it `$VAULT` below.
   - Plugin root: this skill lives at `<plugin>/skills/setup/`, so the plugin root is
     `${CLAUDE_PLUGIN_ROOT}`.
   - If not on macOS (`uname` ≠ `Darwin`): stop and tell the user launchd scheduling is
     macOS-only; they can still run `/hindsight:distill` manually or cron
     `scripts/distill.sh` themselves.

2. **Check dependencies.** `jq`, `git`, `perl`, and `claude` must be on PATH. If `jq`
   is missing, tell the user to `brew install jq` and stop.

3. **Scaffold the vault** (create only what's missing, never overwrite):
   ```bash
   mkdir -p "$VAULT"/{sessions,knowledge/global,knowledge/projects,inbox,logs,bin}
   [ -f "$VAULT/inbox/proposals.md" ] || printf '# hindsight proposals\n\nSkill/automation candidates detected by distill. You approve via /hindsight:proposals.\n' > "$VAULT/inbox/proposals.md"
   ```

4. **Install the launchd shim** (stable entrypoint that survives plugin updates):
   ```bash
   cp "${CLAUDE_PLUGIN_ROOT}/templates/run-distill-shim.sh" "$VAULT/bin/run-distill.sh"
   chmod +x "$VAULT/bin/run-distill.sh"
   ```

5. **Ask the user what time distill should run** (default 19:00, 24h clock). Use the
   AskUserQuestion tool with a few sensible options plus Other.

6. **Render and load the launchd job.** Substitute into
   `${CLAUDE_PLUGIN_ROOT}/templates/com.hindsight.distill.plist.template`:
   - `__HINDSIGHT_HOME__` → `$VAULT` (absolute path)
   - `__HOME__` → the user's home directory (absolute path)
   - `__CLAUDE_BIN_DIR__` → `$(dirname "$(command -v claude)")` — launchd's PATH
     is minimal and nvm/npm installs live outside the standard dirs
   - `__HOUR__` / `__MINUTE__` → chosen time (integers, no leading zeros)

   Write the result to `~/Library/LaunchAgents/com.hindsight.distill.plist`, then
   verify `claude` actually resolves under the plist's PATH before loading:
   ```bash
   plutil -lint ~/Library/LaunchAgents/com.hindsight.distill.plist
   PATH="<the PATH string you rendered into the plist>" command -v claude   # must resolve
   launchctl unload ~/Library/LaunchAgents/com.hindsight.distill.plist 2>/dev/null
   launchctl load ~/Library/LaunchAgents/com.hindsight.distill.plist
   ```

7. **Offer optional git sync.** If `$VAULT` is not already a git repo, ask whether to
   `git init` it (distill then auto-commits knowledge; it pushes only if the user later
   adds an `origin` remote). If yes:
   ```bash
   git -C "$VAULT" init -q
   printf '.distill-scratch/\n.distill.lock/\nlogs/\n' > "$VAULT/.gitignore"
   ```

8. **Check for a conflicting recall install.** If `~/.claude/settings.json` contains
   hook entries pointing at a `recall` install (`grep -i recall ~/.claude/settings.json`),
   warn the user: running both means double capture and double context injection.
   Point them at recall's uninstall steps (remove its two hook entries; `launchctl
   unload ~/Library/LaunchAgents/com.recall.distill.plist` and delete the plist). Do
   NOT edit their settings.json or remove anything yourself unless they ask.

9. **Report**: vault path, scheduled time, git status of the vault, and remind that
   capture/inject hooks are already active via the plugin — the first knowledge
   appears after the first distill run. Suggest `/hindsight:status` to check on it.
