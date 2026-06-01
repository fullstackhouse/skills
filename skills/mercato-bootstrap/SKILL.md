---
name: mercato-bootstrap
description: Bootstrap an Open Mercato application into a monorepo following FullstackHouse conventions — scaffold via create-mercato-app, allocate non-clashing local infra ports, bring up Postgres/pgvector + Redis + Meilisearch, run the generate/migrate/initialize sequence, verify the dev server boots, and drop in conductor + CI (and optionally OpenTofu infra). Use when setting up a new Open Mercato app, adding apps/mercato to a repo, or standing up an Open Mercato dev environment.
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
- Install `templates/conductor.json` at the repo root, replacing `{{PROJECT_SLUG}}` with a
  machine-unique compose project name (e.g. `groomershop-mercato`). This makes conductor
  worktrees **share one docker stack + DB** (rooted at `CONDUCTOR_ROOT_PATH`) and gives each
  worktree a unique app port via `$CONDUCTOR_PORT`.

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

### 7. Strip example modules (only if preset = `classic`)
Prod FSH apps ship **none**. `empty` already has none — skip this step.
For `classic`: remove the `example` and `example_customers_sync` entries from
`src/modules.ts`, `rm -rf src/modules/example*`, then `yarn generate`. Because the example
migrations already ran, the cleanest dev reset is to recreate the DB:
`docker compose down -v && docker compose up -d` then redo step 5 (migrate + initialize).

### 8. CI (and optionally infra) — target-agnostic first
- Add `templates/ci.yml` → `.github/workflows/ci.yml` (Node 24 + corepack →
  install/generate/db:migrate/lint/typecheck/test/build against a pgvector Postgres service).
  This is safe to add immediately; no hosting decision required.
- **Deploy + infra** depend on the hosting target. FSH precedent:
  - GCP Cloud Run + Cloud SQL + Memorystore (covo, edube) — simplest, recommended default.
  - Hetzner k3s + CloudNativePG (tournee) — heavier, uses `tofu`/OpenTofu.
  - Universal infra conventions: **OpenTofu** (`tofu`, not `terraform`), GCS state backend,
    `infra/` at repo root with `bootstrap/` + `_common/modules/` + `dev/` (+ `prod/` later),
    GCP Secret Manager, GitHub OIDC / Workload Identity (no long-lived keys).
  Defer until the user picks a target, then port the modules from covo/edube (GCP) or
  tournee (Hetzner).

### 9. Commit
Commit `apps/mercato/` (incl. `yarn.lock`) + root `conductor.json`/`package.json` + CI.
Confirm `.env`, `node_modules`, `.mercato/generated` are gitignored. Conventional Commits.

## Gotchas
| Symptom | Cause / fix |
|---|---|
| `Bind for 0.0.0.0:7700 failed: port is already allocated` | Another Mercato stack owns default ports → do step 3 (pick-ports). |
| `yarn` runs 1.x / wrong version | Use `corepack yarn …`; run `corepack enable` once. |
| `db:migrate` hangs/errors on connect | Postgres not healthy yet, or `.env` port ≠ compose port. |
| `mercato agentic …` "Module not found" | Expected — agentic setup is create-time only, not a runtime CLI command. |
| Orphan `example_*` tables after classic cleanup | Recreate the dev DB (`docker compose down -v`) — see step 7. |

## Reference repos (FSH)
- `edube` — thin app-only monorepo (this pattern). `tournee` — polyglot + Hetzner k3s.
  `covo` — vendored framework fork + GCP. Use them for CI/infra module sources.
