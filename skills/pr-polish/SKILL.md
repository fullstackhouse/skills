---
name: pr-polish
description: Rewrite a PR's title and description so they are accurate to the branch as it stands and read top-down, general to specific — problem first, then the solution, then technical details and verification. Use when a PR's story has drifted from its diff (rebases, review fixes, scope changes, merged dependencies) or when the body buries the point in technical detail. Args: a PR number/URL, or nothing to use the current branch's PR.
---

# pr-polish

You are running the **pr-polish** skill. Goal: make the PR's title and description something a reviewer can absorb top-down — each section understandable from the ones above it — and trustworthy: no claim in the body that the current diff, commits, and linked PRs don't back.

This skill touches **only PR metadata**. Hard rules: never edit code, commit, push, or merge; never rewrite the title/description of a PR in a repo you don't own (external open-source you're contributing to) — ask first, the maintainer may control them.

## 1. Resolve the PR

- Explicit number/URL → use it.
- Nothing given → the current branch's open PR (`gh pr view --json number,url`). No PR → stop and say so.

## 2. Gather ground truth

- `gh pr view <N> --json title,body,commits,files,reviews,baseRefName` and `gh pr diff <N>` — the diff is the source of truth, not the existing body.
- The full discussion: review threads (`gh api repos/<slug>/pulls/<N>/comments --paginate`) *and* conversation comments (`gh api repos/<slug>/issues/<N>/comments --paginate`) — review-driven changes and decisions recorded in comments are part of the story.
- CI results (`gh pr checks <N>`) — the Verification section may only claim what CI runs, commit messages, or these checks attest to.
- **Every PR/issue the body references**: check its *current* state. "Waits on #252" is wrong the day #252 merges; a "still to come" item may already be an open stacked PR.
- Repo conventions: `CLAUDE.md` / `AGENTS.md` sections on PR bodies and task linking (e.g. bare autolinked task IDs, `Closes`/`Part of` semantics). Follow them over this skill's defaults.

## 3. Verify before you write

The body must describe the PR **as it is now**, not as it was when opened:

- Update or drop stale dependency notes and delivered "still to come" items; name stacked PRs.
- Keep only verification claims the commits or CI actually attest to. Never invent test counts, coverage, or benchmarks — if the old body claims something you can't confirm, keep it only if a commit message or CI run backs it.
- Keep credit for review catches ("caught in review by @x") — one line, where it changed the design.

## 4. Structure — general to specific

**Title**: Conventional Commits style, plain-language *outcome* (what a user/operator gets, not which function changed), task ID per repo convention.

**Body**, in this order — a reader should be able to stop after any section with a correct, just less detailed, understanding:

1. **Context line** — task reference (`Closes`/`Part of` per repo convention), stacking and dependency notes.
2. **The problem** — the observable symptoms and their impact, with numbers where known. No code identifiers yet; a PM should understand this section.
3. **The fix** — root cause in a sentence, then what the PR does, as a short paragraph or a few bullets. A reviewer in a hurry stops here.
4. **Details** — per-fix technical narration: identifiers, why the chosen source/approach beats the alternatives, counter-intuitive facts worth preserving.
5. **Verification** — checks run, tests added mapped to the bug each one catches, mutation checks; then what is *not* covered and why.
6. **Follow-ups** — remaining scope, with live links.

Writing rules:

- No journal narration of the branch's own history ("an earlier revision…", "after review we…") *except* where it changed the design and a future reader needs the lesson — then one tight paragraph.
- No strikethroughs or "edit:" patches — rewrite the paragraph; the old text lives in the edit history.
- Section headers only when the body is long enough to need them; a small PR gets three short paragraphs, not six headers.

## 5. Apply and report

Write the body to a temp file, then `gh pr edit <N> --title "..." --body-file <file>`. Report: old → new title, and what *materially* changed — especially corrected stale claims (readers of the old body may be carrying them).
