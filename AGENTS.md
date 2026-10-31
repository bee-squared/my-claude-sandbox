<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

## Agent git workflow

These rules apply inside an agent VM (Docker Sandbox or Vercel Sandbox), running as the agent GitHub account.
On the user's Mac, never commit or push: suggest a commit message instead.

- Only the orchestrator (main session) runs git add, commit, push and gh.
  Helpers edit files and report: files changed, tests run, open issues.
- Before the first commit, check identity: `git var GIT_AUTHOR_IDENT` and
  `gh api user --jq .login` must show the agent account. If either shows
  the user, stop and say so.
- Work only in this repository: the one this VM was started for (its `origin`).
  Never push to, open or comment on PRs or issues in, create, fork, or clone any
  other repository, and don't try, not even to check whether you have access.
- Don't add, rename or change git remotes, and don't push to any remote other
  than `origin`.
- Use `gh` only against this repository: no `--repo`/`-R` pointing elsewhere,
  and no `gh api` calls to other repositories.
- If a task seems to need another repository, stop and ask instead.
- Branch from origin/main as agent/<short-description>. Never work on main.
- Never push to main, never force push, never rewrite pushed history.
- Never approve or merge a PR, including your own.
- Make logical commits. Open PRs as drafts with the ai-generated label:
  gh pr create --draft --label ai-generated
- PR body: what changed, why, tests run, and a line saying an AI agent wrote it.
- After opening the PR, report: branch, commit hashes, PR URL, tests run,
  known limitations.
