---
name: upstream-pr
description: Open or update a cross-repository (fork) pull request — push the current branch to the fork remote, target the upstream repo's real base branch, respect the upstream's label/QA policy, close any now-duplicate PR inside the fork as superseded, and degrade gracefully when you lack write access there. Use when contributing to a repo you don't own, or whenever the invocation mentions a fork/upstream remote ("make an upstream PR via the X remote"). Never merges.
---

# upstream-pr

You are running the **upstream-pr** skill. Goal: get the current branch reviewed upstream — pushed to the fork you can write to, opened against the upstream's real base branch, with the upstream's own PR policy applied as far as your permissions allow, and any now-duplicate PR inside the fork retired in favour of it.

Contributing from a fork is a **triangle**: commits go to one repo (the fork), review happens in another (the upstream). Almost every `git` and `gh` default assumes a single repo, so all four coordinates — fork remote, upstream slug, base branch, permission level — must be resolved explicitly, and *shown to the user before anything mutating*. Each one has a cheap, silent failure mode: a bare `git push` that hits a repo you shouldn't write to, or a PR opened against the GitHub default branch when the project actually merges into another one.

## Project specifics — read these first

This skill is repo-agnostic. It carries no label taxonomy, no QA rules, no check commands — it reads them from the consuming repo at runtime and defers to them. Before Phase 1, gather:

- **Agent config** — a machine-readable policy file if the repo has one (e.g. `.ai/agentic.config.json`): `baseBranch`, `labels.*`, `qaGate`, `validation.commands`.
- **PR policy docs** — the repo's `CONTRIBUTING.md`, PR template, and any `.ai/docs/pr-workflow.md`-style document: label taxonomy, priority/risk inference, QA gate, and **restricted paths** (trees that are off-limits to outside contributions).
- **`## Skill profile`** in the root `CLAUDE.md` / `AGENTS.md` — the curated source when present. Knobs this skill reads: `forkRemote`, `baseBranch`.
- **Check commands** — only needed if Phase 3 fires; same source as the sibling `deliver` skill.

If a needed value isn't documented and can't be inferred, ask rather than guess.

## Phases

### 0. Preflight

Record the branch and starting SHA:

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
git rev-parse HEAD
```

Refuse to run if `BRANCH` is the base branch or either repo's default branch — this skill operates on a feature branch only. If the working tree has uncommitted changes, surface them and ask the user what to do; never silently `git add -A`.

### 1. Resolve the triangle

Resolve `FORK_REMOTE`, `FORK_SLUG`, `UPSTREAM_SLUG`, `BASE`, and your upstream permission level using the rules in [Resolution rules](#resolution-rules) below. Then print a table of the values **with the source of each**, before anything mutating happens:

```
fork remote   fsh → fullstackhouse/open-mercato   (branch.<branch>.remote, isFork=true, parent matches upstream)
fork slug     fullstackhouse/open-mercato         (remote URL; FORK_OWNER is its first segment)
upstream      open-mercato/open-mercato           (fork's parent)
base branch   develop                             (.ai/agentic.config.json: baseBranch)
permission    READ                                (repos/<up> .permissions: push=false, triage=false)
```

Then fetch the base — everything downstream depends on it being current:

```bash
git fetch "$UPSTREAM_REMOTE" "$BASE"
```

Then bring **the fork's own copy of `$BASE`** up to date. Nothing else in the flow updates it: it is a mirror nobody commits to, so it drifts silently. The branch you just cut is fine either way — *this* PR is diffed against the upstream ref fetched above, and GitHub diffs a cross-fork PR from the merge-base, so a stale fork base cannot corrupt it. What the drift ruins is a PR opened **into** the fork's base: cut a branch from the freshly-fetched upstream ref, as the fetch above encourages, then open it against the fork, and the diff carries every intervening upstream commit as if the author wrote them. The reviewer meets those first. This is the only step positioned to prevent that, and it costs one comparison.

Compare the two refs locally, with the same `--is-ancestor` test Phase 7 uses, so one property has one vocabulary:

```bash
git fetch "$FORK_REMOTE" "$BASE" || echo "fork has no $BASE"
git rev-list --count "$FORK_REMOTE/$BASE..$UPSTREAM_REMOTE/$BASE"          # commits the fork is behind
git merge-base --is-ancestor "$FORK_REMOTE/$BASE" "$UPSTREAM_REMOTE/$BASE" && echo mirror || echo diverged
```

Locally rather than through `gh api .../compare` on purpose: a `$BASE` containing a slash (`release/*`) is an ordinary git ref but splits an API URL path, and these refs are already fetched, so it costs no round trip.

- **`mirror`, count 0** → already current. Say nothing and move on.
- **`mirror`, count > 0** → fast-forward it, and report how many commits it moved:

  ```bash
  gh repo sync "$FORK_SLUG" --branch "$BASE"
  ```

  No `--source` is needed: it defaults to the destination's parent, which is where the upstream slug was resolved from in the first place.

- **`diverged`** → **stop and ask.** The fork's base carries commits the upstream doesn't, so it is not a mirror and `gh repo sync` would need `--force` to land. Never pass it: that rewrites a branch other people's open PRs are based on.

Two ways this degrades, neither fatal — print the command and carry on, because the cost falls on the next branch and not on this PR: the fork may not have `$BASE` at all (forked with `--default-branch-only`, or the upstream created the branch later), in which case the fetch fails and there is nothing to compare; and the sync may fail for lack of permission on the fork.

**This phase runs before Phase 7 and changes its answer** — a fork base fast-forwarded here reads as `mirror` there, which is the desirable direction but makes the two order-dependent.

### 2. Guardrail checks

Hard-stop here, *before* pushing anything:

1. **Base exists** upstream (`git rev-parse --verify "$UPSTREAM_REMOTE/$BASE"` after the fetch).
2. **Branch ≠ base.**
3. **Restricted paths.** Diff against the freshly-fetched base (`git diff --name-only "$UPSTREAM_REMOTE/$BASE"...HEAD`) and check it against the trees the repo's CONTRIBUTING marks as off-limits to outside contributions. If the branch touches one, stop and report — a PR that will be closed unmerged is worse than no PR.
4. **Confidentiality.** Run the [Confidentiality gate](#confidentiality-gate) over the diff and the commit messages. This is the last moment an offending commit message can still be rewritten cheaply.

### 3. Local checks — only if the branch is unpushed or behind

Detect:

```bash
git rev-list --left-right --count '@{push}...HEAD'   # "<behind> <ahead>"; 0 0 = nothing new to push
```

If the right-hand count is 0 (and `@{push}` resolves), the commits are already on the fork and were presumably checked when they got there — **skip this phase**. Otherwise run the sibling **`deliver`** skill's Phase 2 (local checks) rather than duplicating it here, sourcing the commands from the repo's `validation.commands` / `## Skill profile`.

Why this matters more than in a same-repo PR: on a fork PR, CI is usually gated on maintainer approval. A red push doesn't cost you a rerun, it costs a human round-trip.

### 4. Push to the fork

Explicit remote and refspec, always:

```bash
git push "$FORK_REMOTE" "HEAD:refs/heads/$BRANCH"
```

Never a bare `git push` (its target depends on config you didn't set), never `--force`, never `-u` (don't rewrite the user's git config).

### 5. Create or update the PR

Look for an existing PR for this head. **`gh pr list --head "owner:branch"` does not work cross-repo** — it returns `[]` even when the PR exists. Use the REST endpoint, which honours the `owner:branch` form:

```bash
FORK_OWNER=${FORK_SLUG%%/*}
gh api "repos/$UPSTREAM_SLUG/pulls?state=open&head=$FORK_OWNER:$BRANCH"
```

- **An open PR exists** → this is an *update*: the Phase 4 push already refreshed it. Refresh the body only if it no longer describes the current commit set. Never change base, title, or labels on update.
- **No open PR** → re-query with `state=all` before creating. If a **closed** PR exists for this exact head, surface it to the user and ask before opening a replacement — it may have been rejected, and silently re-opening a rejection is a way to annoy maintainers.
- **Otherwise** → create:

  ```bash
  gh pr create --repo "$UPSTREAM_SLUG" --base "$BASE" --head "$FORK_OWNER:$BRANCH" \
    --title "<conventional-commit style>" --body-file .context/upstream-pr/body.md
  ```

  Fill the repo's PR template verbatim — read it and answer its sections. Re-run the [Confidentiality gate](#confidentiality-gate) over `body.md` before posting: the body is written after Phase 2 scanned, so it is the one surface that scan could not have covered. **Never `--fill`**: it discards the template. Open it **ready for review, not as a draft** — a maintainer's first signal should be a PR that's explicitly ready, and a draft may never enter the upstream's review pipeline at all (pipeline labels like `review` typically only apply once it's ready). Pass `--draft` only when the user explicitly asked for one.

  **Never `--label` on create.** Labelling is a write you may not have upstream, and `gh pr create` can fail on it *after* the push — costing you the PR. Labels are applied in Phase 6, once the PR exists and can't be lost.

### 6. Metadata & degradation

`triage` is the threshold for writing PR metadata (labels, assignee, reviewer).

- **At or above `triage`** → apply what the repo's policy calls for: pipeline / category / priority / risk labels and QA meta labels, per its taxonomy and inference rules. Validate every label name against `gh label list --repo "$UPSTREAM_SLUG"` first (label *reads* work at `read`).
- **Below `triage`** → emit exactly **one** consolidated *metadata-intent* comment on the PR: intended labels with the rationale for each, the intended assignee, and the reviewer **by role, never by handle**. Then stop and say so in the report. Specifically:
  - Do **not** post one comment per label, and do not retry the writes.
  - Skip any "claim" label (`in-progress` and friends) entirely — a claim you cannot release later is worse than no claim.
  - If the repo has a QA gate, note that the PR stays gated until a maintainer applies the QA labels; an evidence comment alone doesn't clear it.

Then, on **both** paths, apply any entry in [Upstream exceptions](#upstream-exceptions) matching `UPSTREAM_SLUG`. Those are FSH's own obligations toward that upstream, not its policy — they don't lapse just because you're below `triage`.

The "exactly one" rule above bounds *metadata-intent* comments only. An exception may require its own standalone comment (a slash command has to be the whole body to be parsed) — post it, and never suppress it to satisfy the one-comment rule.

### 7. Retire the superseded fork PR

A branch that reaches upstream has often already been opened as a PR **inside the fork** — internal review via the sibling `deliver` skill, or a placeholder from before upstream access was sorted out. Once the upstream PR exists, that one is duplicate review surface: two comment threads on one diff, and a PR that can't be the thing that merges the change into the product.

Find it — open, in the fork, **head** equal to this branch:

```bash
gh api "repos/$FORK_SLUG/pulls?state=open&head=$FORK_OWNER:$BRANCH" \
  --jq '.[] | {number, base: .base.ref, url: .html_url}'
```

Head only. A PR whose *base* is this branch is stacked work — someone else's branch merging into yours — and closing it throws away their review. Nothing open → skip this phase silently, no report line needed.

Otherwise, before closing anything, check that the fork PR is genuinely redundant. It is only redundant if the fork's base branch is a **mirror** of the upstream's, so the change comes back down when the fork syncs. If the fork's base carries commits of its own, the fork is a product line rather than a mirror, and merging upstream does *not* deliver the change there — the fork PR is the only path that does. With `FORK_BASE` from the `base` field above:

```bash
git fetch "$FORK_REMOTE" "$FORK_BASE"
git merge-base --is-ancestor "$FORK_REMOTE/$FORK_BASE" "$UPSTREAM_REMOTE/$BASE" && echo mirror || echo diverged
```

Same test as Phase 1, and Phase 1 runs first: if `$FORK_BASE` is the branch it fast-forwarded, this reads `mirror` because of that, not independently of it.

- **mirror** → close it, with the note.
- **diverged** → leave it open and say why in the report. Never close it "to tidy up".

The check is deliberately one-sided: a fork that syncs by merge commit rather than fast-forward reads as `diverged` and keeps its PR open. A wrong `diverged` costs a stale PR; a wrong `mirror` costs the change.

Close and explain in one call — a separate `gh pr comment` plus `gh pr close` can leave the PR closed with no explanation if the second half fails:

```bash
gh pr close "$FORK_PR_URL" --comment "Superseded by $UPSTREAM_PR_URL — this change is now under review upstream. Branch \`$BRANCH\` is left in place because it is the head of that upstream PR; deleting it would close the PR."
```

**Never pass `--delete-branch`.** The fork branch *is* the upstream PR's head — deleting it closes the PR you just opened and takes its diff with it. Nothing in this phase touches the branch.

If the close fails for lack of write access on the fork (possible when `FORK_REMOTE` is someone else's fork you were merely given a push ref to), post the comment on its own and name the close as deferred in the report.

The fork of a public upstream is public too, so the closing comment goes through the [Confidentiality gate](#confidentiality-gate) like everything else. The template above adds nothing that isn't already published by this point — the upstream PR's URL, and a branch name that is that PR's head — so keep it to those two. Internal review context (why the fork PR was opened, what came up on it, who asked for what) does not belong in it. If the *branch name itself* trips the gate, that leaked at Phase 4 and the comment is not where you fix it: report it under [On a hit](#on-a-hit).

On **update** (the upstream PR already existed), run this phase anyway: a fork PR can be opened after the upstream one.

### 8. Report

Final message must include:

- The PR URL, and whether it was **created** or **updated**.
- The four resolved values and where each came from.
- Whether the fork's base branch was fast-forwarded, by how many commits — or why it wasn't. Omit when it was already current; Phase 1 says nothing in that case and neither should the report.
- Your permission level upstream and everything that was consequently **deferred to a maintainer** (labels, assignee, reviewer, QA gate).
- The fork PR closed as superseded, if any — or the one left open, with the `diverged` reason.
- Any PR-template checkbox left unticked, named explicitly — especially CLA/legal ones.
- The [Confidentiality gate](#confidentiality-gate) result: the terms scanned for, and anything rewritten because of it.
- Whether a closed PR for the same head exists.
- An explicit line that **this skill does not merge** — the PR is handed to the upstream's process.

Mention these two dead ends once, so nobody re-derives them: `gh pr create --dry-run` is *not* read-only (its own help says it "May still push git changes"), and cross-repo PRs generally can't get package previews from CI (workflows commonly hard-stop on `isCrossRepository: true`).

## Resolution rules

### Fork remote

Ordered, offline-first — one API call on the happy path. Classify a candidate with:

```bash
gh repo view "$SLUG" --json isFork,parent,viewerPermission
```

0. **Named in the invocation** ("via the *fullstackhouse* remote") — a remote name or an owner login. Use it.
1. **Fast path:** `git config --get "branch.$BRANCH.remote"`. Classify it; accept if `isFork == true` **or** `viewerPermission` ∈ {WRITE, MAINTAIN, ADMIN}.
2. `git rev-parse --abbrev-ref '@{push}'`, strip the trailing `/$BRANCH`.
3. **Offline prefilter:** among the remaining remotes, keep only those whose slug's *repo name* matches the upstream's but whose *owner* differs. This drops unrelated same-owner repos (`fullstackhouse/helmet-mercato` vs `open-mercato/open-mercato`) at zero API cost.
4. Classify the survivors: a fork iff `isFork == true` **and** `parent` is the upstream slug (`.parent.owner.login + "/" + .parent.name`).
5. **≥2 survivors** → show the table and ask the user. **0 survivors** → stop and print the `git remote add` command they'd need. Never run `gh repo fork` or `git remote add` yourself.

### Upstream slug

In order: the fork's `parent` → a remote literally named `upstream` → `gh repo view --json parent` on `origin` → `origin` itself.

When several remotes point at the same upstream slug (common: both `origin` and `upstream`), pick the one whose remote-tracking ref for the base is **freshest** — `git log -1 --format=%ci "<remote>/$BASE"` — and use it as `UPSTREAM_REMOTE` for fetching.

### Base branch

**Never hardcode a base.** The GitHub default branch is the *last* resort, not the first — plenty of projects merge into `develop`, `next`, or a release line while `defaultBranchRef` says `main`.

0. `git config --get "branch.$BRANCH.gh-merge-base"`
1. The repo's agent config `baseBranch` (ignore a literal `"auto"`)
2. `## Skill profile` → `baseBranch` in the root `CLAUDE.md` / `AGENTS.md`
3. The PR template's or CONTRIBUTING's wording ("Open PRs against `develop`")
4. The base used by this fork owner's other open upstream PRs
5. `gh repo view "$UPSTREAM_SLUG" --json defaultBranchRef -q .defaultBranchRef.name`

Proceed silently on tiers 0–3 and state the source in the report. State it inline when the value came from tier 4–5. Ask the user only when two inferred tiers **disagree**.

### Permission level

Probe once:

```bash
gh api "repos/$UPSTREAM_SLUG" --jq '.permissions'   # {"admin":false,"maintain":false,"pull":true,"push":false,"triage":false}
```

Do **not** use `repos/<up>/collaborators/<user>/permission` — it returns **403 "Must have push access"** for exactly the read-only accounts that need the fallback path, so it can't be used to detect them.

## Confidentiality gate

Everything this skill publishes — the pushed commits, their messages, the PR title and body, every comment — lands in a repo FSH does not own. Treat all of it as permanently public: edits leave an edit history, and force-pushing is off the table (hard rule #3).

**The rule: no client's non-public details leave FSH.** Clients, their products, repos, environments and internal artifacts are confidential by default — *including when the mention is flattering*. Provenance is the trap: the honest instinct to credit where a pattern was proven ("upstreams the field-proven module from client X") is exactly what writes a client's name into a public diff. Say the engineering claim, drop the address:

> ~~Upstreams the field-proven `acme_telemetry` module from a downstream partner deployment (Acme).~~
> Upstreams a pattern already running in production in a downstream deployment.

(This file is itself published to a public repo, which is why the example is anonymised — the rule applies to the rule's own documentation.)

Confidential unless independently verified public:

- Client / product / brand names, and the names of their staff.
- Their repo names, local checkout paths (`~/src/<client>/…`), internal spec or ticket IDs (`SPEC-042`, `ACME-421`), Slack channels, doc URLs.
- Identifiers that carry the name: module and table prefixes (`acme_telemetry`), env-var prefixes, package scopes, service names.
- Infrastructure: hostnames, domains, collector/API endpoints, account and bucket IDs.
- Their data in any form: fixtures, seed data, screenshots, logs, pasted stack traces.

**The exception is narrow**: the client's own project is public (an open-source repo, a published post) *and* the specific detail appears in that public material. Verify it — don't infer it from the client being well known, and don't let one public fact license the rest.

### Scan

Build the term list from what the branch actually drew on: the repo or directory the work was ported from, the sibling client checkouts next to the current one, every proper noun in the diff that isn't the upstream's own, and the identifier prefixes above. Then check every surface against the freshly-fetched base — plus, by eye, any comment you are about to post:

```bash
TERMS='acme|acmecorp|acme_|ACME-'                                            # case-insensitive alternation
git diff "$UPSTREAM_REMOTE/$BASE"...HEAD | grep -inE "$TERMS"                # code, docs, specs, fixtures
git log "$UPSTREAM_REMOTE/$BASE"..HEAD --format='%B' | grep -inE "$TERMS"    # commit messages
grep -inE "$TERMS" .context/upstream-pr/body.md                              # PR body, before posting
echo "$BRANCH" | grep -inE "$TERMS"                                          # branch name — the Phase 4 push publishes it
```

Keep the terms specific — a bare prefix like `gs_` also matches `flags_` and `settings_`, and a scan that cries wolf is a scan the next run skips. Anchor them (`\bgs_`, `-- 'Acme'`) and drop any term that fires on the upstream's own vocabulary.

Grep is the floor, not the ceiling — it cannot catch a description that identifies without naming ("the client's booking product", a niche vertical plus a city), so also *read* the prose the branch adds: spec files, READMEs, ADRs, code comments, and your own PR body.

### On a hit

- **Not yet pushed** → rewrite and continue. Rewriting a commit message here means `git commit --amend` or a `git rebase` on an unpublished branch, which is fine — that is precisely why this scan sits in Phase 2 and not after the push.
- **Already pushed, or already public** → **stop**. Do not force-push to hide it: hard rule #3 stands, and the race is unwinnable anyway — a force-pushed commit stays reachable by SHA on GitHub, and forks, CI logs, notification emails and scrapers may already hold it. Report to the user exactly what leaked and in which surface, and lay out the options that need a human decision: edit the PR body or comment (cheap; the original survives in the edit history), rewrite published history (their call, and their client's), or accept it. Never make that call silently.

## Upstream exceptions

Named carve-outs, keyed on `UPSTREAM_SLUG`. The bar for an entry is narrow: an obligation **FSH** owes a particular upstream that the *upstream itself doesn't document*, so no runtime read of its `CONTRIBUTING.md` or agent config can discover it. Anything the upstream does document stays out of here — that's hard rule #10.

### `open-mercato/open-mercato` — always label `partner-request`

FSH contributes to Open Mercato as a certified partner (registered under `8lines` in the upstream's `.github/certified-partners.yml`). Every PR we open there carries `partner-request`; it's how maintainers route partner work. The label has no description upstream and appears in no upstream doc — only in `.github/workflows/community-labels.yml` — which is why it lives here.

Apply it **after** the PR exists, never via `gh pr create --label`. Take the first rung that succeeds, then stop:

1. **`triage` or above** — Phase 6 already resolved your level:

   ```bash
   gh pr edit "$PR_URL" --add-label partner-request
   ```

2. **A certified-partner account.** The upstream's `community-labels.yml` accepts `/label partner-request` from any login in that registry, even without repo permissions. Check the acting account:

   ```bash
   ME=$(gh api user --jq .login)
   gh api repos/open-mercato/open-mercato/contents/.github/certified-partners.yml \
     -H 'Accept: application/vnd.github.raw' | grep -i -- "$ME"
   ```

   (The raw `Accept` header skips the base64 hop the contents API otherwise returns — one less decode step, and no `base64 -d` vs `-D` portability trap.)

   Read the hit — it must be an entry in a `contributors:` list, not an incidental substring. If listed, post a comment whose **entire body is the command** — the workflow matches `startsWith(body, '/label ')`, so it must be its own comment, never folded into the Phase 6 consolidated comment and never prefixed with prose:

   ```bash
   gh pr comment "$PR_URL" --body '/label partner-request'
   ```

   The workflow signals by reaction (👍 applied, 😕 refused) and only ever applies `partner-request` — no other label can be requested this way. Verify rather than assume:

   ```bash
   gh pr view "$PR_URL" --json labels --jq '.labels[].name'
   ```

3. **Neither** — ask a human, in one comment, and name it as deferred in the Phase 8 report:

   > @jtomaszewski please apply the `partner-request` label — this is an FSH partner contribution and this account can't set labels here.

   The handle is deliberate and not a placeholder: rung 3 only fires for an account that is neither a collaborator nor in the partner registry, so "mention the right maintainer" is exactly the thing it can't work out on its own. `jtomaszewski` is FSH's Open Mercato partner contact — if that changes, change it here.

On **update**, this overrides "never change labels on update" for this one label: if `partner-request` is absent, run the ladder again. Touch nothing else.

## Hard rules

1. **Never merge.** No `gh pr merge`, no `--auto`, no `--admin`. This skill hands the PR to the upstream's process and stops.
2. **Never push to the upstream remote**, and never to a default or protected branch on any remote. Fast-forwarding the fork's own `$BASE` (Phase 1) is the one exception, and it is narrow: `gh repo sync` calls the merge-upstream API rather than pushing, it is fast-forward-only, and mirroring the upstream is the entire purpose of that branch.
3. **Never force-push.** A fork PR's history is a maintainer's review context.
4. **Never mutate the user's git setup** — no `gh repo fork`, no `git remote add`, no `git config` writes, no `push -u`. Print the command and let them run it.
5. **Never `--no-verify`, never `--no-gpg-sign`.** Fix the hook's root cause.
6. **Always fetch the base before computing any diff.** Not theoretical: a month-stale `upstream/<base>` ref makes a 9-file branch look like 2049 files across trees it never touched — enough to trip a restricted-path guardrail that a fresh base clears. Every diff in this skill is against the freshly-fetched ref.
7. **Respect the PR template verbatim** — no `--fill`.
8. **Never tick a CLA or legal checkbox on the user's behalf.** Leave it unchecked and name it in the report. Tick only factual boxes you actually verified (e.g. "targets `develop`").
9. **Never publish a client's non-public details.** Names, repos, internal IDs, infrastructure and data of FSH clients stay inside FSH — in the diff, the commit messages, the PR body and every comment — unless that exact detail is already public in the client's own material. See [Confidentiality gate](#confidentiality-gate). A leak is the one failure here that cannot be undone by a later commit.
10. **Don't restate the consuming repo's policy** — read `CONTRIBUTING.md` / the workflow doc / the agent config at runtime. Anything hardcoded here goes stale in a repo you don't own. The one exception is [Upstream exceptions](#upstream-exceptions): obligations *FSH* owes a named upstream that the upstream doesn't document, so they can't be read at runtime. Nothing else goes there.
11. **Never delete a branch, and never close a PR you haven't proved redundant.** No `--delete-branch` on `gh pr close`, no `git push --delete`: the fork branch is the upstream PR's head. The only PR this skill may close is an open fork PR whose *head* is this branch **and** whose base cleared the Phase 7 mirror check. The upstream PR is never closed.
