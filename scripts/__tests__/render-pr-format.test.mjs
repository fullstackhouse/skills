import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, readFile, writeFile, mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { parseDoc, parseExtension, renderBody, render, sectionEmoji, templateEmoji, templateProblems, unifiedDiff, main, DEFAULT_DOC } from "../render-pr-format.mjs";

const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const SHA = "0123456789abcdef0123456789abcdef01234567";

const DOC = `<!-- pr-format-version: 7 -->
# Format

- **🎯 The problem:** what went wrong.
- **✅ Testing:** what was proven.
<!-- extension: sections -->
- **⚠️ Worth knowing:** risks.

## A guide

Text.

<!-- extension: guides -->

Last line.
`;

const EXTENSION = `Notes for this repo's readers; not rendered.

<!-- slot: sections -->
- **🌱 Preview data:** what to seed.

<!-- slot: guides -->
## Preview data

Seed it.
`;

function sink() {
  let text = "";
  return { write: (chunk) => (text += chunk), get text() { return text; } };
}

async function fixture({ config = {}, output, extension, template } = {}) {
  const dir = await mkdtemp(join(tmpdir(), "render-pr-format-"));
  await writeFile(join(dir, "canonical.md"), DOC);
  if (extension !== undefined) await writeFile(join(dir, "ext.md"), extension);
  if (template !== undefined) await writeFile(join(dir, "template.md"), template);
  if (output !== undefined) {
    await mkdir(join(dir, "docs"), { recursive: true });
    await writeFile(join(dir, "docs", "pr.md"), output);
  }
  await writeFile(join(dir, "pr-format.json"), JSON.stringify({ source: "acme/skills", sha: SHA, output: "docs/pr.md", ...config }));
  return dir;
}

async function run(dir, args, io = {}) {
  const stdout = sink();
  const stderr = sink();
  const code = await main(args, { cwd: dir, stdout, stderr, fetch: () => { throw new Error("no network in tests"); }, ...io });
  return { code, stdout: stdout.text, stderr: stderr.text };
}

test("parseDoc reads the version, drops the marker and lists the slots", () => {
  const doc = parseDoc(DOC);
  assert.equal(doc.version, "7");
  assert.equal(doc.lines[0], "# Format");
  assert.deepEqual(doc.slots, ["sections", "guides"]);
});

test("parseDoc refuses a doc without a version marker", () => {
  assert.throws(() => parseDoc("# Format\n"), /pr-format-version/);
});

test("parseExtension ignores the preamble and trims each slot", () => {
  const slots = parseExtension(EXTENSION);
  assert.deepEqual([...slots.keys()], ["sections", "guides"]);
  assert.deepEqual(slots.get("sections"), ["- **🌱 Preview data:** what to seed."]);
  assert.deepEqual(slots.get("guides"), ["## Preview data", "", "Seed it."]);
});

test("parseExtension refuses a slot filled twice", () => {
  assert.throws(() => parseExtension("<!-- slot: a -->\nx\n<!-- slot: a -->\ny\n"), /twice/);
});

test("renderBody fills the slots where the doc marks them", () => {
  const { version, markdown } = renderBody(DOC, EXTENSION);
  assert.equal(version, "7");
  assert.equal(
    markdown,
    "# Format\n\n- **🎯 The problem:** what went wrong.\n- **✅ Testing:** what was proven.\n- **🌱 Preview data:** what to seed.\n- **⚠️ Worth knowing:** risks.\n\n## A guide\n\nText.\n\n## Preview data\n\nSeed it.\n\nLast line.\n",
  );
});

test("renderBody drops empty slots without leaving a double blank line", () => {
  const { markdown } = renderBody(DOC);
  assert.equal(markdown, "# Format\n\n- **🎯 The problem:** what went wrong.\n- **✅ Testing:** what was proven.\n- **⚠️ Worth knowing:** risks.\n\n## A guide\n\nText.\n\nLast line.\n");
  assert.doesNotMatch(markdown, /<!--/);
});

test("renderBody refuses an extension filling a slot the doc lacks", () => {
  assert.throws(() => renderBody(DOC, "<!-- slot: footer -->\nx\n"), /"footer".*no slot/);
});

test("render heads a markdown copy with the source, the pin and the extension", () => {
  const text = render({ canonical: DOC, extension: EXTENSION, source: "acme/skills", sha: SHA, extensionPath: "ext.md", renderCommand: "yarn pr-format:render" });
  const [banner, blank, title] = text.split("\n");
  assert.equal(banner, `> Generated from [acme/skills@0123456](https://github.com/acme/skills/blob/${SHA}/${DEFAULT_DOC}) (PR format v7) and \`ext.md\` — edit there, re-render here: \`yarn pr-format:render\`. Don't edit this file.`);
  assert.equal(blank, "");
  assert.equal(title, "# Format");
});

test("render's module form exports the markdown unchanged, escapes included", async () => {
  const tricky = DOC.replace("Text.", "Use `code`, ${notInterpolated} and a \\ backslash.");
  const source = render({ canonical: tricky, source: "acme/skills", sha: SHA, format: "module" });
  assert.match(source, /^\/\/ Generated from acme\/skills@0123456789abcdef0123456789abcdef01234567:/);
  const mod = await import(`data:text/javascript,${encodeURIComponent(source)}`);
  assert.equal(mod.PR_FORMAT, renderBody(tricky).markdown);
  assert.equal(mod.PR_FORMAT_VERSION, "7");
  assert.equal(mod.PR_FORMAT_SOURCE, `acme/skills@${SHA}`);
});

test("sectionEmoji and templateEmoji ignore the emoji variation selector", () => {
  assert.deepEqual(sectionEmoji(renderBody(DOC, EXTENSION).markdown), ["🎯", "✅", "🌱", "⚠"]);
  assert.deepEqual(templateEmoji("## Summary\n### 🎯 <what>\n### Design\n### ⚠️ Worth knowing\n"), ["🎯", "⚠"]);
});

test("templateProblems passes a template in step and names the order when it isn't", () => {
  const markdown = renderBody(DOC, EXTENSION).markdown;
  assert.deepEqual(templateProblems(markdown, "### 🎯 a\n## Other\n### ✅ b\n### 🌱 c\n### ⚠️ d\n"), []);
  assert.match(templateProblems(markdown, "### 🎯 a\n### 🌱 c\n### ✅ b\n### ⚠️ d\n")[0], /🎯 🌱 ✅ ⚠.*🎯 ✅ 🌱 ⚠/);
  assert.equal(templateProblems(markdown, "### 🎯 a\n### ✅ b\n### ⚠️ d\n").length, 1);
});

test("unifiedDiff is empty for equal texts and shows removals before additions", () => {
  assert.equal(unifiedDiff("a\nb\n", "a\nb\n"), "");
  assert.equal(unifiedDiff("a\nb\nc\n", "a\nB\nc\n", "x", "y"), "--- x\n+++ y\n@@ -1,4 +1,4 @@\n a\n-b\n+B\n c\n \n");
});

test("main writes the copy, then --check passes", async () => {
  const dir = await fixture({ config: { extension: "ext.md" }, extension: EXTENSION });
  const written = await run(dir, ["--canonical", "canonical.md"]);
  assert.equal(written.code, 0, written.stderr);
  const text = await readFile(join(dir, "docs", "pr.md"), "utf8");
  assert.match(text, /Preview data/);
  const checked = await run(dir, ["--check", "--canonical", "canonical.md"]);
  assert.equal(checked.code, 0, checked.stderr);
  assert.match(checked.stdout, /matches acme\/skills@0123456/);
});

test("main --check fails with a diff when the copy was edited by hand", async () => {
  const dir = await fixture({ config: { render: "yarn pr-format:render" } });
  await run(dir, ["--canonical", "canonical.md"]);
  const path = join(dir, "docs", "pr.md");
  await writeFile(path, (await readFile(path, "utf8")).replace("risks.", "risks and more."));
  const checked = await run(dir, ["--check", "--canonical", "canonical.md"]);
  assert.equal(checked.code, 1);
  assert.match(checked.stderr, /differs from the PR format at acme\/skills@0123456.*run `yarn pr-format:render`/);
  assert.match(checked.stderr, /^-- \*\*⚠️ Worth knowing:\*\* risks and more\.$/m);
  assert.match(checked.stderr, /^\+- \*\*⚠️ Worth knowing:\*\* risks\.$/m);
});

test("main --check fails when the pin moved but the copy wasn't re-rendered", async () => {
  const dir = await fixture();
  await run(dir, ["--canonical", "canonical.md"]);
  await writeFile(join(dir, "pr-format.json"), JSON.stringify({ source: "acme/skills", sha: "f".repeat(40), output: "docs/pr.md" }));
  const checked = await run(dir, ["--check", "--canonical", "canonical.md"]);
  assert.equal(checked.code, 1);
  assert.match(checked.stderr, /@fffffff/);
});

test("main --check fails when the copy is missing, and never writes", async () => {
  const dir = await fixture();
  const checked = await run(dir, ["--check", "--canonical", "canonical.md"]);
  assert.equal(checked.code, 1);
  assert.match(checked.stderr, /is missing/);
  await assert.rejects(readFile(join(dir, "docs", "pr.md")));
});

test("main --check reports a template out of step even when the copy matches", async () => {
  const dir = await fixture({ config: { template: "template.md" }, template: "### ✅ b\n### 🎯 a\n### ⚠️ d\n" });
  await run(dir, ["--canonical", "canonical.md"]);
  const checked = await run(dir, ["--check", "--canonical", "canonical.md"]);
  assert.equal(checked.code, 1);
  assert.match(checked.stderr, /template\.md: the PR template's ### sections are ✅ 🎯 ⚠/);
});

test("main refuses a pin that is not a full commit SHA", async () => {
  const dir = await fixture({ config: { sha: "main" } });
  const result = await run(dir, ["--canonical", "canonical.md"]);
  assert.equal(result.code, 2);
  assert.match(result.stderr, /full 40-character commit SHA/);
});

test("main fetches the doc from the pinned SHA", async () => {
  const dir = await fixture();
  const urls = [];
  const fetch = async (url) => (urls.push(url), { ok: true, status: 200, text: async () => DOC });
  const result = await run(dir, [], { fetch });
  assert.equal(result.code, 0, result.stderr);
  assert.deepEqual(urls, [`https://raw.githubusercontent.com/acme/skills/${SHA}/${DEFAULT_DOC}`]);
});

test("main reports a failed fetch", async () => {
  const dir = await fixture();
  const result = await run(dir, ["--check"], { fetch: async () => ({ ok: false, status: 404 }) });
  assert.equal(result.code, 2);
  assert.match(result.stderr, /HTTP 404/);
});

test("main rejects unknown arguments", async () => {
  const dir = await fixture();
  const result = await run(dir, ["--write"]);
  assert.equal(result.code, 2);
  assert.match(result.stderr, /unknown argument --write/);
});

test("the canonical doc renders, with a version and both slots", async () => {
  const canonical = await readFile(join(repoRoot, DEFAULT_DOC), "utf8");
  const doc = parseDoc(canonical);
  assert.match(doc.version, /^\d+$/);
  assert.deepEqual(doc.slots, ["sections", "guides"]);
  assert.deepEqual(sectionEmoji(renderBody(canonical).markdown), ["🎯", "🔧", "📦", "🧭", "🧩", "🔍", "✅", "⚠"]);
  assert.doesNotMatch(renderBody(canonical).markdown, /<!--|\n\n\n/);
});
