---
name: review-queue
description: Triage and review every PR awaiting your review in a repo — classify the queue, fan out one read-only reviewer subagent per PR, and merge the results into a linked triage table with verdicts, draft comments, and cross-PR conflicts. Use when asked to "review the PRs waiting for me", "go through my review queue", or review several PRs at once. Nothing is posted to GitHub without explicit per-action approval. Args: optionally a repo (owner/name), specific PR numbers, or a scope widening ("include unassigned").
---

# review-queue

You are running the **review-queue** skill. Goal: turn "N PRs are waiting on me" into one triage report the user can act on — per-PR verdicts, the comments worth posting, and the cross-PR picture no single reviewer sees.

**Draft-first. Hard rule: never post a review, comment, approval, or PR edit, and never merge, without the user's explicit instruction naming the PR.** All output lands in files first. Reviewing is judgment work — this skill's job is to prepare the user's review, not to impersonate it.

## 1. Resolve repo, identity, output dir

- Repo: from the argument, else `gh repo view --json nameWithOwner`.
- Identity: `gh api user --jq .login`.
- Output dir: the profile's scratch dir if named (see §3); else `.context/pr-review/` if a gitignored `.context/` exists; else `/tmp/review-queue-<repo>/`. Create it.

## 2. Build and classify the queue

One call: `gh pr list --state open --json number,title,author,isDraft,reviewDecision,reviewRequests,baseRefName,headRefName,additions,deletions,changedFiles,updatedAt --limit 100`. Classify:

- **A — requested from me**: I'm in `reviewRequests`, not a draft. *This is the default scope.*
- **B — unassigned**: open, non-draft, not mine, no reviewer requested. De-facto queue for a lead.
- **C — mine, awaiting others**: my PRs with no approval yet.
- **D — approved, unmerged**: `reviewDecision: APPROVED` — a merge queue, not a review queue.

Review bucket A (plus any PR the user named, drafts included then). Report B/C/D as one-line counts with linked PR numbers and **ask before widening** — B especially is a judgment call about the user's role, not a fact in the API.

## 3. Gather shared context once (not per agent)

- The consuming repo's `CLAUDE.md` / `AGENTS.md`: PR-body conventions (task-id format, `Closes`/`Part of` semantics), doc doctrine, test strategy, review-relevant "Don'ts".
- The `## Skill profile` section, if present: standing review landmines (perf-sensitive paths, known CI false-fails, encryption/tenancy rules), reviewer-bot login, tracker URL format for ticket links.
- The spec/ADR directory, if the repo has one, so agents can be pointed at cited specs by exact filename.

From the queue itself, derive **per-PR context** to inject into each agent's prompt — this is where the orchestrator earns its keep:

- The ticket(s)/spec(s) the PR cites.
- Sibling and stacked PRs: same files, same spec, or a base branch that is another PR's head.
- Vendored upstream state: if the PR carries a patch/copy of an upstream PR, the agent must check that upstream PR's *current* state — reviews filed since, mechanism replaced, merged.
- The obvious sharp question for the PR's genre: test-only PR → "would this test fail against the pre-fix code?"; revert → "what does main look like after?"; docs → "does the resulting document read clean, not just the diff?"; dependency/patch bump → "what else rides along?"

## 4. Fan out — one read-only reviewer subagent per PR

Launch all agents concurrently (background). Every prompt must carry:

**Isolation rules (verbatim, non-negotiable).** The agents share one clone. Never `git checkout`, `fetch`, `pull`, or write to the working tree (except the one output file). Read PR content via `gh pr view/diff/checks` and `gh api`; read a file at the PR head via `gh api "repos/<slug>/contents/<path>?ref=<headSha>" --jq .content | base64 -d`; read base-branch files locally. Never post anything.

**Ground truth first.** `gh pr view <N> --json title,body,headRefOid,commits,files,reviews,baseRefName` + `gh pr diff <N>`; existing review threads (`gh api repos/<slug>/pulls/<N>/comments --paginate`) and conversation comments (`.../issues/<N>/comments`) — corroborate or extend open threads, never re-raise settled ones; `gh pr checks <N>`, but verify any "failed" check against the head commit's check-runs before calling CI red (skipped notification jobs commonly render as failures), and note which required jobs actually *ran* (a skipped unit-test job under a green banner is a finding).

**Review directives.** Real defects first — correctness, data loss, tenancy/security, missing-or-vacuous test coverage, unbounded queries — then design/conventions. Read enough surrounding code to be *sure*; a confident wrong comment costs the reviewer more than a missed nit. Anything not verified is labeled unverified, not asserted. Judge whether the PR does what its body claims.

**Output template** → `<output-dir>/pr-<N>.md`:

```
# PR #N — <title>
[View](…/pull/N) · [Diff](…/pull/N/files) · [Checks](…/pull/N/checks)
<author> · +A/-D, F files · CI: <verified state> · base: <base, flag if another PR's head>

## TL;DR            ← 2–5 sentences, general→specific; for the reviewer's eyes, never posted
## Verdict          ← Approve / Approve with nits / Request changes / Needs discussion + one sentence
## Comments I'd post ← severity-ordered [blocker|should|nit|question], each written ready to post,
                       anchored `path/file.ts:LINE`; "None." is a fine answer
## Checked / not checked
## PR body health   ← accurate to the diff? If stale, a proposed rewrite in a fenced block — proposal only
```

**Links.** Link every PR, ticket, username, and doc reference (verify doc paths exist before linking; relative links from the output file's location). Leave `path/file.ts:LINE` refs as bare code spans — wrapping them in markdown swallows the line anchor that makes them clickable in terminals and editors.

Each agent returns a ≤12-line summary: verdict, headline risk, comment counts, body-rewrite-needed.

## 5. Merge into the triage report

After all agents finish, write `<output-dir>/README.md` and present the same content to the user:

- **Table**, sorted most-blocking first (Request changes → Needs discussion → Approve with nits → Approve): linked PR, what it is (author + one clause), verdict, the single blocking issue, link to the full review file.
- **Cross-PR findings** — the part only the orchestrator can do: overlapping files ("land #X first, #Y's fix goes on top"), one doc touched by three PRs (consolidate into one edit), stacked bases, PRs actually blocked on external/upstream state rather than on review.
- **The other buckets** (B/C/D) as linked one-liners, plus offered next actions: post comments on a named PR, widen scope, run `pr-polish` on the user's own stale-bodied PRs.

## 6. Act only on explicit instruction

- **"approve N"** → `gh pr review N --approve --body-file …`. The body states what was *actually verified* (and how), the accepted gaps, and the non-blocking nits — not boilerplate. Report resulting `reviewDecision` and anything merge-relevant (stacked base, red-but-unrelated check).
- **"request changes on N" / "post the comments on N"** → post only that PR's verified comments; inline where the line anchors are valid, otherwise one review body. Severity labels survive into the posted text.
- **The author's PR body is theirs.** The TL;DR is for the user; never overwrite someone else's description. If a body is stale, the posted comment says so and quotes the proposed fix — or, for the user's *own* PRs, offer to run `pr-polish`.
- Never resolve threads, never merge — merging is `deliver`'s job.

If any finding leads to filing something **outside the consuming repo** (an upstream issue or PR), the client-confidentiality gate applies: no client names, repo names, local paths, internal ticket/spec IDs, or name-carrying identifiers — state the engineering claim without the provenance, and prefer handing off to `upstream-pr`.
