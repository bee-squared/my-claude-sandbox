@AGENTS.md

## Agent roles

The main session is the orchestrator. It delegates work to two subagents and owns everything they don't.

- `backend` (`.claude/agents/backend.md`) handles `supabase/**`, generated types (`lib/database.types.ts`) and `docs/contracts/db-contract.md`.
- `frontend` (`.claude/agents/frontend.md`) handles `app/**`, `components/**`, `lib/**` (except the generated types), `proxy.ts` and `public/**`.
- Both may write `docs/contracts/requests/**`. The frontend asks for database changes there, and the backend records the resolution.
- The orchestrator owns `package.json`, the lockfile, configs, `.claude/**`, `scripts/**`, `docs/superpowers/**`, `CLAUDE.md` and `AGENTS.md`. Nobody edits `.env*`.
- The ownership map is `scripts/agent-guard/ownership.mjs`. A PreToolUse hook in each agent file enforces it. Change the map and the agent prose together (`pnpm test:guard` checks they agree).
- Ordering: schema, types and contract land before the frontend work that depends on them. Independent tasks may run in parallel worktrees.
- Before merging an agent's work, check `git diff --stat <base>..HEAD` for paths outside its role.
