---
name: zoom-out
description: Step back from the current implementation path and re-derive the approach from the original goal — fresh eyes, sunk work explicitly ignorable. Use when invoked as "/zoom-out", when the user signals tunnel vision ("did you consider anything else?", "do we really need all this?", "back off", "look at this fresh"), when many consecutive steps have optimized within one approach that was never compared against alternatives, or before an expensive/irreversible step (force-push, mass commit, schema change, publishing) of a plan chosen early and never revisited. Read-only until the user picks a direction.
---

# zoom-out

You are running the **zoom-out** skill. The premise: the session (yours or another agent's) has been optimizing *within* a frame — each step locally competent, but the frame itself was inherited, not chosen. Your job is to step outside it, re-derive the approach from the actual goal, and present genuinely different options.

**Hard rule: analysis only.** Do not implement, commit, revert, or push anything until the user picks a direction. The whole point is that the previous direction was auto-piloted; don't auto-pilot the next one.

## 1. Restate the goal — from the request, not the implementation

Write one sentence stating what the user actually needs, sourced from their *original* request, deliberately avoiding the current implementation's vocabulary. "Provenance must survive losing the machine" — not "commit the corpus to the repo".

If a user instruction mid-way shaped the current path ("put it in the repo", "use library X"), treat it as a **goal statement, not a design**: the user was solving the problem with the information they had at that moment. If a smaller or different design satisfies the underlying need, you owe them that option — proposing it is not disobedience.

## 2. Declare sunk work ignorable

Inventory what has been done so far (branch, commits, files, migrations) in a few lines — then explicitly mark it as **candidate output, not a constraint**. The question is "what would we build if we started from the goal right now?", not "how do we finish what we started?". Agents anchor hard on their own prior work; naming the anchor is how you release it.

## 3. Measure the decision space

Before comparing options, compute at least one **cheap, concrete quantification** that the decision actually turns on: a ratio (items used / items stored), a size, a count, a frequency, a cost. Tunnel vision survives on unexamined assumptions; a single real number often makes the answer obvious ("22,412 harvested, 270 cited" ends the debate about keeping the pool). If you can't think of a number that would change the decision, say so — but try first.

## 4. Fresh-eyes second opinion

Spawn one subagent with a **neutral problem statement only**: the goal from step 1, the relevant hard constraints (confidentiality, budget, deadlines), and access to the repo — but **no mention of the current approach, the session history, or the sunk work**. Ask it to propose how it would solve the problem and what it would explicitly *not* do.

This is the core mechanic: you cannot un-see your own approach, but a fresh context genuinely can. If the subagent proposes something materially smaller or structurally different from the current path, that divergence *is* the finding — report it as such, don't rationalize it away.

Write the subagent prompt before sending and check it for leakage: any phrase that hints at the current design ("the sidecar", "the committed corpus", "the migration") contaminates the second opinion.

## 5. Present options and stop

Lay out **2–3 materially different approaches** — different in kind, not in parameter. Always include:

- the **current path** (described fairly — it may still win),
- a **"much less"** option (the smallest thing that satisfies the goal), and
- where honest, **"do nothing"** (the goal is already met, or the problem isn't worth its fix).

For each: what it costs, what it risks, what it forecloses (one-way doors get named explicitly). Then give **one recommendation** with your reasoning — a survey without a verdict pushes the decision work back onto the user.

End there. If the user picks a direction that discards work, the discarding (reverts, force-pushes, closing PRs) is part of the *new* task and follows their explicit choice — including whether history needs rewriting or a plain revert suffices.

## Hard rules

1. **No implementation until the user chooses.** Not even "harmless" preparation of the favored option.
2. **The fresh-eyes subagent gets the goal, never the approach.** A leaked hint invalidates the second opinion — rewrite the prompt rather than caveat the result.
3. **Don't defend the incumbent.** You (or a sibling session) built the current path; arguing for it beyond its fair description is the anchoring this skill exists to break.
4. **Options must differ in kind.** Three variants of the same design is a parameter sweep, not a zoom-out.
5. **Quantify before you rank.** At least one measured number in the comparison, or an explicit statement that no measurement would change the ranking.
