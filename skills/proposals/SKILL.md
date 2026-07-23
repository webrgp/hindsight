---
name: proposals
description: Review hindsight's pending skill/automation proposals and approve, reject, or defer each. Approval scaffolds a real SKILL.md at the proposed scope (project or global). This is the human gate that closes the self-improvement loop.
disable-model-invocation: true
---

# hindsight proposals

Walk the user through the proposal inbox. Nothing was auto-created — distill only
proposes; the user decides here.

Vault: `HINDSIGHT_HOME` env var if set, else `~/.hindsight`. Inbox:
`$VAULT/inbox/proposals.md`.

## Flow

1. **Read the inbox.** If there are no `status: proposed` entries, say so and stop.

2. **Present pending proposals** one batch at a time with AskUserQuestion (approve /
   reject / defer per proposal). Show for each: the pattern name, what it does, how
   often it was seen and where, and the proposed scope.

3. **On approve** — scaffold the skill:
   - Scope `project:<name>` → `<that project's repo root>/.claude/skills/<skill-name>/SKILL.md`.
     If the project's path isn't obvious, check `$VAULT/sessions/<project>__*.md`
     frontmatter for its `cwd`. If still ambiguous, ask the user.
   - Scope `global` → `~/.claude/skills/<skill-name>/SKILL.md`.
   - Write a real, working SKILL.md: frontmatter (`name`, `description` — the
     description must say when to trigger), then concrete steps distilled from the
     proposal's "what". Look at the related knowledge notes in `$VAULT/knowledge/`
     for specifics (commands, paths, conventions) before writing.
   - For `automation: local-cron` or `remote-routine` proposals, scaffold the skill
     AND tell the user how to schedule it (launchd/cron for local, Claude Code
     scheduled routines for remote) — but don't install schedules unless asked.
   - Flip the entry to `status: implemented` and add `- skill: <path>`.

4. **On reject** — flip to `status: rejected` (distill is instructed never to
   re-propose rejected patterns). Keep the entry; it's the memory of the decision.

5. **On defer** — leave `status: proposed` untouched.

6. **Wrap up**: list what was created (paths), remind that project skills take effect
   in that project's next session.
