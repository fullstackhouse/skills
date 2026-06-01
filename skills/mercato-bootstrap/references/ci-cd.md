# CI/CD reference — FSH Open Mercato

The full delivery layer beyond the baseline `ci.yml`. Distilled from **edube** (canonical
GCP Cloud Run implementation) and **covo**. Add this once a hosting target is chosen; the
**patterns** here are provider-agnostic, the **commands** are the GCP concretion to port.

## Workflow set (edube)

| Workflow | Trigger | Purpose | Slack on fail |
|---|---|---|---|
| `ci.yml` | PR, push main | lint/typecheck/test/build (see `templates/ci.yml`) | yes (push main) |
| `deploy.yml` | `workflow_call` | **reusable** build→migrate→deploy→healthcheck | — |
| `deploy-prod.yml` | push `main`, dispatch | prod deploy (+ structural cache purge) | yes |
| `deploy-preview.yml` | PR opened/sync/reopen | per-PR env (service + isolated DB) | — |
| `delete-preview.yml` | PR closed, dispatch | tear down one PR's env | yes |
| `cleanup-previews.yml` | cron `0 2 * * *`, dispatch | nightly sweep of stale envs (closed PRs) | yes |
| `scale-down-previews.yml` | cron `0 3 * * *`, dispatch | scale idle previews to min-instances=0 | — |

> covo adds `deploy-dev.yml` (push main → dev) and runs preview cleanup weekly. edube has no
> dev env (prod + previews only). Pick per project.

## Reusable `deploy.yml` interface

```yaml
inputs:
  environment:     # GitHub Environment name: "prod" | "dev" | "pr-42"
  service_prefix:  # service name: "edube-prod" | "edube-pr-42"
  image_tag:       # "edube-prod:<sha>" | "pr-42-<sha>"
  db_name:         # "mercato" (prod) | "mercato_pr_42" (preview)  ← preview detected by != mercato
  enable_redis:    # default true (attaches VPC connector)
  queue_strategy:  # "async" (prod) | "local" (preview)
  cache_strategy:  # "redis" (prod) | "memory" (preview)
  secrets_prefix:  # default = service_prefix; scopes Secret Manager lookups
```
Logic: preview (`db_name != mercato`) → `yarn db:migrate:preview` (clones DB first); prod →
`yarn db:migrate`. Health check loops `GET /api/health/ready` 30× / 5s. Autoscaling: prod
`min=1,max=10,4Gi,2cpu`; non-prod `min=0,max=5,2Gi,1cpu`.

## Preview environment pattern

**Naming (the backbone):**
```
service  = {app}-pr-{N}
database = {default_db}_pr_{N}     e.g. mercato_pr_42
image    = pr-{N}-{sha}
```

### Create (`deploy-preview.yml`, on PR open/sync/reopen)
1. Auth (GCP workload identity) → build & push image (registry layer cache).
2. **Isolated DB:** one Cloud SQL instance hosts all preview DBs. Build the URL by rewriting
   the base secret — no per-DB creds:
   ```bash
   BASE=$(gcloud secrets versions access latest --secret="${PREFIX}-database-url")
   DATABASE_URL="${BASE%/mercato}/${DB_NAME}"     # …/mercato_pr_42
   ```
   Run migrations as a **Cloud Run Job** with `yarn db:migrate:preview` (clones then migrates).
3. Optional setup job: reset `superadmin@acme.com` password for manual testing.
4. Deploy service: `APP_ENV=preview`, `QUEUE_STRATEGY=local`, `CACHE_STRATEGY=memory`,
   `min-instances=0` (cost), attachments via GCS volume mount.
5. Health check → **comment the URL on the PR** (update the existing bot comment) + create a
   GitHub Deployment with `transient-environment: true`.

### Teardown (`delete-preview.yml`, on PR closed)
1. **Cancel in-flight** `deploy-preview` runs for the head branch (race protection), sleep 30s.
2. Delete service `{app}-pr-{N}` (retry 4× / 30s — a cancelled deploy may still create it).
3. Delete Cloud Run jobs matching `^{app}-pr-{N}(-.+)?$` (catches `-migrations`, `-set-password`).
4. Delete Artifact Registry images under `{app}-pr-{N}`.
5. Drop the DB via an **ephemeral cleanup job** running `yarn db:cleanup-orphaned`, passing
   `OPEN_PR_NUMBERS` so other PRs' DBs are preserved; delete the job after (capture rc, then
   propagate). Use `--set-env-vars "^@^OPEN_PR_NUMBERS=1,2,42"` (`^@^` = `@` delimiter, since
   the value contains commas).

### Eventual-consistency sweep (`cleanup-previews.yml`, nightly 2am)
Enumerate services/jobs/images/DBs, cross-reference open PRs (GitHub API), delete anything
whose PR is closed. Same ephemeral-job DB cleanup. This is the safety net for races the
on-close delete missed.

### Cost control (`scale-down-previews.yml`, nightly 3am)
For each `{app}-pr-*` service: if `min-instances>0` and no HTTP requests in the last 24h
(Cloud Logging query) → set `min-instances=0`.

**Key gotchas:** (1) race between PR-close and queued deploy → cancel + retry; (2) ephemeral
jobs MUST be deleted after running or they accumulate; (3) preview passes `DATABASE_URL` as an
env var (computed at deploy time) while prod injects it via `--set-secrets`.

## Slack-on-failure pattern

Action: **`fullstackhouse/slack-notify-action@v1`** (FSH-owned). Two credential modes:
- **bot-token** (edube): `bot-token: ${{ secrets.FSH_SLACK_BOT_TOKEN }}` + `channel: "#fsh-alerts"`.
- **webhook** (covo): `webhook-url: ${{ vars.SLACK_WEBHOOK_URL }}` (a `vars`, not a secret).

Always a separate job `notify-failure` with `if: failure()` + `needs: [<job>]`. Triggers:
CI guards on push-to-main (`&& github.ref == 'refs/heads/main'`); deploy/cleanup/delete fire on
any failure. Message templating uses
`${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}` (run link),
`${{ github.ref_name }}`, and `${{ github.event.pull_request.number || inputs.pr_number }}`.

The pattern is copy-pasted ~7× across edube+covo with **no composite action**. This skill ships
one (`templates/notify-slack-on-failure.action.yml`) to centralize it — prefer it for new repos.

**Secrets to configure** (org-level recommended): `FSH_SLACK_BOT_TOKEN` (xoxb-…, bot-token mode)
or `SLACK_WEBHOOK_URL` (webhook mode).

## Porting checklist (once hosting target is chosen)
- [ ] Copy `deploy.yml` + `deploy-prod.yml` (+ `deploy-dev.yml` if you want a dev env) from edube/covo; swap project/region/service/secret-prefix.
- [ ] Copy the 4 preview workflows; rename `{app}` → your service prefix.
- [ ] Install `templates/notify-slack-on-failure.action.yml` → `.github/actions/…`; wire `FSH_SLACK_BOT_TOKEN`.
- [ ] Set up GCP: Workload Identity pool + provider, Artifact Registry, Cloud SQL, Secret Manager (`{prefix}-{name}`), VPC connector for Redis. (Hetzner variant: port tournee's k3s deploy instead.)
- [ ] Confirm the app exposes `/api/health/ready`.
