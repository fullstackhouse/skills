---
name: explain
description: Explain anything so the user understands it in one read and can decide — a change (working tree, branch, PR, commit), a decision ask ("A30", or an ask's title/body pasted or seeded in the prompt), a spec, a bug, a term ("wdym by X"), a system ("how does search work, before/after"), or "what have we done in this workspace". Always leads with a short plain-words answer (who it touches, a person, one analogy, one diagram, the options as consequences, one recommendation); the full detail only on request or in a file. Use for "explain", "wdym", "what does X mean", "simply put", "eli5", "tldr", "illustrate", "why do we need this", "should I merge this". Read-only on the code.
---

# explain

Goal: the user understands the target well enough to **decide or move on after one read**. A
second "explain again" means this skill failed.

What worked for this reader: a one-line "simply put"; a named person in a concrete scenario;
one everyday analogy kept all the way through; a before/after picture; options written as
"if you pick X, then…"; one stated recommendation; how others solve it; ~1–2k characters.
What failed: file paths, code identifiers and internal jargon up front; no "why do we need
this"; no picture of the whole; 4–6k-character walls without a diagram; options that took for
granted the feature behind them is worth keeping.

**Read-only on the code.** Never edit, stage, commit, push, request reviews or merge. The only
files you may write are `EXPLAIN.md` (and an optional HTML figure) in your working directory —
not in the target's repo when that is elsewhere. Never stage or commit them.

## 1. Resolve the target

| The user gave | Read it with |
|---|---|
| PR number/URL, branch, commit, range | `gh pr view <N> --json title,body,state,mergedAt,headRefName,baseRefName` + `gh pr diff <N>`; `git show` / `git diff <range>` |
| nothing, on a feature branch / with uncommitted work | the open PR (`gh pr view`), else `git diff <default>...HEAD`, else `git diff` + `git diff --staged` |
| an ask id ("A30") | the asks or tracker tool if present (Paseo: `ask_list`, status all); else ask for its text — don't guess it |
| ask content in the prompt ("explain this ask: …") | that text is the target; needs no other tool. Follow its links (PR, commit, spec) for facts |
| a spec, doc or ticket | read it, then the code or decision it points at |
| a bug (issue, error, symptom) | the report, logs and the code path that produces it |
| a term ("wdym by quarantine") | where it was said: this session, the ask, the repo (`rg -i`). Several local meanings → the one nearest the user's words. None → the general meaning, saying so |
| a system ("how does search work") | trace the flow in code from entry point to storage |
| "what have we done here" | branch log vs base, PRs from this branch, this session |

Open with one line, before the Short, naming what you took the target to be. Ambiguous → pick
the likeliest and give the runner-up one line at the end ("If you saw it on X instead: …").
Don't stop to ask.

## 2. Gather and verify

- **Context, not the surface.** For a change: the ticket, the code around each hunk and its
  callers, the tests. For anything: the project's own docs for the domain (`AGENTS.md`, module
  READMEs). Broad surface → one subagent per area; keep the conclusions, not file dumps.
- **Who uses it.** For a decision or a change, find out who depends on the feature at stake,
  today and soon: callers, config, enabled flags, data, the roadmap. A decision about a feature
  nobody uses is a different decision. If you can't find out, that is the first thing the
  Short says.
- **Every fact checked, attributed or marked.** Checked: you read or ran it. Attributed: "the
  PR says tests failed before the fix". Otherwise `(unverified)`. Never ask what you can look
  up — count it, run it, read it.
- **The target can be wrong.** When the ask, PR or spec misstates a fact, say so in one line
  ("Correction: the copy is deleted in PR 11, not PR 10"). Never fix it silently.
- **Names may be invented, behaviour may not.** The person is made up; what happens to them,
  and the numbers, must match the code and the data.
- **How others do it** — when a design choice is in play (a decision, a design, a term, a
  change that picks one approach over another): 1–3 known products or standards, from pages
  you opened. Two pages per product at most; nothing found → say "no prior art found". One line
  in the Short, links in Detail.

## 3. Short — always, first

≤ ~250 words (~350 for a decision) plus one diagram, in the language the user wrote in. **No file paths, code
identifiers or internal jargon** — name things by what they do for a person. Define an
unavoidable term once, in passing. More risks or facts than fit → keep the ones a person
would notice; the rest go to Detail.

1. **Simply put** — one sentence: the effect on a person.
2. **Who it touches** — who uses this today and soon, with the source; or "unknown — tell me
   who uses it" when you couldn't find out. Skip for a term.
3. **Picture it** — a named person doing something concrete ("Ben, who just changed teams,
   searches *budget*…"), and **one** everyday analogy (a photocopy, a badge, two keys). If the
   target already uses one, reuse it. Keep it to the end; never mix in a second one.
4. **Why we need it** — what goes wrong, or what it costs, if nothing changes.
5. **One diagram** — Mermaid `flowchart TD`, ≤ 12 nodes, quoted plain labels, every arrow
   labelled with what passes along it. Where Mermaid doesn't render (a plain terminal), draw
   the same as ASCII. A change or decision: two subgraphs, `today` and
   `after` (`before` and `now` once merged). A term or system: the whole picture with the
   subject in its place. A screen: an ASCII mockup instead. If drawing it shows a simpler
   design than the ones on the table, say so — that is a good outcome, not a detour.
6. **By target:**
   - **Decision** — options as consequences: "**A** — if you pick it, Ben…; costs…; lets us
     delete…; closes off…; undo by…". Name what each option removes as well as what it
     degrades. Alternatives that differ in kind, always including **dropping or freezing the
     feature that forces the question**, plus any design the picture revealed; **status quo
     last**, priced like the rest (its cost is usually delay). When an ask's buttons are fixed,
     keep its options in order and add the others as "Not on the buttons: …". Then ➡️ **one**
     recommendation, confidence (high/normal/low), and what would change your mind.
   - **Change, unmerged** — what it does for the person; what's tested and what's not, by
     behaviour in plain words ("nothing tests a buyer with no store rules"), test names to Detail; the residual risk; ➡️ **merge / merge after X / don't merge yet**,
     confidence, and the one biggest reason.
   - **Change, merged** — what is different now; tested and not; ➡️ **keep / follow up with X /
     revert**, confidence, what would make you revisit.
   - **Term, system, bug, history** — the answer, where it shows up here (or how others use
     it), one "watch out".
7. One closing line offering Detail — only when there is more worth reading.

**Depth knobs** from the user's words: *tldr* → items 1 and the recommendation, 2–4 lines;
*eli5* → analogy-led, zero identifiers; *illustrate* / *show me* → diagram or mockup first;
*in detail* / *deep dive* → Short, then Detail.

Example (decision, Short):

> **Simply put:** search still lists files people lost access to; the fix makes search check
> the same access list the folders do.
> **Who it touches:** everyone who changes teams, ~30 people a month (access log).
> **Picture it:** Ben left the finance team on Monday. His folders no longer show its files, but
> searching *budget* still lists them — like changing the front-door lock while his old badge
> still opens the side entrance. Nothing is leaked yet, but one search can show a salary file.
> *(today/after diagram)*
> **A** — search checks the live access list on every query: always right, a little slower;
> lets us delete the nightly permission re-sync.
> **B** — rebuild the search index on every access change: fast, wrong for minutes after each change.
> **C** — drop search inside team folders: nothing to keep in step; people browse instead.
> **D (status quo)** — people who changed teams keep finding files they can no longer open.
> ➡️ **A**, normal confidence; I'd switch to B if searches got noticeably slower.

## 4. Detail — on request, or in a file

Order: the whole-system picture → how others do it, with links → evidence (what you read or
ran, with the numbers) → risks and what nobody verified → file references last.

The whole-system picture zooms in only as far as it needs to, one diagram per level (same
rules as the Short's): **system** — the people and outside systems around ours; **modules** —
the deployable parts and who calls whom; **inside a module** — its main components. Skip a
level that would repeat the one above.

Longer than ~600 words → write it to `EXPLAIN.md` and keep the chat to the Short plus the path.
Mermaid renders in Paseo chat, ask bodies and `.md` previews; a UI mockup Mermaid can't draw
may go in a small self-contained `.html` beside it.

## 5. When the target is an ask

After the Short, offer **a rewritten ask body** — the Short as paste-ready markdown, with any
corrections applied: the question as the title, options lettered with the status quo last,
the recommendation marked, and the Short's diagram reused rather than redrawn. It doesn't count
toward the Short's word budget. It is chat output: don't edit an ask you didn't create.

## Hard rules

1. **Short first, every time.** Nothing in it needs a code editor to understand.
2. **Read-only on the code.** Fixing what the explanation surfaces is a separate request.
3. **Checked, attributed or `(unverified)`.** Invented names are fine; invented behaviour and
   numbers are not. Errors in the target are called out, not quietly fixed.
4. **One recommendation**, with the reasons against it, the status quo priced, and "drop the
   feature" on the table — a survey hands the work back.
5. **One analogy, one diagram** in the Short. More of either is noise.
6. **Stay scoped.** Adjacent problems get one line, not an audit.
