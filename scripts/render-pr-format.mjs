#!/usr/bin/env node
// Renders the house PR-description format into a consuming repo, or checks that the repo's copy
// still matches it. Node 18+, no dependencies.
//
// The canonical doc is skills/pr-polish/references/pr-description.md in fullstackhouse/skills. A
// consumer pins it in a pr-format.json (paths relative to that file):
//
//   {
//     "source": "fullstackhouse/skills",           // GitHub owner/repo holding the doc
//     "sha": "<40-hex commit>",                    // the pin: a full commit SHA, never a branch
//     "output": ".ai/docs/pr-description.md",      // the generated copy (.md, or .ts/.js/.mjs)
//     "extension": ".ai/docs/pr-description.extension.md", // optional: the repo's slot contents
//     "template": ".github/PULL_REQUEST_TEMPLATE.md",      // optional: its ### emoji headings must
//                                                          // match the doc's sections, in order
//     "render": "yarn pr-format:render"            // optional: the command named in the banner
//   }
//
//   node render-pr-format.mjs [--config pr-format.json] [--check] [--canonical <file>]
//
// Without --check it writes `output`. With --check it writes nothing and exits 1, printing a diff,
// when `output` differs from what this script renders at the pinned SHA (or the template's headings
// are out of step). --canonical reads the doc from a local file instead of fetching it.
//
// The doc marks its version with `<!-- pr-format-version: N -->` and its repo slots with
// `<!-- extension: NAME -->` lines. An extension file fills them with `<!-- slot: NAME -->` blocks;
// anything above the first block is a note to its readers and is not rendered.

import { readFile, writeFile, mkdir } from "node:fs/promises";
import { dirname, resolve, relative, extname } from "node:path";
import { realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";

export const DEFAULT_DOC = "skills/pr-polish/references/pr-description.md";
const VERSION_MARKER = /^<!--\s*pr-format-version:\s*(\S+)\s*-->$/;
const EXTENSION_MARKER = /^<!--\s*extension:\s*([a-z][a-z0-9-]*)\s*-->$/;
const SLOT_MARKER = /^<!--\s*slot:\s*([a-z][a-z0-9-]*)\s*-->$/;
const SECTION_BULLET = /^- \*\*(\S+) [^*]*:\*\*/u;
const EMOJI = /\p{Extended_Pictographic}/u;

/** Splits the canonical doc into its version and its body (the marker line removed). */
export function parseDoc(text) {
  const lines = normalize(text).split("\n");
  const index = lines.findIndex((line) => VERSION_MARKER.test(line.trim()));
  if (index === -1) throw new Error("the canonical doc has no `<!-- pr-format-version: N -->` marker");
  const version = lines[index].trim().match(VERSION_MARKER)[1];
  lines.splice(index, 1);
  while (lines.length && lines[0].trim() === "") lines.shift();
  const slots = lines.map((line) => line.trim().match(EXTENSION_MARKER)?.[1]).filter(Boolean);
  return { version, lines, slots };
}

/** Reads an extension file's `<!-- slot: NAME -->` blocks into a Map of name → markdown. */
export function parseExtension(text) {
  const slots = new Map();
  let current = null;
  for (const line of normalize(text).split("\n")) {
    const name = line.trim().match(SLOT_MARKER)?.[1];
    if (name) {
      if (slots.has(name)) throw new Error(`the extension fills slot "${name}" twice`);
      slots.set(name, []);
      current = name;
    } else if (current) slots.get(current).push(line);
  }
  return new Map([...slots].map(([name, lines]) => [name, trimBlank(lines)]));
}

/**
 * Renders the doc body with the extension's slots filled. Returns the markdown without a banner.
 * A slot the extension leaves empty disappears with its marker line.
 */
export function renderBody(canonical, extensionText) {
  const doc = parseDoc(canonical);
  const fill = extensionText == null ? new Map() : parseExtension(extensionText);
  const unknown = [...fill.keys()].filter((name) => !doc.slots.includes(name));
  if (unknown.length)
    throw new Error(`the extension fills ${unknown.map((name) => `"${name}"`).join(", ")}, which the canonical doc has no slot for (slots: ${doc.slots.join(", ") || "none"})`);
  const out = [];
  let dropBlank = false;
  for (const line of doc.lines) {
    const name = line.trim().match(EXTENSION_MARKER)?.[1];
    if (dropBlank && line.trim() === "") {
      dropBlank = false;
      continue;
    }
    dropBlank = false;
    if (!name) out.push(line);
    else if (fill.get(name)?.length) out.push(...fill.get(name));
    else dropBlank = out.at(-1)?.trim() === ""; // the slot stays empty: drop its line and one blank around it
  }
  return { version: doc.version, markdown: trimBlank(out).join("\n") + "\n" };
}

/** Renders the full generated file: banner plus body, as markdown or as a JS/TS module. */
export function render({ canonical, extension, source, sha, doc = DEFAULT_DOC, extensionPath, renderCommand, format = "md" }) {
  const { version, markdown } = renderBody(canonical, extension);
  const origin = `${source}@${sha}`;
  const editHere = extensionPath ? ` and \`${extensionPath}\`` : "";
  const how = renderCommand ? `\`${renderCommand}\`` : "render-pr-format.mjs";
  if (format === "md") {
    const banner = `> Generated from [${source}@${sha.slice(0, 7)}](https://github.com/${source}/blob/${sha}/${doc}) (PR format v${version})${editHere} — edit there, re-render here: ${how}. Don't edit this file.`;
    return `${banner}\n\n${markdown}`;
  }
  const header = [
    `// Generated from ${origin}:${doc} (PR format v${version})${editHere.replace(/`/g, "")}`,
    `// — edit there, re-render here: ${how.replace(/`/g, "")}. Don't edit this file.`,
  ];
  return [
    ...header,
    `export const PR_FORMAT_VERSION = ${JSON.stringify(version)};`,
    `export const PR_FORMAT_SOURCE = ${JSON.stringify(origin)};`,
    `export const PR_FORMAT = \`${markdown.replace(/\\/g, "\\\\").replace(/`/g, "\\`").replace(/\$\{/g, "\\${")}\`;`,
    "",
  ].join("\n");
}

/** The emoji of the doc's section list, in order (`- **🎯 The problem:** …`). */
export function sectionEmoji(markdown) {
  return normalize(markdown)
    .split("\n")
    .map((line) => line.match(SECTION_BULLET)?.[1])
    .filter((token) => token && EMOJI.test(token))
    .map(stripVariation);
}

/** The emoji opening a template's `###` headings, in order; headings without one are skipped. */
export function templateEmoji(template) {
  return normalize(template)
    .split("\n")
    .map((line) => line.match(/^###\s+(\S+)/)?.[1])
    .filter((token) => token && EMOJI.test(token))
    .map(stripVariation);
}

/** Problems with a PR template's section headings against the rendered doc; empty when in step. */
export function templateProblems(markdown, template) {
  const want = sectionEmoji(markdown);
  const have = templateEmoji(template);
  if (want.join(" ") === have.join(" ")) return [];
  return [`the PR template's ### sections are ${have.join(" ") || "missing"}, but the format's are ${want.join(" ")}, in that order`];
}

/** A unified diff of two texts, three lines of context; empty when they are equal. */
export function unifiedDiff(before, after, fromLabel = "a", toLabel = "b") {
  if (before === after) return "";
  const a = before.split("\n");
  const b = after.split("\n");
  const lcs = Array.from({ length: a.length + 1 }, () => new Uint32Array(b.length + 1));
  for (let i = a.length - 1; i >= 0; i--)
    for (let j = b.length - 1; j >= 0; j--) lcs[i][j] = a[i] === b[j] ? lcs[i + 1][j + 1] + 1 : Math.max(lcs[i + 1][j], lcs[i][j + 1]);
  const ops = [];
  let i = 0;
  let j = 0;
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && a[i] === b[j]) ops.push({ kind: " ", text: a[i], i: i++, j: j++ });
    else if (i < a.length && (j === b.length || lcs[i + 1][j] >= lcs[i][j + 1])) ops.push({ kind: "-", text: a[i], i: i++, j });
    else ops.push({ kind: "+", text: b[j], i, j: j++ });
  }
  const out = [`--- ${fromLabel}`, `+++ ${toLabel}`];
  const changed = ops.map((op, index) => (op.kind === " " ? -1 : index)).filter((index) => index >= 0);
  let start = 0;
  while (start < changed.length) {
    let end = start;
    while (end + 1 < changed.length && changed[end + 1] - changed[end] <= 7) end++;
    const from = Math.max(0, changed[start] - 3);
    const to = Math.min(ops.length - 1, changed[end] + 3);
    const hunk = ops.slice(from, to + 1);
    const aCount = hunk.filter((op) => op.kind !== "+").length;
    const bCount = hunk.filter((op) => op.kind !== "-").length;
    out.push(`@@ -${hunk[0].i + 1},${aCount} +${hunk[0].j + 1},${bCount} @@`, ...hunk.map((op) => op.kind + op.text));
    start = end + 1;
  }
  return out.join("\n") + "\n";
}

/** Parses argv, renders or checks, and returns the exit code. `io` is injectable for tests. */
export async function main(argv, io = {}) {
  const { fetch: fetchImpl = globalThis.fetch, cwd = process.cwd(), stdout = process.stdout, stderr = process.stderr } = io;
  let args;
  try {
    args = parseArgs(argv);
  } catch (error) {
    stderr.write(`render-pr-format: ${error.message}\n`);
    return 2;
  }
  try {
    const configPath = resolve(cwd, args.config);
    const base = dirname(configPath);
    const config = JSON.parse(await readFile(configPath, "utf8"));
    for (const key of ["source", "sha", "output"]) if (typeof config[key] !== "string" || !config[key]) throw new Error(`${args.config} needs "${key}"`);
    if (!/^[\w.-]+\/[\w.-]+$/.test(config.source)) throw new Error(`"source" must be a GitHub owner/repo, not ${JSON.stringify(config.source)}`);
    if (!/^[0-9a-f]{40}$/.test(config.sha)) throw new Error(`"sha" must be a full 40-character commit SHA, so the pin cannot move: ${JSON.stringify(config.sha)}`);
    const doc = config.doc ?? DEFAULT_DOC;
    const canonical = args.canonical ? await readFile(resolve(cwd, args.canonical), "utf8") : await fetchDoc(fetchImpl, config.source, config.sha, doc);
    const extension = config.extension ? await readFile(resolve(base, config.extension), "utf8") : undefined;
    const outputPath = resolve(base, config.output);
    const format = [".ts", ".js", ".mjs", ".mts"].includes(extname(outputPath)) ? "module" : "md";
    const expected = render({ canonical, extension, source: config.source, sha: config.sha, doc, extensionPath: config.extension, renderCommand: config.render, format });
    const shown = relative(cwd, outputPath) || outputPath;
    const problems = config.template ? templateProblems(renderBody(canonical, extension).markdown, await readFile(resolve(base, config.template), "utf8")).map((problem) => `${config.template}: ${problem}`) : [];
    const fix = config.render ? `run \`${config.render}\`` : "re-render it";

    if (args.check) {
      const actual = await readFile(outputPath, "utf8").catch((error) => (error.code === "ENOENT" ? null : Promise.reject(error)));
      let failed = problems.length > 0;
      if (actual === null) {
        stderr.write(`render-pr-format: ${shown} is missing; ${fix}.\n`);
        failed = true;
      } else if (actual !== expected) {
        stderr.write(`render-pr-format: ${shown} differs from the PR format at ${config.source}@${config.sha.slice(0, 7)}. Edit the format there (or the extension), then ${fix}.\n`);
        stderr.write(unifiedDiff(actual, expected, `${shown} (in the repo)`, `${shown} (rendered)`));
        failed = true;
      }
      for (const problem of problems) stderr.write(`render-pr-format: ${problem}\n`);
      if (!failed) stdout.write(`render-pr-format: ${shown} matches ${config.source}@${config.sha.slice(0, 7)}.\n`);
      return failed ? 1 : 0;
    }

    await mkdir(dirname(outputPath), { recursive: true });
    await writeFile(outputPath, expected);
    stdout.write(`render-pr-format: wrote ${shown} from ${config.source}@${config.sha.slice(0, 7)}.\n`);
    for (const problem of problems) stderr.write(`render-pr-format: ${problem}\n`);
    return problems.length ? 1 : 0;
  } catch (error) {
    stderr.write(`render-pr-format: ${error.message}\n`);
    return 2;
  }
}

async function fetchDoc(fetchImpl, source, sha, doc) {
  const url = `https://raw.githubusercontent.com/${source}/${sha}/${doc}`;
  const response = await fetchImpl(url);
  if (!response.ok) throw new Error(`fetching ${url} failed: HTTP ${response.status}`);
  return response.text();
}

function parseArgs(argv) {
  const args = { config: "pr-format.json", check: false, canonical: null };
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (arg === "--check") args.check = true;
    else if (arg === "--config" || arg === "--canonical") {
      const value = argv[++index];
      if (!value) throw new Error(`${arg} needs a path`);
      args[arg.slice(2)] = value;
    } else throw new Error(`unknown argument ${arg} (usage: render-pr-format.mjs [--config pr-format.json] [--check] [--canonical <file>])`);
  }
  return args;
}

function normalize(text) {
  return text.replace(/\r\n?/g, "\n");
}

function stripVariation(token) {
  return token.replace(/\uFE0F/g, "");
}

function trimBlank(lines) {
  let start = 0;
  let end = lines.length;
  while (start < end && lines[start].trim() === "") start++;
  while (end > start && lines[end - 1].trim() === "") end--;
  return lines.slice(start, end);
}

if (process.argv[1] && realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url))) {
  process.exitCode = await main(process.argv.slice(2));
}
