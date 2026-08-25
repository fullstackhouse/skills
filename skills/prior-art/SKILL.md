---
name: prior-art
description: Research how other systems actually solve a design problem, with every claim tied to a primary source. Use when invoked as "/prior-art", when the question is "how do other big players/systems do this?", "is X a good pattern?", "what's standard practice for Y?", "has anyone solved this already?", before committing to a non-obvious architectural decision, or when a spec/ADR/PR asserts what the industry does without citing anything. Read-only — it researches and recommends, it never implements.
---

# prior-art

You are running the **prior-art** skill. Someone is about to decide something and wants to know how the rest of the world decided it.

**The premise: this is the highest-confabulation question anyone asks an LLM.** "How does Stripe handle idempotency", "do big systems enable RCSI", "what do most teams do for X" — all of it produces fluent, confident, sourceless prose that is often part-invented, and it is *dangerous* precisely because it then gets pasted into a spec as justification. A wrong answer here doesn't lose an argument; it gets cited.

Your job is not to answer the question. It is to answer it **in a form the reader can check**.

**Hard rule: read-only.** Research and recommend. Don't implement, don't edit the spec, don't post the comment — hand back text the user places.

## 1. Sharpen the question into a decision

Restate what is actually being decided, in one sentence, as a choice between options: *"Should we enable read-committed snapshot isolation on the sync database, or keep the current locking behaviour and fix contention another way?"* Not *"is RCSI good?"* — no design property is good in the abstract, only under constraints.

Then write down **our constraints** — the three or four facts that make an outside answer transferable or not. Scale, write pattern, consistency requirement, team size, uptime budget, whether we control the schema, what we can't change. If you can't name them, ask; a survey without them ranks by fame and will mislead.

## 2. Look inside before you look outside

Cheapest source first, and the one most often skipped: search the consuming repo's `docs/`, specs, ADRs, `CLAUDE.md`/`AGENTS.md`, and the tracker for this exact decision. It is common to find that we already decided it, decided it once and drifted, or hit the failure mode the outside world is about to warn us of. Report that first — it outranks any external finding.

## 3. Choose comparables by constraint, not by fame

Pick systems that **share our constraint**, then say why each qualifies. A niche database with our write pattern is worth more than a household name with a different one.

**The big-player fallacy is the main failure mode of this skill.** "Stripe does X" is only evidence if Stripe's problem is our problem — usually they operate at a scale that justifies costs we can't carry, or under consistency requirements we don't have. Where a comparable is famous but not comparable, say so and use it as a *contrast*, not support.

Favour targets whose behaviour is inspectable: open-source systems (you can read the code), vendors with real reference docs, and teams that publish postmortems. A closed system you can only guess about produces exactly the folklore this skill exists to filter.

## 4. Sweep by source type, not by search box

Fan out subagents — one per source class, because each finds what the others structurally cannot:

- **Primary docs** — the vendor's or project's own documentation, including its "when not to use this" and limitations pages, which is where the honest trade-off usually hides.
- **Source and configuration** — what the code, default config, or migration actually does. Beats every blog post.
- **Field reports** — engineering blogs, postmortems, conference talks, mailing-list/RFC threads, issue trackers. Postmortems are the highest-value genre here: they describe the pattern *failing*, which docs never do.
- **The dissent** — deliberately search for who argues against it and why. A survey that finds only advocates hasn't finished.

Each subagent returns claims with URLs, never prose summaries you'd have to re-verify.

**Queries go to third parties.** Phrase every one generically — no client names, repo names, internal ticket or spec IDs, module or env-var prefixes, hostnames, or paths. "SQL Server snapshot isolation for an ERP sync workload", never the client's system by name. This is the same standing rule as the publishing skills; searching is publishing.

## 5. Grade every claim, and let the weak ones die

Label each finding:

- **Documented** — a specific URL says this. Quote or link it.
- **Inferred** — you read the code/config and concluded it. Say what you read.
- **Folklore** — widely repeated, no source found.

**Folklore may appear in the report but may never be used as justification**, and label it as such rather than dropping it silently — "everyone says X and nobody documents it" is itself a finding about how well-founded the practice is. If a claim you'd have liked to make has no source, say "couldn't verify" and move on. An honest three-source answer beats a confident ten-source one, and *"there is no consensus"* is a legitimate, common, and useful result.

Two findings this format must be able to express, because a fill-in-the-options table can't:

- **They avoid the situation.** The most valuable answer is often that comparable systems arranged things so the question never arises. That reframes the decision instead of settling it.
- **They do it, and regret it.** Adoption is not endorsement. Prefer sources that report the outcome.

## 6. Verdict, against our constraints

Close with the part that makes the research usable:

- **What comparable systems do**, in a few lines — grouped by the *reason* they chose it, not by company.
- **What that implies for us**, given the step-1 constraints — including where our situation genuinely differs and the majority answer therefore doesn't apply.
- **One recommendation**, with the strongest argument against it stated fairly.
- **What remains unknown**, and what would settle it — a benchmark to run, a doc to find, a person to ask. This list is not optional; it's what stops the reader treating the survey as complete.

Size it to drop into the spec section, ADR, ticket comment, or PR reply the user asked for — not a standalone essay. Hand it back; let them place it.

## Hard rules

1. **No unsourced claim about a named system.** Documented, inferred, or explicitly folklore. There is no fourth category, and "I know this" isn't one.
2. **Comparable by constraint, never by fame.** Every included system carries one line on why its problem is our problem.
3. **"No consensus", "they avoid it", and "couldn't verify" are results.** Manufacturing a clean majority out of thin evidence is the failure this skill exists to prevent.
4. **Search queries carry no client-identifying detail.** Generic phrasing, always.
5. **Read-only.** No edits, no posts, no implementation — the user places the output.
6. **End with a verdict and an unknowns list.** A survey without a recommendation hands the work back; a recommendation without unknowns oversells it.
