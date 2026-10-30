// PreToolUse guard for the backend/frontend subagents.
// Usage (from agent frontmatter): node guard.mjs <role>  < hook-input.json
// Exits 2 with the reason on stderr when the call is outside the role.
// Any other failure also exits 2: Claude Code only blocks on exit 2.

import path from "node:path";
import { pathToFileURL } from "node:url";
import { GIT_READ, GIT_READ_DENY_FLAGS, OWNERSHIP, READ_ONLY_BASH } from "./ownership.mjs";

const ok = { ok: true };
const deny = (reason) => ({ ok: false, reason: `agent-guard: ${reason}` });

// Lone `&`, redirects, substitutions, single quotes and escapes are never needed by
// the allowlisted commands and each one opens a way around the word-level checks.
const SHELL_FEATURES = /[<>`$\\']|(?<!&)&(?!&)/;
const GLOB_CHARS = /[*?[\]{}~]/;
// The only quoted form allowed: a plain commit message.
const COMMIT = /^git commit -m "[^"]*"$/;

function relativeInRepo(file, root) {
  if (typeof file !== "string" || file === "") return null;
  const rel = path.relative(root, path.resolve(root, file));
  if (rel.startsWith("..") || path.isAbsolute(rel)) return null;
  return rel;
}

// Matching is case-insensitive because the repo may sit on a case-insensitive
// filesystem, where lib/Database.types.ts is the generated types file.
const matches = (rel, globs) => globs.some((glob) => path.matchesGlob(rel.toLowerCase(), glob));

function mayWrite(rules, rel) {
  return matches(rel, rules.write) && !matches(rel, rules.exclude);
}

// A staged path may be a directory: it is owned only if everything under it is.
function mayStage(rules, rel) {
  if (matches(rel, rules.exclude)) return false;
  if (rel !== "" && mayWrite(rules, rel)) return true;
  const key = rel.toLowerCase();
  const insideOwnedTree = rules.write.some((glob) => {
    if (!glob.endsWith("/**")) return false;
    const base = glob.slice(0, -3);
    return key === base || key.startsWith(`${base}/`);
  });
  const coversExcluded = rules.exclude.some((glob) => glob.startsWith(`${key}/`));
  return insideOwnedTree && !coversExcluded;
}

function checkWrite(role, rules, file, root) {
  const rel = relativeInRepo(file, root);
  if (rel === null) return deny(`${role} may not write outside the repo`);
  if (!mayWrite(rules, rel)) return deny(`${role} may not write ${rel}`);
  return ok;
}

const hasPrefix = (segment, prefix) => segment === prefix || segment.startsWith(`${prefix} `);
const startsWithFlag = (words, flags) =>
  words.some((word) => flags.some((flag) => word.startsWith(flag)));

function checkGitAdd(role, rules, words, root) {
  const paths = [];
  let afterDashes = false;
  for (const word of words.slice(2)) {
    if (!afterDashes && word === "--") afterDashes = true;
    else if (!afterDashes && word.startsWith("-")) return deny(`${role} may not stage everything`);
    else paths.push(word);
  }
  if (paths.length === 0) return deny(`${role} may not stage everything`);
  for (const p of paths) {
    const rel = relativeInRepo(p, root);
    if (rel === null || !mayStage(rules, rel)) return deny(`${role} may not stage ${p}`);
  }
  return ok;
}

function supabaseAllowed(supabase, words, root) {
  if (!supabase || words[0] !== "pnpm" || words[1] !== "supabase") return false;
  const rest = words.slice(2);
  const sub = supabase.subcommands.find((s) => {
    const parts = s.split(" ");
    return parts.every((part, i) => rest[i] === part);
  });
  if (!sub) return false;
  const args = rest.slice(sub.split(" ").length);
  if (startsWithFlag(args, supabase.denyFlags)) return false;
  // Any path-like argument must stay inside supabase/.
  return args
    .filter((arg) => arg.includes("/"))
    .every((arg) => {
      const rel = relativeInRepo(arg.replace(/^--?[\w-]+=/, ""), root);
      return rel !== null && (rel === "supabase" || rel.startsWith("supabase/"));
    });
}

function segmentAllowed(rules, segment, words, root) {
  if (COMMIT.test(segment)) return true;
  if (segment.includes('"') || GLOB_CHARS.test(segment)) return false;
  if (rules.exact.includes(segment)) return true;
  if (READ_ONLY_BASH.some((prefix) => hasPrefix(segment, prefix))) return true;
  if (GIT_READ.some((prefix) => hasPrefix(segment, prefix)))
    return !startsWithFlag(words, GIT_READ_DENY_FLAGS);
  return supabaseAllowed(rules.supabase, words, root);
}

function checkBash(role, rules, command, root) {
  if (typeof command !== "string") command = "";
  if (SHELL_FEATURES.test(command)) return deny("redirects and substitutions are not allowed");

  for (const raw of command.split(/&&|\|\||;|\||\n/)) {
    const segment = raw.trim().replace(/\s+/g, " ");
    const words = segment.split(" ");
    if (hasPrefix(segment, "git add") && !GLOB_CHARS.test(segment) && !segment.includes('"')) {
      const result = checkGitAdd(role, rules, words, root);
      if (!result.ok) return result;
      continue;
    }
    if (!segmentAllowed(rules, segment, words, root))
      return deny(`${role} may not run: ${segment}`);
  }
  return ok;
}

export function check(role, input, root) {
  const rules = Object.hasOwn(OWNERSHIP, role) ? OWNERSHIP[role] : null;
  if (!rules) return deny(`unknown role ${role}`);

  const toolInput = input?.tool_input ?? {};
  switch (input?.tool_name) {
    case "Edit":
    case "Write":
      return checkWrite(role, rules, toolInput.file_path, root);
    case "NotebookEdit":
      return checkWrite(role, rules, toolInput.notebook_path ?? toolInput.file_path, root);
    case "Bash":
      return checkBash(role, rules, toolInput.command, root);
    default:
      return ok;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const role = process.argv[2];
    const root = path.resolve(import.meta.dirname, "../..");
    let raw = "";
    for await (const chunk of process.stdin) raw += chunk;

    let input;
    try {
      input = JSON.parse(raw);
    } catch {
      process.stderr.write("agent-guard: unreadable hook input\n");
      process.exit(2);
    }

    const result = check(role, input, root);
    if (!result.ok) {
      process.stderr.write(`${result.reason}\n`);
      process.exit(2);
    }
  } catch (error) {
    process.stderr.write(`agent-guard: internal error: ${error?.message ?? error}\n`);
    process.exit(2);
  }
}
