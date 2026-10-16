---
name: blacksmith
description: Migrate a repository's GitHub Actions workflows to Blacksmith runners — inventory every job, move the ones that build, run or test the app (image builds get the sticky-disk Docker actions, a size-capped cache and a Dockerfile audit for cache killers), leave glue, deploy and credential-bound jobs on GitHub, capture a per-step timing baseline, hand off to `deliver --no-merge` with the decision table in the PR, and measure real rebuilds on that PR before it merges. Use when asked to "move CI to Blacksmith", "cut GitHub Actions spend", "make the image build faster", or right after the Blacksmith app was installed on an org. Args: a repo path (default: the current repo), plus `--audit-only` to print the decision table and write nothing.
---

# blacksmith

You are running the **blacksmith** skill. Goal: move the *compute* in a repo's CI onto Blacksmith runners, move nothing else, and leave behind the numbers that prove it paid off.

The policy below was bought with measurements on an FSH monorepo, recorded in [`references/policy.md`](./references/policy.md) — read it before Phase 2. The short version: CI image builds are bound by moving bytes, not computing them, so bare metal with a local layer cache cut one build 12.4 → 3.6 min (hardware −53%, sticky disk a further −33%). Test and e2e jobs gained 12–44%. Sub-minute glue gained nothing and became one more thing that can wedge a repo. A second repo added the other half: its layer cache had been missing on every build because of the Dockerfile itself, which no runner fixes — so this skill audits the Dockerfile too, and measures before it merges.

Blacksmith is the house route; running our own runners was weighed and rejected. Don't re-litigate it here.

## 0. Gate

- **The Blacksmith GitHub App must be installed on the org.** Their runners register through GitHub's org-level runner API; without the app every `blacksmith-*` job queues until GitHub times it out instead of failing fast.

  ```bash
  ORG=$(gh repo view --json owner -q .owner.login)
  gh api "/orgs/$ORG/installations" -q '.installations[].app_slug' | grep -qx blacksmith-sh && echo installed
  ```

  That endpoint needs `admin:org`, which most tokens lack: a 404 means *unknown*, not *missing*. Then look for evidence instead — another repo in the org already running `blacksmith-*` jobs (`gh search code 'runs-on: blacksmith-' --owner "$ORG" -L 5`), and, once the PR is pushed, its first `blacksmith-*` job leaving `QUEUED` within a minute. Proven missing → stop and say so (app.blacksmith.sh, org scope, all repos or this one). `--audit-only` may continue; a write run may not.
- `gh auth status` must pass; `actionlint` must be on PATH (`brew install actionlint`) for Phase 4.
- **Ownership** (`git remote -v`). In a client's repo, every migrated job's secrets will be read on a third party's hardware — a subprocessor question, not a technical one. Proceed, but the report names those jobs (Phase 2 "ask" list) so the owner can veto.

## 1. Inventory and baseline

```bash
"${CLAUDE_SKILL_DIR}/scripts/inventory.sh" [repo-path] | tee /tmp/blacksmith-inventory.md
"${CLAUDE_SKILL_DIR}/scripts/ci-timing.sh" | tee /tmp/blacksmith-baseline.txt
"${CLAUDE_SKILL_DIR}/scripts/step-timing.sh" --workflow <each slow workflow> | tee -a /tmp/blacksmith-steps.txt
"${CLAUDE_SKILL_DIR}/scripts/build-steps.sh" --run <a recent image-build run> --job <its build job>
```

- `inventory.sh` — one row per job: current label, mapped label, timeout, the signals it classifies on, and a *suggested* verdict with its reason. Suggestions are heuristics; you judge every row, and `REVIEW` rows you read in full.
- `ci-timing.sh` — wall-clock and priced cost per workflow and runner label over the last 14 days. This is the "before". Reusable workflows report no runs of their own — their jobs bill under the caller — so the numbers sit on calling workflows.
- `step-timing.sh` — per job and per step: n, median, min–max over successful runs. The "after" is judged per step against this, not per workflow: a workflow average hides that the build got faster while a cleanup or an upload did not.
- `build-steps.sh` — inside one image build: the slowest BuildKit steps, and whether each dependency-install step was `CACHED`. Read it before Phase 3. Installs that *ran* on a build that changed no lockfile mean the Dockerfile invalidates them on every commit — fix that in the Dockerfile audit, or the sticky disk caches nothing that matters. A slowest step that isn't compute (a source-map or artifact upload, the registry push) goes in the report by name: a runner won't fix it, and it can be the cheapest win in the repo — one upload was 75% of an app's build.
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
- Machine-local or network-scoped credentials: `KUBECONFIG` pointing at a file on the runner, a WireGuard peer config, SSH to a host that allowlists the runner's IP.
- **A self-triggering workflow that has been dormant** (lists itself in `paths:` and hasn't run in 60+ days — the inventory flags these). Listing itself is normal; dormancy is the problem: your edit runs it for the first time in months, and a pre-existing failure then looks like yours. If it fails on something unrelated to runners, revert that file to byte-identical, report the failure, and don't fix it here — not even with a comment in the file, because the comment is an edit and re-fires it.

**Ask once**, in a single `AskUserQuestion`, with the numbers beside each item:

- Fused build + deploy jobs (buildx *and* kubectl/gcloud/ssh in one job). Recommend splitting the build into its own job in the same workflow (Phase 3, [`templates/build-job.yml`](./templates/build-job.yml)) — a reusable build workflow only when several workflows already share one build. If declined, the job stays.
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
      # buildkit invalidates layers itself; keying on the Dockerfile's contents would
      # discard the whole cache on every edit.
      - name: Set up Docker Buildx (Blacksmith sticky disk)
        uses: useblacksmith/setup-docker-builder@v2
        with:
          cache-key: {{REPO}}-{{BUILD_TARGET}}   # e.g. myrepo-web: one per Dockerfile + target

      # No cache-from/cache-to: the sticky disk replaces them, and exporting to the
      # registry as well would re-incur the network cost the disk exists to remove.
      - name: Build and push
        uses: useblacksmith/build-push-action@v2
        with:            # context, file, target, push, tags, build-args, platforms: unchanged

      # Bounds what the sticky disk carries into the next run (billed per GB-month).
      # Runs before the disk is committed at job end. Never fails the job: an uncapped
      # cache costs money, not correctness.
      - name: Cap the Docker layer cache
        continue-on-error: true
        run: docker buildx prune --force --max-used-space 20gb
```

**`cache-key`** names one sticky disk. Make it one per Dockerfile + target, shared by every workflow and environment that builds it — preview, dev and prod builds of one Dockerfile differ only in build args, so they share every install layer, and a PR build starts from the layers `main` left. Never a deploy name: a per-PR image name (`app-pr-123`) mints one disk per PR, each starting cold and each billed. Two genuinely different images get two keys.

**Size cap.** `setup-docker-builder@v2` has no size input (v1's `max-cache-size-mb` is gone; v2 garbage-collects by age only), and storage is what turned one month's bill up 25%. The prune step above holds the disk under 20 GB; one full cold build of a Node app left 12.4 GB, so 20 GB keeps roughly a full set plus the last change. Raise it per image if `build-steps.sh` shows installs re-running after a prune.

**"Free runner disk space" steps** (`rm -rf /usr/share/dotnet …`, `docker system prune -af`) existed for GitHub's 14 GB root disk. With the sticky-disk builder, BuildKit writes to its own disk, not the root disk, and the root disk on a 2-vCPU runner had 80 GB free. Keeping the step is harmless — 0.2 min on Blacksmith against 2.4 on GitHub — but it guards nothing in a job that builds through `setup-docker-builder`; drop it there, keep it where a job still builds through the local daemon. Multi-platform builds: one job per platform on the matching runner (`…-arm` for arm64), no QEMU.

**Dockerfile audit.** The sticky disk only keeps layers the Dockerfile lets survive. Before the swap, check every stage the build uses:

- **Per-commit `ARG`s go last.** A changed `ARG` value misses the cache at every `RUN` *after* its declaration, used or not. An `ARG GIT_SHA` / `RELEASE` / `VERSION` near the top of a stage re-runs that stage's dependency install on every commit. Declare it immediately before its first use, ideally as the stage's last instructions.
- **Package caches in cache mounts, not layers.** Replace `RUN yarn install && yarn cache clean` (or `npm ci && npm cache clean`, `pip install --no-cache-dir`) with `RUN --mount=type=cache,target=<the tool's cache dir> <install>`. Confirm the dir in the base image (`yarn config get cacheFolder` — Yarn 4: `/root/.yarn/berry/cache`). Cache mounts live on the sticky disk too, so a lockfile change re-links from disk instead of downloading everything.
- **Know what the old cache never held.** `cache-to: …,mode=min` exports only the final stage's layers, so builder stages were always rebuilt; `docker build --cache-from <image>:latest` reuses nothing unless that image was pushed with inline cache metadata. Either way the "before" was a cold build, and the baseline says so.

Each fix is an ordinary Dockerfile change that helps on any runner; it ships in this PR because the cache is the point of the migration. `build-steps.sh` on the second warm build is the proof: install steps `CACHED`.

**Splitting a fused build + deploy job** (if the "ask" said yes): [`templates/build-job.yml`](./templates/build-job.yml) is the new `build` job on Blacksmith; the old job keeps everything after the image, stays on GitHub and gains `needs: [build]`. Then:

- Move the job's `env:` to the workflow level, so both jobs read the same values. Values a step writes to `$GITHUB_ENV` (an image tag) are per job — repeat that step in `build`.
- Pass the image by its deterministic tag (`…:${{ github.sha }}`), not a job output, so re-running the deploy job alone still finds it.
- Drop the build-only steps from the deploy job: registry login, disk cleanup, build-context prep.
- `notify-failure` and any `if: always()` joiner: add `build` to `needs:` and to the condition.
- Cloud trust: if the provider's attribute condition is repo-scoped, `build` needs no `environment:` — and shouldn't get one, since an environment means a second deployment record and a second approval on protected environments. If the condition names the environment (`assertion.environment`), `build` must carry it.
- The deploy job's GitHub-deployment record now appears only once the build succeeds. Say so in the PR.

**Dependency caches in CI jobs.** Where a test job has none, adding one is fine (see Don't). One trap: `actions/setup-node`'s `cache: yarn` runs before `corepack enable`, so it asks the runner's preinstalled Yarn 1 for its folder and caches the wrong directory. For Yarn 2+, use `actions/cache` on `~/.yarn/berry/cache` keyed on the lockfile(s).

**Every migrated job gets `timeout-minutes`** if it lacks one. A stuck VM on either vendor otherwise burns GitHub's 6-hour default. Value: 1.5 × the slowest run in the baseline, rounded up, minimum 10.

**`.github/actionlint.yaml`** from [`templates/actionlint.yaml`](./templates/actionlint.yaml), `{{LABELS}}` = the labels you introduced (one `    - ` line each); no repo has one before this, so create it. actionlint otherwise reads the labels as typos.

**Don't:**

- Add `runner:` inputs or `if: startsWith(inputs.runner, 'blacksmith')` dual paths. That is pilot scaffolding; the PR is the rollback unit, and the in-house pilot deleted exactly this once the decision was made.
- Touch existing `actions/cache` steps or the caching in `setup-node`/`setup-*` — they work transparently on Blacksmith, and `useblacksmith/cache` is deprecated. Adding one where a job has none is fine.
- Swap `actions/checkout` for `useblacksmith/checkout` unless the clone itself takes minutes (multi-GB repos).
- Annotate plain `runs-on` swaps. One comment on each Docker-builder swap is the only prose this change needs.
- Propagate stale claims in headers you pass through (an "arm64" banner over an amd64 build stays wrong; fix or leave, don't copy).

## 4. Verify

```bash
# actionlint: no NEW findings. Most repos carry shellcheck notes already, so "clean" is the
# wrong bar — compare against the base branch, line numbers stripped.
lint() { actionlint -oneline 2>&1 | sed -E 's/:[0-9]+:[0-9]+:/:/' | sort; }
git worktree add -q /tmp/blacksmith-base "origin/$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)"
(cd /tmp/blacksmith-base && lint) > /tmp/al-base.txt; git worktree remove --force /tmp/blacksmith-base
lint > /tmp/al-after.txt; comm -13 /tmp/al-base.txt /tmp/al-after.txt   # empty, or each line explained
grep -rn 'cache-from\|cache-to' .github/workflows            # none left on migrated builds
grep -rn 'runs-on:' .github/workflows | grep -v blacksmith   # exactly the "stay" rows
git diff --stat                                              # exactly the "migrate" files (+ actionlint.yaml)
git diff --quiet -- <every dormant workflow left alone>       # byte-identical
```

The diff must reconcile with the decision table line for line. A file in the diff that isn't in the table, or vice versa, is a mistake — find it before delivering. A new actionlint line is acceptable only when it is an existing finding carried into a copied step (a split job repeating a `>> $GITHUB_ENV` step) — say so in the PR.

## 5. Deliver and watch

Hand off with `/deliver --no-merge`. When an image build moved and a PR-triggered workflow builds it (a preview deploy, a PR image build), measure on the PR before it merges — the "after" then exists at review time instead of a week later:

```bash
M="${CLAUDE_SKILL_DIR}/scripts/measure.sh"
"$M" --workflow <pr-triggered workflow> --file <path inside the build context> --label cold --runs 1
"$M" --workflow <pr-triggered workflow> --file <same path> --label after --runs 5
"$M" --summary
```

- `--file` must sit inside the build context and not be `.dockerignore`d, so each push invalidates `COPY . .` like a real PR (hard rule 6). The script refuses to run without an open PR on the branch, and runs strictly one at a time.
- The first run lands on a cold disk; give it its own label and leave it out of the comparison.
- **One variable per series.** To try a second change — dropping a disk-cleanup step, skipping an upload `build-steps.sh` exposed — commit it, then start a new `--label`. Never two changes in one series.
- A failure after a green build job (a deploy, a migration) gets one re-run; the build numbers count, end-to-end doesn't. Recreating the same environment every ~15 minutes can wake races a normal PR cadence never hits — report them, fix them elsewhere (hard rule 5).
- Delete `--file` before review and squash-merge, so the measurement commits never reach the default branch.

PR body, in this order:

1. **What moved and what stayed** — the decision table, reasons included.
2. **Baseline** — `ci-timing.sh` and `step-timing.sh` output in fenced blocks, the `measure.sh --summary` table if you measured, plus *how to judge*: re-run the same commands a week after merge; compare per job and step against its own baseline, on n ≥ 5, never on one run. Two in-house samples of the same job spanned 27%.
3. **What the first run will look like** — the first image build lands on a cold disk and shows only the hardware gain; the second is the number to plan around. A rebuild of an unchanged commit is a no-op that hits every layer, so never quote it as the build time.
4. **Side effects** — registry `:buildcache` / `:cache` tags are now neither written nor read and can be reaped; deploy-path builds no longer refresh them. A split job creates its deployment record only after a successful build.
5. **Needs a human** — the "ask" items and their answers; any dormant workflow left alone and why; non-compute build costs `build-steps.sh` named.

After merge, three signals, in order: `blacksmith-*` jobs leave `QUEUED` within a minute (the app works); the service-container test job passes (the environment is drop-in); on the image build's *second* run, `build-steps.sh` shows the install steps `CACHED` (the disk works — "faster than the first run" is too weak a test: it passes on hardware alone while a Dockerfile still misses every layer). If jobs sit in `QUEUED`, the app isn't installed — cancel them rather than let them time out.

## 6. Report

- **Moved** / **stayed** / **asked**, as three lists with one reason each.
- **Baseline captured** — where, and the re-measure command. Measured series, if any, with their medians.
- **Dockerfile fixes** — each cache killer found and what changed.
- **Left alone on purpose** — dormant workflows, self-hosted jobs, machine-bound credentials.
- **Needs a human** — a dormant failure surfaced by touching a workflow, a deploy job worth splitting, a client agreement to check.

## Hard rules

1. **Never re-size while re-hosting.** 8 cores → 8 vCPU. A size change is its own PR with its own measurement.
2. **Never migrate the branch-protection required check** or an `if: always()` gate. Seconds of runtime, and it protects `main`.
3. **Never hash the Dockerfile into `cache-key`, and never key it on a deploy name.** A constant per Dockerfile + target; buildkit owns invalidation. A per-PR or per-environment key is one cold, billed disk each.
4. **Never build pilot scaffolding** — no `runner` inputs, no label-guarded dual step paths. Revert the PR to roll back.
5. **Never fix a pre-existing failure that your edit woke up**, and never leave a comment about it in a self-triggering file — the comment re-fires the job. Revert the file, report it.
6. **Never quote a no-op rebuild as the build time.** Perturb a file inside the build context (`measure.sh` does it), measure that, remove the perturbation.
7. **Never conclude from n=1.** The first result on a job is a hint; the in-house pilot got the same job wrong twice before n reached 25.
8. **Confidentiality.** The PR names only the repo it lives in. Nothing from another client's migration — repo names, ticket ids, numbers tied to a name — goes into it.
