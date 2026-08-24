#!/usr/bin/env node
/**
 * check-agents-md-budget — keep agent instructions inside the budget agents actually read.
 *
 * An agent loads the AGENTS.md files from the repo root down to its working directory and
 * stops once the COMBINED size reaches its project-instruction budget (Codex's default
 * `project_doc_max_bytes` is 32,768 bytes). Everything past that offset is dropped from the
 * prompt silently — no warning, no truncation notice. So the rules at the bottom of a long
 * file are not "lower priority", they are absent.
 *
 * Two limits:
 *   1. Root hard limit  — the root file alone, so its own tail always arrives and nested
 *                         files still get a share of the budget.
 *   2. Chain ratchet    — a root-to-leaf chain inside the budget may grow freely. Once it is
 *                         over, its NESTED files may only shrink. This freezes existing debt
 *                         instead of hiding it, and blocks new debt outright.
 *
 * Usage:
 *   node scripts/check-agents-md-budget.mjs                 # check (exit 1 on violation)
 *   node scripts/check-agents-md-budget.mjs --update-baseline
 *
 * Wire it into the CI job that already runs lint/typecheck. Re-record the baseline
 * deliberately, in a PR that explains why.
 */
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync, writeFileSync, statSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'

const DEFAULTS = { rootMaxBytes: 31232, chainBudgetBytes: 32768 }
const UPDATE = process.argv.includes('--update-baseline')

const repoRoot = execFileSync('git', ['rev-parse', '--show-toplevel'], { encoding: 'utf8' }).trim()
process.chdir(repoRoot)
const BASELINE_PATH = resolve(repoRoot, 'scripts/agents-md-budget.baseline.json')

const baseline = existsSync(BASELINE_PATH)
  ? { ...DEFAULTS, chains: {}, ...JSON.parse(readFileSync(BASELINE_PATH, 'utf8')) }
  : { ...DEFAULTS, chains: {} }

const tracked = execFileSync('git', ['ls-files'], { encoding: 'utf8' })
  .split('\n')
  .filter((f) => /(^|\/)(AGENTS|CLAUDE)\.md$/.test(f))

/** The file an agent actually loads for a directory: AGENTS.md, else CLAUDE.md. */
function effectiveDoc(dir) {
  for (const name of ['AGENTS.md', 'CLAUDE.md']) {
    const p = dir === '.' ? name : join(dir, name)
    if (existsSync(p)) return p
  }
  return null
}

// statSync, not lstatSync: a CLAUDE.md/AGENTS.md symlink must weigh what the agent reads.
const sizeOf = (p) => (existsSync(p) ? statSync(p).size : 0)

const dirs = [...new Set(tracked.map((f) => dirname(f)))].sort()
if (dirs.length === 0) {
  console.log('check-agents-md-budget: no AGENTS.md or CLAUDE.md found — nothing to check.')
  process.exit(0)
}

const rootDoc = effectiveDoc('.')
const rootBytes = rootDoc ? sizeOf(rootDoc) : 0
const leaves = dirs.filter((d) => !dirs.some((o) => o !== d && o.startsWith(d === '.' ? '' : `${d}/`)))

const chains = leaves.map((leaf) => {
  const parts = dirs
    .filter((d) => d === '.' || d === leaf || leaf.startsWith(`${d}/`))
    .map(effectiveDoc)
    .filter(Boolean)
    .map((doc) => ({ doc, bytes: sizeOf(doc) }))
  const total = parts.reduce((s, p) => s + p.bytes, 0)
  return { leaf, parts, total, nested: total - rootBytes }
})

if (UPDATE) {
  const next = {
    rootMaxBytes: baseline.rootMaxBytes,
    chainBudgetBytes: baseline.chainBudgetBytes,
    chains: Object.fromEntries(
      chains
        .filter((c) => c.total > baseline.chainBudgetBytes)
        .map((c) => [c.leaf, { nestedBytes: c.nested }]),
    ),
  }
  writeFileSync(BASELINE_PATH, `${JSON.stringify(next, null, 2)}\n`)
  console.log(`check-agents-md-budget: baseline written to ${BASELINE_PATH}`)
  console.log(`  over-budget chains recorded: ${Object.keys(next.chains).length}`)
  process.exit(0)
}

const failures = []

if (!rootDoc) {
  failures.push('No root AGENTS.md (or CLAUDE.md). Nested agent docs are never reached from the repo root.')
} else if (rootBytes > baseline.rootMaxBytes) {
  failures.push(
    `${rootDoc} is ${rootBytes}B, over the ${baseline.rootMaxBytes}B root limit by ${rootBytes - baseline.rootMaxBytes}B.\n` +
      '  Move long-form procedure into a referenced doc; keep hard rules and routing here.',
  )
}

for (const c of chains) {
  if (c.total <= baseline.chainBudgetBytes) continue
  const recorded = baseline.chains?.[c.leaf]?.nestedBytes
  const lost = c.total - baseline.chainBudgetBytes
  const shape = c.parts.map((p) => `      ${String(p.bytes).padStart(7)}B  ${p.doc}`).join('\n')
  if (recorded === undefined) {
    failures.push(
      `New over-budget chain at ${c.leaf}: ${c.total}B, ${lost}B past the ${baseline.chainBudgetBytes}B budget.\n${shape}`,
    )
  } else if (c.nested > recorded) {
    failures.push(
      `Chain at ${c.leaf} grew: nested files ${recorded}B -> ${c.nested}B. Already over budget, so they may only shrink.\n` +
        `  ${lost}B of this chain never reaches an agent working there.\n${shape}`,
    )
  }
}

const overBudget = chains.filter((c) => c.total > baseline.chainBudgetBytes)
console.log(
  `check-agents-md-budget: root ${rootBytes}B/${baseline.rootMaxBytes}B, ` +
    `${chains.length} chain(s), ${overBudget.length} over the ${baseline.chainBudgetBytes}B budget.`,
)
for (const c of overBudget) {
  console.log(`  over: ${c.leaf} — ${c.total}B (${c.total - baseline.chainBudgetBytes}B unreachable)`)
}

if (failures.length) {
  console.error('\ncheck-agents-md-budget FAILED:\n')
  for (const f of failures) console.error(`  - ${f}\n`)
  console.error('  Shrink the file, or re-record deliberately: --update-baseline (explain it in the PR).')
  process.exit(1)
}

console.log('check-agents-md-budget: ok')
