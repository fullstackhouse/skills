---
name: test-drive
description: Boot a change on a throwaway instance, prove login actually works, seed the data the change needs to be visible, then hand over a click-by-click route through it. Use when you want to see a change working before merging — "boot this PR so I can click through it", "set me up to review X by hand", "let me try this". Knows Open Mercato's ephemeral command; degrades to any repo's documented boot. Args: nothing (current worktree), or a PR number/URL to check out first.
---

# test-drive

You are running the **test-drive** skill. Goal: put a running instance of the change in the user's hands, with working credentials, the data that makes the change visible, and a route through it — so they can form their own opinion by clicking, not by reading a diff.

This is **not** `explain` (which translates a diff into a merge decision without running anything) and **not** an automated-QA skill (which drives a browser and posts pass/fail evidence to a pipeline). You do not drive the UI. You boot, you prove auth, you seed, you write the route — the human does the clicking.

A URL handed over without a completed login round-trip and a named record to look at is a **failure of this skill**, not a success. "It's running on port 5001" is setup, not a test drive.

## Project specifics — read these first

This skill is repo-agnostic, with Open Mercato as its known case. Gather the concrete details from the repository you're running in:

- **How to boot a throwaway instance** — the command that stands up a disposable app + database, where it records its base URL, and which credentials it guarantees. Open Mercato is resolved in Phase 2; for anything else, derive from the repo's `CLAUDE.md` / `AGENTS.md` / `package.json` scripts, or its **`## Skill profile`** section (the curated source) under the **Throwaway instance** knob.
- **How a changed file maps to a URL** — the route directory convention or a generated route manifest. The click route is *derived* from the diff, so you need this before Phase 4.
- **How records get created through the real path** — the API route convention per module, or the UI form that owns each entity. You need this before Phase 5.

If a needed value isn't documented and you can't infer it, ask the user rather than guessing.

## Arguments

- **Empty** — the current worktree, as it stands. Diff target is the branch against the repo's default branch.
- **A PR number / URL** — `gh pr checkout <N>` first, and only into a clean tree. A dirty tree is a stop, not a stash: say what's uncommitted and let the user decide.
- **`--fresh`** — never attach to an already-running instance; always build a new one.
- **`--no-seed`** — skip Phase 5 and hand over against whatever data already exists.

## Hard rules

1. **Hand over nothing you haven't verified.** Every URL in the click route must have been fetched and returned 200. Every seeded record must have been read back. A route full of plausible-looking URLs you never requested is worse than no route.
2. **Never write to the database directly.** Seed through the real API or the real UI form. A row inserted behind the app skips validation, events, and index/search updates — the app then treats it differently from a real record, and the drive demonstrates something that can't happen in production.
3. **Never seed against a database that isn't the throwaway one.** Before the first write, confirm the base URL is the instance this run booted (or one recorded in the ephemeral state file). If you can't confirm it, stop and ask. Seeding into someone's dev database is not recoverable by apologising.
4. **Don't demo a build you can't attribute.** Prove the running instance was built from the commit under test, or restart it fresh. See the reuse trap in Phase 2 — it is the most likely way this skill lies to the user.
5. **Say what the drive can't show.** A throwaway instance runs with outbound email, the scheduler, and enterprise modules disabled — though queue workers *do* run, so job-backed flows work. A click route that omits that invites the user to conclude a feature is broken when it's merely switched off.
6. **Read-only on source.** Boot, seed, and write the handover — never edit files, commit, push, or merge. `gh pr checkout` with an explicit PR argument is the single exception.
7. **The handover goes to the user.** This skill posts nothing to GitHub, Slack, or a tracker.

## Phases

### 1. Resolve the target

- **PR argument** → verify the tree is clean, `gh pr checkout <N>`, then `gh pr diff <N>` for the change surface.
- **No argument** → the current branch against the repo default (`git diff <default>...HEAD`; derive the default via `gh repo view --json defaultBranchRef` or `git symbolic-ref refs/remotes/origin/HEAD`).

State the target and the HEAD sha + subject in one line before doing anything expensive, so the user can stop you if you picked the wrong thing. You'll need that sha again in Phase 2 and in the handover.

### 2. Boot a throwaway instance

**Check preconditions first**, and report a failure with its fix rather than a stack trace:

- `node -v` → Open Mercato's ephemeral runner requires Node 24 or newer, and says so with a fix; check it yourself so the user hears it before the build starts, not after.
- `docker info` → must succeed. A non-standard runtime (Colima and friends) is auto-detected from the active Docker context; a dead daemon is not.

**Warn about the cost before starting, not after.** A cold boot runs the full initialize + production build pipeline: several minutes and RAM-heavy. Tell the user what they're waiting for.

**Resolve the boot command** — first hit wins, and the last rung is a real probe rather than an assumption:

1. Root `package.json` has `test:integration:ephemeral:start` → `yarn test:integration:ephemeral:start`. This is the Open Mercato monorepo; the script wraps `mercato test:ephemeral`.
2. `yarn mercato test:ephemeral` (equivalently `yarn mercato test ephemeral`).
3. A `create-mercato-app` scaffold — no root ephemeral script, but `@open-mercato/cli` is installed under the app. Probe for the alias before using it: `yarn --cwd apps/mercato exec mercato --help`, then `yarn --cwd apps/mercato exec mercato test:ephemeral`.
4. The repo's own documented boot (`## Skill profile` → **Throwaway instance**, or `CLAUDE.md` / `AGENTS.md`). If that resolves to a **long-lived shared dev stack** rather than a disposable one, say so explicitly and get consent before Phase 5 writes anything (Hard rule 3).

Useful flags: `--verbose` (full bootstrap/build logs — reach for it the moment a boot fails silently), `--no-reuse-env` (always a brand-new instance on an isolated port), `--no-screenshots` (irrelevant here; this skill doesn't drive a browser).

**Run it backgrounded.** The command holds the terminal until `Ctrl+C` — that's by design, it's what keeps the instance alive for the user.

**The reuse trap.** The ephemeral command silently *attaches* to an already-running instance recorded in `.ai/qa/ephemeral-env.json` when source mtimes and a build-cache TTL say it's still valid. After a branch switch or a `gh pr checkout`, that can hand you a running build of **different code** while everything looks fine. Before trusting a reused instance, prove it was built from the commit under test — compare the state file's `startedAt` against the checkout and the working tree. If you can't prove it, pass `--no-reuse-env`. `--fresh` always passes it.

**Capture the base URL from the ready line**, which is authoritative:

```
[ephemeral] Ready for QA exploration at http://127.0.0.1:<port>
[ephemeral] Default credentials: admin@acme.com / secret
```

`.ai/qa/ephemeral-env.json` (`baseUrl`, `port`, `databaseUrl`, `startedAt`) is a useful bonus, but it lives at the *project root* — which differs between the monorepo and a scaffold. Find it; don't assume the path. The backend UI is at `<baseUrl>/backend`.

### 3. Prove login — a real round-trip, not a guess

```bash
curl -s -X POST "$BASE_URL/api/auth/login" \
  -H 'content-type: application/x-www-form-urlencoded' \
  --data-urlencode 'email=admin@acme.com' --data-urlencode 'password=secret'
```

Expect 200 and a `token` in the body. Then **use the token** — one authenticated request against a route the change touches:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/<route>"
```

A login that mints a token while every subsequent call returns 401 is exactly what this second request catches, and it's a failure the user would otherwise hit on their first click.

- Credentials the ephemeral env guarantees: `admin@acme.com`, `superadmin@acme.com`, `employee@acme.com`, all with password `secret` (it pins the init passwords). **The guarantee is ephemeral-only** — in a normal environment the companion account passwords are randomly generated, so never present these as universal.
- The login route is rate-limited (a handful of attempts per minute per email). A `429` means back off, not bad credentials — do not loop on it.
- Keep the token for Phase 5. Never put it in the handover.

### 4. Read the change

Enough to say what it does in product terms — and, more importantly, to name **the user-visible surfaces it touches**. That list is what the click route is built from.

- Derive routes from the changed files using the repo's route convention or generated manifest. Don't guess a URL; a 404 in the handover destroys the user's trust in the rest of it.
- Pull the linked ticket if the branch or PR references one — it usually states the change in exactly the user terms you want.
- If the change has **no UI surface** (a worker, a migration, an API-only change), say so plainly and route the drive through the API or CLI instead of inventing a screen.

For a full merge-decision writeup — scenarios, what's tested, residual risk — that's `explain`. This is the short version that feeds the route.

### 5. Seed what the change needs

Skip if `--no-seed`.

1. **Ask what state makes the change visible.** An order in a particular status, a product with a variant, a customer carrying the new field. The change is only demonstrable against data that exercises it.
2. **Check what already exists first.** Open Mercato's initialize seeds a tenant plus demo customers, catalog, sales, and todos. An existing record that fits beats a new one, and it keeps the click route shorter. (Outside an ephemeral instance, never *assume* demo data is present — verify.)
3. **Create through the real API.** Discover the route from the changed module's own `api/` directory rather than guessing it, then `POST` with the bearer token and `Content-Type: application/json`.
4. **Read every record back** with a separate `GET`. Trusting the create response is how you hand over a record that isn't really there — or one the app can't find because an index never updated.
5. **No API route for it?** Put the UI form into the click route as step 0, with the exact fields to fill. Do not fake it in the database (Hard rule 2).

For each seeded record, note its **human-visible identifier** (name, number, title) and the **backend URL where the user will find it**. That pairing is what makes the handover clickable rather than a description.

### 6. Write the handover

The deliverable. Inline in your final message:

```markdown
# Test drive: <change in one line>

## Instance
- URL: <baseUrl>/backend — port <n>, built from <sha> "<subject>"
- Login: admin@acme.com / secret
  Verified: POST /api/auth/login → 200; GET <route> → 200
- Stop it: <exact command> — this destroys the container and everything seeded below.

## What the change does
<2–4 sentences in product terms — the situation it addresses and what's different now>

## Click route
1. <URL> → <what you should see, naming the seeded record> — <what to check>
2. <URL> → <...>
- Worth poking at: <the edge the diff makes interesting>

## Seeded for this drive
| Record | Where to find it | Created via |
|---|---|---|
| <identifier> | <URL> | <POST /api/...> |

## What this drive can't show
- <e.g. no outbound email (delivery disabled); scheduled jobs won't fire (scheduler off,
  though queue workers run, so job-backed flows do work); enterprise modules off;
  CRUD API caching on — plus anything specific to this change>
```

Writing rules:
- Every URL is one you fetched. Every record is one you read back.
- Say what the user should *see*, not just where to go. "Order ACME-1042 now shows a Partially shipped badge" beats "check the orders list".
- Be honest about what you couldn't set up. A missing step named is useful; a missing step hidden wastes the user's afternoon.

### 7. Hand over

Leave the instance running — that's the point of the skill. State plainly how to stop it, and that stopping destroys the container along with everything seeded. If you started it backgrounded, give the user the exact way to kill it.

## Things to remember

- A reused instance is someone else's build until you've proven otherwise.
- A 200 from login is not proof of authorization — make one authenticated call.
- Demo data is a starting point, never an assumption.
- If the click route contains no seeded or named record, the drive probably shows nothing.
- The first boot is slow. Warn before, not after.
- A URL you didn't fetch is a guess wearing a link.
- If the change has no screen, say so — don't send the user hunting for one.
