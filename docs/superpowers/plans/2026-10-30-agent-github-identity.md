# Agent GitHub Identity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Claude on the Mac can never act as the user on GitHub and never commits; an agent in a Docker Sandbox VM commits, pushes and opens PRs as a separate machine account, with only its orchestrator touching git.

**Architecture:** Three layers. The user's Mac settings remove the old setup and block host Claude from GitHub (network deny, no sandbox escape, deny and ask rules). The repo carries the rules every VM reads (`AGENTS.md`, `CLAUDE.md`, the agent-guard, CODEOWNERS). GitHub and Docker hold the agent's identity (machine account, scoped token in `sbx secret`, `main` ruleset).

**Tech Stack:** Node 22 `node:test` (agent-guard), Claude Code settings, Docker Sandboxes (`sbx`), GitHub rulesets, pnpm.

**Spec:** "Agent GitHub Identity Setup" Claude Doc, https://claude.ai/artifact/J9VS1tyeF2enimkoCCgKi6 (approved 2026-10-30). Part numbers below refer to it.

## Global Constraints

- Host Claude never runs `git commit`, `git push` or `gh`. Every commit in this plan is made **by the user**; a "Commit" step means: hand the user the command and message.
- Steps marked **(user, own terminal)** edit `~/.claude/` or other home files; the sandbox blocks Claude from them, by design.
- Nobody edits `.env*`. pnpm only.
- Guard tests: `pnpm test:guard`. Lint: `pnpm lint`.
- Repo changes (Tasks 3–5) reach `main` before the ruleset (Task 6, step 6.6) is switched on.
- Agent login: `silicon-sidekick` (the existing bot from the old guide, reused as the agent). User login: `bee-squared`.

## Review Focus

1. **rtk-prefixed helper commands.** rtk rewrites `git …` to `rtk git …`. Expect `rtk git add`, `rtk git commit`, `rtk git push` from a helper to be denied like the plain forms. Test added in Task 3.
2. **A commit hidden in a compound command** (`pnpm lint && git commit -m "x"`). Expect a deny naming the commit segment. Test in Task 3.
3. **Other spellings of git** (`git -C . add app`, `GIT commit -m x`, extra spaces). Expect deny. Test in Task 3.
4. **Untracking must not delete the local file.** After `git rm --cached .claude/settings.local.json`, the file still exists on disk. Check in Task 5.
5. **Helpers' read-only git still works with rtk on.** `git status`, `git diff -- app` stay allowed in the guard (test kept in Task 3); a live check with rtk on is in Task 8.

---

### Task 1: Roll back the old Mac setup (user, own terminal)

Spec: Part 1.

An earlier setup on this Mac built a `claude-safe` launcher that gives host Claude the `silicon-sidekick` bot token. This session's `GH_TOKEN` (invalid) and `GIT_CONFIG_*` values come from it. `launchctl getenv GH_TOKEN` is empty (checked 2026-10-30).

**Files:** VS Code User settings, `~/.zshrc`, `~/bin/claude-safe`, `~/.config/claude-gh/`, `~/.claude/settings.json`, `~/.claude/CLAUDE.md`, project `.claude/settings.local.json`

- [ ] **Step 1:** Remove the launcher path: clear `claudeCode.claudeProcessWrapper` (VS Code User settings) and any "claude (bot)" entry in `terminal.integrated.profiles.osx`; delete `alias claude='claude-safe'` (and the `~/bin` PATH line if `~/bin` will be empty) from `~/.zshrc`; `rm ~/bin/claude-safe`; `rm -r ~/.config/claude-gh`. Quit and reopen VS Code.
  Verify: in a new terminal `type claude` prints a path, not an alias; `ls ~/bin/claude-safe ~/.config/claude-gh` prints "No such file" twice; in a new Claude conversation `[ -n "$GH_TOKEN" ] && echo set || echo not set` prints `not set`.
- [ ] **Step 2:** On GitHub as `silicon-sidekick`, delete the old `claude-code` token. As bee-squared, run `gh auth login` in your terminal to refresh your own expired login.
  Verify: `gh api user --jq .login` prints `bee-squared` (in your terminal).
- [ ] **Step 3:** In `~/.claude/settings.json`: delete the `PreToolUse` entry that checks `gh pr create` for `--draft` (keep `rtk hook claude`); remove `"gh *"` from `sandbox.excludedCommands`; remove the old deny rules (`gh repo delete`, `gh api -X DELETE`, `gh auth`, `git push --force`, `git push -f`); remove any `permissions.allow` rule mentioning GitHub or `gh`. Do the same allow-rule cleanup in this project's `.claude/settings.local.json`.
  Verify: `grep -cE 'gh pr create|"gh \*"|domain:api.github.com' ~/.claude/settings.json` prints `0`.
- [ ] **Step 4:** In `~/.claude/CLAUDE.md`, delete the bullets about opening PRs as drafts with the `ai-generated` label and asking before creating the label. Add: `- Never commit, push, or use gh. The user makes all commits.` Keep the ask-first bullet, minus "committing, pushing, or opening or merging a pull request".
  Verify: `grep -c 'ai-generated' ~/.claude/CLAUDE.md` prints `0`.

### Task 2: Lock host Claude out of GitHub (user, own terminal)

Spec: Part 2, including "Code that runs as you" and "If you use rtk".

**Files:** `~/.claude/settings.json`

- [ ] **Step 1:** Merge Part 2's `sandbox` block (`enabled`, `autoAllowBashIfSandboxed: false`, `allowUnsandboxedCommands: false`, `network.deniedDomains` for `github.com`, `*.github.com`, `githubusercontent.com`, `*.githubusercontent.com`) into `~/.claude/settings.json`.
- [ ] **Step 2:** Merge `permissions.deny`: Part 2's list plus every `rtk`-prefixed git/gh rule from "If you use rtk".
- [ ] **Step 3:** Merge `permissions.ask` from "Code that runs as you".
- [ ] **Step 4:** Verify the file parses and loaded.
  Run: `jq '.sandbox.allowUnsandboxedCommands, (.permissions.deny | length), (.permissions.ask | length)' ~/.claude/settings.json`
  Expected: `false`, a number ≥ 34 (21 from Part 2 + 13 rtk-prefixed), `8`. Then `/status` in a new Claude session lists `User settings` with no Settings Error.
- [ ] **Step 5:** Verify no hook manager: `git config core.hooksPath` in this repo prints nothing.

### Task 3: Agent-guard — helpers never stage, commit or push

Spec: Part 6 (agent-guard row) and "Inside the VM".

**Files:**
- Modify: `scripts/agent-guard/guard.mjs:1-4,17-18,35-47,59-73,95,110-114`
- Modify: `scripts/agent-guard/guard.test.mjs:85-90,115-127,153-169`
- Modify: `scripts/agent-guard/agents.test.mjs` (new test inside the role loop)
- Modify: `.claude/agents/backend.md:48-49`, `.claude/agents/frontend.md:36,43,49`

**Interfaces:**
- Consumes: `check(role, input, root) -> { ok: true } | { ok: false, reason: string }` (unchanged signature).
- Produces: every `git add` / `git commit` segment now falls through to `segmentAllowed` and is denied as `agent-guard: <role> may not run: <segment>`.

- [ ] **Step 1: Rewrite the guard tests**

In `guard.test.mjs`:
- In "allowed Bash commands pass", replace line 87 with `allowed("backend", bash("pnpm db:types && pnpm db:types:check"));`. Add `allowed("frontend", bash("git status"));` and `allowed("backend", bash("git log --oneline"));`.
- Replace the tests at lines 115–127 and 153–169 with:

```js
test("helpers may not stage", () => {
  for (const command of ["git add app", "git add -- supabase", "git add -A", "git add .", "git -C . add app", "rtk git add app"]) {
    denied("frontend", bash(command), `agent-guard: frontend may not run: ${command}`);
  }
});

test("helpers may not commit, even inside a compound command", () => {
  denied("frontend", bash('git commit -m "feat: x"'), 'agent-guard: frontend may not run: git commit -m "feat: x"');
  denied(
    "backend",
    bash('pnpm db:types && git commit -m "chore: regen types"'),
    'agent-guard: backend may not run: git commit -m "chore: regen types"',
  );
  for (const command of ["GIT commit -m x", "rtk git commit -m x"]) {
    denied("backend", bash(command), `agent-guard: backend may not run: ${command}`);
  }
});

test("helpers may not push, move branches, rewrite history or use gh", () => {
  for (const command of [
    "git push", "git push origin agent/x", "rtk git push", "git reset --hard", "git checkout main",
    "git switch main", "git rebase main", "git merge main", "git stash", "git tag v1",
    "gh pr create --draft", "gh api user", "rtk gh pr list",
  ]) {
    denied("frontend", bash(command), `agent-guard: frontend may not run: ${command}`);
  }
});
```

In `agents.test.mjs`, inside the `for (const role …)` loop, add:

```js
test(`${role} agent body never tells it to stage or commit`, () => {
  assert.doesNotMatch(readAgent(role).body, /git (add|commit)/);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pnpm test:guard`
Expected: FAIL — "helpers may not stage" (`git add app` currently allowed), "helpers may not commit…" (`git commit -m "feat: x"` currently allowed), and both "agent body never tells it to stage or commit" tests.

- [ ] **Step 3: Remove the git write allowances in `guard.mjs`**

Delete `COMMIT` (line 18) and its check in `segmentAllowed` (line 95), the `git add` branch in `checkBash` (lines 110–114), and the now-unused `checkGitAdd` and `mayStage`. Keep `GLOB_CHARS` (still used by `segmentAllowed`). Add one line to the file's header comment: `// Helpers never stage, commit or push: the orchestrator owns git.`

- [ ] **Step 4: Update the agent prose**

- `backend.md` Definition of done, item 4 → `Report the files you changed and the tests you ran. Do not stage or commit: the orchestrator reviews and commits.` Item 3 → "…is updated alongside the schema change…" (drop "in the same commit").
- `frontend.md` line 36 → "Cite the guide in your report." Line 43 → "…write `docs/contracts/requests/YYYY-MM-DD-<slug>.md` from `_template.md`, report its path, and stop." Definition of done, item 3 → same wording as backend item 4, plus "Include the Next.js guide citation in your report."

- [ ] **Step 5: Run tests to verify they pass**

Run: `pnpm test:guard && pnpm lint`
Expected: all tests PASS, lint clean.

- [ ] **Step 6: Commit (user)**

```bash
git add scripts/agent-guard .claude/agents
git commit -m "feat(agent-guard): helpers never stage or commit; orchestrator owns git"
```

### Task 4: Repo rules every VM reads

Spec: Part 6 (AGENTS.md section, CLAUDE.md row).

**Files:**
- Modify: `AGENTS.md` (append after the Next.js managed block)
- Modify: `CLAUDE.md` ("Agent roles" section)
- Modify: `docs/superpowers/plans/2026-10-28-mvp-phase-1.md:30,456`

- [ ] **Step 1:** Append the guide's "Agent git workflow" section to `AGENTS.md`, verbatim from Part 6 (the fenced markdown block).
- [ ] **Step 2:** In `CLAUDE.md` "Agent roles", add after the first paragraph:
  - `- The orchestrator owns all git and GitHub work: staging, commits, pushes and PRs. Helpers edit their own paths and report files changed and tests run; the guard blocks them from git writes.`
  - `- On the user's Mac, Claude never commits or pushes. It hands the user a suggested commit message. Inside a Docker Sandbox VM, the orchestrator commits as the agent account (see AGENTS.md).`
  Replace the last bullet with: `- Before committing helpers' work, check git diff --stat for paths outside each role.`
- [ ] **Step 3:** In the MVP plan, line 30: "Cite the guide in the commit message" → "Cite the guide in the report; the orchestrator puts it in the commit message". Line 456: "confirm each commit touched only its own role's paths" → "confirm the orchestrator's commits keep each role's paths separate".
- [ ] **Step 4: Verify**

Run: `grep -c "Agent git workflow" AGENTS.md; grep -c "orchestrator owns all git" CLAUDE.md; pnpm test:guard`
Expected: `1`, `1`, PASS.

- [ ] **Step 5: Commit (user)**

```bash
git add AGENTS.md CLAUDE.md docs/superpowers/plans/2026-10-28-mvp-phase-1.md
git commit -m "docs: orchestrator owns git; agent git workflow for VMs"
```

### Task 5: Untrack local settings, add CODEOWNERS and PR template

Spec: Part 6 (`.gitignore`, CODEOWNERS, PR template rows), Part 3.7, "The project's `.claude/settings.json`".

**Files:**
- Modify: `.gitignore`
- Create: `.github/CODEOWNERS`, `.github/pull_request_template.md`
- Check only: `.claude/settings.json`

- [ ] **Step 1:** Append to `.gitignore`:
  ```
  # claude code personal settings
  .claude/settings.local.json
  ```
- [ ] **Step 2 (user):** `git rm --cached .claude/settings.local.json`
  Verify: `git ls-files .claude/settings.local.json` prints nothing, `git check-ignore -v .claude/settings.local.json` names `.gitignore`, and `ls .claude/settings.local.json` still shows the file.
- [ ] **Step 3:** Create `.github/CODEOWNERS` containing exactly `* @bee-squared`.
- [ ] **Step 4:** Create `.github/pull_request_template.md` with four headings: `## What changed`, `## Why`, `## Tests run`, `## AI disclaimer` (the last with the line `Written by an AI agent (Claude Code). Review before merging.`).
- [ ] **Step 5:** Confirm `.claude/settings.json` holds only `sandbox.enabled: true` and `sandbox.autoAllowBashIfSandboxed: false`, with no GitHub deny rules.
  Run: `jq -c . .claude/settings.json`
  Expected: `{"sandbox":{"enabled":true,"autoAllowBashIfSandboxed":false}}`
- [ ] **Step 6: Commit and merge (user)**

```bash
git add .gitignore .github
git commit -m "chore: untrack local Claude settings; add CODEOWNERS and PR template"
```

Then get Tasks 3–5 into `main` (push your branch and merge it, or merge locally and push) **before** Task 6.6.

### Task 6: GitHub — agent account, access, token, ruleset (user, browser)

Spec: Part 3 (3.1–3.8).

- [ ] **6.1** Skip account creation: `silicon-sidekick` exists. In a private window signed in as it, confirm 2FA is on and Settings → Emails has "Keep my email addresses private" and "Block command line pushes that expose my email" ticked. If the old fork model was used, delete `silicon-sidekick`'s fork of the repo. If an old `protect-default` ruleset exists on the repo, delete it (6.6 replaces it).
- [ ] **6.2** Note the ID: `curl -s https://api.github.com/users/silicon-sidekick | grep '"id"'`. Commit email: `<id>+silicon-sidekick@users.noreply.github.com`.
- [ ] **6.3** As the agent: classic token, scope `repo` only, 90 days. Keep the page open for Task 7.
- [ ] **6.4** As you: make sure `silicon-sidekick` is a collaborator on `bee-squared/my-claude-sandbox` with **Write** (repo → Settings → Collaborators; change it from Read if the fork model set Read); accept any pending invite as the agent.
- [ ] **6.5** As you: `gh label create ai-generated --color BFD4F2 --description "Opened by the AI agent"`; Watch → All activity.
- [ ] **6.6** As you: ruleset `protect-main` exactly as in the 3.6 table (Repository admin bypass, PR-only; restrict updates; restrict deletions; block force pushes; PR with 1 approval, dismiss stale, Code Owners, latest push, conversation resolution).
  Verify: Settings → Rules shows `protect-main` as **Active** (the real push and merge tests are in Task 8). If the repo is private on a free plan, GitHub says the ruleset isn't enforced: choose GitHub Pro or a public repo before going on.

### Task 7: Docker Sandboxes (user, own terminal)

Spec: Part 4.

- [ ] **7.1** `brew trust docker/tap && brew install docker/tap/sbx && sbx login`
- [ ] **7.2** `sbx settings set ssh.agentForwardingEnabled false && sbx daemon restart`
  Verify: `sbx settings get ssh.agentForwardingEnabled` prints `false`.
- [ ] **7.3** `sbx secret set github` and paste the **agent's** token from 6.3. Never `--command 'gh auth token'`, never `sbx secret import`.
  Verify: `sbx secret ls` lists `github` and nothing unexpected.

### Task 8: First VM and the Part 7 checks (user)

Spec: Part 5, Part 7.

- [ ] **8.1** `cd ~/Documents/Projects/my-claude-sandbox && git switch main && git pull && sbx run --clone --name msb-identity-check claude .` → choose **Balanced** → `/login`.
- [ ] **8.2** Run Part 5.3's `git config` and `set-url` lines, then its three checks. All show `silicon-sidekick`; none show `bee-squared`.
- [ ] **8.3** Work through every Part 7 checklist (host checks with rtk on; Docker; VM; end-to-end PR incl. approved-PR merge refusal and the helper `git commit` block; you are still you).
- [ ] **8.4** Close the test PR and delete its branch as yourself; `sbx rm msb-identity-check`.
- [ ] **8.5** If any check fails, stop and use the guide's Troubleshooting table before giving the agent real work.
</content>
