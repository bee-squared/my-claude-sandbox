// Single source of truth for which agent may write what.
// Anything not listed here belongs to the orchestrator (the main session).

// Read-only commands either role may run with any arguments.
export const READ_ONLY_BASH = ["ls", "cat", "head", "tail", "wc", "grep"];

// Git read commands, minus the flags that write files or run external programs.
export const GIT_READ = ["git status", "git diff", "git log", "git show"];
export const GIT_READ_DENY_FLAGS = ["--output", "--ext-diff", "--textconv"];

export const OWNERSHIP = {
  backend: {
    write: [
      "supabase/**",
      "lib/database.types.ts",
      "docs/contracts/db-contract.md",
      "docs/contracts/requests/**",
    ],
    exclude: [],
    // Commands allowed only exactly as written, with no extra arguments.
    exact: ["pnpm db:types", "pnpm db:types:check"],
    // Local-only Supabase CLI. Path arguments must stay under supabase/.
    supabase: {
      subcommands: [
        "start",
        "stop",
        "status",
        "db reset",
        "db diff",
        "db advisors",
        "db schema declarative sync",
        "migration new",
        "migration list",
        "test db",
      ],
      denyFlags: ["--linked", "--db-url", "--project-ref", "--workdir", "--profile"],
    },
  },
  frontend: {
    write: [
      "app/**",
      "components/**",
      "lib/**",
      "proxy.ts",
      "public/**",
      "docs/contracts/requests/**",
    ],
    exclude: ["lib/database.types.ts"],
    exact: ["pnpm dev", "pnpm build", "pnpm lint", "pnpm exec tsc --noEmit"],
    supabase: null,
  },
};
