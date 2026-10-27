// Fails when lib/database.types.ts differs from freshly generated types.
// Needs the local Supabase stack running (pnpm supabase start).

import { execFileSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..");
const typesFile = path.join(root, "lib/database.types.ts");
const normalise = (text) => text.replace(/[ \t]+$/gm, "").trimEnd();

const fresh = execFileSync("pnpm", ["supabase", "gen", "types", "typescript", "--local"], {
  cwd: root,
  encoding: "utf8",
  stdio: ["ignore", "pipe", "inherit"],
});

if (!existsSync(typesFile) || normalise(readFileSync(typesFile, "utf8")) !== normalise(fresh)) {
  console.error("database types are stale: run pnpm db:types");
  process.exit(1);
}
