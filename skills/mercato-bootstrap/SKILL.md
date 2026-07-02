---
name: mercato-bootstrap
description: Bootstrap an Open Mercato application into a monorepo following FullstackHouse conventions — scaffold via create-mercato-app, allocate non-clashing local infra ports, bring up Postgres/pgvector + Redis + Meilisearch, run the generate/migrate/initialize sequence, verify the dev server boots, and drop in conductor + CI (Slack-on-failure, preview environments, and OpenTofu infra patterns). Use when setting up a new Open Mercato app, adding apps/mercato to a repo, or standing up an Open Mercato dev environment.
---

# Bootstrap Open Mercato (FSH conventions)

Stands up a standalone Open Mercato app (`apps/mercato`) that consumes the published
`@open-mercato/*` npm packages. The repo root stays a **thin monorepo** that delegates to
the app. This is the **edube pattern** and the recommended layout for client engagements.

## When to use
- "Set up Open Mercato for dev", "scaffold apps/mercato", "bootstrap a new Mercato project".
- NOT for editing an existing Mercato app's modules/features — that's the app's own `AGENTS.md`.

## Decisions to settle first (ask the user if unset)
- **Preset** (`--preset`): `empty` (default — clean core only; enable commerce modules
  deliberately) · `classic` (full commerce suite + 2 example modules to strip — good for
  fast demos) · `crm`. For bespoke client products prefer **`empty`**.
- **Hosting target** (only needed for the infra/deploy step, not for dev): GCP Cloud Run
  (covo/edube precedent, simplest) vs Hetzner k3s (tournee). Defer if dev-only.
- Packages are **public on npm** — no private registry/auth needed.

## Prerequisites
Run the bundled check: `bash scripts/preflight.sh` — requires **Node ≥ 24**, **Docker
running**, **corepack** (provides yarn 4 via the app's `packageManager`). Global yarn may
be 1.x; always invoke the app with `corepack yarn …`.

## Steps

### 1. Scaffold into `apps/mercato`
```bash
mkdir -p apps && cd apps
npx create-mercato-app@latest mercato --preset empty --skip-agentic-setup --no-init-git
```
- `--skip-agentic-setup`: the agentic wizard is a create-time AI/editor/MCP config step; skip
  for reproducibility (the app already ships `AGENTS.md` + `CLAUDE.md`). It is NOT the app
  CLI — `mercato agentic` does not exist in the runtime.
- `--no-init-git`: never nest a git repo inside the monorepo.
- Pins `@open-mercato/* @ latest` (0.6.x) in `apps/mercato/package.json`.

### 2. Reconcile with the monorepo root
- Keep a **thin root `package.json`** that proxies to the app (`yarn --cwd apps/mercato <script>`
  for setup/dev/build/lint/typecheck/test/generate/db:migrate/initialize).
- Install the **conductor per-worktree isolation** system from `templates/conductor/` (replace
  `{{PROJECT_SLUG}}` with a machine-unique compose project name, e.g. `groomershop-mercato`):
  - `settings.toml` → `.conductor/settings.toml` (concurrent `setup` + `run` hooks).
  - `conductor-setup.sh` / `conductor-run.sh` → `scripts/`.
  - `conductor-db.mjs` → `apps/mercato/scripts/` (maintenance-level create/clone/drop SQL).
  - `.worktreeinclude` → repo root (copies `.env` per worktree instead of symlinking, so each
    worktree's `DATABASE_URL` rewrite stays local).
  - All worktrees **share one docker stack**, but **each gets its own database**. Setup keeps a
    project **template DB** (named after the compose project, e.g. `groomershop_mercato`; migrated
    + seeded once) and CLONES each worktree's DB from it (`CREATE DATABASE <worktree> TEMPLATE
    <project>`) — so a new worktree is ready in seconds, **already seeded, with no per-worktree
    `yarn initialize` reseed**. The worktree DB name is derived from its folder (so it never
    collides with the template); the app port is per-worktree via `$CONDUCTOR_PORT`.
  - Prereq: the scaffold's `apps/mercato/scripts/dev-database-url.mjs` (ships with
    create-mercato-app) — the hooks reuse its `deriveDatabaseNameFromCwd` / `rewriteDatabaseUrl`
    / `validateDatabaseName` helpers. (The older single-shared-DB `conductor.json` is superseded
    by this per-worktree system.)

### 3. Allocate non-clashing infra ports  ← critical on multi-project machines
The framework defaults (Postgres 5432 / Redis 6379 / Meilisearch 7700) collide with any other
running Mercato stack. Pick a free block and pin it **per project**:
```bash
bash scripts/pick-ports.sh        # prints POSTGRES_PORT / REDIS_PORT / MEILISEARCH_PORT
```
Then in `apps/mercato/.env` set those three vars AND update `DATABASE_URL`'s host port to match.
(`docker-compose.yml` reads `${POSTGRES_PORT:-5432}` etc., so the container binds the chosen ports.)

### 4. Env
```bash
cd apps/mercato && cp .env.example .env   # then apply the port remap from step 3
```
Dev defaults (`JWT_SECRET=change-me-…`, etc.) are fine for local. Note the printed
`TENANT_DATA_ENCRYPTION_FALLBACK_KEY` — fine for dev, must be a real secret for prod.

### 5. Bring up infra + initialize
```bash
docker compose up -d                 # Postgres(+pgvector) / Redis / Meilisearch
corepack yarn install                # if not already
corepack yarn generate               # codegen (entities, DI, OpenAPI, …)
corepack yarn db:migrate             # all module migrations
corepack yarn initialize             # seeds tenant + admin/superadmin/employee (prints logins)
```
Wait for `docker inspect -f '{{.State.Health.Status}}' <project>-postgres-1` = `healthy`
before `db:migrate`.

### 6. Verify
```bash
corepack yarn dev &                  # http://localhost:3000
bash scripts/verify.sh               # asserts / = 200 and /backend = 200/redirect
```
Log in at `/backend` with the seeded `admin@acme.com` / `secret`. First dev compile is
RAM-heavy (~10–14 GB) and slow — normal. Stop the server after verifying.

### 7. Brand the app  ← rename the display title to the client's brand
The scaffold ships **"Open Mercato"** as the app's display/document title. Rebrand it to the
engagement's brand (ask the user for `{{APP_BRAND}}`, e.g. `Groomershop`, `Edube`, `FSH Mercato`).

**Critical: brand ≠ package.** Change only the *display/document title*; never touch the
framework's package identity or install references — a blind find-and-replace of "Open Mercato"
breaks npm packages and install links.

- **Rebrand** these (locate them — scaffold versions drift; these are the known touchpoints):
  - i18n (each locale in `src/i18n/*.json`): `app.metadata.title`, `app.page.title`,
    `app.page.logoAlt`, `appShell.productName`; brand-swap inside `app.title`, `api.docs.title`.
  - Hardcoded fallbacks: `src/app/layout.tsx`, `src/lib/metadata.ts`,
    `src/app/(backend)/backend/layout.tsx`, `src/app/api/docs/{openapi,markdown}/route.ts`.
- **Leave intact** (these name the OSS framework, not the brand):
  - `@open-mercato/*` npm packages, the package/dir name, and any `npm install` references.
  - Demo/onboarding copy that links to the framework: `startPage.*`, `notices.demo.installLink`.
- Re-validate each edited locale JSON. Confirm `grep -ri "open mercato"` only matches the
  intentional framework/install references above.
- **Out of the app's reach:** a few runtime strings — notably the **login-page brand** and the
  **transactional email footer** — come from the `@open-mercato/*` **package** i18n defaults, not
  `src/i18n/*.json`, so this rebrand can't touch them; they keep showing "Open Mercato". Override
  them **per-tenant via directory branding settings** if the client needs it. Don't chase them in
  `src` — set the right scope expectation up front (they surfaced as a "why does it still say Open
  Mercato" loop otherwise).

### 8. Strip example modules (only if preset = `classic`)
Prod FSH apps ship **none**. `empty` already has none — skip this step.
For `classic`: remove the `example` and `example_customers_sync` entries from
`src/modules.ts`, `rm -rf src/modules/example*`, then `yarn generate`. Because the example
migrations already ran, the cleanest dev reset is to recreate the DB:
`docker compose down -v && docker compose up -d` then redo step 5 (migrate + initialize).

### 9. CI / CD — add the target-agnostic parts now, defer the rest
**Now (no hosting decision needed):**
- Add `templates/ci.yml` → `.github/workflows/ci.yml` (Node 24 + corepack →
  install/generate/db:migrate/lint/typecheck/test/build against a pgvector Postgres service).
  It already includes the FSH **Slack-on-failure** job (push-to-main) — set org/repo secret
  `FSH_SLACK_BOT_TOKEN` (or delete that job). See Slack pattern in `references/ci-cd.md`.
- Optionally install `templates/notify-slack-on-failure.action.yml` →
  `.github/actions/notify-slack-on-failure/action.yml` (reusable composite — preferred over
  copy-pasting the slack step across deploy/cleanup workflows).
- The CI `lint` step fails on a stock empty-preset scaffold — apply the `yarn lint` fix from the
  Gotchas table (pin `eslint ^9`, install `templates/eslint.config.mjs`, `lint = eslint .`) so
  the step is green out of the box.

**After the hosting target is chosen — full CD (deploy + preview environments):**
See **`references/ci-cd.md`** for the complete, ported-from-edube pattern:
- Reusable `deploy.yml` (build→migrate→deploy→healthcheck) + `deploy-prod.yml`/`deploy-dev.yml`.
- **Preview environments**: per-PR service `{app}-pr-{N}` + isolated DB `mercato_pr_{N}`
  (URL-rewrite trick), PR-comment with the URL, `deploy-preview.yml` (create) /
  `delete-preview.yml` (PR-close teardown, race-protected) / `cleanup-previews.yml` (nightly
  sweep) / `scale-down-previews.yml` (idle → min-instances=0).
- **Infra conventions** (universal): **OpenTofu** (`tofu`, not `terraform`), GCS state backend,
  `infra/` at repo root = `bootstrap/` + `_common/modules/` + `dev/` (+ `prod/` later),
  GCP Secret Manager (`{prefix}-{name}`), GitHub OIDC / Workload Identity (no long-lived keys).
- Targets: GCP Cloud Run + Cloud SQL + Memorystore (covo, edube — recommended default) vs
  Hetzner k3s + CloudNativePG (tournee). Port modules from the matching repo.

### 10. Commit
Commit `apps/mercato/` (incl. `yarn.lock`) + root `package.json` + the conductor system
(`.conductor/settings.toml`, `scripts/conductor-*.sh`, `apps/mercato/scripts/conductor-db.mjs`,
`.worktreeinclude`) + CI. Confirm `.env`, `node_modules`, `.mercato/generated` are gitignored.
Conventional Commits.

## Gotchas
| Symptom | Cause / fix |
|---|---|
| `Bind for 0.0.0.0:7700 failed: port is already allocated` | Another Mercato stack owns default ports → do step 3 (pick-ports). |
| `yarn` runs 1.x / wrong version | Use `corepack yarn …`; run `corepack enable` once. |
| `db:migrate` hangs/errors on connect | Postgres not healthy yet, or `.env` port ≠ compose port. |
| `mercato agentic …` "Module not found" | Expected — agentic setup is create-time only, not a runtime CLI command. |
| Orphan `example_*` tables after classic cleanup | Recreate the dev DB (`docker compose down -v`) — see step 8. |
| "Demo environment" banner on a **deployed** env | `DEMO_MODE` defaults ON unless explicitly `"false"`. `.env.example` sets it false (local is clean), but `gcloud run deploy --set-env-vars` replaces env — add `DEMO_MODE=false` to the deploy command (and the tofu service env). |
| `yarn lint` fails: `next lint` "Invalid project directory" or eslint-plugin-react `getFilename is not a function` | Empty preset ships `lint = next lint` (removed in Next 16) and mis-pins `eslint ^10` (incompatible with eslint-config-next 16's react plugin). Fix: set `eslint ^9`, install `templates/eslint.config.mjs` (flat config importing `eslint-config-next/core-web-vitals` + `/typescript`), set `lint = eslint .`. **Scope, don't blanket, the rule relaxations:** downgrade the newer react-hooks/TS rules the vendored scaffold trips to `warn` **only for `src/app/**` + `src/components/**`** (upstream scaffold code) so your own `src/modules/**` + `src/lib/**` keep the strict defaults — a global downgrade silently kills `no-explicit-any` for your code too. The shipped template already scopes it this way. |

## Reference repos (FSH)
- `edube` — thin app-only monorepo (this pattern). `tournee` — polyglot + Hetzner k3s.
  `covo` — vendored framework fork + GCP. Use them for CI/infra module sources.
