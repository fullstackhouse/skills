---
name: explain
description: Explain anything so the user understands it in one read and can decide — a change (working tree, branch, PR, commit), a decision ask ("A30", or an ask's title/body pasted or seeded in the prompt), a spec, a bug, a term ("wdym by X"), a system ("how does search work, before/after"), or "what have we done in this workspace". Always leads with a short plain-words answer (a person, one analogy, one before/after diagram, the options as consequences, one recommendation); the full detail only on request or in a file. Use for "explain", "wdym", "what does X mean", "simply put", "eli5", "tldr", "illustrate", "why do we need this", "should I merge this". Read-only on the code.
---

# explain

Goal: the user understands the target well enough to **decide or move on after one read**. A
second "explain again" means this skill failed.

What worked for this reader: a one-line "simply put"; a named person in a concrete scenario;
one everyday analogy kept all the way through; a before/after picture; options written as
"if you pick X, then…"; one stated recommendation; how others solve it; ~1–2k characters.
What failed: file paths, code identifiers and internal jargon up front; no "why do we need
this"; no picture of the whole; 4–6k-character walls without a diagram.

**Read-only on the code.** Never edit, stage, commit, push, request reviews or merge. The only
files you may write are `EXPLAIN.md` (and an optional HTML figure) in the current workspace.

## 1. Resolve the target

| The user gave | Read it with |
|---|---|
| PR number/URL, branch, commit, range | `gh pr view <N> --json title,body,headRefName,baseRefName` + `gh pr diff <N>`; `git show` / `git diff <range>` |
| nothing, on a feature branch / with uncommitted work | the open PR (`gh pr view`), else `git diff <default>...HEAD`, else `git diff` + `git diff --staged` |
| an ask id ("A30") | the asks tool if present (`ask_list`, scope workspace, status all); else ask for its text — don't guess it |
| ask content in the prompt ("explain this ask: …") | that text is the target; needs no other tool. Follow its links (PR, commit, spec) for facts |
| a spec, doc or ticket | read it, then the code or decision it points at |
| a bug (issue, error, symptom) | the report, logs and the code path that produces it |
| a term ("wdym by quarantine") | where it was said: this session, the ask, the repo (`rg -i`). The local meaning wins; no local use → the general meaning, saying so |
| a system ("how does search work") | trace the flow in code from entry point to storage |
| "what have we done here" | branch log vs base, PRs from this branch, this session |

Say in one line what you took the target to be. Ambiguous → pick the likeliest, say so, and
name the other reading in half a line. Don't stop to ask.

## 2. Gather and verify

- **Context, not the surface.** For a change: the ticket, the code around each hunk and its
  callers, the tests. For anything: the project's own docs for the domain (`AGENTS.md`, module
  READMEs). Broad surface → one subagent per area; keep the conclusions, not file dumps.
- **Every fact checked or marked `(unverified)`.** Never ask what you can look up — count it,
  run it, read it.
- **Never invent examples.** The person and scenario must be faithful to what the code does,
  with names and numbers plausible for the domain. A wrong example is worse than none.
- **How others do it** — for a decision, a design or a concept: 1–3 known products or
  standards, from pages you actually opened. One line in Short, links in Detail.

## 3. Short — always, first

≤ ~250 words plus one diagram, in the language the user wrote in. **No file paths, code
identifiers or internal jargon** — name things by what they do for a person. Define an
unavoidable term once, in passing.

1. **Simply put** — one sentence: the effect on a person.
2. **Picture it** — a named person doing something concrete ("Ben, who just changed teams,
   searches *budget*…"), and **one** everyday analogy (a photocopy, a badge, two keys). Keep that
   analogy to the end; never mix a second one in.
3. **Why we need it** — what goes wrong, or what it costs, if nothing changes.
4. **One diagram** — Mermaid `flowchart TD`, ≤ 12 nodes, quoted plain labels, every arrow
   labelled with what passes along it; a change or decision shows `today` and `after` as two
   subgraphs. A screen → an ASCII mockup instead. A term → the whole picture with the term in
   its place. If drawing it shows a simpler design than the ones on the table, say so — that
   is a good outcome, not a detour.
5. **By target:**
   - **Decision** — options as consequences: "**A** — if you pick it, Ben…; costs…; closes
     off…; undo by…". Alternatives that differ in kind, plus any design alternative the
     picture revealed; **status quo always last**, priced like the rest (its cost is usually
     delay). Then ➡️ **one** recommendation, its confidence (high/normal/low), and what
     would change your mind.
   - **Change** — what it does for the person; what's tested and what's not, specifically;
     the residual risk; ➡️ **merge / merge after X / don't merge yet**, confidence, and the one
     biggest reason. Already merged → what is different now and what to watch.
   - **Term, system, bug, history** — the answer, where it shows up here, one "watch out".
6. One closing line offering Detail — only when there is more worth reading.

**Depth knobs** from the user's words: *tldr* → items 1 and the recommendation, 2–4 lines;
*eli5* → analogy-led, zero identifiers; *illustrate* / *show me* → diagram or mockup first;
*in detail* / *deep dive* → Short, then Detail.

Example (decision, Short):

> **Simply put:** search still lists files people lost access to; the fix makes search check
> the same access list the folders do.
> **Picture it:** Ben left the finance team on Monday. His folders no longer show its files, but
> searching *budget* still lists them — like changing the front-door lock while his old badge
> still opens the side entrance.
> *(today/after diagram)*
> **A** — search checks the live access list on every query: always right, a little slower.
> **B** — rebuild the search index on every access change: fast, but wrong for minutes after each change.
> **C (status quo)** — people who changed teams keep finding files they can no longer open.
> ➡️ **A**, normal confidence; I'd switch to B if searches got noticeably slower.

## 4. Detail — on request, or in a file

Order: the whole-system picture (zoom levels from [pr-description](../pr-polish/references/pr-description.md)
§ How the pieces fit, only the levels that matter) → how others do it, with links → evidence
(what you read or ran, with the numbers) → risks and what nobody verified → file references
last.

Longer than ~600 words → write it to `EXPLAIN.md` in the current workspace and keep the chat to
the Short plus the path. Mermaid renders in Paseo chat, ask bodies and `.md` previews; a UI
mockup Mermaid can't draw may go in a small self-contained `.html` beside it.

## 5. When the target is an ask

After the Short, offer **a rewritten ask body** — the Short as paste-ready markdown: the
question as the title, options lettered with the status quo last, the recommendation marked —
so the ask itself gets clearer. Don't edit an ask you didn't create; hand over the text.

## Hard rules

1. **Short first, every time.** Nothing in it needs a code editor to understand.
2. **Read-only on the code.** Fixing what the explanation surfaces is a separate request.
3. **Verified or marked `(unverified)`.** No invented people, numbers or behaviour.
4. **One recommendation**, with the reasons against it and the status quo priced — a survey
   hands the work back.
5. **One analogy, one diagram** in the Short. More of either is noise.
6. **Stay scoped.** Adjacent problems get one line, not an audit.
