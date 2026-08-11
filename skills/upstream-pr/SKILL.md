---
name: upstream-pr
description: Open or update a cross-repository (fork) pull request — scrub every client-identifying detail before anything is published, push the current branch to the fork remote, target the upstream repo's real base branch, respect the upstream's label/QA policy, and degrade gracefully when you lack write access there. Use when contributing to a repo you don't own, or whenever the invocation mentions a fork/upstream remote ("make an upstream PR via the X remote"). Never merges.
---

# upstream-pr

You are running the **upstream-pr** skill. Goal: get the current branch reviewed upstream — pushed to the fork you can write to, opened against the upstream's real base branch, with the upstream's own PR policy applied as far as your permissions allow, and **carrying nothing that identifies the client the work was done for**.

Contributing from a fork is a **triangle**: commits go to one repo (the fork), review happens in another (the upstream). Almost every `git` and `gh` default assumes a single repo, so all four coordinates — fork remote, upstream slug, base branch, permission level — must be resolved explicitly, and *shown to the user before anything mutating*. Each one has a cheap, silent failure mode: a bare `git push` that hits a repo you shouldn't write to, or a PR opened against the GitHub default branch when the project actually merges into another one.

## Project specifics — read these first

This skill is repo-agnostic. It carries no label taxonomy, no QA rules, no check commands — it reads them from the consuming repo at runtime and defers to them. Before Phase 1, gather:

- **Agent config** — a machine-readable policy file if the repo has one (e.g. `.ai/agentic.config.json`): `baseBranch`, `labels.*`, `qaGate`, `validation.commands`.
- **PR policy docs** — the repo's `CONTRIBUTING.md`, PR template, and any `.ai/docs/pr-workflow.md`-style document: label taxonomy, priority/risk inference, QA gate, and **restricted paths** (trees that are off-limits to outside contributions).
- **`## Skill profile`** in the root `CLAUDE.md` / `AGENTS.md` — the curated source when present. Knobs this skill reads: `forkRemote`, `baseBranch`, `confidentialTerms`.
- **Client identity** — everything the branch must not carry upstream. `confidentialTerms` is the curated list when it exists; otherwise derive candidates per [Client confidentiality](#client-confidentiality). Never assume "this repo has no client" — ask.
- **Check commands** — only needed if Phase 4 fires; same source as the sibling `deliver` skill.

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

Resolve `FORK_REMOTE`, `UPSTREAM_SLUG`, `BASE`, and your upstream permission level using the rules in [Resolution rules](#resolution-rules) below. Then print a table of the four values **with the source of each**, before anything mutating happens:

```
fork remote   fsh → fullstackhouse/open-mercato   (branch.<branch>.remote, isFork=true, parent matches upstream)
upstream      open-mercato/open-mercato           (fork's parent)
base branch   develop                             (.ai/agentic.config.json: baseBranch)
permission    READ                                (repos/<up> .permissions: push=false, triage=false)
```

Then fetch the base — everything downstream depends on it being current:

```bash
git fetch "$UPSTREAM_REMOTE" "$BASE"
```

### 2. Guardrail checks

Hard-stop here, *before* pushing anything:

1. **Base exists** upstream (`git rev-parse --verify "$UPSTREAM_REMOTE/$BASE"` after the fetch).
2. **Branch ≠ base.**
3. **Restricted paths.** Diff against the freshly-fetched base (`git diff --name-only "$UPSTREAM_REMOTE/$BASE"...HEAD`) and check it against the trees the repo's CONTRIBUTING marks as off-limits to outside contributions. If the branch touches one, stop and report — a PR that will be closed unmerged is worse than no PR.

### 3. Client-confidentiality scrub

Run the full procedure in [Client confidentiality](#client-confidentiality) now — before the push, not before the PR. The fork is world-readable and a push publishes the branch name, the commits, and their authors *whether or not a PR ever exists*.

Outcome of this phase is one of:

- **Clean** → continue, and set `PUSH_BRANCH="$BRANCH"`.
- **Fixable** → fix (new commit on top / a different `PUSH_BRANCH` / a rewritten body), re-scan, continue.
- **Not fixable without a force-push, or client-specific by nature** → stop and report. Do not push.

### 4. Local checks — only if the branch is unpushed or behind

Detect:

```bash
git rev-list --left-right --count '@{push}...HEAD'   # "<behind> <ahead>"; 0 0 = nothing new to push
```

If the right-hand count is 0 (and `@{push}` resolves), the commits are already on the fork and were presumably checked when they got there — **skip this phase**. Otherwise run the sibling **`deliver`** skill's Phase 2 (local checks) rather than duplicating it here, sourcing the commands from the repo's `validation.commands` / `## Skill profile`.

When Phase 3 gave you a `PUSH_BRANCH` different from `BRANCH`, `@{push}` won't answer the question — compare against `"$FORK_REMOTE/$PUSH_BRANCH"` instead (and treat "ref doesn't exist" as unpushed).

Why this matters more than in a same-repo PR: on a fork PR, CI is usually gated on maintainer approval. A red push doesn't cost you a rerun, it costs a human round-trip.

### 5. Push to the fork

Explicit remote and refspec, always — and the *destination* name is `PUSH_BRANCH` from Phase 3, which may differ from the local branch:

```bash
git push "$FORK_REMOTE" "HEAD:refs/heads/$PUSH_BRANCH"
```

Never a bare `git push` (its target depends on config you didn't set), never `--force`, never `-u` (don't rewrite the user's git config).

### 6. Create or update the PR

Look for an existing PR for this head. **`gh pr list --head "owner:branch"` does not work cross-repo** — it returns `[]` even when the PR exists. Use the REST endpoint, which honours the `owner:branch` form:

```bash
FORK_OWNER=${FORK_SLUG%%/*}
gh api "repos/$UPSTREAM_SLUG/pulls?state=open&head=$FORK_OWNER:$PUSH_BRANCH"
```

- **An open PR exists** → this is an *update*: the Phase 5 push already refreshed it. Refresh the body only if it no longer describes the current commit set. Never change base, title, or labels on update.
- **No open PR** → re-query with `state=all` before creating. If a **closed** PR exists for this exact head, surface it to the user and ask before opening a replacement — it may have been rejected, and silently re-opening a rejection is a way to annoy maintainers.
- **Otherwise** → create:

  ```bash
  gh pr create --repo "$UPSTREAM_SLUG" --base "$BASE" --head "$FORK_OWNER:$PUSH_BRANCH" \
    --title "<conventional-commit style>" --body-file .context/upstream-pr/body.md
  ```

  Title and body are publication too: re-run the Phase 3 term scan over both before this command, and confirm `.context/` is gitignored so a draft body never rides along in a commit.

  Fill the repo's PR template verbatim — read it and answer its sections. **Never `--fill`**: it discards the template. Open it **ready for review, not as a draft** — a maintainer's first signal should be a PR that's explicitly ready, and a draft may never enter the upstream's review pipeline at all (pipeline labels like `review` typically only apply once it's ready). Pass `--draft` only when the user explicitly asked for one.

  **Never `--label` on create.** Labelling is a write you may not have upstream, and `gh pr create` can fail on it *after* the push — costing you the PR. Labels are applied in Phase 7, once the PR exists and can't be lost.

### 7. Metadata & degradation

`triage` is the threshold for writing PR metadata (labels, assignee, reviewer).

- **At or above `triage`** → apply what the repo's policy calls for: pipeline / category / priority / risk labels and QA meta labels, per its taxonomy and inference rules. Validate every label name against `gh label list --repo "$UPSTREAM_SLUG"` first (label *reads* work at `read`).
- **Below `triage`** → emit exactly **one** consolidated *metadata-intent* comment on the PR: intended labels with the rationale for each, the intended assignee, and the reviewer **by role, never by handle**. Scan it against the term list before posting — a rationale is prose, and prose is where a client name slips out ("needed for the Acme rollout"). Then stop and say so in the report. Specifically:
  - Do **not** post one comment per label, and do not retry the writes.
  - Skip any "claim" label (`in-progress` and friends) entirely — a claim you cannot release later is worse than no claim.
  - If the repo has a QA gate, note that the PR stays gated until a maintainer applies the QA labels; an evidence comment alone doesn't clear it.

Then, on **both** paths, apply any entry in [Upstream exceptions](#upstream-exceptions) matching `UPSTREAM_SLUG`. Those are FSH's own obligations toward that upstream, not its policy — they don't lapse just because you're below `triage`.

The "exactly one" rule above bounds *metadata-intent* comments only. An exception may require its own standalone comment (a slash command has to be the whole body to be parsed) — post it, and never suppress it to satisfy the one-comment rule.

### 8. Report

Final message must include:

- The PR URL, and whether it was **created** or **updated**.
- The four resolved values and where each came from.
- The confidentiality scrub: which term list you used and where it came from, which surfaces were scanned, what you rewrote (and how — new commit, different `PUSH_BRANCH`, reworded body), and anything you could **not** clean. This part of the report is for the user's eyes and may name the terms; nothing upstream may.
- Your permission level upstream and everything that was consequently **deferred to a maintainer** (labels, assignee, reviewer, QA gate).
- Any PR-template checkbox left unticked, named explicitly — especially CLA/legal ones.
- Whether a closed PR for the same head exists.
- An explicit line that **this skill does not merge** — the PR is handed to the upstream's process.

Mention these two dead ends once, so nobody re-derives them: `gh pr create --dry-run` is *not* read-only (its own help says it "May still push git changes"), and cross-repo PRs generally can't get package previews from CI (workflows commonly hard-stop on `isCrossRepository: true`).

## Client confidentiality

FSH's work is done for clients; the upstream is a public project that has no business knowing which one. **The standard: an upstream contribution must read as generic open-source work to someone who has no idea who paid for it.** Not "no confidential details" — no client *identity* at all. The name alone is the leak; "we hit this at Acme" tells a competitor who is on which stack.

Publication here is irreversible. A push to the fork is world-readable immediately, GitHub's events API and the upstream's notification mail capture the branch name and commit subjects, and a later force-push retracts none of it. That's why this runs at Phase 3, before the first push, and again before every string you send upstream.

### Build the term list

In order; stop at the first that gives you a usable list, then add the cheap derived candidates on top:

1. **`confidentialTerms`** in the consuming repo's `## Skill profile` — the curated list. Client names, former names, internal code names, domains, tenant/account ids, tracker prefixes.
2. **Named in the invocation** ("don't mention Acme").
3. **Derived candidates** — cheap to collect, always worth collecting even when 1 or 2 answered:
   - Repo identity: `package.json` `name`/scope/`author`/`repository`, `LICENSE` copyright holder, root `README` title, Docker image and registry names, the slugs of every `git remote` that isn't the fork or the upstream.
   - Tracker and comms: ticket-key prefixes (`ACME-1234`), Linear/Jira/Notion URLs, Slack channel names — grep the branch's commit messages and code comments for them.
   - People: author, committer and `Co-Authored-By` identities on the branch whose email domain is neither the FSH domain nor `users.noreply.github.com`.
   - Infra: non-`example.com` hostnames, subdomains, bucket names, SSO/tenant ids, env-var prefixes in `.env.example` and CI config.

If none of these yields anything and you can't tell whether the repo has a client at all, **ask before pushing**. "I found nothing" is not the same as "there is nothing", and the cost of asking is one question versus an unretractable publication.

Match case-insensitively and across the shapes a name mutates into: `AcmeCorp`, `acme-corp`, `acme_corp`, `ACME`, `acme.com`, and the tracker prefix. Do **not** silently rewrite an ambiguous hit — a client called Atlas and the `atlas` library look identical to `grep`. Show the user the hits and let them adjudicate.

FSH's own identity is not a client identity. The fork lives under the FSH org and the contribution is openly FSH's — `fullstackhouse`, the FSH domain, and FSH handles stay.

### Surfaces to scan

All of them. A clean diff on a branch named `acme-checkout-fix` still leaks.

1. **Branch name** — the one you're about to push.
2. **Commit subjects, bodies and trailers** on `base..HEAD`, including ticket refs and `Co-Authored-By`.
3. **Commit author and committer identities** on those commits (name *and* email).
4. **The diff** — added and removed lines, plus new and renamed paths and directory names.
5. **Everything bound for the upstream**: PR title, body, PR-template answers, the metadata-intent comment, any evidence you attach.
6. **Fixtures, seeds, snapshots, `.env.example`, test data** — real customer records, order ids, emails, addresses. These are the classic carrier: nobody reads a snapshot file before committing it.
7. **Opaque additions you can't grep** — screenshots, PDFs, `.har` captures, DB dumps, `.zip`. Open them and look, or drop them from the branch. A screenshot of the client's UI leaks branding, data and URL at once.

```bash
git log --format='%H%n%an <%ae>%n%cn <%ce>%n%B' "$UPSTREAM_REMOTE/$BASE"..HEAD
git diff --name-status "$UPSTREAM_REMOTE/$BASE"...HEAD
git diff "$UPSTREAM_REMOTE/$BASE"...HEAD | grep -inE "$TERMS"
```

(`$TERMS` is an alternation of the shapes above. Diff against the *freshly fetched* base — hard rule 7 applies here as everywhere.)

### Remedies

Never scrub silently, and never force-push to scrub.

| Surface | Remedy |
|---|---|
| Branch name | Push under a clean one: set `PUSH_BRANCH` and let Phase 5's refspec do the rest. Don't rename the user's local branch. |
| Commit message / trailer / author, **not yet pushed** | Propose the rewrite, get the user's OK, then `git commit --amend` / `git rebase` (with `--reset-author` or `-c user.email=…` for an identity) before the first push. |
| Commit message / trailer / author, **already pushed** | Stop. Cleaning it needs a force-push, which hard rule 4 forbids on a live PR. Report it and hand the call to the user — closing the PR and opening a fresh one from a clean branch is usually the answer, and it's theirs to make. |
| Diff content | It's a code change like any other: rename the identifier, generalize the fixture, delete the file — in a **new commit on top**. Re-scan afterwards. |
| PR title / body / comment | Rewrite before sending. Nothing has been published; this one is free. |
| The change is client-specific by nature | Stop. There's nothing to scrub — the branch isn't upstreamable as-is. Report which parts would have to be generalized (extract the generic fix, drop the client-specific config) and let the user decide whether that's worth doing. |

### Don't leak the scrub itself

The term list never goes upstream — not in a comment, not in a commit message, not as a redaction marker. "Renamed to avoid mentioning our client" and `<REDACTED-CLIENT>` both announce that there's a client to look for, and the second invites a maintainer to ask who. Generalize instead: the fixture is named `acme_orders` → it becomes `sample_orders`, not `redacted_orders`. Likewise, never ask the upstream a question that carries the answer ("is this fine given our Acme deployment?").

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

## Upstream exceptions

Named carve-outs, keyed on `UPSTREAM_SLUG`. The bar for an entry is narrow: an obligation **FSH** owes a particular upstream that the *upstream itself doesn't document*, so no runtime read of its `CONTRIBUTING.md` or agent config can discover it. Anything the upstream does document stays out of here — that's hard rule #10.

### `open-mercato/open-mercato` — always label `partner-request`

FSH contributes to Open Mercato as a certified partner (registered under `8lines` in the upstream's `.github/certified-partners.yml`). Every PR we open there carries `partner-request`; it's how maintainers route partner work. The label has no description upstream and appears in no upstream doc — only in `.github/workflows/community-labels.yml` — which is why it lives here.

Apply it **after** the PR exists, never via `gh pr create --label`. Take the first rung that succeeds, then stop:

1. **`triage` or above** — Phase 7 already resolved your level:

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

   Read the hit — it must be an entry in a `contributors:` list, not an incidental substring. If listed, post a comment whose **entire body is the command** — the workflow matches `startsWith(body, '/label ')`, so it must be its own comment, never folded into the Phase 7 consolidated comment and never prefixed with prose:

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

1. **Never publish anything that identifies a client.** Branch name, commit messages, commit authors, diff, fixtures, PR title and body, comments, screenshots — everything the fork or the upstream can see must read as generic work. The bar is the *name*, not just the secrets. Publication is one-way: force-pushing does not retract a ref GitHub has already indexed and emailed. When you can't tell whether something identifies a client, don't push — ask. See [Client confidentiality](#client-confidentiality).
2. **Never merge.** No `gh pr merge`, no `--auto`, no `--admin`. This skill hands the PR to the upstream's process and stops.
3. **Never push to the upstream remote**, and never to a default or protected branch on any remote.
4. **Never force-push.** A fork PR's history is a maintainer's review context. This also means a client name in an already-pushed commit message can't be cleaned by this skill — escalate to the user instead.
5. **Never mutate the user's git setup** — no `gh repo fork`, no `git remote add`, no `git config` writes, no `push -u`, no renaming the user's branch (push under a different name with a refspec instead). Print the command and let them run it.
6. **Never `--no-verify`, never `--no-gpg-sign`.** Fix the hook's root cause.
7. **Always fetch the base before computing any diff.** Not theoretical: a month-stale `upstream/<base>` ref makes a 9-file branch look like 2049 files across trees it never touched — enough to trip a restricted-path guardrail that a fresh base clears. Every diff in this skill is against the freshly-fetched ref.
8. **Respect the PR template verbatim** — no `--fill`.
9. **Never tick a CLA or legal checkbox on the user's behalf.** Leave it unchecked and name it in the report. Tick only factual boxes you actually verified (e.g. "targets `develop`").
10. **Don't restate the consuming repo's policy** — read `CONTRIBUTING.md` / the workflow doc / the agent config at runtime. Anything hardcoded here goes stale in a repo you don't own. The one exception is [Upstream exceptions](#upstream-exceptions): obligations *FSH* owes a named upstream that the upstream doesn't document, so they can't be read at runtime. Nothing else goes there.
