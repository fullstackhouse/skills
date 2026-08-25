# Documentation conventions

The rubric `docs-audit` grades against. Every rule here was extracted from repos that had
already paid for getting it wrong, so each one carries the failure it prevents rather than a
preference.

Two tests decide most questions:

- **Genre** — is this artifact *state* or *record*? The rules invert between them (§1).
- **Budget** — will an agent actually receive this text, or does it fall off the end (§2.2)?

---

## 1. State and record

Everything written is one of two genres. Decide which before editing.

**State** — architecture and contract docs, mapping tables, runbooks, every `README`, **the
body of every spec**, and **code comments**. They describe the system *as it is today*. Git
holds the history; the tracker holds the status. A reader must never have to subtract earlier
revisions to work out the current rule.

**Record** — incident reports, discovery notes from a meeting, options/estimate/proposal docs,
task findings, and each spec's `## Changelog`. These *are* journals, correctly so: a record is
dated, and a dated document is never wrong, only old. **A record is closed** — once its date
passes it is not edited, only superseded by a newer one or moved to an archive directory. The
moment you start amending a record it becomes a stale body with a patch stack on top.

Never write, in a state doc:

- **Corrections addressed to the doc** — "corrected 2026-08-04", "an earlier revision quoted…",
  "this section used to say the field is empty". State the fact; `git log -p` explains why it
  changed.
- **Before/after narration of our own changes** — "before #290 the read ordered only by id",
  "which cost 224 records their warning until #288 fixed it". State the invariant instead.
- **One-off migration steps** — "rows synced before #290 pick it up on the next run", plus the
  verification query. That belongs in the PR body or the spec.
- **A ticket id on every sentence.** Cite a task only when it is the doc's own subject or an
  open item.
- **A strikethrough of a superseded passage**, or a diagram plus a note explaining that the
  diagram is wrong. Delete the passage; redraw the diagram.

Do keep the *reason* behind a counter-intuitive rule, in a sentence — a field whose name lies
about its contents, a column that holds staff-written text despite being called a customer
comment. That is current-state knowledge a future reader needs in order not to "fix" the
mapping wrongly.

**Budget.** A bug fix should move a state doc's line count by roughly zero, not add a section.
When a finding needs forty lines of measurements to justify itself, the measurements go in the
spec (dated, historical by design) and the doc gets the one-line conclusion plus a link. One
integration-contract doc nearly doubled — 2,800 → 5,000 words — across two bug-fix PRs exactly
this way.

**A spec is both — keep the seam sharp.** The **body** is state: it describes the design as it
now stands, and you *rewrite* it when the design changes. The **Changelog** is the record: one
line per milestone, newest first, not one per edit. The failure mode is amending the body from
the changelog — a row reading "supersedes this spec's earlier dataset language" means the body
still says the wrong thing and the reader is expected to apply the patch themselves. If a
change invalidates a paragraph, **edit the paragraph** and leave one line in the changelog.

**Code comments follow the same rule**: a comment explains the code as it is and why a
non-obvious choice is right — never the version it replaced, never the review thread it came
from. `git blame` covers both. A `// TICKET-N — what and why` header on a non-obvious block is
the one place a ticket id earns its keep. A comment block longer than the function it
describes is a spec section in the wrong file.

---

## 2. The agent-instruction layer

### 2.1 One canonical file

`AGENTS.md` is canonical. `CLAUDE.md` is a pointer next to it containing exactly:

```
@AGENTS.md
```

Why this and not the alternatives:

- **A fork** (two independent files) drifts, silently, and the drift is invisible until an
  agent behaves differently depending on which tool was used.
- **A symlink** works, but breaks on Windows checkouts and on export/archive paths, and it
  inverts in repos where someone symlinked the wrong direction — leaving the canonical name
  as the pointer.
- **A `CLAUDE.md`-only repo** is invisible to every non-Claude agent. Codex, Cursor, and
  most CI review bots read `AGENTS.md` and nothing else.

### 2.2 The instruction budget

Coding agents load the agent docs from the repository root down to the working directory and
stop once the **combined** size reaches their project-instruction budget. Codex's default
`project_doc_max_bytes` is **32,768 bytes** — a byte budget, not a token budget. Everything
past that offset is silently dropped from the first-turn prompt, with no warning that it
happened.

Two consequences:

1. The root file must stay under the budget on its own, or its own tail never reaches any agent.
2. The root also spends the budget the nested files need. The more the root takes, the less of
   `packages/<pkg>/AGENTS.md` survives when an agent starts inside that package.

The working limits: **root ≤ 31,232 B** (the budget minus a 1.5 KB reserve so nested files get
some of it), and **every root-to-leaf chain ≤ 32,768 B**.

This is not theoretical. Chains measured in the wild: a backend package doc at 33 KB that
exceeds the whole budget by itself, and a monorepo chain totalling 48 KB — a third of it
unreachable, including the "never do X" rules at the bottom of the file.

**Rule of thumb when editing any agent doc:** hard rules, boundaries and routing stay in the
file; long-form procedure, tables of options and worked examples move into a referenced
document the agent reads on demand.

### 2.3 Structure

The root doc, in this order:

1. **What this repo is** — two or three sentences, including what it is *not*.
2. **Repository structure** — the map, one line per package.
3. **Boundary labels** — `## Always`, `## Ask First`, `## Never`, `## Validation Commands`.
   - `Always` — required defaults agents apply without asking.
   - `Ask First` — decisions needing a human before changing behavior, scope, dependencies,
     branch/deploy flow, or contract surfaces.
   - `Never` — prohibited actions and unsafe shortcuts.
   - `Validation Commands` — short, real commands that prove the relevant path.
4. **Task Router** — once there are three or more nested agent docs. A table: task shape on
   the left, which guide to read on the right. Without it, nested docs are only found by
   accident, and an agent that starts at the root never learns the package rules apply.
5. **Conventions** — naming, commit style, language policy.
6. **`## Skill profile`** — the machine-read block (§2.4).

Nested docs cover local architecture, imports and validation for their subtree, and nothing
the root already says.

### 2.4 Skill profile

A `## Skill profile` section in the root doc carries the values repo-agnostic skills would
otherwise have to guess: base branch, per-package check commands, tracker and its status
vocabulary, spec location, reviewer bot, merge policy, status channel and audience. Its
knobs are listed in this repo's README.

The test of a good profile: a skill invoked in a fresh session asks the user nothing.

### 2.5 Staleness

Every command an agent doc prints is a claim. A `yarn typecheck` that no longer exists in
`package.json` sends the agent down a diagnostic rabbit hole before it can start. Check the
referenced scripts, not just the prose.

---

## 3. The doc system

**One index per directory, and the index carries judgment.** A file list is what `ls` is for.
An index says what each doc is *good for*, so "look at how we did X" resolves in one step
instead of a filesystem safari. An index that needs a paragraph per entry is a sign the
paragraph belongs in the doc itself.

**Every doc is reachable from an index.** A doc nothing links to is reachable only by someone
who already knows it exists — which means it wants an index row, or deletion. Raw corpora
(imported sources, `_archive/`) are the deliberate exception; say so in the directory's README.

**Specs.** One directory (`docs/specs/` or `.ai/specs/`), and:

- **Naming** — `SPEC-{NNN}-{YYYY-MM-DD}-{kebab-title}.md`. Sequential number, creation date,
  descriptive title. The number is the citation handle; never renumber, never reuse. (Repos
  that skipped the index have collided twice.)
- **A committed template** — `SPEC-000-template.md`, so a new spec starts from the house shape
  rather than from whichever spec the author last read. Sections: TLDR, Problem Statement,
  Proposed Solution, Data Models, API Contracts, Implementation Approach, Key Design
  Decisions, Open Questions, Changelog. Plus a header block: Date, Status, Owner, tracker link.
- **An index** — `README.md` in the spec directory: when to write a spec, the naming rule, the
  workflow, and a table of every spec with its status and a one-line description.
- **Status is a lifecycle**, not decoration: Draft → Approved → Implemented → Superseded. A
  directory where everything is permanently "Draft" is telling you the status field is unused.

**Records** get their own home — `docs/archive/`, or a dated filename prefix — so that the
state docs around them stay editable and the records stay closed.

**Keep docs near execution.** Durable knowledge belongs in the repo that executes on it.
Reusable method belongs wherever the company keeps its handbook. Do not mirror one into the
other without a sync script — an unsynced copy is a second source of truth that ages.

---

## 4. Prose rules

- **Verdict first, evidence attached.** State the conclusion, then the measurement that earns
  it: dates, numbers, PR numbers, file paths. A claim with no evidence reads as an opinion and
  gets re-litigated.
- **One clause per row in a table.** If a row needs a paragraph, the paragraph belongs in the
  document that row points at.
- **Label cautionary examples as such.** "Go here for X. Cautionary: its root doc is 26 KB,
  half of it post-incident essays" is more useful than either praise or silence.
- **Self-limiting sections.** An index that explains how to keep itself honest ("adding a row
  is cheap; adding a *section* means this file is turning into the thing it exists to avoid")
  survives contact with a year of edits.
- **Language policy is explicit.** Where a repo mixes languages — client-facing writing in one,
  engineering in another — state the rule and state which terms stay untranslated.

---

## 5. Enforcement

A rule nobody can fail is a preference. If a convention matters, gate it:

- The instruction budget is CI-checkable in ~100 lines (`templates/check-agents-md-budget.mjs`
  in this skill).
- A "did you bump the version / update the index" rule is a `git diff` check in a workflow.
- Prefer a **ratchet** to a hard failure on legacy debt: a chain already over budget may only
  shrink, so the debt is frozen rather than hidden, and new files still get a hard limit.

The corollary, and the reason this section exists: **do not add a manual "verify X" checklist
step.** Make the command that consumes X fail loudly instead.

---

## 6. Fast checklist

| Symptom | Rule |
|---|---|
| `CLAUDE.md` and `AGENTS.md` both have content | §2.1 — pointer, not fork |
| No `AGENTS.md` at all | §2.1 — non-Claude agents read nothing |
| Root doc > 31 KB, or a chain > 32 KB | §2.2 — the tail never arrives |
| Nested docs exist, no Task Router | §2.3 — they're found by accident |
| Skills keep asking which branch / what to run | §2.4 — no Skill profile |
| A documented command no longer exists | §2.5 |
| "corrected 2026-…", "previously this said", `~~struck through~~` | §1 — state doc narrating its past |
| A doc grew a section during a bug fix | §1 — budget |
| Specs with reused numbers, or no template | §3 |
| A doc nothing links to | §3 — index row or delete |
| No CI gate on any of this | §5 |
