# Why the policy is what it is

Measured on two repos. The first, an FSH monorepo, September 2026: four Docker images, eleven test/e2e workflows,
~30k job-minutes a month. Every "after" below is on the same vCPU count as its "before".

## The mechanism

CI image builds are bound by moving bytes, not computing them. The dominant costs were pulling
a registry layer cache and exporting it back; the compute in between was a fraction. Bare metal
with a local NVMe layer store removes the transfer. That is why builds respond dramatically and
test suites only moderately — a suite that spends its time booting Postgres and Meilisearch, or
waiting on a browser, is not CPU-bound either way.

## One image build, decomposed

| Scenario | Total job |
|---|---:|
| GitHub-hosted, registry cache — baseline, n=23, sd 1.7, fastest 9.3 | **11.6 min** |
| Blacksmith, `runs-on` only, no sticky disk | 5.4 |
| Blacksmith, sticky disk, cold (first build) | 5.3 |
| Blacksmith, warm, **no source change** — a no-op, every layer hit | 0.6 |
| Blacksmith, warm, **source changed** ← what a real PR looks like | **3.6** |

Hardware alone: −53%. The sticky disk on top: a further −33%. The cache is real and it is the
*smaller* effect — and it is the effect that costs the vendor-fork actions. Cost per build −80%.

The 0.6 min row is why hard rule 6 exists: dispatching the same commit twice measures nothing.
The realistic number came from a one-line change to a source file, measured, then reverted.

## Every migrated job shape

| Job | vCPU | Baseline | After | Δ |
|---|---|---:|---:|---:|
| Browser e2e, app A | 8 | 21.0 (n=18) | 11.8 | −44% |
| Browser e2e, app B | 8 | 14.7 (n=7) | 8.7 | −41% |
| Image build, app A | 2 | 12.4 (n=23) | 3.6 | −69% |
| Image build, app B | 2 | 12.0 (n=40) | 6.5 (cold) | −46% |
| Tests with service containers | 8 | 7.7 (n=25) | 4.8–6.1 | −29% |
| Tests, no services | 2 | 9.1 (n=25) | 8.0 | −12% |

Every "after" lands below its baseline's *fastest observed run*, not merely below the mean.

## Why n=1 is not a result

The same 8-vCPU test job was called "−14%" off a 20-run baseline, then "inside the noise" off
one sample against 25 runs, then "−29%" once a second sample landed below the GitHub floor.
The two Blacksmith samples themselves spanned 4.8–6.1 min — 27% between them. Judge on n ≥ 5,
each job against its own history.

## A second repo: when the cache was never working

October 2026, a Node monorepo: one Dockerfile built for preview, dev and prod at 2 vCPU, test
and e2e jobs at 2 vCPU. Measured on preview deploys, which push-trigger on a PR, with a one-line
change inside the build context per run, n=5 per series, before the PR merged:

| Preview deploy, end to end | Median | Image build |
|---|---:|---:|
| GitHub-hosted, registry cache — baseline, n=25 | 23.8 min | 18.5 ¹ |
| Blacksmith, sticky disk, cold | 16.2 | 10.5 |
| Blacksmith, warm, Dockerfile fixed | 14.2 | 9.3 |
| … and the disk-cleanup step removed | 14.9 | 9.4 |
| … and the source-map upload skipped | **10.5** | **4.3** |

¹ Build and deploy were one job; this is the time to a pushed image.

What that run taught:

- **The Dockerfile was the cache's real enemy.** `ARG GIT_SHA` near the top of the runtime stage
  missed the cache at every later `RUN`, so the production install (156 s) re-ran on every
  commit. `cache-to: mode=min` never stored the builder stage, so its install (168 s) re-ran
  too, and one workflow's `--cache-from :latest` reused nothing at all — the image carried no
  cache metadata. The "before" was a cold build every time. Moving the `ARG` to the end of the
  stage and putting the package cache in a `--mount=type=cache` brought every install step
  back `CACHED` on 15 of 15 warm runs.
- **The disk-cleanup step guards nothing on the sticky-disk builder.** 0.2 min on Blacksmith
  (2.4 on GitHub); without it the 2-vCPU runner's root disk still had 80 GB free after the build,
  because BuildKit writes to the sticky disk. The A/B difference sat inside run-to-run noise.
- **The biggest remaining cost wasn't compute.** A source-map upload inside `next build` — 4,020
  files in 75 sequential batches — took 75% of the build step. Skipping it for previews saved
  another 4.4 min, almost half of what the runner and the cache fixes saved together.
  `build-steps.sh` exists because this was invisible in every workflow-level number.
- **Disk size:** one cold build left 12.4 GB on the sticky disk; a 20 GB prune cap held it
  under 19 GB across 16 builds.
- **Registry push** ("exporting to image") is now the largest fixed cost of the build at
  90–100 s; a smaller runtime image is the next lever, not a faster runner.
- **Measuring finds things.** Recreating one preview environment every 15 minutes exposed a
  pre-existing race in its database reset (2 of 16 deploys). The build numbers were kept, the
  deploy jobs re-run, and the race fixed in its own PR.

CI jobs on the same pushes, same vCPU: tests with service containers 8.1 → 4.3 min (−47%),
browser e2e 16.8 → 11.0 min (−35%), n=15 against n=15.

## Rates

Blacksmith bills linear in vCPU off a $0.004 base; GitHub's larger runners are priced steeper
than linear. So the *rate* discount shrinks where the money is: ~33% at 2 vCPU, ~27% at 8,
~24% at 16. The case rests on wall-clock, which compounds with the rate — the four biggest
jobs went from ~$0.93 to ~$0.37 per occurrence.

Add-ons: sticky disks and Docker layer cache at $0.50/GB/month; disks evicted after 7 days
idle; 3,000 free minutes a month.

## What stayed, and what happened when it didn't

- The required-check aggregator (0.2 min) and the `if: always()` joiners: nothing to gain; the
  merge gate stays on the most boring infrastructure available.
- Deploy jobs: `kubectl rollout status` and health checks wait on the cluster. Faster cores buy
  nothing, and the cluster kubeconfig has no reason to be read on a third party's hardware.
- A test job federating into a cloud account via workload identity was first excluded, then
  included once the vendor became the route rather than a comparison — an accepted trade, taken
  consciously. In a client's repo that is the owner's call, hence the "ask" list.
- One workflow triggered on its own file. Adding a `runs-on` change ran it for the first time in
  two months and it failed — a stale copy of a version table, unrelated to runners. The
  *explanatory comment* about the failure was itself an edit to the file and re-fired the failing
  job on every push. The fix was to leave the file byte-identical and put the finding in the PR.
- The pilot carried a `runner:` input defaulting to `ubuntu-latest` and label-guarded dual step
  paths so dev and prod stayed untouched while the answer was open. Once the vendor was chosen,
  all of it was deleted: it existed to protect a decision, not a workload.

## Vendor facts worth knowing

- The GitHub App must be installed on the org; without it `blacksmith-*` jobs queue until GitHub
  times them out. Check `gh api /orgs/<org>/installations` — it needs `admin:org`, and returns
  404 without it, which proves nothing. A job picked up in seconds proves the app works.
- `useblacksmith/setup-docker-builder@v2` has no cache-size input (v1's `max-cache-size-mb` was
  dropped) and garbage-collects by age only; cap size with `docker buildx prune
  --max-used-space` before the job ends.
- A 2-vCPU Ubuntu runner: 150 GB root disk with ~80 GB free; the Docker sticky disk mounts
  separately at `/var/lib/buildkit` (~590 GB).
- `actions/cache` and `setup-*` caching are intercepted transparently; `useblacksmith/cache` is
  deprecated. Cache is scoped per branch like GitHub's, 25 GB/repo/week free.
- The Docker layer cache is a sticky disk per `cache-key`, shared across the org's runners;
  committed at job end on success; last write wins between concurrent builds, so it may take a
  few runs for every branch's layers to land.
- Multi-platform builds: one job per platform on the matching native runner; no QEMU.
- Installing the app makes their PR bot append a footer to PR bodies. Cosmetic.
