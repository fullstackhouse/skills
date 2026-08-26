---
name: prior-art
description: Research how other systems actually solve a design problem, with every load-bearing claim opened and checked by you. Use when invoked as "/prior-art", when the question is "how do other big players/systems do this?", "is X a good pattern?", "what's standard practice for Y?", "has anyone solved this already?", before committing to a non-obvious architectural decision, or when a spec/ADR/PR asserts what the industry does without citing anything. Read-only — it researches and recommends, it never implements.
---

# prior-art

Someone is about to decide something and wants to know how the rest of the world decided it.

**This is the highest-confabulation question anyone asks an LLM.** It returns fluent, sourceless prose about what Stripe or Postgres or "most teams" do, and it is dangerous precisely because it doesn't lose an argument — it gets *cited*. Your job is not to answer the question. It is to answer it in a form the reader can check.

**Read-only.** Research and recommend; don't implement, don't edit the spec, don't post the comment.

## 1. Sharpen the question into a decision

Restate what is being decided as a choice between named options: *"Grow our existing job record into a durable lease, or adopt an off-the-shelf durable-execution engine?"* Not *"is X good?"* — no design property is good in the abstract.

A vague question cannot be researched, only answered plausibly. If you can't state the options, that *is* the first deliverable: sharpen it, say what you assumed, and continue.

## 2. Look inside before you look outside

Search the consuming repo — `docs/`, specs, ADRs, `CLAUDE.md`/`AGENTS.md` — and the tracker for this exact decision.

**This step outranks everything below it.** We have often already decided this, decided it and drifted, or already hit the failure the outside world is about to warn us of. An internal incident beats an external blog post: it happened to us, under our constraints, with consequences someone remembers. Report internal findings first and separately.

## 3. Name the one axis that decides transferability

List our constraints, then do the work that matters: identify **the single axis along which comparable systems' answers diverge**. "Is this system the book of record?" "Does an external system own the transitions?" "Do they control the whole stack?"

That axis, not a constraint list, is what sorts the evidence. Every included system gets one line: where it sits on the axis, and why that makes it comparable to us or a contrast.

**Fame is not the axis.** "Stripe does X" is evidence only if Stripe's problem is our problem. Where a famous system sits on the far side of the axis, keep it as an explicit **contrast**, never as support.

**Engineering maturity is a separate weight — and it changes what you read the system for, not whether you read it.** A team with a strong engineering record chose deliberately, so their choice is evidence about the design. A legacy or poorly-built system's choice is evidence of nothing — but its *failures* are, and they are often the best evidence available anywhere, because a mature system's bugs in this area were found and quietly fixed years ago while a legacy one's are public, reproducible, and frequently still open. **Read mature systems for what they chose; read legacy systems for what broke.** Neither is disqualified — they answer different questions, and a survey drawing only on the admirable ones has no failure data in it at all.

## 4. Sweep by source class — with a budget

Four classes, because each finds what the others structurally cannot: **primary docs** (including the "when not to use this" page, where the honest trade-off hides), **source and config** (what the code actually does — beats every blog post), **field reports** (postmortems, issue trackers, RFC threads — the highest-value genre, because they describe the pattern *failing*), and **the dissent** (who argues against it, and why).

Delegating these to parallel subagents is fine, but the fan-out is this skill's most reliable way to fail. Bind it:

- **Search budget is finite and shared.** Give each sweep a hard query cap and **reserve at least a third of the total for step 5**. An unbudgeted fan-out spends everything on breadth and leaves nothing for checking.
- **Run the dissent sweep first.** It's the one a hard rule protects and the first casualty of an exhausted budget.
- **Sanitize the sweep prompts explicitly.** Subagents inherit the consuming repo's `CLAUDE.md`/`AGENTS.md` and mine it for specifics; telling them to "stay generic" does not work, because they infer the client's products and vendors from that inherited context and search for them *by name*. Give each sweep the sanitized question text plus an explicit list of terms it may not put in a query.
- **Where two sweeps disagree** about the same system, neither claim is usable until you check it yourself.
- **A sweep that returns nothing has three meanings** — nothing exists, the tool failed, or the system doesn't publish. Record which. "No dissent found" from a sweep whose queries were all refused is not a finding, it's a missing measurement; label it as one and re-run before anyone cites the silence. For a closed enterprise system, all four sweeps coming back empty is the base rate and not evidence of anything — see step 6.

If search is unavailable, say so and fall back to fetching known URLs directly — but note that field reports and dissent are exactly the classes you cannot reach by guessing URLs, so the survey is incomplete in its most important dimension.

## 5. Verify before you cite

**Open, yourself, every source the verdict rests on.** Not a sample of them — all of them.

This is the step that separates this skill from asking the question directly, and it is the one under budget pressure to disappear. Fabricated attributions arrive confidently formatted and correctly labelled: a page cited for a claim it never makes, one platform's source code credited to another, a real quote pinned to the wrong URL. Nothing about the shape of a delegated claim reveals this. Only opening it does.

Budget for this before you spend on breadth. **A verified survey of three systems beats an unverified one of ten.**

**What a failed verification means depends on the system.** In an open codebase, not finding the feature is strong evidence it isn't there. For a vendor that publishes nothing, failing to open a page tells you about their documentation, not about their design — that claim belongs in step 6 as `consensus`, not reported as an absence you never measured.

Two mechanics make the check real rather than asserted:

- **Quote, don't cite.** Every documented claim in the verdict carries a verbatim phrase from the page, not just a URL. You cannot quote a page that doesn't say it, and the reader can check it in one click. A citation without a quote is an assertion that you read something.
- **Date the state-bearing claims.** "Still open", "deprecated", "the default is", "no longer supported" — these were true once and rot silently. Record what you saw and when, or the claim's failure mode is being *stale* rather than wrong, which is far harder for a reader to spot.

## 6. Grade on two axes

Every claim carries both:

- **Strength** — `documented` (a specific page says it, quoted), `inferred` (you read the code/config and concluded it; say what you read), `consensus` (no source is reachable, but the people who run the system daily would all recognise the claim — see below), or `folklore` (widely repeated, and nobody is positioned to correct it).
- **Provenance of the check** — `opened` (you fetched it), `secondhand` (a sweep reported it; nobody opened it), or `recall` (you knew it; no page was involved at any point).

The second axis exists because the first is a self-report. A well-formatted wrong attribution passes the strength label cleanly. **`documented` + `secondhand` is a claim about a subagent's formatting, not about the world** — it may appear in the evidence, never in the verdict.

### Closed systems, and the claims nobody can source

Whole classes of comparable system — SAP, Palantir, Oracle, Monitor, most vertical ERPs — ship no source, and their documentation is marketing, paywalled, or renders only under JS. All four sweeps come back empty there, every time. **Treating that as "unverified" deletes the most expensive and often most comparable systems from every survey**, and leaves a verdict drawn entirely from whatever happens to be on GitHub. That is a bias, not neutrality, and it points the same way each time: toward small open projects and away from the incumbents the reader is actually choosing between.

`consensus` is how those systems get back in. The test is not whether you can cite it — you can't, that's the premise — but whether the claim is **error-corrected by use**: would someone who works with the system every day object to this exact sentence? "SAP PS separates the WBS from the activity network" survives that test, because thousands of consultants would correct it if it were wrong. "SAP added that in 4.6C" does not — nobody's daily work depends on that being right in your head.

So the line runs through grain, not through confidence:

- **Admissible** — the architectural shape, the vocabulary the system uses for it, the trade-off it is famous for having made.
- **Never** — field names, counts, defaults, versions, dates, prices. And **never a quote**: a remembered quote is a fabricated quote, and no hedge repairs it.
- **Never the reason.** Recall gives you *what* a closed system does; the *why* is rarely published, and a reconstructed rationale is the most fluent thing an LLM produces. Step 7 groups systems by reason — a `consensus` system enters that grouping on its observable shape or stays ungrouped.

Two containments keep this from swallowing the skill:

- **Write it down before the sweep, not after.** Declared first, a recall claim is a prediction: confirmed, it upgrades to `documented`; contradicted, that's a finding worth more than either; unreachable, it stays `consensus` and the reader knows the search was tried. Declared after, it is unfalsifiable and arrives in exactly the shape the verdict wanted — which is what confabulation looks like from the inside.
- **Never load-bearing alone.** `consensus` may corroborate, may contrast, may occupy the quadrant nothing else reaches. If deleting every `consensus` line would change the recommendation, the survey isn't finished — say that instead of leaning on them.

Label them in the verdict sentence itself, not in a footnote. The failure this skill exists to prevent is laundering, not uncertainty: a reader who can see the grade can discount it.

**Do not read the strength labels as a confidence ranking.** `inferred` from reading the source is in practice the *most* reliable grade, because reading code is expensive enough that nobody claims it falsely, and because source is what runs while docs drift. `documented` is the least reliable, because citing a page is cheap and confident-looking. Hedges are similarly trustworthy — a hedge costs the writer something, so it is rarely false. Ranking by grade rather than by what you checked inverts the real reliability order. `consensus` about a system's shape is routinely sounder than `documented` about one of its fields, for the same reason: the shape is the part thousands of people would have noticed was wrong.

Folklore may be reported and may never justify a decision — "everyone says it and nobody documents it" is itself a finding about how well-founded the practice is. Record what you dropped and why; dropped claims are among the most useful output.

Three results this format must be able to express, because an options table can't:

- **They avoid the situation.** Often the most valuable answer: comparable systems arranged things so the question never arises. That reframes the decision instead of settling it.
- **They do it, and regret it.** Adoption is not endorsement. Prefer sources that report the outcome.
- **There is no consensus** — legitimate and common. Equally: where a real consensus exists, say so plainly. This licence is not an instruction to hedge.

## 7. Two artifacts, not one

**The verdict** — about a page, the thing that gets pasted:

- what comparable systems do, grouped by the *reason* they chose it, not by company;
- what that implies for us on the step-3 axis — including, when it applies, that **the majority answer doesn't transfer**, which is a headline and not a footnote;
- one recommendation, with the strongest argument against it stated fairly;
- what remains unknown and what would settle each — a measurement, a doc, a person to ask.

**The evidence** — a separate file, as long as it needs to be: graded findings, what was dropped, the sweep record, and every query issued verbatim.

Keep them separate. One document that is both a verdict and an evidence file always becomes the evidence file, and nobody pastes a 4,000-word essay into a spec.

## Hard rules

1. **Nothing enters the verdict on a subagent's word.** Every `documented` claim is `opened` by you and carries a quote; `secondhand` stays in the evidence file. `consensus` may appear, graded in the sentence and never as the only support.
2. **Comparable by axis, never by fame.** Each system carries one line on where it sits and why that transfers.
3. **Budget the fan-out; dissent goes first.** Reserve a third of the search budget for step 5.
4. **Search queries carry no client-identifying detail** — and the leak comes from *inherited repo context*, not from what you type, so sanitize the sweep prompts explicitly.
5. **Distinguish "nothing found" from "couldn't look".** A tool failure reported as an absence is the worst output this skill can produce.
6. **"No consensus", "they avoid it", "couldn't verify" are results.** Manufacturing a majority out of thin evidence is the failure this skill exists to prevent.
7. **Recall gives you shape — never specifics, never a quote, never a reason** — and only if you wrote it down before the sweep ran.
8. **Read-only, and two artifacts.** The user places the output.
