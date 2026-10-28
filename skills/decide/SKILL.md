---
name: decide
description: Work through the decisions a session has left open — one at a time, each briefed on its own (what's at stake first, then the detail), facts looked up instead of asked, 1-2 alternatives plus the status quo as the last lettered option, one recommendation — then stop and wait for the answer before raising the next. Records each answer where the project keeps decisions before moving on. Use when the user asks "what's still open / what's left to decide", "co do decyzji", "present each one separately and ask me", "walk me through them one by one", or when a long session is ending with deferred choices nobody ever answered. `grill-me` interrogates a plan the user brought; this one empties a queue the work produced.
---

# decide

The failure this skill exists to fix: a long session closes with *"still open: DHCP Guard,
RPC passwords, and that unidentified device"* in its last paragraph — and nothing is ever
decided, because a list of three one-liners is not a question anyone can answer. Each item
needs its own briefing, and the user needs to answer one before hearing the next.

**One decision per turn. Then stop.** Violating this is the whole way this skill fails:
the model briefs all five at once, the user answers two, three vanish.

## 1. Harvest — don't invent

Collect what is *actually* open, from:

- **this session** — everything it deferred, recommended without approval, or ended a message with;
- **the project's own state** — wherever this repo keeps it (task lists, spec "open questions"
  sections, a decision journal, `TODO` / `⚠️` / "to decide" / "do rozstrzygnięcia" markers);
- **the tracker**, if one is configured and has items parked on a decision;
- **changes already made on the user's behalf and never ratified.** An agent that switched
  something on without asking created a decision, it did not remove one. List it as
  *ratify or revert*, with the revert cost.

Then subtract: anything the user already answered, in this session or in the journal —
including implicitly ("I'd just cut it off" is an answer). Re-asking a settled decision
spends the user's trust in the queue.

**No padding.** If two items are the same decision, merge them. If something is a task
rather than a choice, it belongs in the task list, not here. Three real decisions beat
eight that include filler.

## 2. The map first — general before specific

Open with the whole list: numbered, one line each, in the order you'll take them. Order by
**dependency** (a decision that reshapes others goes first), then by **cost of delay**, and
put the cheap-and-reversible ones late. The user needs to see the shape and the length of
the interview before entering it.

More than ~7? Say so, show the map anyway, and offer to cover the top N now and park the rest.

## 3. One decision, one brief, then wait

Per decision — headings written in the language the user is writing in:

```
## <n>/<total> — <the decision, one line, in the user's own terms>

**What's at stake** — one or two sentences. Include what happens if nobody decides.

**Why it's open** — what raised it, plus what's already true, measured, with the
source. Not "probably" — the number, and where it came from.

**Options** — 1-2 alternatives that differ in kind (2-3 when the status quo is not
available, so there are always at least two letters), then **the status quo, always
last**, under its own letter. Each one, the status quo included, with: cost, what it
forecloses (one-way doors named explicitly), how reversible.

➡️ **Recommendation** — exactly one, with the reason in a sentence.

❓ **<the question>** — with the answer shape: "A / B / C", "yes / no / later".
```

Then **end the turn.** No "and the next one is…", no preparing the favored option.

### The status quo gets the last letter

Its own letter makes "leave it" answerable in one keystroke and forces it through the
same cost / forecloses / reversibility test as everything else — its cost is usually the
cost of delay, and it stops being reversible when a deadline passes; say when. Last, so
the brief leads with the moves and "leave it" is always found in the same place.

- **Ratify-or-revert items:** the status quo is the change the agent already made, so the
  last option is *keep it* (ratify), after *revert* with its cost.
- **Leaving it unchanged is impossible**, not merely costly (the API it calls is being
  shut down, the trial ends either way): end the options with
  `Status quo — not available: <why>`, unlettered. A deadline, a broken build, or a client
  waiting on the answer doesn't qualify — that is the status quo's cost of delay; price it.

### Facts are yours, decisions are theirs

Before asking, compute the one cheap number the decision turns on — a count, a cost, a
ratio, a "does it even work here" probe. Dispatch subagents or run the check; never ask the
user for something you can look up. A decision presented without its load-bearing fact is a
guess with a question mark.

If the lookup is slow, say which decision is waiting on it and move to the next one — don't
hold the whole queue.

## 4. Record the answer before raising the next

Write the answer where this project keeps decisions (its decision journal, the spec, the
tracker item) **immediately** — what was chosen, why, and what was rejected. That write,
not the chat message, is what makes the session durable.

**Don't execute mid-interview** unless the answer says to act now. Default: record, keep
going, and offer an execution order at the end. When the user does say "do it", keep the
action scoped to that one decision and come back to the queue.

## 5. Answers that aren't A/B/C

- **"Later" / "park it"** — a real answer. Record it as parked *with the fact or event that
  would reopen it*, and don't re-ask it this run.
- **"I don't know"** — then it wasn't ready. If it hinges on a fact, go get the fact. If it
  hinges on an experiment, name the smallest one that would decide it, and park it on that.
- **"You decide"** — take it: choose your recommendation, record it as *decided by the
  agent, unratified*, and say so in the closing summary.
- **A new decision falls out of an answer** — add it to the map (say that you did) and keep
  the order rule: dependents come after what they depend on.

## 6. Done

When the queue is empty, close with one list: each decision, the answer, where it was
recorded, and what is parked on what. Then — and only then — propose the execution order for
whatever the answers authorized.

**Unattended** (`-p`, cron, no human to answer): do not fake the interview and do not decide
for the user. Produce the map and every brief as a document, each with its recommendation,
and stop. Say plainly that nothing was decided.

## Hard rules

1. **One decision per turn, then stop.** No batching, no previews of the next.
2. **Never ask what you can measure.** The fact-finding is the work; the question is the output.
3. **The status quo is the last lettered option** whenever leaving it is possible, priced
   like the others. "Decide nothing" has a cost and a benefit, and it is frequently the
   right answer.
4. **Record before advancing.** An answer that only exists in the chat is lost.
5. **Don't re-open what's settled**, and don't pad the queue to look thorough.
6. **Recommend.** A survey without a verdict hands the work back to the user, who asked you
   precisely because there are too many open loops.
