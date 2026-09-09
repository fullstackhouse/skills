---
name: blacksmith
description: Migrate a repository's GitHub Actions workflows to Blacksmith runners — inventory every job, move the ones that build, run or test the app (image builds get the sticky-disk Docker actions), leave glue, deploy and credential-bound jobs on GitHub, capture a timing baseline, and hand off to `deliver --no-merge` with the decision table in the PR. Use when asked to "move CI to Blacksmith", "cut GitHub Actions spend", "make the image build faster", or right after the Blacksmith app was installed on an org. Args: a repo path (default: the current repo), plus `--audit-only` to print the decision table and write nothing.
---

# blacksmith

You are running the **blacksmith** skill. Goal: move the *compute* in a repo's CI onto Blacksmith runners, move nothing else, and leave behind the numbers that prove it paid off.

The policy below was bought with measurements on an FSH monorepo, recorded in [`references/policy.md`](./references/policy.md) — read it before Phase 2. The short version: CI image builds are bound by moving bytes, not computing them, so bare metal with a local layer cache cut one build 12.4 → 3.6 min (hardware −53%, sticky disk a further −33%). Test and e2e jobs gained 12–44%. Sub-minute glue gained nothing and became one more thing that can wedge a repo.

Blacksmith is the house route; running our own runners was weighed and rejected. Don't re-litigate it here.

## 0. Gate

- **The Blacksmith GitHub App must be installed on the org.** Their runners register through GitHub's org-level runner API; without the app every `blacksmith-*` job queues until GitHub times it out instead of failing fast.

  ```bash
  ORG=$(gh repo view --json owner -q .owner.login)
  gh api "/orgs/$ORG/installations" -q '.installations[].app_slug' | grep -qx blacksmith-sh && echo installed
  ```

  Not installed → stop and say so (app.blacksmith.sh, org scope, all repos or this one). `--audit-only` may continue; a write run may not.
- `gh auth status` must pass; `actionlint` must be on PATH (`brew install actionlint`) for Phase 4.
- **Ownership** (`git remote -v`). In a client's repo, every migrated job's secrets will be read on a third party's hardware — a subprocessor question, not a technical one. Proceed, but the report names those jobs (Phase 2 "ask" list) so the owner can veto.

## 1. Inventory and baseline

```bash
"${CLAUDE_SKILL_DIR}/scripts/inventory.sh" [repo-path] | tee /tmp/blacksmith-inventory.md
"${CLAUDE_SKILL_DIR}/scripts/ci-timing.sh" | tee /tmp/blacksmith-baseline.txt
```

- `inventory.sh` — one row per job: current label, mapped label, timeout, the signals it classifies on, and a *suggested* verdict with its reason. Suggestions are heuristics; you judge every row, and `REVIEW` rows you read in full.
- `ci-timing.sh` — wall-clock and priced cost per workflow and runner label over the last 14 days. This is the "before". Reusable workflows report no runs of their own — their jobs bill under the caller — so the numbers sit on calling workflows.
- **Callers.** A job that `uses: ./.github/workflows/x.yml` has no `runs-on`; the edit lands in the callee. A callee shared by preview and prod callers moves both — fine for a build, and a deploy callee stays anyway.

## 2. Classify

One question decides most rows: **does this job build, run or test the app, and take long enough to matter?** Yes → migrate. No → stay.

**Migrate** — same vCPU count, never re-sized, so the before/after measures hardware and not sizing:

| Job shape | Also |
|---|---|
| Docker image build (`docker/setup-buildx-action` + `docker/build-push-action`) | swap to the Blacksmith actions, Phase 3 |
| Unit / lint / typecheck / build (a toolchain setup step, no services) | — |
| Tests with `services:` containers | — |
| Browser e2e (Playwright, `container:` images) | — |
| A long CPU-bound step inside a deploy workflow (e.g. `eas update`, which bundles before it uploads) | move that job only; its `kubectl` siblings stay |

**Stay** — leave the YAML untouched, give the reason in the table:

- Short, and neither builds nor runs the app: the branch-protection required check, `if: always()` joiners, `notify-failure`, PR commenters, `paths-filter` jobs, cancel-workflows, labelers, deployment bookkeeping, config computation. Seconds of runtime, so nothing to gain — and the merge gate in particular should sit on the most boring infrastructure available.
- Waits on an external system: `kubectl rollout status`, Cloud Run deploys, health checks, cron pollers. Faster cores buy nothing, and there is no reason to hand a third-party runner the cluster kubeconfig for no gain.
- `self-hosted` or an unknown custom label. It is on that hardware for a reason — cluster LAN, on-disk kubeconfig.
- Machine-local or network-scoped credentials: `KUBECONFIG` pointing at a file on the runner, a WireGuard or tailscale/headscale join into someone's LAN, SSH to a host that allowlists the runner's IP.
- **A self-triggering workflow that has been dormant** (lists itself in `paths:` and hasn't run in 60+ days — the inventory flags these). Listing itself is normal; dormancy is the problem: your edit runs it for the first time in months, and a pre-existing failure then looks like yours. If it fails on something unrelated to runners, revert that file to byte-identical, report the failure, and don't fix it here — not even with a comment in the file, because the comment is an edit and re-fires it.

**Ask once**, in a single `AskUserQuestion`, with the numbers beside each item:

- Fused build + deploy jobs (buildx *and* kubectl/gcloud/ssh in one job). Recommend splitting into a reusable build workflow plus a deploy job; if declined, the job stays.
- Test jobs holding cloud-federation credentials (`google-github-actions/auth` with workload identity, OIDC → kubeconfig). Default: migrate — that trade has been accepted in-house — but list them explicitly so a client-repo owner can say no.

`--audit-only` stops here: print the decision table and the baseline, write nothing.

## 3. Rewrite

**Labels.** Match on vCPU, keep the OS version:

| From | To |
|---|---|
| `ubuntu-latest`, `ubuntu-24.04` | `blacksmith-2vcpu-ubuntu-2404` |
| `ubuntu-22.04` | `blacksmith-2vcpu-ubuntu-2204` |
| `ubuntu-latest-{4,8,16}-cores` | `blacksmith-{4,8,16}vcpu-ubuntu-2404` |
| `ubuntu-24.04-arm` | `blacksmith-2vcpu-ubuntu-2404-arm` |
| `windows-latest` / `macos-latest` | `blacksmith-2vcpu-windows-2025` / `blacksmith-6vcpu-macos-latest` |

**Image builds.** Changing `runs-on` alone does *not* enable layer caching. Replace both Docker actions and delete the external cache:

```yaml
      # Mounts the org's sticky disk as the buildkit layer store, so a restore is a
      # local NVMe read rather than a registry pull. `cache-key` namespaces these
      # layers away from every other image in the org and is deliberately a constant —
      # buildkit invalidates layers itself; keying on the Dockerfile would discard the
      # whole cache on every edit.
      - name: Set up Docker Buildx (Blacksmith sticky disk)
        uses: useblacksmith/setup-docker-builder@v2
        with:
          cache-key: {{REPO}}-{{IMAGE}}

      # No cache-from/cache-to: the sticky disk replaces them, and exporting to the
      # registry as well would re-incur the network cost the disk exists to remove.
      - name: Build and push
        uses: useblacksmith/build-push-action@v2
        with:            # context, file, target, push, tags, build-args, platforms: unchanged
```

Keep any "free runner disk space" step — it still guards the image's own size. Multi-platform builds: one job per platform on the matching runner (`…-arm` for arm64), no QEMU.

**Every migrated job gets `timeout-minutes`** if it lacks one. A stuck VM on either vendor otherwise burns GitHub's 6-hour default. Value: 1.5 × the slowest *healthy* run in the baseline, rounded up, minimum 10 — not the slowest run outright, which may be the very stall you are removing.

**`.github/actionlint.yaml`** from [`templates/actionlint.yaml`](./templates/actionlint.yaml), `{{LABELS}}` = the labels you introduced (one `    - ` line each); no repo has one before this, so create it. actionlint otherwise reads the labels as typos.

**Don't:**

- Add `runner:` inputs or `if: startsWith(inputs.runner, 'blacksmith')` dual paths. That is pilot scaffolding; the PR is the rollback unit, and the in-house pilot deleted exactly this once the decision was made.
- Touch `actions/cache` or the caching in `setup-node`/`setup-*` — they work transparently on Blacksmith, and `useblacksmith/cache` is deprecated.
- Swap `actions/checkout` for `useblacksmith/checkout` unless the clone itself takes minutes (multi-GB repos).
- Annotate plain `runs-on` swaps. One comment on each Docker-builder swap is the only prose this change needs.
- Propagate stale claims in headers you pass through (an "arm64" banner over an amd64 build stays wrong; fix or leave, don't copy).

## 4. Verify

```bash
actionlint                                                   # clean, with the new config
grep -rn 'cache-from\|cache-to' .github/workflows            # none left on migrated builds
grep -rn 'runs-on:' .github/workflows | grep -v blacksmith   # exactly the "stay" rows
git diff --stat                                              # exactly the "migrate" files (+ actionlint.yaml)
git diff --quiet -- <every dormant workflow left alone>       # byte-identical
```

The diff must reconcile with the decision table line for line. A file in the diff that isn't in the table, or vice versa, is a mistake — find it before delivering.

## 5. Deliver and watch

Hand off with `/deliver --no-merge`. PR body, in this order:

1. **What moved and what stayed** — the decision table, reasons included.
2. **Baseline** — `ci-timing.sh` output in a fenced block, plus *how to judge*: re-run the same command a week after merge; compare per job against its own baseline, on n ≥ 5, never on one run. Two in-house samples of the same job spanned 27%.
3. **What the first run will look like** — the first image build lands on a cold disk and shows only the hardware gain; the second is the number to plan around. A rebuild of an unchanged commit is a no-op that hits every layer, so never quote it as the build time.
4. **Side effects** — registry `:buildcache` tags are now neither written nor read and can be reaped; deploy-path builds no longer refresh them.
5. **Needs a human** — the "ask" items and their answers; any dormant workflow left alone and why.

After merge, three signals, in order: `blacksmith-*` jobs leave `QUEUED` within a minute (the app works); the service-container test job passes (the environment is drop-in); the image build's *second* run is faster than its first (the disk works). If jobs sit in `QUEUED`, the app isn't installed — cancel them rather than let them time out.

## 6. Report

- **Moved** / **stayed** / **asked**, as three lists with one reason each.
- **Baseline captured** — where, and the re-measure command.
- **Left alone on purpose** — dormant workflows, self-hosted jobs, machine-bound credentials.
- **Needs a human** — a dormant failure surfaced by touching a workflow, a deploy job worth splitting, a client agreement to check.

## Hard rules

1. **Never re-size while re-hosting.** 8 cores → 8 vCPU. A size change is its own PR with its own measurement.
2. **Never migrate the branch-protection required check** or an `if: always()` gate. Seconds of runtime, and it protects `main`.
3. **Never hash the Dockerfile into `cache-key`.** A constant per image; buildkit owns invalidation.
4. **Never build pilot scaffolding** — no `runner` inputs, no label-guarded dual step paths. Revert the PR to roll back.
5. **Never fix a pre-existing failure that your edit woke up**, and never leave a comment about it in a self-triggering file — the comment re-fires the job. Revert the file, report it.
6. **Never quote a no-op rebuild as the build time.** Perturb a source file, measure that, revert the perturbation.
7. **Never conclude from n=1.** The first result on a job is a hint; the in-house pilot got the same job wrong twice before n reached 25.
8. **Confidentiality.** The PR names only the repo it lives in. Nothing from another client's migration — repo names, ticket ids, numbers tied to a name — goes into it.
