import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  // Frontend guardrails: app code never holds the secret key or a non-SSR client.
  {
    files: ["app/**", "components/**", "lib/**", "proxy.ts"],
    ignores: ["lib/database.types.ts"],
    rules: {
      "no-restricted-syntax": [
        "error",
        {
          selector:
            "MemberExpression[object.object.name='process'][object.property.name='env'][property.name='SUPABASE_SECRET_KEY']",
          message: "SUPABASE_SECRET_KEY is backend-only; request an RPC (docs/contracts/requests/)",
        },
      ],
      "no-restricted-imports": [
        "error",
        {
          paths: [
            {
              name: "@supabase/supabase-js",
              allowTypeImports: true,
              message: "Use @supabase/ssr clients from @/lib/supabase",
            },
          ],
        },
      ],
    },
  },
  // Override default ignores of eslint-config-next.
  globalIgnores([
    // Default ignores of eslint-config-next:
    ".next/**",
    "out/**",
    "build/**",
    "next-env.d.ts",
    // Local git worktrees of this repo, linted in their own checkout.
    ".claude/worktrees/**",
  ]),
]);

export default eslintConfig;
