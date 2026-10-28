import assert from "node:assert/strict";
import { test } from "node:test";
import { check } from "./guard.mjs";

const root = "/repo";
const edit = (file) => ({ tool_name: "Edit", tool_input: { file_path: `${root}/${file}` } });
const bash = (command) => ({ tool_name: "Bash", tool_input: { command } });

function allowed(role, input) {
  assert.deepEqual(check(role, input, root), { ok: true });
}

function denied(role, input, reason) {
  assert.deepEqual(check(role, input, root), { ok: false, reason });
}

test("backend may write its owned paths", () => {
  for (const file of [
    "supabase/schemas/10_profiles.sql",
    "lib/database.types.ts",
    "docs/contracts/db-contract.md",
    "docs/contracts/requests/2026-10-27-x.md",
  ]) {
    allowed("backend", edit(file));
  }
});

test("backend may not write frontend or orchestrator paths", () => {
  for (const file of ["app/page.tsx", "lib/supabase/server.ts", ".env.local", "package.json"]) {
    denied("backend", edit(file), `agent-guard: backend may not write ${file}`);
  }
});

test("frontend may write its owned paths", () => {
  for (const file of [
    "app/page.tsx",
    "components/ui/button.tsx",
    "lib/supabase/server.ts",
    "proxy.ts",
    "public/x.svg",
    "docs/contracts/requests/a.md",
  ]) {
    allowed("frontend", edit(file));
  }
});

test("frontend may not write backend or orchestrator paths", () => {
  for (const file of [
    "lib/database.types.ts",
    "supabase/seed.sql",
    "docs/contracts/db-contract.md",
    ".env.local",
    ".claude/agents/frontend.md",
    "scripts/agent-guard/guard.mjs",
  ]) {
    denied("frontend", edit(file), `agent-guard: frontend may not write ${file}`);
  }
});

test("Write and NotebookEdit are checked like Edit", () => {
  denied(
    "frontend",
    { tool_name: "Write", tool_input: { file_path: `${root}/supabase/a.sql` } },
    "agent-guard: frontend may not write supabase/a.sql",
  );
  denied(
    "backend",
    { tool_name: "NotebookEdit", tool_input: { notebook_path: `${root}/app/n.ipynb` } },
    "agent-guard: backend may not write app/n.ipynb",
  );
});

test("traversal is resolved before matching", () => {
  denied(
    "frontend",
    edit("app/../supabase/a.sql"),
    "agent-guard: frontend may not write supabase/a.sql",
  );
});

test("paths outside the repo are denied", () => {
  denied(
    "backend",
    { tool_name: "Edit", tool_input: { file_path: "/etc/passwd" } },
    "agent-guard: backend may not write outside the repo",
  );
});

test("allowed Bash commands pass", () => {
  allowed("backend", bash("pnpm supabase test db"));
  allowed("backend", bash("pnpm db:types && git add lib/database.types.ts"));
  allowed("frontend", bash("pnpm lint"));
  allowed("frontend", bash("git diff -- app"));
});

test("Bash outside the role's allowlist is denied", () => {
  denied(
    "frontend",
    bash("pnpm supabase db reset"),
    "agent-guard: frontend may not run: pnpm supabase db reset",
  );
  denied("backend", bash("pnpm build"), "agent-guard: backend may not run: pnpm build");
  denied(
    "backend",
    bash("pnpm supabase db push"),
    "agent-guard: backend may not run: pnpm supabase db push",
  );
  denied(
    "backend",
    bash("pnpm supabase link --project-ref x"),
    "agent-guard: backend may not run: pnpm supabase link --project-ref x",
  );
  denied("backend", bash("pnpm add zod"), "agent-guard: backend may not run: pnpm add zod");
});

test("compound Bash checks every segment", () => {
  denied(
    "frontend",
    bash("pnpm lint && rm -rf supabase"),
    "agent-guard: frontend may not run: rm -rf supabase",
  );
});

test("redirects and substitutions are denied", () => {
  const reason = "agent-guard: redirects and substitutions are not allowed";
  denied("frontend", bash("pnpm dev; echo x > supabase/a.sql"), reason);
  denied("frontend", bash("cat $(ls)"), reason);
  denied("frontend", bash("cat `ls`"), reason);
});

test("git add checks each staged path", () => {
  allowed("frontend", bash("git add app components/ui lib/supabase"));
  denied("frontend", bash("git add app supabase"), "agent-guard: frontend may not stage supabase");
  denied("frontend", bash("git add lib"), "agent-guard: frontend may not stage lib");
  denied(
    "backend",
    bash("git add -- app/page.tsx"),
    "agent-guard: backend may not stage app/page.tsx",
  );
});

test("git add without explicit owned paths is denied", () => {
  denied("frontend", bash("git add -A"), "agent-guard: frontend may not stage everything");
  denied("frontend", bash("git add -u"), "agent-guard: frontend may not stage everything");
  denied("frontend", bash("git add"), "agent-guard: frontend may not stage everything");
  denied("frontend", bash("git add ."), "agent-guard: frontend may not stage .");
});

test("background operator, process substitution, quotes and escapes are shell features", () => {
  const reason = "agent-guard: redirects and substitutions are not allowed";
  denied("frontend", bash("pnpm lint & rm -rf supabase"), reason);
  denied("frontend", bash("cat <(rm -rf supabase)"), reason);
  denied("backend", bash("pnpm supabase db pu''sh"), reason);
  denied("backend", bash("pnpm supabase db pu\\sh"), reason);
});

test("allowlisted commands that can run code or write files are denied", () => {
  denied(
    "frontend",
    bash("rg --pre sh . app/evil.sh"),
    "agent-guard: frontend may not run: rg --pre sh . app/evil.sh",
  );
  denied(
    "frontend",
    bash("pnpm lint -c app/evil.mjs"),
    "agent-guard: frontend may not run: pnpm lint -c app/evil.mjs",
  );
  denied(
    "frontend",
    bash("pnpm exec tsc --noEmit false"),
    "agent-guard: frontend may not run: pnpm exec tsc --noEmit false",
  );
  denied(
    "frontend",
    bash("git diff --output=supabase/schemas/x.sql"),
    "agent-guard: frontend may not run: git diff --output=supabase/schemas/x.sql",
  );
  denied(
    "backend",
    bash("git show --output=app/page.tsx HEAD"),
    "agent-guard: backend may not run: git show --output=app/page.tsx HEAD",
  );
});

test("git commit allows only a plain -m message", () => {
  allowed("frontend", bash('git commit -m "feat: add list page"'));
  allowed(
    "backend",
    bash('pnpm db:types && git add lib/database.types.ts && git commit -m "chore: regen types"'),
  );
  for (const command of [
    "git commit -a -m x",
    "git commit --amend --no-edit",
    "git commit -m x supabase/a.sql",
  ]) {
    denied("frontend", bash(command), `agent-guard: frontend may not run: ${command}`);
  }
});

test("git add cannot reach the excluded generated types", () => {
  denied(
    "frontend",
    bash("git add lib/database.types.ts"),
    "agent-guard: frontend may not stage lib/database.types.ts",
  );
  denied(
    "frontend",
    bash("git add app/../lib/database.types.ts"),
    "agent-guard: frontend may not stage app/../lib/database.types.ts",
  );
  denied("frontend", bash("git add lib/*"), "agent-guard: frontend may not run: git add lib/*");
});

test("case variants of excluded paths are denied", () => {
  denied(
    "frontend",
    edit("lib/Database.types.ts"),
    "agent-guard: frontend may not write lib/Database.types.ts",
  );
});

test("backend supabase commands are limited to local subcommands", () => {
  for (const command of [
    "pnpm supabase start",
    "pnpm supabase status",
    "pnpm supabase db reset",
    "pnpm supabase db schema declarative sync -f todo_01_profiles --apply",
    "pnpm supabase migration new todo_02_lists",
    "pnpm supabase test db supabase/tests/database/00_helpers.test.sql supabase/tests/database/10_profiles.test.sql",
  ]) {
    allowed("backend", bash(command));
  }
  for (const command of [
    "pnpm supabase db reset --db-url=postgres://prod",
    "pnpm supabase db reset --linked=true",
    "pnpm supabase db reset --project-ref abc",
    "pnpm supabase db --debug push",
    'pnpm supabase db "push"',
    "pnpm supabase db dump --local -f app/page.tsx",
    "pnpm supabase --workdir app init",
    "pnpm supabase test db app/x.sql",
  ]) {
    denied("backend", bash(command), `agent-guard: backend may not run: ${command}`);
  }
});

test("frontend cannot read local Supabase secrets via status", () => {
  denied(
    "frontend",
    bash("pnpm supabase status -o env"),
    "agent-guard: frontend may not run: pnpm supabase status -o env",
  );
});

test("malformed input fails closed for guarded tools", () => {
  denied("frontend", { tool_name: "Edit" }, "agent-guard: frontend may not write outside the repo");
  denied("frontend", { tool_name: "Bash", tool_input: {} }, "agent-guard: frontend may not run: ");
});

test("unguarded tools pass", () => {
  allowed("frontend", { tool_name: "Read", tool_input: { file_path: `${root}/.env.local` } });
  allowed("backend", { tool_name: "Grep", tool_input: { pattern: "x" } });
});

test("unknown role is denied", () => {
  denied("other", edit("app/page.tsx"), "agent-guard: unknown role other");
});
