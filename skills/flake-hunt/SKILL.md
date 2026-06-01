---
name: flake-hunt
description: Reproduce, diagnose, and fix a flaky Playwright e2e test via a detect → diagnose → fix → verify loop. Forbids cheap papering-over (timeouts, retries, skip). Files a tracker task on give-up.
---

# flake-hunt

You are running the **flake-hunt** skill against a Playwright spec. Your job is to find the **root cause** of a flake and fix it — not to make the test pass.

A green run achieved by adding a timeout, raising retries, or skipping the test is a **failure of this skill**, not a success.

## Project specifics — read these first

This skill is repo-agnostic. Gather from the repository you're running in:

- **Playwright project root** — the directory containing `playwright.config.{ts,js}` and the single-spec run command. Derive from the repo's `CLAUDE.md` / `AGENTS.md` / `package.json` scripts.
- **Worker constraints** — some projects must run local e2e with `workers=1` (e.g. a dev server that can't handle concurrent SSR) while CI runs higher parallelism. Honor whatever the project's `playwright.config` / docs document; don't assume.
- **Shared-DB / worktree caveats** — if the project uses per-worktree or shared template databases, inconsistent failures across runs of the *same code* are often environment, not an app race. Note how the repo says to check migration state.
- **Give-up tracker** — where to file a flake task (the `## Skill profile` in the repo's root `CLAUDE.md`: tracker id + default status/priority/tags). If none configured, ask the user.

## Arguments

The user invokes this skill with one of:

- **A spec path** (relative to the Playwright project root) — hunt that single spec.
- **A PR number** — diff against the base branch, identify changed/new spec files, hunt each one.

If args are empty, ask the user which spec to target. Do not guess.

## Hard rules

1. **Root cause or bust.** If you cannot name a falsifiable hypothesis backed by trace/log/network evidence, you must NOT edit the test or the code under test. Keep diagnosing or file a tracker task and stop.
2. **Forbidden fixes** (without explicit user override):
   - `waitForTimeout(N)` or any literal-ms sleep
   - Raising any `timeout` value (per-test, per-action, expect)
   - `expect.poll` / `expect.toPass` introduced without a corresponding upstream change
   - Bumping Playwright `retries` (config or per-test)
   - `test.skip` / `test.fixme` / `.only` — except via the Quarantine flow below
   - Adding generic `try/catch` to swallow assertion failures
   - Tightening selectors solely to avoid a race (the race is the bug)
3. **Rule out environment first.** In a shared-DB / worktree setup, inconsistent failures across runs of the *same code* often mean a sibling branch migrated the shared DB or a dev server cold-started. Rule this out (check the project's migration state and recent migration commits) before assuming an app-code race.
4. **Run from the Playwright project root** for all commands. Spec paths are relative to that directory.
5. **Never run the full e2e suite.** Only the spec(s) you're hunting.

## Phases

### 1. Detect

Run the spec multiple times to see if and how it flakes. Pick runs/workers per the project's constraints — typically **5 runs** locally (with the project's required worker count, often **1**) and **10 runs / higher parallelism** matching CI.

Use the bundled helper (or the project's own flake-runner if it ships one). Output goes to a fresh dir; keep traces under a gitignored path:

```bash
# from the Playwright project root
"${CLAUDE_SKILL_DIR}/scripts/flake-run.sh" \
  "tests/path/to/foo.spec.ts" \
  5 1 \
  .flake-hunt/foo/detect
```

Parse the resulting `results.json`:

- Walk `suites[].specs[].tests[].results[]`; bucket by `status` (`passed`, `failed`, `timedOut`).
- For each failure, capture a **fingerprint**: error message (first line), file:line of the failed assertion, last network URL touched, last console error.
- Group failures by fingerprint. Multiple fingerprints = multiple bugs; treat each separately.

Outcomes:

- **0 fails / N runs** → report "did not reproduce in N runs". Do NOT claim "not flaky" — claim "didn't reproduce, would need more runs." Stop here unless the user pushes for more.
- **≥1 fail** → proceed to Diagnose.

### 2. Diagnose (hypothesis before any edit)

Before touching code, write a hypothesis. It must:

- Name a **root-cause category** (race / shared-state / timing / environment / real-bug).
- Cite **evidence** from this detect pass — trace file, network log line, console message, repeated log, screenshot. "Probably a race" with no evidence is rejected; keep diagnosing.
- Predict a **cheap diagnostic** that would falsify it.

Categories and the diagnostic each one points to:

- **Race (UI rendered before data, Suspense/loading not awaited)** — grep the spec for explicit `waitFor`s, check the data-layer cache keys, look for a missing `waitFor` after a navigation.
- **Shared state (DB row leaked from a previous test, cache hit, seed ordering)** — run the spec in isolation once with a fresh DB. If isolated runs pass but suite runs fail, it's state leak. Check whether the spec uses unique fixture data.
- **Timing (animation, debounce, network jitter)** — look at the trace timeline; if the failing action happens within ~100ms of a network response, suspect debounce or animation.
- **Environment (shared/worktree DB migrated by a sibling branch, dev-server cold start, network blip)** — check migration state and recent migration commits, and whether the web server was reused vs started fresh.
- **Real bug** — the feature actually breaks under N% of runs. Reproducible bug, not a test bug. Fix the app code, not the test.

You get **3 diagnose passes**. If after 3 hypothesis-and-test cycles you cannot pin the cause, **stop and Quarantine** (below). Don't guess.

### 3. Fix

Implement the fix that follows from the validated hypothesis. The fix MUST address the root cause:

- Race → add the *correct* `waitFor` for the specific state being waited on (a network response, an element appearing, a loading boundary settling). Not a blanket timeout.
- Shared state → make the spec self-isolating (unique fixture data, explicit setup/teardown). Not a `.skip` and not a runner retry.
- Timing → coordinate with the actual event (await the animation end, the network response, the state transition). Not a sleep.
- Environment → if it's shared-DB drift, escalate (don't "fix" it in the spec). The skill exists to find this kind of issue, not paper over it.
- Real bug → fix the app code, add the test as a guard.

Read every diff against the **Hard rules → Forbidden fixes** list before saving. If your fix touches any of those patterns, stop and reconsider.

### 4. Verify

Re-run the spec, more aggressively than detect — e.g. **5/5** locally (with the project's worker count) and recommend a heavier CI pass (e.g. **20/20** at CI parallelism):

```bash
"${CLAUDE_SKILL_DIR}/scripts/flake-run.sh" \
  "tests/path/to/foo.spec.ts" \
  5 1 \
  .flake-hunt/foo/verify
```

- Anything less than a clean pass = not fixed. Loop back to Diagnose.
- If a *new* fingerprint shows up in verify that didn't appear in detect, treat it as a second flake — diagnose separately.
- After the fix is verified locally, recommend the user push and let CI run the heavier verify pass.

### 5. Report

Output a markdown summary at `.flake-hunt/<spec-slug>/report.md`:

```markdown
# Flake hunt: <spec relative path>

## Detect
- Runs: N / Workers: W / Env: local|CI
- Passed: X / Failed: Y
- Fingerprints:
  - `<error first line>` × N (trace: <path>)

## Hypothesis (validated)
- Category: race | shared-state | timing | environment | real-bug
- Evidence: <trace/log/network citation>
- Diagnostic run: <what you tried and what it showed>

## Fix
- Files changed: <list>
- Summary: <one sentence>
- Why this is not a forbidden fix: <one sentence>

## Verify
- Runs: N / Workers: W / Env: local|CI
- Passed: X / Failed: Y
- Status: GREEN | NOT YET FIXED
```

If the work is on a PR, also post the report as a PR comment via `gh pr comment <N> --body-file <report-path>`.

### Quarantine (give-up flow)

Only when you've exhausted 3 diagnose passes without a falsifiable hypothesis. Steps:

1. **File a flake task** in the project's configured tracker (from the `## Skill profile`; if none, ask the user). Include:
   - **Title**: `Flake: <spec relative path>`
   - **Status / Priority / Tags**: per the project's defaults (raise priority if the spec gates a critical user flow).
   - **Body**: full markdown of all detect runs, every hypothesis tried and ruled out, every trace path, the spec link. Include enough that another engineer can pick this up cold.
   - Link the current PR if one exists.
2. **Mark the spec with `test.fixme`** — not `.skip`. Include a reason string referencing the tracker task URL:
   ```ts
   test.fixme(true, 'Flaky — see <tracker task URL>');
   ```
3. **Do not** disable the spec by other means (no `.skip`, no commented-out test, no `--grep-invert`).
4. **Tell the user** explicitly: the spec is quarantined, the task is filed, root cause is unknown.

## Things to remember

- Save every trace; keep them under a gitignored path (e.g. `.flake-hunt/`) for the duration of the hunt.
- Don't read a large `results.json` into context — parse it via `node -e` one-liners and pull only what you need.
- **Local "clean" is suggestive, not authoritative** when the project's CI runs at higher parallelism against a different target than local. A spec that passes locally can still flake under CI's parallel load — always recommend a CI verify run before closing the loop.
- This skill targets **Playwright e2e**. A unit-test flake (Vitest/Jest and similar) is a different beast — say so and stop if the user points you at one.
