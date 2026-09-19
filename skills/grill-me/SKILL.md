---
name: grill-me
description: Grill the user relentlessly about a plan, decision, or design they already have, round by round, until every branch of it is settled. Use when the user says "grill me", "grill this plan", "poke holes in this", "stress-test my thinking", or wants a plan interrogated before building it. For an idea not yet worth committing to ("should we build this?"), use `brainstorm` instead — it questions *whether*; this questions *how*.
---

# grill-me

Adapted from [mattpocock/skills](https://github.com/mattpocock/skills) (`grill-me` + `grilling`), MIT © Matt Pocock.

Interview the user until you share one understanding of the plan. Map it as a **design tree**: every decision branches into the decisions that hang off it.

## Rounds

The **frontier** is every decision whose prerequisites are already settled — the questions you can ask *now* without guessing at answers you haven't heard. Ask the whole frontier in one round, numbered, each with your recommended answer, then wait:

```
❓ **Q1** - **<question title>**: <question body, may be several paragraphs, incl. options>

➡️ <your recommended answer>

---

❓ **Q2** - **<question title>**: <question body>

➡️ <your recommended answer>
```

Each answer reshapes the tree: recompute the frontier and ask the next round. A question that depends on another question still open this round belongs to a *later* round.

## Facts vs decisions

- **Facts are your job.** When a question needs a fact from the environment (code, repo, tracker, tools), dispatch a subagent to find it — never ask the user for something you can look up. Don't block on it: only the questions downstream of a running lookup wait; ask the rest of the frontier now.
- **Decisions are the user's.** Put each one to them and wait.

## Done

The session is done when the frontier is empty: every branch visited, nothing silently assumed. Do not act on the plan until the user confirms you've reached a shared understanding. Then summarize the settled decisions in one list; if the user wants to build it, offer to write them as a brief to `.context/briefs/{YYYY-MM-DD}-{kebab-slug}.md` (when `.context/` exists) so `/kickoff` can pick it up.
