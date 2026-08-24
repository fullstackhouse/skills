---
name: docs-audit
description: Audit a repository's documentation and agent instructions against the house conventions, fix what is mechanical, and leave the rest as a ranked proposal — measured, not eyeballed: instruction-budget overflow (the rules an agent never receives), CLAUDE.md/AGENTS.md drift, stale commands, dead links, unindexed docs, spec-convention breaks, and state docs narrating their own history. Optionally installs the CI gate so the rules hold without re-running it. Use when onboarding a repo, when agents keep ignoring documented rules, when someone asks "is our documentation any good / bring this repo up to standard", or before handing a repo to a new contributor. Args: a repo path (default: the current repo), plus `--audit-only` to write nothing.
---

# docs-audit

You are running the **docs-audit** skill. Goal: make a repository's documentation *work on the reader it actually has* — half of whom are agents that read a fixed number of bytes and then stop.

The failure this exists to catch is silent. A rule at the bottom of a 33 KB `AGENTS.md` is not low-priority, it is **absent**: the agent's context ends before it. Nobody notices, because the symptom is an agent that "ignores the conventions" and a human who writes the rule a third time, further down.

**Scope: structure, wiring, indexes and enforcement. Never the claims.** You may move a paragraph, split a file, add an index row, fix a link, install a gate. Correcting what a doc *asserts* is a different job with a different review — report it, don't fold it in.

The rubric is [`references/conventions.md`](./references/conventions.md). **Read it before Phase 3**; it carries the reasoning each rule was bought with, and you will need that to argue for an edit.

## 1. Resolve the target and the mode

- **Target** — the path given, else the current repo. Always work from the repo root (`git rev-parse --show-toplevel`).
- **Mode** — write by default: mechanical fixes applied (Phase 4), judgment calls proposed (Phase 5). `--audit-only` writes nothing at all.
- **Ownership decides how far you go.** `git remote -v` plus the repo's own docs:
  - **Ours** — audit and fix.
  - **A client's, that we work in** — audit and fix, but their stated conventions win over this rubric (see Hard rule 5).
  - **Upstream we don't own** — **propose only**, however wrong it looks. Reformatting a maintainer's `AGENTS.md` in a drive-by PR is how a contribution gets closed unread. Report, and offer to open one narrow PR for the single highest-value fix.
- **Read the repo's own rules first.** A root `AGENTS.md`/`CLAUDE.md`, a `docs/README.md`, a spec-directory `README.md`, `CONTRIBUTING.md`. A repo that has *deliberately* chosen differently is not in violation.

## 2. Measure

Facts first — the byte arithmetic and the link graph are not things to eyeball.

```bash
"${CLAUDE_SKILL_DIR}/scripts/doc-audit.sh" [repo-path] | tee /tmp/doc-audit.txt
```

Read-only, a couple of seconds on a large repo. It reports ten sections: instruction-budget chains, `CLAUDE.md`/`AGENTS.md` wiring, the `## Skill profile`, commands that no longer resolve, dead relative links, unindexed docs, spec convention, state-vs-record candidates, size outliers, and whether anything is CI-enforced.

Two of its sections are **heuristics, not findings** — §8 (state-vs-record) matches prose patterns and will flag a doc that merely *discusses* revision history, and §6 (orphans) flags raw corpora (`sources/`, `_archive/`, imported material) that are legitimately unlinked. Judge each; never paste them through as verdicts.

The other eight are arithmetic. Trust them.

## 3. Diagnose

Read the root doc and every nested agent doc in full. Skim the doc tree. Then name the shapes — these recur:

- **Fork at the top.** `AGENTS.md` and `CLAUDE.md` both carrying content. They have already drifted or will; the drift shows up as an agent that behaves differently depending on which tool ran it.
- **Claude-only repo.** No `AGENTS.md` anywhere. Every non-Claude agent — Codex, Cursor, most CI review bots — starts this repo with no instructions at all, and nothing in the repo says so.
- **Budget overflow.** A chain over 32 KB. Say *which rules* fall past the cutoff, by reading down to that byte offset — it is nearly always the `Never` list and the validation commands, because they sit at the bottom.
- **Procedure in the routing file.** The root doc carries worked examples, option tables, and step-by-step recipes. Those are what a referenced doc is for; the root's job is hard rules, boundaries, and where to look next.
- **No router.** Three or more nested agent docs and no Task Router table at the root. They get found by accident, if at all.
- **Absent or stale `## Skill profile`.** Every repo-agnostic skill then interrogates the user for the base branch, the check commands, the tracker, the reviewer.
- **Commands that lie.** A documented `yarn typecheck` that no longer exists sends an agent into a diagnostic detour before it can begin.
- **Journal in a state doc.** "corrected 2026-…", "an earlier revision said", a struck-through paragraph left in place, a diagram plus a note explaining the diagram is wrong. See rubric §1 — this is the rule most repos have never stated, and the one that compounds fastest.
- **Doc grown by bug fixes.** A contract or mapping doc that gains a section every time something breaks. The measurements belong in the spec (dated, historical by design); the doc gets the one-line conclusion.
- **Spec sprawl.** No template, no index, reused numbers, or every spec permanently `Draft` — a status field nobody moves is a status field nobody reads.
- **Index as a file listing.** An index that says *what exists* rather than *what each doc is good for* saves nobody a directory walk.
- **Nothing gated.** Every rule above holds only as long as someone re-reads it. See rubric §5.

Rank by what it costs: **rules that never arrive** > **instructions that mislead** (stale commands, drifted forks) > **friction** (missing profile, no router) > **hygiene** (dead links, orphans, naming).

## 4. Fix what is mechanical

Apply these directly — they have one correct answer and a reviewable diff:

- **The pointer.** Replace a forked or inverted `CLAUDE.md` with the two-line pointer; where only `CLAUDE.md` exists, `git mv` it to `AGENTS.md` and leave the pointer behind. Content unchanged, so the diff is pure wiring.
- **Dead links** — repoint to the moved file, or remove the link if its target is gone.
- **Index rows** for orphans that should be reachable; a one-clause description each, saying what the doc is good for.
- **Spec scaffolding** — the template and the index `README.md` when missing, from the rubric's section list. Backfill the index table from the specs already there.
- **`## Skill profile`** — write the skeleton and fill only what the repo can prove: default branch from `git`, check commands from `package.json` and the CI workflow, reviewer from recent PRs. Leave the rest as explicit `TODO:` lines rather than plausible guesses; a wrong tracker id is worse than a missing one.

Run whatever the repo uses to validate docs (link checkers, markdown lint) after editing.

## 5. Propose what is judgment

These change meaning or lose information. **Show the plan, apply after agreement** — and for a large one, do the first instance and let the user react before the rest.

- **Splitting an over-budget doc.** Propose the split line: what stays (hard rules, boundaries, router) and what moves to a referenced doc, with the byte count each side lands on. Never summarize a rule while moving it — move the text.
- **Deleting or archiving orphans.** Say which look superseded and by what.
- **Rewriting journal narration.** Quote the passage and give the state-doc replacement beside it. One example is more persuasive than the rule.
- **Handoffs, not duplicates.** A spec that is accurate but unreadable → `/spec-polish`. A ticket → `/ticket-polish`. A stale PR description → `/pr-polish`. Say so; don't do their job here.

## 6. Enforce

If the repo is over budget, or within ~15% of it, offer the gate — it is the difference between a rule and a preference:

```bash
mkdir -p scripts && cp "${CLAUDE_SKILL_DIR}/templates/check-agents-md-budget.mjs" scripts/
node scripts/check-agents-md-budget.mjs                    # see where it stands
node scripts/check-agents-md-budget.mjs --update-baseline  # only if debt exists already
```

Then wire it in: a `package.json` script (`"agents:check-budget"`), and a step in the CI job that already runs lint/typecheck — never a new workflow for one check.

The baseline is a **ratchet**: chains inside the budget grow freely; a chain already over it may only shrink, and a *new* over-budget chain fails outright. That freezes existing debt visibly instead of hiding it. Record the baseline only when the repo starts out over — a clean repo needs no baseline file.

## 7. Report

- **What never reaches an agent** — first, and quantified: which chains, how many bytes, which specific rules fall past the cutoff. This is the finding people act on.
- **Ranked list** of everything else, by the cost ranking in Phase 3.
- **Applied vs. proposed**, as two lists. Every applied edit in one commit per category, so each is separately revertible.
- **Deliberately left alone** — a convention the repo has chosen differently on purpose, a corpus directory that is meant to be unlinked, a client repo where we don't set policy.
- **What needs a human**: a doc whose facts look stale (name it, don't fix it), a rule that contradicts another rule, a spec directory nobody has touched in a year.

To ship it: `/deliver` (or `/deliver --no-merge` where a human should read the doc changes first).

## Hard rules

1. **Never change what a doc claims.** Structure, wiring, indexes and gates only. A factual correction inside a restructuring diff is an unreviewed edit — report it separately.
2. **Never delete a doc on your own judgment.** Propose, with what supersedes it.
3. **Never restructure a repo we don't own.** Report; offer one narrow PR for the single highest-value fix.
4. **The repo's deliberate convention beats this rubric.** Record the conflict in the report and move on. "Different from the house style" is not a finding.
5. **Never paste a heuristic through as a finding.** §6 and §8 of the script output are candidates; you judge them.
6. **Never add a manual "verify X" step** to a checklist as the fix. Gate it (Phase 6) or leave it — a checklist item nobody can fail is a preference with extra words.
7. **Confidentiality.** If the audit report, or any doc you touch, will land anywhere public — a public repo, an upstream PR — apply the gate in this repo's `AGENTS.md`: no client name, repo, path, ticket id, name-carrying identifier or infrastructure of theirs unless already public in their own material. A leak inherited from the old text becomes yours once you re-save the file.
