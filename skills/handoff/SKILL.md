---
name: handoff
description: Compact the current conversation into a handoff document a fresh agent session can pick up from. Manual-invoke only.
argument-hint: "What will the next session be used for?"
disable-model-invocation: true
---

# handoff

Adapted from [mattpocock/skills](https://github.com/mattpocock/skills), MIT © Matt Pocock.

Write a handoff document summarizing this conversation so a fresh agent can continue the work. (Not to be confused with `desktop-handoff` / `claude-desktop-handoff`, which hand one GUI step to another session and take the result back.)

**Where:** `.context/handoffs/{YYYY-MM-DD}-{kebab-slug}.md` when the repo has a `.context/` dir (Conductor — other agents in the workspace can read it); otherwise the OS temp dir. Never inside tracked files; never `git add` it.

**What:**
- The goal, the current state, and the next concrete step.
- Decisions made and why, plus dead ends already ruled out — so the next agent doesn't re-litigate or retry them.
- Open questions and anything still unverified.
- **Suggested skills** — which skills the next agent should invoke (e.g. `/kickoff`, `/deliver`, `/bug-hunt`), and with what arguments.

**Rules:**
- Don't duplicate what an artifact already holds (spec, plan, brief, ticket, PR, commits, diff) — reference it by path or URL.
- Redact secrets (API keys, tokens, passwords) and personal data.
- If the user passed an argument, treat it as what the next session will focus on and tailor the doc to it.

End by printing the file path and a one-line prompt the user can paste into the new session, e.g. `Read <path> and continue.`
