---
name: om-test-drive
description: Boot a change on a throwaway instance, prove login actually works, seed the data the change needs to be visible, then hand over a click-by-click route through it. Use when you want to see a change working before merging — "boot this PR so I can click through it", "set me up to review X by hand", "let me try this". Knows Open Mercato's ephemeral command; degrades to any repo's documented boot. Args: nothing (current worktree), or a PR number/URL to check out first.
---

# om-test-drive

You are running the **om-test-drive** skill. Goal: put a running instance of the change in the user's hands, with working credentials, the data that makes the change visible, and a route through it — so they can form their own opinion by clicking, not by reading a diff.

This is **not** `explain` (which translates a diff into a merge decision without running anything) and **not** an automated-QA skill (which drives a browser and posts pass/fail evidence to a pipeline). You do not drive the UI. You boot, you prove auth, you seed, you write the route — the human does the clicking.

**Scope: Open Mercato first, and honestly so.** The boot step degrades to any repo that documents a disposable environment, but the auth and seeding phases are written around Open Mercato's routes. On another stack this skill boots and then needs its profile to supply the auth contract — without that, stop and say so rather than half-driving an app you can't log into.

A URL handed over without a completed login round-trip and a named record to look at is a **failure of this skill**, not a success. "It's running on port 5001" is setup, not a test drive.

## Project specifics — read these first

This skill is repo-agnostic, with Open Mercato as its known case. Gather the concrete details from the repository you're running in:

- **How to boot a throwaway instance** — the command that stands up a disposable app + database, where it records its base URL, and which credentials it guarantees. Open Mercato is resolved in Phase 2; for anything else, derive from the repo's `CLAUDE.md` / `AGENTS.md` / `package.json` scripts, or its **`## Skill profile`** section (the curated source) under the **Throwaway instance** knob.
- **How to authenticate against it** — the login route, its method and payload shape, and whether it returns a bearer token or sets a session cookie. Phases 3 and 5 are written around Open Mercato's `POST /api/auth/login` → `{token}`; **a repo that authenticates differently will boot and then fail every later phase**, so if its profile doesn't document the auth contract, stop and ask rather than guessing at a login route.
- **How a changed file maps to a URL** — the route directory convention or a generated route manifest. The click route is *derived* from the diff, so you need this before Phase 4.
- **How records get created through the real path** — the API route convention per module, or the UI form that owns each entity. You need this before Phase 5.

If a needed value isn't documented and you can't infer it, ask the user rather than guessing.

## Arguments

- **Empty** — the current worktree, as it stands. Diff target is the branch against the repo's default branch.
- **A PR number / URL** — `gh pr checkout <N>` first, and only into a clean tree. A dirty tree is a stop, not a stash: say what's uncommitted and let the user decide.
- **`--fresh`** — never attach to an already-running instance; always build a new one.
- **`--no-seed`** — skip Phase 5 and hand over against whatever data already exists.

## Hard rules

1. **Hand over nothing you haven't verified, and don't overclaim what you did verify.** Every URL in the click route must have been fetched *authenticated* and resolved. Every seeded record must have been read back through the app — the API when a route exists, and when it doesn't (the UI-form fallback in Phase 5) say plainly that the record is unverified and the user is confirming it themselves. But know the ceiling of a no-browser drive: you have proven the route resolves and the data persisted — **not** that the UI renders it. Say which of the two you checked; never let a 200 stand in for "the change works".
2. **Never write to the database directly.** Seed through the real API or the real UI form. A row inserted behind the app skips validation, events, and index/search updates — the app then treats it differently from a real record, and the drive demonstrates something that can't happen in production.
3. **Never seed against a database that isn't the throwaway one — and consent doesn't change that.** Before the first write, confirm the base URL is the instance this run booted (or one recorded in the ephemeral state file). If it's a long-lived or shared environment, do not offer to seed it "with permission": another developer's database is not disposable just because someone said yes. Drive it read-only with `--no-seed` and say what that costs, or stop. Seeding into someone's dev database is not recoverable by apologising.
4. **Don't demo a build you can't attribute — and you usually can't.** The ephemeral state file records `startedAt`, a port and a database URL, but **no source SHA or build digest**, so a timestamp newer than your checkout is not evidence: a process can start after the checkout and still serve stale build output. Treat provenance as unprovable and force a fresh instance after any branch switch or PR checkout. See the reuse trap in Phase 2 — it is the most likely way this skill lies to the user.
5. **Say what the drive can't show, from the environment you actually booted.** Open Mercato's ephemeral env disables outbound email, the scheduler and enterprise modules, while queue workers *do* run — so job-backed flows work and scheduled ones don't. Those specifics are Open Mercato's, not a property of throwaway instances in general: on any other profile, read the limitations off that environment rather than repeating this list. A click route that omits them invites the user to call a feature broken when it's merely switched off.
6. **Read-only on source — not on build output.** Never edit source, commit, push, or merge. Bootstrapping deliberately writes build artifacts: `yarn install` rewrites `node_modules`, `yarn generate` writes the generated registry, `build:packages` fills `dist/`. That is expected and unavoidable — the instance is built from this tree — but it is a real mutation of the user's checkout, so **tell them in the handover what was installed, generated or rebuilt, and which branch the checkout is left on.** The two genuine exceptions to read-only are `gh pr checkout` with an explicit PR argument, and that bootstrap. Never edit tracked configuration to make a boot work: an `.env` that blocks startup is fixed with environment overrides for the run, not by rewriting the user's file.
7. **The handover goes to the user.** This skill posts nothing to GitHub, Slack, or a tracker.

## Phases

### 1. Resolve the target

- **PR argument** → verify the tree is clean, then `gh pr checkout <N> --repo <owner/name>`. Pass `--repo` explicitly: a checkout with several remotes (a fork alongside its upstream) usually has no default repo set, and bare `gh pr checkout` just errors out. Take the change surface from `gh pr diff <N> --repo <owner/name>` — scope that call too, or an unqualified number can resolve a PR in the *other* repo of a fork/upstream pair.
- **No argument** → the current branch against the repo default (`git diff <default>...HEAD`; derive the default via `gh repo view --json defaultBranchRef` or `git symbolic-ref refs/remotes/origin/HEAD`). **Fetch the base first.** A local base ref is only as fresh as your last fetch, and a stale one silently turns a 15-file change into a 4,000-file diff — every conclusion drawn after that is wrong. **Include uncommitted work** (`git diff` and `git diff --staged` on top of the branch range): the instance is built from the working tree, so anything staged or unstaged is running in the app you hand over, and a surface derived from committed history alone would omit exactly the code the user is about to click on.

State the target and the HEAD sha + subject in one line before doing anything expensive, so the user can stop you if you picked the wrong thing. You'll need that sha again in Phase 2 and in the handover.

### 2. Boot a throwaway instance

**Resolve the boot command before checking anything.** The preconditions and the bootstrap below are Open Mercato's, and applying them to a repo that boots some other way would reject a perfectly good environment for lacking Node or Docker. Run the discovery ladder first; only if it lands on the Mercato rungs do the rest of this phase's specifics apply.

**Then check the preconditions**, reporting each failure with its fix rather than a stack trace:

- `node -v` → Open Mercato's ephemeral runner requires Node 24 or newer, and says so with a fix; check it yourself so the user hears it before the build starts, not after.
- `docker info` → must succeed. A non-standard runtime (Colima and friends) is auto-detected from the active Docker context; a dead daemon is not.

**Warn about the cost before starting, not after.** A cold boot runs the full initialize + production build pipeline: several minutes and RAM-heavy. Tell the user what they're waiting for.

**Bootstrap the tree before you run the ephemeral command.** It is not a from-zero installer — it assumes a repo that has already been installed and built once, and it runs `initialize` *before* its own codegen and build steps. On a freshly-installed tree, or after a checkout that changed the lockfile, it fails on missing artifacts with errors that name the symptom and not the cause. In the monorepo the required sequence is exactly what the root `build` script already encodes:

```bash
yarn install          # after any checkout that touches yarn.lock
yarn build:packages   # `yarn mercato` *is* packages/cli/dist/bin.js — it must exist to run at all
yarn generate         # writes the generated entity registry
yarn build:packages   # rebuild so the generated files land in dist/
```

Map the error you get back to the rung you skipped:

| Error | Missing rung |
|---|---|
| `Couldn't find the node_modules state file` | `yarn install` |
| `Cannot find module '.../packages/cli/dist/bin.js'` | `yarn build:packages` |
| `Cannot find module '.../packages/core/dist/generated/entities.ids.generated.js'` while "Bootstrapping application" | `yarn generate`, then `yarn build:packages` again |

Note the trap in the third: `initialize` applies every migration successfully and *then* dies, so a codegen problem presents as a database one. Don't reach for `--verbose` on any of these — it adds log volume, not the missing artifact.

**A throwaway instance runs in production mode, so dev-safe placeholders become hard failures.** `apps/mercato/.env` ships `JWT_SECRET=change-me-dev-secret` (straight out of `.env.example`), and the app's own production guard refuses to start on a known placeholder secret. The build succeeds, the server starts, and *then* it exits — the boot reports only `Application process exited before readiness check`, with the actual refusal buried in the app's stderr where you'll only see it under `--verbose`. Supply real secrets for the run instead:

```bash
JWT_SECRET=$(openssl rand -hex 32) AUTH_SECRET=$(openssl rand -hex 32) \
  yarn mercato test:ephemeral
```

Pass them in the environment; **do not edit the repo's `.env`** — it's the user's file and this skill is read-only on the tree (Hard rule 6). Treat any "exited before readiness" as this class of problem until `--verbose` proves otherwise: the app process failing *after* a clean build is a configuration refusal far more often than a code fault.

**Resolve the boot command** — first hit wins, and the last rung is a real probe rather than an assumption:

1. Root `package.json` has `test:integration:ephemeral:start` → `yarn test:integration:ephemeral:start`. This is the Open Mercato monorepo; the script wraps `mercato test:ephemeral`.
2. `yarn mercato test:ephemeral` (equivalently `yarn mercato test ephemeral`).
3. A `create-mercato-app` scaffold — no root ephemeral script, but `@open-mercato/cli` is installed under the app. Probe for the alias before using it: `yarn --cwd apps/mercato exec mercato --help`, then `yarn --cwd apps/mercato exec mercato test:ephemeral`.
4. The repo's own documented boot (`## Skill profile` → **Throwaway instance**, or `CLAUDE.md` / `AGENTS.md`). If that resolves to a **long-lived shared dev stack** rather than a disposable one, say so and drop to `--no-seed` for the rest of the run — do not ask for permission to write into it (Hard rule 3).

Useful flags: `--verbose` (full bootstrap/build logs — worth a re-run once the tree is bootstrapped and a boot still fails silently), `--no-reuse-env` (always a brand-new instance on an isolated port), `--no-screenshots` (irrelevant here; this skill doesn't drive a browser).

**Run it backgrounded.** The command holds the terminal until `Ctrl+C` — that's by design, it's what keeps the instance alive for the user.

**The reuse trap.** The ephemeral command silently *attaches* to an already-running instance recorded in `.ai/qa/ephemeral-env.json` when source mtimes and a build-cache TTL say it's still valid. After a branch switch or a `gh pr checkout`, that can hand you a running build of **different code** while everything looks fine.

You cannot verify your way out of this: the state file carries `startedAt`, a port and a database URL, but **no source SHA or build digest**, and a process that started after your checkout may still be serving output built before it. So don't try to reason from the timestamp — **after any branch switch or PR checkout, always pass `--no-reuse-env`** (`--fresh` does it for you). Reuse is only safe when you booted the instance yourself, in this run, from this tree.

One caveat on the escape hatch: `--no-reuse-env` takes the runner's setup lock and will not build a second instance while another ephemeral process holds it. If it blocks, report the lock owner and let the user stop it — don't promise a fresh instance you can't get.

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

Capture the token and fail loudly if it isn't there — a probe that prints the response and moves on can send `Bearer ` to the next call and still look like it passed:

```bash
TOKEN=$(curl -s -X POST "$BASE_URL/api/auth/login" \
  -H 'content-type: application/x-www-form-urlencoded' \
  --data-urlencode 'email=admin@acme.com' --data-urlencode 'password=secret' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("token",""))')
[ -n "$TOKEN" ] || { echo "login failed"; exit 1; }
```

Then **use the token** on a stable, always-present collection endpoint — *not* a route the change touches. Route discovery is Phase 4 and hasn't run yet, and a UI-only change may add no API route at all:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/<a known collection>"
```

A login that mints a token while every subsequent call returns 401 is exactly what this catches, and it's a failure the user would otherwise hit on their first click. Re-check the *changed* surfaces once Phase 4 has identified them, and accept whatever success status each one actually returns — a create is a 201, a delete often a 204, and demanding 200 everywhere would fail a working drive.

**Fetching pages, not just the API.** An authenticated page needs the login *cookie*, not the bearer token — grab a jar on login and reuse it:

```bash
JAR=$(mktemp); trap 'rm -f "$JAR"' EXIT      # a live session credential — never in the worktree
curl -s -c "$JAR" -X POST "$BASE_URL/api/auth/login" \
  -H 'content-type: application/x-www-form-urlencoded' \
  --data-urlencode 'email=admin@acme.com' --data-urlencode 'password=secret' -o /dev/null
curl -s -b "$JAR" -o /dev/null -w '%{http_code}\n' "$BASE_URL/backend/<path>"
```

The jar holds a working session for the whole drive. Put it in `mktemp` and delete it on exit — written into the repo it is one `git add -A` away from being published. (The cookies come back flagged `Secure` even on `http://127.0.0.1`; curl sends them anyway because it treats loopback as a secure context, so no HTTPS workaround is needed. If a future curl tightens that, the symptom is a 307 with the jar — not a silent pass.)

Read the status codes correctly, or you'll report working things as broken and broken things as fine:
- **`307`/`302` on an anonymous `/backend` fetch is correct** — that's the login redirect, not a failure.
- **`200` with the cookie means the route exists and you're authenticated. It does not mean the change rendered.** The backend is a client-rendered app: the detail page returns over a megabyte of shell HTML and fetches its data afterwards, so grepping that HTML for your seeded values finds nothing even when everything works. Prove the data at the API layer and be explicit in the handover that rendering is the user's job to confirm.

- Credentials the ephemeral env guarantees: `admin@acme.com`, `superadmin@acme.com`, `employee@acme.com`, all with password `secret` (it pins the init passwords). **The guarantee is ephemeral-only** — in a normal environment the companion account passwords are randomly generated, so never present these as universal.
- The login route is rate-limited (a handful of attempts per minute per email). A `429` means back off, not bad credentials — do not loop on it.
- Keep the token for Phase 5. Never put it in the handover.

### 4. Read the change

Enough to say what it does in product terms — and, more importantly, to name **the user-visible surfaces it touches**. That list is what the click route is built from.

- Take the changed-file list from `gh pr diff <N> --name-only` (or a freshly-fetched base), then map each file to a route with the repo's convention. In Open Mercato a module's `backend/<path>/page.tsx` is `/backend/<path>`, and detail pages re-export each other — `sales/orders/[id]` renders the `sales/documents/[id]` component, so one changed component surfaces under several routes.
- Don't guess a URL; a 404 in the handover destroys the user's trust in everything else in it.
- Pull the linked ticket if the branch or PR references one — it usually states the change in exactly the user terms you want.
- If the change has **no UI surface** (a worker, a migration, an API-only change), say so plainly and route the drive through the API or CLI instead of inventing a screen.

For a full merge-decision writeup — scenarios, what's tested, residual risk — that's `explain`. This is the short version that feeds the route.

### 5. Seed what the change needs

Skip if `--no-seed`.

1. **Ask what state makes the change visible.** An order in a particular status, a product with a variant, a customer carrying the new field. The change is only demonstrable against data that exercises it.
2. **If the change ships an integration or e2e spec, read it first.** It is the author's own recipe for the state the change needs — exact route, exact payload, exact read-back — and reusing it means your seed exercises the path they intended rather than one you invented.
3. **Check what already exists first.** Open Mercato's initialize seeds a tenant plus demo customers, catalog, sales, and todos. An existing record that fits beats a new one, and it keeps the click route shorter. (Outside an ephemeral instance, never *assume* demo data is present — verify.)
4. **Create through the real API.** Discover the route from the changed module's own `api/` directory rather than guessing it, then `POST` with the bearer token and `Content-Type: application/json`.
5. **Read every record back** with a separate `GET`. Trusting the create response is how you hand over a record that isn't really there — or one the app can't find because an index never updated.
6. **No API route for it?** Put the UI form into the click route as step 0, with the exact fields to fill. Do not fake it in the database (Hard rule 2).

For each seeded record, note its **human-visible identifier** (name, number, title) and the **backend URL where the user will find it**. That pairing is what makes the handover clickable rather than a description.

### 6. Write the handover

The deliverable. Inline in your final message:

```markdown
# Test drive: <change in one line>

## Instance
- URL: <baseUrl>/<app path> — port <n>, built from <sha> "<subject>"
- Login: <the credentials the booted profile guarantees; Open Mercato's ephemeral env pins admin@acme.com / secret>
  Verified: <method> <auth route> → <status>; <method> <checked route> → <status>
- Stop it: <exact command>. <If this run booted the instance: destroys the container and everything
  seeded below. If it attached to one already running: Ctrl+C only detaches — the runtime and the
  seeded data stay up for its owner.>
- Left in your checkout: <branch now checked out; what bootstrap installed / generated / rebuilt>

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
- Rendering is unverified — this drive proved the route resolves and the data persisted
  through the API, not that the component paints it. That's the first thing to check.
- <the booted environment's own switched-off surfaces. Open Mercato's ephemeral env: no outbound
  email (delivery disabled); scheduled jobs won't fire (scheduler off, though queue workers run,
  so job-backed flows do work); enterprise modules off; CRUD API caching on>
- <anything specific to this change you couldn't set up>
```

Writing rules:
- Every URL is one you fetched authenticated. Every record is one you read back. Neither is a claim about what the screen looks like.
- Say what the user should *see*, not just where to go. "Order ACME-1042 now shows a Partially shipped badge" beats "check the orders list".
- Be honest about what you couldn't set up. A missing step named is useful; a missing step hidden wastes the user's afternoon.

### 7. Hand over

Leave the instance running — that's the point of the skill. Give the exact way to stop it, and describe stopping **as it will actually behave**: if this run booted the instance, stopping destroys the container and everything seeded; if it attached to one already running, `Ctrl+C` merely detaches and the runtime survives for whoever owns it. Telling a user their data was destroyed when it is still live — or the reverse — is a small lie with real consequences.

Say what the run changed in their checkout, too: the branch it left them on, and whatever the bootstrap installed, generated or rebuilt (Hard rule 6).

## Things to remember

- A reused instance is someone else's build, and the state file gives you nothing to prove otherwise. After a branch switch, boot fresh.
- A 200 from login is not proof of authorization — make one authenticated call.
- Demo data is a starting point, never an assumption.
- If the click route contains no seeded or named record, the drive probably shows nothing.
- The first boot is slow. Warn before, not after.
- "Exited before readiness" is the app refusing its own config, not the harness failing. Read its stderr before blaming the change.
- A 200 from a client-rendered page proves routing and auth, nothing about the change. Don't grep the HTML and call it verified.
- A URL you didn't fetch is a guess wearing a link.
- If the change has no screen, say so — don't send the user hunting for one.
