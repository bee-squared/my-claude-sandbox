// Single source of truth for which agent may write what.
// Anything not listed here belongs to the orchestrator (the main session).

export const SHARED_BASH = [
  "ls",
  "cat",
  "head",
  "tail",
  "wc",
  "grep",
  "rg",
  "git status",
  "git diff",
  "git log",
  "git show",
  "git commit",
  "pnpm supabase status",
];

export const OWNERSHIP = {
  backend: {
    write: [
      "supabase/**",
      "lib/database.types.ts",
      "docs/contracts/db-contract.md",
      "docs/contracts/requests/**",
    ],
    exclude: [],
    bash: ["pnpm supabase", "pnpm db:types", "pnpm db:types:check"],
    bashDeny: ["--linked", "db push", "link", "--db-url"],
  },
  frontend: {
    write: ["app/**", "components/**", "lib/**", "proxy.ts", "public/**", "docs/contracts/requests/**"],
    exclude: ["lib/database.types.ts"],
    bash: ["pnpm dev", "pnpm build", "pnpm lint", "pnpm exec tsc --noEmit"],
    bashDeny: [],
  },
};
