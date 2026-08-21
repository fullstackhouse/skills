---
name: spec-polish
description: Restructure a spec or design doc that is accurate but hard to enter — a first screen a newcomer can stop after, the decision the doc asks of its reader stated up front, the argument before the evidence, catalogues and traceability ids moved to appendices, sections in reader order rather than template order. Form only, facts unchanged — it spot-checks the spec's evidence against the code first and refuses to polish stale claims. Use when a spec "reads like a reviewer's notebook", opens with a table or a wall of metadata, when someone asks "what is this doc actually saying", or after a long spec-writing session before the spec is shared. Args: a spec path, or nothing to use the specs touched on the current branch.
---

# spec-polish

You are running the **spec-polish** skill. Goal: make a spec readable top-down — *od ogółu do szczegółu* — so that a reader who stops after the first screen has a correct, just less detailed, picture, and knows what the document asks them to decide.

This is `pr-polish` and `ticket-polish` one artifact over. A spec written carefully over a long session is usually **accurate and unreadable at once**: every claim was verified, every finding got an id, and the ids, tables and metadata crowded out the story. The author cannot see it — they hold the whole map; the reader meets the legend first.

**Scope: the spec file(s), and one changelog line each.** Never change a fact, a finding, a requirement or a decision. Never delete evidence. Never edit code.

## 1. Resolve the spec(s)

- Explicit path → use it. A spec series (`…-01-…`, `…-02-…` or cross-linked "part n" docs) is polished as a set: the parts must open the same way and agree on the series' purpose.
- Nothing given → specs added or modified on the current branch vs. its base (`git diff --name-only <base>...HEAD`, filtered to the repo's specs location). None → stop and say so.
- Where specs live and what they must contain: the repo's `## Skill profile` (`Specs` knob), its specs-folder `AGENTS.md` / `README` / template, or convention (`docs/specs/`, `.ai/specs/`, `specs/`). Note any **required sections** the repo mandates; their *names* are binding, their *order* is not unless the repo says so.

## 2. Gate: does the spec still describe reality?

A polish rearranges; it must not launder. Specs cite code, PRs and numbers — each is a claim that ages.

- **Pin.** Find the commit the spec was written against (a `HEAD`/SHA in its header, the spec's own commit date, or the branch point). Diff the cited paths from that commit to the current tree (`git diff <sha> -- <paths>`); a cited path that changed is a claim to re-check.
- **Spot-check** three to five concrete evidence citations — file paths, function names, constants, line references — against the current tree. Prefer the ones the argument leans on.
- **Linked artifacts.** Every PR / issue / sibling spec the spec references: does it still exist, and is its state what the spec implies ("waits on #N" ages the day #N merges)?

Anything contradicted → **stop and report it before restructuring.** Correcting facts is a different job with a different review; do it as a separate, clearly labelled edit only if the user asks, then polish. Never fix a fact *inside* the polish — a reader checking the diff cannot tell a reshape from a retraction.

A spec already in an `implemented/` state (or whose changelog records shipped phases) is history as much as design: restructure its entry, keep the implementation record intact, and append — never rewrite — the changelog.

## 3. Diagnose the decay

Read the entire spec (all parts of a series) before touching anything. Name the shapes it suffers from — these recur:

- **Metadata wall.** Five bold-label lines of scope, SHAs, PR numbers and caveats before the reader knows what the document is. Keep one line of status; move the rest to a "Scope and method" section after the first screen.
- **Technical TL;DR.** The summary already names constants, functions and flags. A TL;DR a product manager cannot follow is a details section with the wrong heading. The first screen is written for the least technical person who will have to act on the doc.
- **Id-soup.** Finding ids (`D-12`, `W-18`), class ids, requirement ids and their prefix legend appear before the reader has met a single finding in prose. Ids are a citation system: the narrative refers to them, it does not open with them. The legend lives in the appendix.
- **Table before narrative.** A 20-row catalogue in the first screen. A table is evidence; the reader needs the claim it supports first. Move catalogues to appendices or to the end of the section they back, and lead each section with the two or three rows that matter most, in prose.
- **No ask.** The doc does not say what the reader is expected to do with it — approve a direction, pick between options, agree the requirements are the bar, file tickets. State the ask in the first screen; the rest of the doc is the case for it.
- **Template order.** Sections in the order the template lists them rather than the order a reader needs them (data model before the reader knows the problem; risks after the implementation plan). Keep mandated section names; reorder for the reader.
- **Requirements without alternatives.** Decisions or requirements stated before the reader has seen what they rule out. One line of "instead of" per decision is usually enough.
- **Review scaffolding left in.** Traceability matrices, compliance checklists, "verified by" notes interleaved with the design. They earned their place; it is at the back.
- **Title drift.** A title that describes the session ("review of X") rather than the document's claim or question.

## 4. Rewrite

Top-down, general to specific. A reader should be able to stop after each of these and be right, just less detailed:

1. **Title** — the claim or the question, not the activity.
2. **First screen** (≤ 1 screen, no tables, no ids, no code identifiers): what this document is, who it is for, **what it asks the reader to decide**, and the whole argument in three to five plain sentences. Series → one shared paragraph naming the parts and this part's role.
3. **The argument** — the handful of findings, decisions or requirements that carry the conclusion, in prose, with the evidence cited by id or section. A reviewer in a hurry stops here.
4. **The evidence** — the detailed sections, in the order the argument needs them. Mandated sections keep their names.
5. **Appendices** — catalogues, matrices, id legends, traceability, compliance reports, method and scope caveats.
6. **Changelog** — one line: "restructured for readability; no findings, requirements or decisions changed".

Writing rules:

- **Facts unchanged.** Same findings, same ids, same numbers, same requirements, same open decisions. If you cannot restate a sentence without altering its claim, keep the sentence.
- **Ids survive; prose leads.** Renumbering breaks every external citation; never do it. Moving a table to an appendix is fine; dropping a row is not.
- **Shrink or question the polish.** Restructuring should cut repetition — the same finding told in prose, in a table and in a matrix can be told once and cited twice. If the spec does not get shorter, say why.
- Section headers only where the reader needs to navigate; a short spec gets paragraphs, not a table of contents.
- No journal narration of the spec's own history ("an earlier draft proposed…") unless a future reader needs the lesson — then one tight paragraph.
- **Confidentiality.** If the spec is in a public repo or one not owned by the client whose material it draws on, apply the same gate as `pr-polish`: no client name, repo, path, internal ticket id, name-carrying identifier, host or endpoint of theirs — unless already public in their own material. A leak inherited from the old text is yours once you re-save it: strip it and report where else it may survive (git history, linked PRs).

## 5. Verify the polish

Before reporting, prove the facts survived:

- **Id census.** Extract every id defined (`D-n`, `R-x`, `Δ-n`, whatever the spec uses) before and after; the sets must be identical and every cited id must still resolve.
- **Number census.** Every number, SHA, PR reference and path in the old text appears in the new text or is listed in the report as a deliberate removal of duplication (with the place it survives).
- **Fresh-context read.** Give a subagent only the polished file(s) and the question "what does this document ask me to decide, and what is its argument in three sentences?". If its answer is wrong or it needs the appendices to answer, the first screen is not done.

## 6. Report

- **What the gate found** — first. Stale citations are news; a reshaped doc is a nicety.
- Before/after size and the one-line structural story ("metadata wall + 28-row table → one-paragraph ask; catalogue moved to appendix A; ids unchanged: 261 defined, 245 cited, 0 dangling").
- What was deliberately *not* changed and why (a mandated section kept in an awkward place, an id scheme left alone).
- Anything the polish surfaced that needs a human: a requirement with no evidence behind it, a decision the first screen cannot state because the doc never actually made it.

## Hard rules

1. **Never change a fact.** Same claim, better shape. A polish that alters a finding, number or requirement has become an unreviewed edit.
2. **Never delete evidence or renumber ids** — move it, cite it, compress the prose around it.
3. **Never polish over a stale spec.** Gate first; report contradictions before restructuring.
4. **Never drop a section the repo mandates** — rename nothing, reorder freely.
5. **One changelog line per file, pointing at the edit** — never a second summary long enough to become another document.
