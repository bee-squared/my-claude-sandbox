import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import { OWNERSHIP } from "./ownership.mjs";

const root = path.resolve(import.meta.dirname, "../..");

const SKILLS = {
  backend: [
    "supabase:supabase",
    "supabase:supabase-postgres-best-practices",
    "superpowers:test-driven-development",
  ],
  frontend: ["supabase:supabase"],
};

function readAgent(role) {
  const text = readFileSync(path.join(root, ".claude/agents", `${role}.md`), "utf8");
  const [, frontmatter, body] = text.split(/^---$/m);
  return { frontmatter, body };
}

function listedSkills(frontmatter) {
  const block = frontmatter.match(/^skills:\n((?:\s+- .+\n)+)/m);
  return block ? block[1].trim().split("\n").map((line) => line.replace(/^\s*- /, "").trim()) : [];
}

for (const role of Object.keys(OWNERSHIP)) {
  test(`${role} agent frontmatter wires the guard`, () => {
    const { frontmatter } = readAgent(role);
    assert.match(frontmatter, new RegExp(`^name: ${role}$`, "m"));
    assert.match(frontmatter, /matcher: "Edit\|Write\|NotebookEdit\|Bash"/);
    // Claude Code only blocks on exit 2, so any guard failure must become exit 2.
    assert.match(frontmatter, new RegExp(`command: .*guard\\.mjs" ${role} \\|\\| exit 2'`));
  });

  test(`${role} agent preloads exactly its skills`, () => {
    assert.deepEqual(listedSkills(readAgent(role).frontmatter), SKILLS[role]);
  });

  test(`${role} agent body lists every owned path from the ownership map`, () => {
    const { body } = readAgent(role);
    for (const glob of [...OWNERSHIP[role].write, ...OWNERSHIP[role].exclude]) {
      assert.ok(body.includes(glob), `body is missing ${glob}`);
    }
  });
}
