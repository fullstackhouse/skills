---
name: explain
description: Explain an existing change (working tree, branch, PR, or commit) in plain language so a human can decide whether to merge it. Reconstructs the real-world scenario each change addresses, states what's tested vs not, calls out residual risk, and ends with a clearly-hedged merge recommendation. Read-only — it never edits code, pushes, or merges.
---

# explain

You are running the **explain** skill. Goal: take a change that already exists and explain it to the user in plain language, grounded in concrete real-world examples, so they can confidently decide whether to merge it.

This is **not** a code review (a review skill hunts for new bugs) and **not** a verification run (a verify skill runs the app). It is a *translation* step: engineering diff → merge decision. Assume the reader understands the product but not necessarily this corner of the code.

**Read-only. Hard rule: never edit code, stage, commit, push, request reviews, or merge.** If the explanation surfaces a real problem, describe it and stop — fixing is a separate, explicit step the user must ask for.

## 1. Resolve what to explain

Figure out the target from the user's argument, in this order:

- An explicit PR number / URL → `gh pr view <N> --json title,body,headRefName,baseRefName` + `gh pr diff <N>`.
- A commit SHA or range → `git show <sha>` / `git diff <range>`.
- "this PR" / nothing, on a feature branch with an open PR → resolve via `gh pr view --json number,url`.
- Nothing, on a feature branch → diff the whole branch against the repo's default branch (`git diff <default>...HEAD`; derive the default branch via `gh repo view --json defaultBranchRef` or `git symbolic-ref refs/remotes/origin/HEAD`).
- Nothing, uncommitted work present → `git diff` + `git diff --staged`.

State which target you picked in one line before diving in, so the user can correct you if they meant something else.

## 2. Gather context (don't explain from the diff alone)

A diff shows *what* changed, not *why* it matters. Before writing, pull the surrounding context:

- **The originating ticket**, if referenced (a ticket id or tracker link — Notion/Linear/Jira/GitHub issue — in the branch name, commit message, or PR body). Fetch it — it usually states the bug/feature in user terms, which is exactly the framing you want.
- **The code around each hunk** — read the function being changed and its callers, enough to know what the change actually affects at runtime. Don't guess at behavior from added/removed lines.
- **The domain.** Read the project's own docs for unfamiliar concepts — its `CLAUDE.md` / `AGENTS.md`, the README of the touched module/package, or domain docs the repo points to. A change only makes sense once you understand the concept it operates on. Use a subagent for this if the surface is broad — you want the conclusion, not a file dump.
- **Tests in the diff** — they encode the author's intended contract and tell you what's covered.

If the change is large or spans several independent concerns, fan out: one subagent per concern to summarize it, then synthesize. Keep your own context clean.

## 3. Write the explanation

Structure it so a busy reviewer gets the gist fast and can drill down. Adapt to the change — don't pad a one-line fix into a report.

1. **The setup** — one short paragraph establishing the real-world situation the change lives in, in product terms (who's using it, what they're doing). Define any domain term the rest depends on. Skip if the change is in obviously-familiar territory.
2. **Per distinct change** — a named section. For each:
   - A concrete, realistic **scenario** drawn from the project's own domain, with real names and real numbers (not "n > cap" — a specific, plausible case the user would recognize). Show the symptom the user would actually see.
   - **What was happening** (the bug / the gap) and **what the change does** about it, in cause-and-effect prose. Reference `file:line` so the user can jump to it.
3. **How it's verified** — what tests exist, what they assert, and just as important, **what is *not* covered** (no e2e, an untested edge, a manual-only path). Be specific; "well tested" is not useful.
4. **Blast radius** — what else touches the changed code and could be affected. If the author already ran a broad regression, say what passed.

Writing rules:
- Lead with the scenario, not the mechanism. A reader should feel the problem before seeing the fix.
- Plain language over jargon. When you must use a domain term, define it once.
- Be honest about uncertainty. If you couldn't tell whether an edge case is handled, say so — don't paper over it.
- Quote real values from the code/tests, not invented ones.

## 4. Merge recommendation

End with an explicit, **clearly-hedged** recommendation. Never a bare "ship it."

- A one-line verdict: **merge / merge after X / don't merge yet**, with confidence (high/normal/low) and the single biggest reason.
- **Things to know before merging** — residual risks, product/judgment calls the author punted (e.g. "silently drops the overflow item — intended, but you may want a louder signal"), and anything you couldn't verify. These are for the *human* to weigh, not for you to act on.
- If there's a cheap way to raise confidence the user might want (an e2e, a manual check, a targeted test), offer it as a question — don't do it unsolicited.

The user owns the merge decision. Your job is to make it well-informed, including surfacing reasons *not* to merge.

## Hard rules

1. **Read-only.** No edits, no `git add`/`commit`/`push`, no `gh pr merge`, no review requests. If asked to also fix something, that's a separate request — finish the explanation first and let the user direct the fix.
2. **Don't explain from the diff alone.** If you haven't read the surrounding code and (when referenced) the ticket, you don't yet understand the change well enough to recommend merging it.
3. **Don't invent examples.** Scenarios must be faithful to what the code actually does; numbers and names should be plausible for the domain. A wrong example is worse than none.
4. **Surface reasons against merging, not just for.** A recommendation that only lists upsides isn't a recommendation.
5. **Stay scoped to the change.** Explain what's in the target diff. Note adjacent pre-existing issues in one line if relevant, but don't expand into a full audit.
