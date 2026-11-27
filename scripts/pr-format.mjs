#!/usr/bin/env node
// Copy this file into a repo that keeps a generated copy of the house PR format (see README →
// "The house PR format in other repos"). It fetches render-pr-format.mjs at the SHA pinned in
// ./pr-format.json and runs it with this script's arguments, e.g. `node scripts/pr-format.mjs --check`.
// The pin is a full commit SHA, so the code it runs cannot change under you.
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";

const { source, sha } = JSON.parse(readFileSync("pr-format.json", "utf8"));
if (!/^[\w.-]+\/[\w.-]+$/.test(source ?? "") || !/^[0-9a-f]{40}$/.test(sha ?? "")) {
  console.error('pr-format.json needs "source" (owner/repo) and "sha" (a full 40-character commit SHA)');
  process.exit(2);
}
const url = `https://raw.githubusercontent.com/${source}/${sha}/scripts/render-pr-format.mjs`;
const response = await fetch(url);
if (!response.ok) {
  console.error(`fetching ${url} failed: HTTP ${response.status}`);
  process.exit(2);
}
const script = join(mkdtempSync(join(tmpdir(), "pr-format-")), "render-pr-format.mjs");
writeFileSync(script, await response.text());
process.exit(spawnSync(process.execPath, [script, ...process.argv.slice(2)], { stdio: "inherit" }).status ?? 2);
