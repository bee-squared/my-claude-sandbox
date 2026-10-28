import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";

const root = path.resolve(import.meta.dirname, "../..");

const SECRET_MSG = "SUPABASE_SECRET_KEY is backend-only; request an RPC (docs/contracts/requests/)";
const IMPORT_MSG = "Use @supabase/ssr clients from @/lib/supabase";

// Biome 2.6.3 `lint --stdin-file-path` never prints diagnostics (it echoes the source and exits 1
// for any input, even clean code), so lint a real file instead. The probe lives in a throwaway
// sandbox that copies the real biome.json and plugins, so the repo tree is never touched.
function lint(filePath, source) {
  const sandbox = mkdtempSync(path.join(tmpdir(), "biome-probe-"));
  try {
    const config = JSON.parse(readFileSync(path.join(root, "biome.json"), "utf8"));
    delete config.$schema;
    delete config.vcs; // the sandbox is not a git repo
    writeFileSync(path.join(sandbox, "biome.json"), JSON.stringify(config));
    cpSync(path.join(root, "scripts/biome-plugins"), path.join(sandbox, "scripts/biome-plugins"), {
      recursive: true,
    });
    const target = path.join(sandbox, filePath);
    mkdirSync(path.dirname(target), { recursive: true });
    writeFileSync(target, source);
    const result = spawnSync(
      path.join(root, "node_modules/.bin/biome"),
      ["lint", "--colors=off", filePath],
      { cwd: sandbox, encoding: "utf8" },
    );
    return { code: result.status, output: `${result.stdout}${result.stderr}` };
  } finally {
    rmSync(sandbox, { recursive: true, force: true });
  }
}

const DOT_SECRET = "export const k = process.env.SUPABASE_SECRET_KEY;\n";
const BRACKET_SECRET = 'export const k = process.env["SUPABASE_SECRET_KEY"];\n';

test("denies secret key in app", () => {
  const { code, output } = lint("app/probe.ts", DOT_SECRET);
  assert.notEqual(code, 0, output);
  assert.ok(output.includes(SECRET_MSG), output);
});

test("denies bracket secret key in lib", () => {
  const { code, output } = lint("lib/probe.ts", BRACKET_SECRET);
  assert.notEqual(code, 0, output);
  assert.ok(output.includes(SECRET_MSG), output);
});

test("allows secret key outside frontend paths", () => {
  const { output } = lint("scripts/probe.mjs", DOT_SECRET);
  assert.ok(!output.includes(SECRET_MSG), output);
});

test("denies runtime supabase-js import", () => {
  const { code, output } = lint(
    "proxy.ts",
    'import { createClient } from "@supabase/supabase-js";\ncreateClient;\n',
  );
  assert.notEqual(code, 0, output);
  assert.ok(output.includes(IMPORT_MSG), output);
});

test("allows type-only supabase-js import", () => {
  const { output } = lint(
    "lib/probe.ts",
    'import type { SupabaseClient } from "@supabase/supabase-js";\nexport type C = SupabaseClient;\n',
  );
  assert.ok(!output.includes(IMPORT_MSG), output);
});

test("ignores generated types", () => {
  const { output } = lint("lib/database.types.ts", DOT_SECRET);
  assert.ok(!output.includes(SECRET_MSG), output);
});
