# Frontend / Backend Agent Roles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create two Claude Code subagents, `backend` and `frontend`, with enforced segregation of duties and a written contract between them, so later feature plans (starting with `2026-10-27-todo-schema.md`) can be split across them safely.

**Architecture:** One ownership map (`scripts/agent-guard/ownership.mjs`) is the single source of truth for who may write what. A guard script reads PreToolUse hook JSON and blocks out-of-scope Edit/Write/Bash calls with exit code 2. Each agent file wires the guard in its own frontmatter `hooks`, so it runs only while that agent is active. The contract between agents is generated types (`lib/database.types.ts`) plus `docs/contracts/db-contract.md`. ESLint rules stop app code from using the secret key or a non-SSR Supabase client. The main session is the orchestrator and owns everything neither agent owns.

**Tech Stack:** Claude Code subagents (`.claude/agents/*.md`, frontmatter `tools`, `skills`, `hooks`), Node 26 (`node:test`, `path.matchesGlob`), Next 16.3.6 App Router (Middleware is now `proxy.ts`), `@supabase/ssr` 0.12, Supabase CLI 2.120 via `pnpm supabase`, ESLint 9 flat config, pnpm.

**Spec:** The agent-setup prompt agreed in the 2026-10-27 session. Its requirements are restated verbatim-in-substance under Global Constraints and the ownership table. Claude Code mechanics are from the official docs (sub-agents, hooks, permissions, skills), checked 2026-10-27.

## Global Constraints

- pnpm for everything. Never npm/npx. Neither agent runs `pnpm add`/`pnpm remove`. Dependencies are requested from the orchestrator.
- The database is the only enforcer of business rules and access control. The frontend never re-implements a rule as the source of truth and never bypasses RLS.
- Frontend uses only `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` with the user's session. `SUPABASE_SECRET_KEY` never appears in `app/`, `components/`, `lib/` or `proxy.ts`. Privileged work becomes a backend RPC.
- No code branches on a status's name or id, only on `behavior` (todo-schema spec anti-goal).
- Before using a Next.js API, read its guide in `node_modules/next/dist/docs/` (AGENTS.md).
- `lib/database.types.ts` is generated only, by `pnpm db:types`. Never hand-edited.
- Path-scoped permissions in a subagent's `tools` field are **not** documented. Do not use `Edit(app/**)` there. Enforcement is the guard hook.
- `Write(path)` permission rules never match. Irrelevant here because the guard reads `tool_input.file_path` directly, but don't add such rules.
- The guard resolves the project root from its own location (`path.resolve(import.meta.dirname, "../..")`), not from `cwd` or `$CLAUDE_PROJECT_DIR`. The hook command finds the script with `git rev-parse --show-toplevel`, which also works inside worktrees.
- Don't put hook scripts in `.claude/hooks/`. That path is write-protected by this machine's sandbox. Use `scripts/agent-guard/`.

### Ownership map (exact globs, relative to repo root)

| Role | May write |
| --- | --- |
| `backend` | `supabase/**`, `lib/database.types.ts`, `docs/contracts/db-contract.md`, `docs/contracts/requests/**` |
| `frontend` | `app/**`, `components/**`, `lib/**` except `lib/database.types.ts`, `proxy.ts`, `public/**`, `docs/contracts/requests/**` |
| orchestrator (main session, unguarded) | everything else: `package.json`, `pnpm-lock.yaml`, all configs, `.claude/**`, `scripts/**`, `docs/superpowers/**`, `CLAUDE.md`, `AGENTS.md` |
| nobody | `.env*` |

Bash allowlist (each `&&`/`||`/`;`/`|` segment must match. Any segment containing `>`, `` ` ``, or `$(` is denied):

| Role | Allowed command prefixes |
| --- | --- |
| both | `ls`, `cat`, `head`, `tail`, `wc`, `grep`, `rg`, `git status`, `git diff`, `git log`, `git show`, `pnpm supabase status`, `git add <owned paths>`, `git commit` |
| `backend` | `pnpm supabase` (denied if it contains `--linked`, `db push`, `link`, or `--db-url`), `pnpm db:types`, `pnpm db:types:check` |
| `frontend` | `pnpm dev`, `pnpm build`, `pnpm lint`, `pnpm exec tsc --noEmit` |

### Guard messages (tests match on these, written to stderr, exit 2)

| Case | Message |
| --- | --- |
| file outside role | `agent-guard: <role> may not write <relpath>` |
| file outside repo | `agent-guard: <role> may not write outside the repo` |
| Bash not allowed | `agent-guard: <role> may not run: <segment>` |
| Bash shell feature | `agent-guard: redirects and substitutions are not allowed` |
| `git add` path | `agent-guard: <role> may not stage <path>` |

## Review Focus

1. **Path traversal.** `app/../supabase/schemas/x.sql` or an absolute path into another role's area must be denied after normalisation. Pinned in Task 1.
2. **Compound Bash smuggling.** `pnpm lint && rm -rf supabase`, `pnpm dev; echo x > supabase/a.sql`, `git add app supabase` must be denied. Pinned in Task 1.
3. **Worktree execution.** An agent running in `.claude/worktrees/<name>/` must be checked against that worktree's root, not the main checkout. Pinned in Task 1 (root comes from script location) and verified in Task 5.
4. **Auto / acceptEdits mode.** The guard must still block when the session auto-approves edits. The docs don't confirm the ordering. Verified in Task 5. If it fails, stop and report. Don't weaken the plan.
5. **Malformed hook input** (empty stdin, missing `tool_input`, unknown tool) must fail closed for Edit/Write/Bash and pass for every other tool (Read, Grep, Glob). Pinned in Task 1.

---

### Task 1: Ownership map and guard script

**Files:**
- Create: `scripts/agent-guard/ownership.mjs`
- Create: `scripts/agent-guard/guard.mjs`
- Test: `scripts/agent-guard/guard.test.mjs`
- Modify: `package.json` (add script `"test:guard": "node --test scripts/agent-guard/"`)

**Interfaces:**
- Produces:
  - `ownership.mjs`: `export const OWNERSHIP: Record<"backend"|"frontend", { write: string[]; exclude: string[]; bash: string[]; bashDeny: string[] }>` and `export const SHARED_BASH: string[]`, values exactly as in the tables above.
  - `guard.mjs`: `export function check(role: string, input: object, root: string): { ok: true } | { ok: false; reason: string }`. When run as a CLI (`node guard.mjs <role>`), it reads JSON from stdin, calls `check` with the root derived from `import.meta.dirname`, and on `ok: false` writes `reason` to stderr and exits 2. Otherwise it exits 0.
  - Tools checked: `Edit`, `Write`, `NotebookEdit` (path from `tool_input.file_path` or `tool_input.notebook_path`), `Bash` (`tool_input.command`). Every other `tool_name` returns `{ ok: true }`.

- [ ] **Step 1: Write the failing tests** in `guard.test.mjs` using `node:test` and `assert/strict`. Use `root = "/repo"` and build inputs like `{ tool_name: "Edit", tool_input: { file_path: "/repo/app/page.tsx" } }`. Assertions:
  - `backend` allowed: `supabase/schemas/10_profiles.sql`, `lib/database.types.ts`, `docs/contracts/db-contract.md`, `docs/contracts/requests/2026-10-27-x.md`
  - `backend` denied with the exact message: `app/page.tsx`, `lib/supabase/server.ts`, `.env.local`, `package.json`
  - `frontend` allowed: `app/page.tsx`, `components/ui/button.tsx`, `lib/supabase/server.ts`, `proxy.ts`, `public/x.svg`, `docs/contracts/requests/a.md`
  - `frontend` denied: `lib/database.types.ts`, `supabase/seed.sql`, `docs/contracts/db-contract.md`, `.env.local`, `.claude/agents/frontend.md`, `scripts/agent-guard/guard.mjs`
  - Traversal: `frontend` + `/repo/app/../supabase/a.sql` is denied. `backend` + `/etc/passwd` gets the "outside the repo" message.
  - Bash allowed: `backend` `pnpm supabase test db`, `backend` `pnpm db:types && git add lib/database.types.ts`, `frontend` `pnpm lint`, `frontend` `git diff -- app`
  - Bash denied: `frontend` `pnpm supabase db reset`, `backend` `pnpm build`, `backend` `pnpm supabase db push`, `backend` `pnpm supabase link --project-ref x`, `frontend` `pnpm lint && rm -rf supabase`, `frontend` `pnpm dev; echo x > supabase/a.sql` (redirect message), `frontend` `cat $(ls)`, `frontend` `git add app supabase` (stage message names `supabase`), `backend` `pnpm add zod`
  - Fail closed: `{ tool_name: "Edit" }` with no `tool_input` is denied. `{ tool_name: "Read", tool_input: { file_path: "/repo/.env.local" } }` is ok.
  - Unknown role: `check("other", editInput, root)` is denied.

- [ ] **Step 2: Run to verify failure**

Run: `node --test scripts/agent-guard/`
Expected: FAIL, cannot find module `./guard.mjs`

- [ ] **Step 3: Implement `ownership.mjs` and `check()` in `guard.mjs`.** Normalise with `path.resolve(root, file)` then `path.relative(root, abs)`. A result starting with `..` or absolute is outside the repo. Match with `path.matchesGlob(rel, glob)` against `write`, then reject anything matching `exclude`. For Bash: reject on `>`, `` ` ``, `$(` first. Split on `&&`, `||`, `;`, `|`, newline. Trim each segment and require it to equal a prefix or start with `prefix + " "`. Reject if it contains any `bashDeny` token. For `git add`, check every non-flag argument (after `--` too) as a write path.

- [ ] **Step 4: Run to verify pass**

Run: `pnpm test:guard`
Expected: all tests PASS

- [ ] **Step 5: CLI smoke check**

Run: `echo '{"tool_name":"Edit","tool_input":{"file_path":"'"$PWD"'/supabase/seed.sql"}}' | node scripts/agent-guard/guard.mjs frontend; echo "exit=$?"`
Expected: stderr `agent-guard: frontend may not write supabase/seed.sql`, `exit=2`

- [ ] **Step 6: Commit**

```bash
git add scripts/agent-guard package.json
git commit -m "feat: add agent ownership map and PreToolUse guard"
```

---

### Task 2: Agent definitions and orchestrator rules

**Files:**
- Create: `.claude/agents/backend.md`
- Create: `.claude/agents/frontend.md`
- Modify: `CLAUDE.md` (append an "Agent roles" section below `@AGENTS.md`. Don't edit `AGENTS.md`, because `next dev` rewrites it.)
- Test: `scripts/agent-guard/agents.test.mjs`

**Interfaces:**
- Consumes: `OWNERSHIP` from Task 1 and the CLI `node scripts/agent-guard/guard.mjs <role>`.
- Produces: subagent types `backend` and `frontend`, which the orchestrator dispatches by name.

Frontmatter (exact fields, camelCase. Unknown fields are silently ignored, so typos fail quietly):

```yaml
# backend.md
name: backend
description: Database/backend work for this repo: Supabase schemas, migrations, RLS, triggers, RPCs, pgTAP tests, generated DB types and the DB contract doc. Use for any change under supabase/.
tools: Read, Grep, Glob, Edit, Write, Bash, Skill
model: inherit
skills:
  - supabase:supabase
  - supabase:supabase-postgres-best-practices
  - superpowers:test-driven-development
hooks:
  PreToolUse:
    - matcher: "Edit|Write|NotebookEdit|Bash"
      hooks:
        - type: command
          command: 'node "$(git rev-parse --show-toplevel)/scripts/agent-guard/guard.mjs" backend'
```

`frontend.md` is the same shape with `name: frontend`, a description covering Next.js App Router pages, layouts, Server Components, Server Actions, route handlers, `proxy.ts`, Supabase SSR clients, UI and styling, `skills: [supabase:supabase]`, and the guard arg `frontend`.

The body of each file (prose, kept under about 60 lines) states:
- Role, owned paths (copied from the ownership table) and forbidden actions (from Global Constraints).
- **Backend definition of done:** a pgTAP test fails first and then passes (`pnpm supabase test db`). `pnpm db:types` is run. `docs/contracts/db-contract.md` is updated in the same commit as any schema change. New error messages are added to the contract's error catalogue.
- **Frontend definition of done:** `pnpm lint` and `pnpm build` pass. Every Supabase call is typed with `Database` from `@/lib/database.types`. Errors are mapped from the contract's catalogue. The relevant `node_modules/next/dist/docs/` guide was read and is cited in the commit body.
- **Handoff:** when blocked on something outside its paths, the agent writes `docs/contracts/requests/YYYY-MM-DD-<slug>.md` from the template, stops, and reports the file path. It never works around the block.

The `CLAUDE.md` "Agent roles" section, about 10 lines, says:
- The main session orchestrates. It delegates `supabase/**` work to `backend` and app work to `frontend`.
- It owns the shared files and reviews each agent diff with `git diff --stat` for paths outside the ownership map before merging.
- Ordering: schema, types and contract land before the frontend work that depends on them. Independent tasks may run in parallel worktrees.

- [ ] **Step 1: Write the failing test** `agents.test.mjs`. For each role, read `.claude/agents/<role>.md` and parse the frontmatter between `---` lines (plain string parsing, no YAML dependency). Assert:
  - `name: <role>` is present.
  - The hook command line contains `guard.mjs <role>`.
  - The matcher is `Edit|Write|NotebookEdit|Bash`.
  - Every listed skill exists in this table: `{backend: [supabase:supabase, supabase:supabase-postgres-best-practices, superpowers:test-driven-development], frontend: [supabase:supabase]}`.
  - The body contains each `OWNERSHIP[role].write` glob as text, so the prose can't drift from the map.

- [ ] **Step 2: Run to verify failure**

Run: `pnpm test:guard`
Expected: FAIL with ENOENT on `.claude/agents/backend.md`

- [ ] **Step 3: Write both agent files and the `CLAUDE.md` section** as specified above.

- [ ] **Step 4: Run to verify pass**

Run: `pnpm test:guard`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add .claude/agents CLAUDE.md scripts/agent-guard/agents.test.mjs
git commit -m "feat: define backend and frontend subagents with scoped guard hooks"
```

---

### Task 3: The contract (generated types, drift check, contract doc, request template)

**Files:**
- Modify: `package.json`. Add scripts `"db:types": "pnpm supabase gen types typescript --local > lib/database.types.ts"` and `"db:types:check": "node scripts/check-db-types.mjs"`.
- Create: `scripts/check-db-types.mjs`
- Create: `lib/database.types.ts` (generated)
- Create: `docs/contracts/db-contract.md`
- Create: `docs/contracts/requests/_template.md`

**Interfaces:**
- Produces: `Database` type exported from `@/lib/database.types`. `pnpm db:types:check` exits 0 when the committed file matches fresh output, otherwise exits 1 with `database types are stale: run pnpm db:types`.
- Note: the `db:types` script uses `>`, which the guard rejects inside a Bash segment. The backend agent runs `pnpm db:types` (allowed prefix), and the redirect happens inside the package script, outside the hook's view. That is intended.

- [ ] **Step 1: Write `check-db-types.mjs`.** It runs `pnpm supabase gen types typescript --local` with `execFileSync`, compares the output to `lib/database.types.ts` after trimming trailing whitespace on both, and exits as described above. If the file is missing, it prints the same message and exits 1.

- [ ] **Step 2: Verify it fails before types exist**

Run: `pnpm supabase start` (if not running), then `pnpm db:types:check; echo "exit=$?"`
Expected: `database types are stale: run pnpm db:types`, `exit=1`

- [ ] **Step 3: Generate types**

Run: `pnpm db:types && pnpm db:types:check; echo "exit=$?"`
Expected: `exit=0`

- [ ] **Step 4: Prove drift detection.** Append `// drift` to `lib/database.types.ts` and run `pnpm db:types:check; echo "exit=$?"`. Expected `exit=1`. Then run `pnpm db:types` to restore it.

- [ ] **Step 5: Write `docs/contracts/db-contract.md`** with these sections:
  - **How to use** (frontend reads, backend writes, regenerated per schema change)
  - **Tables and client-writable columns:** one row per table from the todo-schema spec's Tables section and the plan's column grants (`profiles`, `lists`, `list_members`, `task_statuses`, `tasks`, `task_status_events`), each marked `status: planned` until its todo-schema task lands
  - **RPCs:** `transfer_list_ownership`, marked `planned`, with the signature from the todo-schema plan
  - **Error catalogue:** copied exactly from the todo-schema plan's Error catalogue table, plus the Postgres codes line under it
  - **Status rule:** branch on `behavior` only

- [ ] **Step 6: Write `docs/contracts/requests/_template.md`** with headings: `Requested by`, `Date`, `Need` (what the UI must do), `Why it can't be done in frontend`, `Proposed shape` (table/column/RPC/policy), `Resolution` (backend fills in: commit, contract section).

- [ ] **Step 7: Commit**

```bash
git add package.json scripts/check-db-types.mjs lib/database.types.ts docs/contracts
git commit -m "feat: add DB contract doc, generated types and drift check"
```

---

### Task 4: Lint guardrails for frontend code

**Files:**
- Modify: `eslint.config.mjs`
- Test: `scripts/agent-guard/lint-fixtures/` (temporary fixtures, created and deleted inside the test, not committed)

**Interfaces:**
- Produces: these lint errors in `app/**`, `components/**`, `lib/**` and `proxy.ts`:
  - `no-restricted-syntax` on `MemberExpression[object.object.name='process'][object.property.name='env'][property.name='SUPABASE_SECRET_KEY']`, with message `SUPABASE_SECRET_KEY is backend-only; request an RPC (docs/contracts/requests/)`
  - `no-restricted-imports` for `@supabase/supabase-js` with `allowTypeImports: true`, with message `Use @supabase/ssr clients from @/lib/supabase`

- [ ] **Step 1: Write fixtures.** Create `app/__lint_probe__.ts`, which reads `process.env.SUPABASE_SECRET_KEY`, and `app/__lint_probe2__.ts`, which has `import { createClient } from "@supabase/supabase-js"`.

- [ ] **Step 2: Verify the probes pass lint today (rule missing)**

Run: `pnpm lint app/__lint_probe__.ts app/__lint_probe2__.ts; echo "exit=$?"`
Expected: no errors from those rules, `exit=0`

- [ ] **Step 3: Add a config block** to `eslint.config.mjs` with `files: ["app/**", "components/**", "lib/**", "proxy.ts"]`, `ignores: ["lib/database.types.ts"]`, and the two rules above.

- [ ] **Step 4: Verify the probes fail**

Run: `pnpm lint app/__lint_probe__.ts app/__lint_probe2__.ts; echo "exit=$?"`
Expected: both messages above, `exit=1`

- [ ] **Step 5: Delete the probes and confirm the repo is clean**

Run: `rm app/__lint_probe__.ts app/__lint_probe2__.ts && pnpm lint`
Expected: exit 0

- [ ] **Step 6: Commit**

```bash
git add eslint.config.mjs
git commit -m "chore: lint-block secret key and non-SSR supabase client in app code"
```

---

### Task 5: Dry run. Prove both agents work in bounds and are blocked out of bounds

The orchestrator dispatches each agent with the Agent tool (`subagent_type: "backend"` / `"frontend"`). Start a fresh Claude Code session first, so the new `.claude/agents/` files load and the workspace trust dialog has been accepted. Project agent hooks don't run until it is, and a `-p` session doesn't count.

**Files:**
- Create (by the frontend agent): `lib/supabase/server.ts`, `lib/supabase/client.ts`, `proxy.ts`
- Create (by the frontend agent): `docs/contracts/requests/2026-10-27-dry-run.md`
- Modify (orchestrator, before dispatch): `package.json`, adding `server-only` via `pnpm add server-only`

**Interfaces:**
- Produces: `createClient(): Promise<SupabaseClient<Database>>` in `lib/supabase/server.ts` (`import "server-only"`, cookies via `next/headers`), `createClient(): SupabaseClient<Database>` in `lib/supabase/client.ts`, and a `proxy.ts` that refreshes the session per the `supabase:supabase` skill's Next.js SSR guidance and `node_modules/next/dist/docs/01-app/01-getting-started/16-proxy.md`. These are what later frontend tasks import.

- [ ] **Step 1: Backend in-bounds.** Prompt: "Run `pnpm db:types:check`. If it is stale, run `pnpm db:types` and commit. Report the output." Expected: it succeeds with no guard message.

- [ ] **Step 2: Backend out-of-bounds.** Prompt: "Create `app/backend-probe.tsx` containing `export default function P(){return null}`. If blocked, report the exact error and do not try another way." Expected: it reports `agent-guard: backend may not write app/backend-probe.tsx`, and `git status` shows no such file.

- [ ] **Step 3: Frontend in-bounds.** Prompt: "Create `lib/supabase/server.ts`, `lib/supabase/client.ts` and `proxy.ts` per the Interfaces above. Read the Next proxy guide first. Run `pnpm lint && pnpm build`, then commit." Expected: lint and build pass, a commit exists, and no guard message appears.

- [ ] **Step 4: Frontend out-of-bounds, two ways.**
  - (a) "Add a comment line to `supabase/seed.sql`." Expected: `agent-guard: frontend may not write supabase/seed.sql`.
  - (b) "Run `pnpm supabase db reset`." Expected: `agent-guard: frontend may not run: pnpm supabase db reset`.

  Neither change happens. Then: "File a request asking backend for a `profiles` read RPC." Expected: `docs/contracts/requests/2026-10-27-dry-run.md` exists, follows the template, and is committed by the frontend agent.

- [ ] **Step 5: Mode ordering (Review Focus 4).** Repeat Step 4(a) with the session in auto mode (or `acceptEdits`). Expected: still blocked. If not blocked, stop and report to the user. Don't continue to Step 6.

- [ ] **Step 6: Worktree (Review Focus 3).** Dispatch `frontend` with `isolation: "worktree"` and repeat Step 4(a). Expected: blocked, with the relpath shown relative to the worktree root.

- [ ] **Step 7: Full verification**

Run: `pnpm test:guard && pnpm lint && pnpm build && pnpm db:types:check && pnpm supabase test db`
Expected: all exit 0. `pnpm supabase test db` may report "no tests" until todo-schema Task 1 lands, which is acceptable here.

- [ ] **Step 8: Delete the dry-run request file** (orchestrator, `git rm docs/contracts/requests/2026-10-27-dry-run.md`) and commit `chore: remove dry-run request`.

---

## Deviations from the prompt (decided here)

1. **The dry run doesn't execute todo-schema Task 1 or read `lists`.** Neither exists yet. Executing another plan's task here would couple the two plans. The backend dry run uses the types pipeline instead, and the frontend builds the SSR clients it needs anyway. After this plan, run `2026-10-27-todo-schema.md` with `backend` as the implementer.
2. **Neither agent may change dependencies.** `package.json` is orchestrator-owned, so the orchestrator adds `server-only` in Task 5.
3. **Requests are writable by both roles.** Frontend creates them and backend fills in the Resolution.
4. **The Bash allowlist is deliberately strict** (no redirects or substitutions, no `find`, `sed`, `rm`). Agents use the Edit/Write tools, which the guard can check.
