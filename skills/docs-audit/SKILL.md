---
name: docs-audit
description: Audit a repository against its own stated documentation contract — agent instruction files (AGENTS.md / CLAUDE.md) and what every session actually loads, spec numbering and template conformance, docs nothing links to, and links that no longer resolve — then repair what it finds. Use when an agent doc has grown long or stale, before adding a rule to one that is already big, when agents in a large repo seem to miss instructions that are written down, when specs or docs have drifted from the convention the repo describes, or on "clean up our CLAUDE.md", "our docs are a mess", "is any of this still accurate?". Read-only until each change is approved.
---

# docs-audit

You are running the **docs-audit** skill. The premise: agent instruction files
only ever grow. Every incident, review nit and correction adds a section, and
nothing ever removes one — measured across six FSH repos, roughly **2.5 KB per
month, per repo, indefinitely**. Past a point the file stops being read
carefully by anyone, human or agent, and some of it stops being true.

The same rot shows up in the rest of the documentation: specs drift from the
naming the repo describes, links rot, docs stop being reachable from anywhere.

Your job is to hold the repo to the contract **it already wrote for itself**, and
to make that contract readable again — not to impose a house style, and not to
delete rules you personally find verbose.

**The conventions are derived, never imposed.** There is no FSH house style to
enforce: groomershop and covo number and date their specs, tournee numbers them
without a date, open-mercato dates them without a number. Three conventions
across four repos. The script infers each directory's convention from its own
majority pattern and each spec template from the repo's own template file — so a
"violation" always means *the repo disagrees with itself*, which is the only kind
worth reporting.

**Hard rule: propose, don't apply.** Every change is shown as a diff and applied
only on approval. These files govern how every future session behaves; a rule
silently dropped is a behaviour silently changed.

## 1. Measure

```bash
python3 skills/docs-audit/scripts/docs_audit.py --root <repo>
```

Four rule families run by default; narrow with `--only chain,specs,index,links`.

**`chain`** — the agent instruction files, and what agents actually load:

- **Chains** — root → working dir, the unit that actually matters. Agents
  concatenate agent docs from the repo root down to where they are working.
  Codex stops at `project_doc_max_bytes` (32,768) and drops the rest **with no
  warning**; Claude Code loads the root file into every turn of every session.
  A chain at 175% means an agent working in that directory never sees the tail.
- **Largest files, with their three biggest sections** — where the bytes are.
  Start there, not at the top of the file.
- **Findings** — hard limits and structural problems.

**`specs`** — per spec directory, the convention derived from its own contents,
then: number collisions (`SPEC-041` used three times), files deviating from that
convention, and sections the repo's own template mandates that most specs carry
but some omit. Lettered variants (`SPEC-022a` following `SPEC-022`) are a
deliberate FSH pattern and are **not** collisions.

**`index`** — docs under a `docs/` path that nothing else in the repo points at,
by link or by name. Untracked files are ignored: Conductor scratch is not part of
the contract.

**`links`** — relative links that do not resolve. Placeholders in illustrative
snippets (`…/pull/N`, `<branch>`, `{{SLUG}}`) and `file.ts:191` code references
are not links and are skipped.

Budgets come from the consuming repo's `## Skill profile` if it sets them
(`agentDocs: rootMaxLines / budgetBytes`); otherwise 230 lines and 32,768 bytes.
Pass them through with `--root-max-lines` / `--budget-bytes`.

If the repo is clean and nothing is stale, say so and stop. A no-op run is a
good outcome.

## 2. Re-true before re-shaping

Restructuring a false rule only makes it more convincing. For every rule that
makes a checkable claim, check it — cheaply, in parallel:

- **Paths, commands, env vars, scripts it names** — do they still exist?
- **Rules now enforced in code** — a rule saying "always pass `--foo`" is dead
  weight once the tool defaults to it. This is the most common form of stale:
  the fix landed, the prose stayed.
- **Rules that duplicate a lint/CI gate** — the gate is the rule; the prose is
  a second copy that can drift out of agreement with it.
- **Links to specs, tickets, docs** — resolve them.

Anything contradicted is a **finding, not a rewrite**: report it and let the
user decide, because you usually cannot tell whether the rule or the world is
wrong.

## 3. Classify every section

One verdict per section. This is the whole skill — the rest is bookkeeping.

| Verdict | Test | Action |
|---|---|---|
| **Rule** | Names a decision an agent would otherwise get wrong. "MUST", "never", a non-obvious default. | Keep in place. |
| **Router** | Points at a deeper doc for a class of task. | Keep, as one line. |
| **Reference** | Explains how a subsystem works — conventions, patterns, API shapes. True and useful, but only when you are in that subsystem. | **Move** to a doc, leave a router row. Nothing is lost. |
| **Essay** | Narrates an incident: what we believed, what went wrong, the evidence. | Compress to the one-sentence rule; the evidence goes to a lessons/RCA record or to git. |
| **Stale** | §2 contradicted it, or code now enforces it. | Delete, or fix — user's call. |

**Reference and Essay are different diseases and need different medicine.** A
30 KB backend manual is good content in the wrong container: it moves, intact.
A file that is half post-incident write-ups needs compression, and that is a
conversation about what to lose. Never treat the first as the second — proposing
deletion of correct reference material is how this skill loses trust.

**The test for root-file space**: would an agent working *anywhere* in this repo
make a worse decision without it? If it only matters inside one directory, it
belongs in that directory's doc or a referenced doc. If it matters nowhere
specific, it probably is not a rule.

## 4. Propose

Order by bytes recovered. For each item:

- the section, its verdict and **why** that verdict
- where the content goes (never just "delete" for Reference)
- byte/line delta, and a running total against the limit

Then state the endpoint: `16,515 B / 263 lines → 9,200 B / 140 lines`, and which
findings that clears. If the target is still not reachable without cutting
something the user values, **say so** rather than trimming to fit.

## 5. Apply, then re-measure

Apply only what was approved. Re-run the script and show the real delta — not
the predicted one. Leave the repo committed-clean but **do not push or open a
PR**; hand that to `/deliver`.

## 6. Offer the gate

Prose limits do not hold. `om-create-agents-md` has said "root MUST stay under
230 lines" for months, and both repos that ship it are over — one by 62%. Once a
repo is inside its limits, offer to install the check:

1. Copy `scripts/docs_audit.py` into the repo (`scripts/`).
2. Record a baseline: `--baseline scripts/docs-audit.baseline.json --update-baseline`.
3. Add a CI step: `--check --baseline scripts/docs-audit.baseline.json`.

Only error-severity findings fail `--check`: collisions, dead links and budget
overruns are unambiguous, while naming deviations and orphans need a human to say
whether they are deliberate.

The baseline is a **ratchet, not a wall**: chains under budget grow freely;
chains already over may only shrink. That freezes existing debt without blocking
ordinary work, and makes re-recording it a deliberate, reviewable act.

Offer it. Don't install it unasked.

## Hard rules

1. **Nothing is applied without approval** — including deletions that look obvious.
2. **Never delete Reference content.** Move it and leave a router row. If there
   is nowhere to move it, say so and leave it alone.
3. **Re-true before re-shape.** Never restructure around a claim you have not checked.
4. **Keep the reason a counter-intuitive rule exists.** One sentence of "why"
   is what stops the next session from "fixing" it back.
5. **Git holds the history.** Never keep a struck-through passage, a "this used
   to say…" note, or a correction addressed to the document.
6. **Never rename a spec to resolve a collision without asking.** The number is
   cited from tickets, PRs and other specs; renaming breaks those references, and
   which of the two should move is a judgment only the author has.
7. **Report what you skipped**, so the filter stays reviewable.
8. **Client repos:** these files name internal systems, staff and infrastructure.
   Quote them into the local edit and your message to the user — never into a
   commit message, PR body, or anything that leaves the machine.
