---
name: pr-polish
description: Rewrite a PR's title and description so they are accurate to the branch as it stands and read top-down, general to specific — the problem, the fix and the impact first, then technical details and testing. Use when a PR's story has drifted from its diff (rebases, review fixes, scope changes, merged dependencies) or when the body buries the point in technical detail. Args: a PR number/URL, or nothing to use the current branch's PR.
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
- CI results (`gh pr checks <N>`) — the Testing section may only claim what CI runs, commit messages, or these checks attest to.
- **Every PR/issue the body references**: check its *current* state. "Waits on #252" is wrong the day #252 merges; a "still to come" item may already be an open stacked PR.
- Repo conventions: `AGENTS.md` / `CLAUDE.md` sections on PR bodies and task linking (e.g. bare autolinked task IDs, `Closes`/`Part of` semantics). Follow them over this skill's defaults.

## 3. Verify before you write

The body must describe the PR **as it is now**, not as it was when opened:

- Update or drop stale dependency notes and delivered "still to come" items; name stacked PRs.
- Keep only verification claims the commits or CI actually attest to. Never invent test counts, coverage, or benchmarks — if the old body claims something you can't confirm, keep it only if a commit message or CI run backs it.
- Keep credit for review catches ("caught in review by @x") — one line, where it changed the design.
- **Confidentiality.** If the repo is public or isn't owned by the client whose material the PR draws on, the body must name no client of FSH, no client repo or local path, no internal spec/ticket ID, no name-carrying identifier (module or env-var prefix, service name), no host or endpoint of theirs — unless that exact detail is already public in the client's own material. Provenance is where this slips: "upstreams client X's field-proven module" credits honestly and leaks anyway. Rewrite it to the engineering claim ("upstreams a pattern already running in production downstream"). This applies to what you *keep* as much as what you write — a leak inherited from the old body is still yours once you re-post it; strip it, and say in the report that you did and where else it may survive (commit messages, the diff, earlier comments), since those are outside this skill's reach.

## 4. Structure — general to specific

**Title**: Conventional Commits style, plain-language *outcome* (what a user/operator gets, not which function changed), task ID per repo convention.

**Body**: open with a **context line** when there is one: task reference (`Closes`/`Part of` per repo convention), stacking and dependency notes. Then follow [`references/pr-description.md`](./references/pr-description.md): a short paragraph with no headings for a small PR; otherwise 🎯 → 🔧 → 🧭 → 🧩 → 🔍 → ✅ → ⚠️, dropping empty sections, with heading words that state this PR's actual problem, fix or impact. `### 🎯 The problem` is not acceptable.

Where this skill's content lands:

- Tests added mapped to the bug each one catches, mutation checks, and what is *not* covered and why: **✅**.
- Remaining scope, with live links: **⚠️**.

Writing rules:

- No journal narration of the branch's own history ("an earlier revision…", "after review we…") *except* where it changed the design and a future reader needs the lesson — then one tight paragraph.
- No strikethroughs or "edit:" patches — rewrite the paragraph; the old text lives in the edit history.

## 5. Apply and report

Write the body to a temp file, then `gh pr edit <N> --title "..." --body-file <file>`. Report: old → new title, and what *materially* changed — especially corrected stale claims (readers of the old body may be carrying them).
