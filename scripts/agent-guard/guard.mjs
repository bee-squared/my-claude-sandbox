// PreToolUse guard for the backend/frontend subagents.
// Usage (from agent frontmatter): node guard.mjs <role>  < hook-input.json
// Exits 2 with the reason on stderr when the call is outside the role.

import path from "node:path";
import { pathToFileURL } from "node:url";
import { OWNERSHIP, SHARED_BASH } from "./ownership.mjs";

const ok = { ok: true };
const deny = (reason) => ({ ok: false, reason: `agent-guard: ${reason}` });

function relativeInRepo(file, root) {
  if (typeof file !== "string" || file === "") return null;
  const rel = path.relative(root, path.resolve(root, file));
  if (rel.startsWith("..") || path.isAbsolute(rel)) return null;
  return rel;
}

function mayWrite(rules, rel) {
  return (
    rules.write.some((glob) => path.matchesGlob(rel, glob)) &&
    !rules.exclude.some((glob) => path.matchesGlob(rel, glob))
  );
}

// A staged path may be a directory: it is owned only if everything under it is.
function mayStage(rules, rel) {
  if (rel !== "" && mayWrite(rules, rel)) return true;
  const insideOwnedTree = rules.write.some((glob) => {
    if (!glob.endsWith("/**")) return false;
    const base = glob.slice(0, -3);
    return rel === base || rel.startsWith(`${base}/`);
  });
  const coversExcluded = rules.exclude.some((glob) => glob.startsWith(`${rel}/`));
  return insideOwnedTree && !coversExcluded;
}

function checkWrite(role, rules, file, root) {
  const rel = relativeInRepo(file, root);
  if (rel === null) return deny(`${role} may not write outside the repo`);
  if (!mayWrite(rules, rel)) return deny(`${role} may not write ${rel}`);
  return ok;
}

const hasPrefix = (segment, prefix) => segment === prefix || segment.startsWith(`${prefix} `);

function containsWords(words, phrase) {
  const target = phrase.split(" ");
  return words.some((_, i) => target.every((word, j) => words[i + j] === word));
}

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

function checkBash(role, rules, command, root) {
  if (typeof command !== "string") command = "";
  if (/[>`]|\$\(/.test(command)) return deny("redirects and substitutions are not allowed");

  for (const raw of command.split(/&&|\|\||;|\||\n/)) {
    const segment = raw.trim().replace(/\s+/g, " ");
    const words = segment.split(" ");
    if (hasPrefix(segment, "git add")) {
      const result = checkGitAdd(role, rules, words, root);
      if (!result.ok) return result;
      continue;
    }
    const permitted =
      [...SHARED_BASH, ...rules.bash].some((prefix) => hasPrefix(segment, prefix)) &&
      !rules.bashDeny.some((phrase) => containsWords(words, phrase));
    if (!permitted) return deny(`${role} may not run: ${segment}`);
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
}
