import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";

const root = path.resolve(import.meta.dirname, "../..");

const SECRET_MSG = "SUPABASE_SECRET_KEY is backend-only; request an RPC (docs/contracts/requests/)";
const IMPORT_MSG = "Use @supabase/ssr clients from @/lib/supabase";

const SECRET_CONTROL = "export const k = process.env.SUPABASE_SECRET_KEY;\n";
const IMPORT_CONTROL = 'import { createClient } from "@supabase/supabase-js";\ncreateClient;\n';

function runBiome(cwd, filePath) {
  const result = spawnSync(
    path.join(root, "node_modules/.bin/biome"),
    ["lint", "--colors=off", filePath],
    { cwd, encoding: "utf8" },
  );
  return {
    code: result.status,
    error: result.error,
    output: `${result.stdout}${result.stderr}`,
  };
}

// Biome 2.6.3 `lint --stdin-file-path` never prints diagnostics (it echoes the source and exits 1
// for any input, even clean code), so lint a real file instead. The probe lives in a throwaway
// sandbox that copies the real biome.json and plugins, so the repo tree is never touched.
//
// Every call also lints a positive control (a known violation in app/ and proxy.ts) in the same
// sandbox, and asserts Biome ran, the config parsed and both plugins compiled and fired. Without
// this, "allows" and "ignores" assertions would pass vacuously on a broken setup.
//
// `generatedTypesOnlyByOverride` removes `!**/database.types.ts` from the copy's `files.includes`,
// so the file is excluded by the override alone and not by the global ignore.
function lint(filePath, source, { generatedTypesOnlyByOverride = false } = {}) {
  const sandbox = mkdtempSync(path.join(tmpdir(), "biome-probe-"));
  try {
    const config = JSON.parse(readFileSync(path.join(root, "biome.json"), "utf8"));
    delete config.$schema;
    delete config.vcs; // the sandbox is not a git repo
    if (generatedTypesOnlyByOverride) {
      config.files.includes = config.files.includes.filter((p) => p !== "!**/database.types.ts");
    }
    writeFileSync(path.join(sandbox, "biome.json"), JSON.stringify(config));
    cpSync(path.join(root, "scripts/biome-plugins"), path.join(sandbox, "scripts/biome-plugins"), {
      recursive: true,
    });
    const write = (rel, content) => {
      const target = path.join(sandbox, rel);
      mkdirSync(path.dirname(target), { recursive: true });
      writeFileSync(target, content);
    };
    write("app/__control_secret.ts", SECRET_CONTROL);
    write("proxy.ts", IMPORT_CONTROL);
    write(filePath, source);

    for (const [file, msg] of [
      ["app/__control_secret.ts", SECRET_MSG],
      ["proxy.ts", IMPORT_MSG],
    ]) {
      if (file === filePath) continue;
      const control = runBiome(sandbox, file);
      assert.equal(control.error, undefined, `biome failed to spawn: ${control.error}`);
      assert.ok(
        control.output.includes(msg),
        `control ${file} did not report its guardrail, so the setup is broken:\n${control.output}`,
      );
    }

    const probe = runBiome(sandbox, filePath);
    assert.equal(probe.error, undefined, `biome failed to spawn: ${probe.error}`);
    assert.notEqual(probe.code, null, "biome was killed before exiting");
    assert.ok(
      !/during loading of plugins|Failed to compile|configuration|Failed to deserialize/i.test(
        probe.output,
      ),
      `biome reported a config or plugin error:\n${probe.output}`,
    );
    return probe;
  } finally {
    rmSync(sandbox, { recursive: true, force: true });
  }
}

function denies(filePath, source, message) {
  const { code, output } = lint(filePath, source);
  assert.notEqual(code, 0, output);
  assert.ok(output.includes(message), output);
}

function allows(filePath, source, message) {
  const { output } = lint(filePath, source);
  assert.ok(!output.includes(message), output);
}

const DOT_SECRET = "export const k = process.env.SUPABASE_SECRET_KEY;\n";
const BRACKET_SECRET = 'export const k = process.env["SUPABASE_SECRET_KEY"];\n';
const OPTIONAL_SECRET = "export const k = process.env?.SUPABASE_SECRET_KEY;\n";

test("denies secret key in app", () => {
  denies("app/probe.ts", DOT_SECRET, SECRET_MSG);
});

test("denies bracket secret key in lib", () => {
  denies("lib/probe.ts", BRACKET_SECRET, SECRET_MSG);
});

test("denies optional-chaining secret key", () => {
  denies("app/probe.ts", OPTIONAL_SECRET, SECRET_MSG);
  denies("app/probe.ts", 'export const k = process.env?.["SUPABASE_SECRET_KEY"];\n', SECRET_MSG);
  denies("app/probe.ts", "export const k = process?.env.SUPABASE_SECRET_KEY;\n", SECRET_MSG);
});

// The root supabase/ ignore must not also match a nested folder of the same name.
test("denies both guardrails in lib/supabase", () => {
  denies("lib/supabase/probe.ts", DOT_SECRET, SECRET_MSG);
  denies("lib/supabase/probe.ts", IMPORT_CONTROL, IMPORT_MSG);
});

test("allows secret key outside frontend paths", () => {
  allows("scripts/probe.mjs", DOT_SECRET, SECRET_MSG);
});

test("denies runtime supabase-js import", () => {
  denies(
    "proxy.ts",
    'import { createClient } from "@supabase/supabase-js";\ncreateClient;\n',
    IMPORT_MSG,
  );
});

test("denies mixed inline type and value import", () => {
  denies(
    "lib/probe.ts",
    'import { type A, B } from "@supabase/supabase-js";\nexport type T = A;\nB;\n',
    IMPORT_MSG,
  );
});

test("denies default, namespace and default-plus-named imports", () => {
  denies("lib/probe.ts", 'import D from "@supabase/supabase-js";\nD;\n', IMPORT_MSG);
  denies("lib/probe.ts", 'import * as S from "@supabase/supabase-js";\nS;\n', IMPORT_MSG);
  denies(
    "lib/probe.ts",
    'import D, { type A } from "@supabase/supabase-js";\nD;\nexport type T = A;\n',
    IMPORT_MSG,
  );
});

test("denies side-effect import", () => {
  denies("lib/probe.ts", 'import "@supabase/supabase-js";\n', IMPORT_MSG);
});

test("denies export-from", () => {
  denies("lib/probe.ts", 'export { createClient } from "@supabase/supabase-js";\n', IMPORT_MSG);
  denies("lib/probe.ts", 'export * from "@supabase/supabase-js";\n', IMPORT_MSG);
});

test("allows type-only supabase-js import", () => {
  allows(
    "lib/probe.ts",
    'import type { SupabaseClient } from "@supabase/supabase-js";\nexport type C = SupabaseClient;\n',
    IMPORT_MSG,
  );
});

test("allows multi-line type-only supabase-js import", () => {
  allows(
    "lib/probe.ts",
    'import type {\n  SupabaseClient,\n  User,\n} from "@supabase/supabase-js";\nexport type C = [SupabaseClient, User];\n',
    IMPORT_MSG,
  );
});

test("allows inline all-type supabase-js import", () => {
  allows(
    "lib/probe.ts",
    'import { type SupabaseClient, type User as U } from "@supabase/supabase-js";\nexport type C = [SupabaseClient, U];\n',
    IMPORT_MSG,
  );
  allows(
    "lib/probe.ts",
    'import {\n  type SupabaseClient,\n  type User,\n} from "@supabase/supabase-js";\nexport type C = [SupabaseClient, User];\n',
    IMPORT_MSG,
  );
});

test("allows type-only imports and exports containing comments", () => {
  for (const source of [
    'import { type A, /* note */ type B } from "@supabase/supabase-js";\n',
    'import { /* note */ type A } from "@supabase/supabase-js";\n',
    'import { type /* note */ A } from "@supabase/supabase-js";\n',
    'import { type A as /* note */ B } from "@supabase/supabase-js";\n',
    'import { type A, // note\n  type B } from "@supabase/supabase-js";\n',
    'import { /** doc **/ type A, /***/ type B } from "@supabase/supabase-js";\n',
    'import /* note */ type { A } from "@supabase/supabase-js";\n',
    'import type /* note */ { A } from "@supabase/supabase-js";\n',
    'export { type A, /* note */ type B } from "@supabase/supabase-js";\n',
    'export /* note */ type { A } from "@supabase/supabase-js";\n',
  ]) {
    allows("lib/probe.ts", source, IMPORT_MSG);
  }
});

test("allows type-only forms without whitespace or with unusual names", () => {
  for (const source of [
    'import type{ A } from "@supabase/supabase-js";\n',
    'export type{ A } from "@supabase/supabase-js";\n',
    'import type from from "@supabase/supabase-js";\n',
    'import { type "a-b" as C } from "@supabase/supabase-js";\n',
  ]) {
    allows("lib/probe.ts", source, IMPORT_MSG);
  }
});

test("denies a default import named type", () => {
  denies("lib/probe.ts", 'import type from "@supabase/supabase-js";\ntype;\n', IMPORT_MSG);
  denies("lib/probe.ts", 'import /* note */ type from "@supabase/supabase-js";\n', IMPORT_MSG);
});

test("denies runtime imports and exports hidden by comments", () => {
  for (const source of [
    'import { type A, /* note */ createClient } from "@supabase/supabase-js";\n',
    'import { /* type A */ createClient } from "@supabase/supabase-js";\n',
    'import { type A, // type B\n  createClient } from "@supabase/supabase-js";\n',
    'import /* a */ D, /* b */ { type A } from "@supabase/supabase-js";\n',
    'import { /* a */ createClient, /* b */ type A } from "@supabase/supabase-js";\n',
    'import /* type { */ D from "@supabase/supabase-js";\n',
    'import // type {\n  D from "@supabase/supabase-js";\n',
    'export /* note */ { createClient } from "@supabase/supabase-js";\n',
    'export /* type { */ { createClient } from "@supabase/supabase-js";\n',
  ]) {
    denies("lib/probe.ts", source, IMPORT_MSG);
  }
});

test("allows type-only export-from", () => {
  allows("lib/probe.ts", 'export type { User } from "@supabase/supabase-js";\n', IMPORT_MSG);
});

test("allows other modules and string literals", () => {
  allows("lib/probe.ts", 'import { x } from "other";\nexport { x };\n', IMPORT_MSG);
  allows("lib/probe.ts", 'export const u = "@supabase/supabase-js";\n', IMPORT_MSG);
});

test("ignores generated types", () => {
  // `debugger` proves Biome still lints the file; only the guardrail must be absent.
  const { output } = lint("lib/database.types.ts", `${DOT_SECRET}debugger;\n`, {
    generatedTypesOnlyByOverride: true,
  });
  assert.ok(output.includes("noDebugger"), `file was not linted at all:\n${output}`);
  assert.ok(!output.includes(SECRET_MSG), output);
});
