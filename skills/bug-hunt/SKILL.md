---
name: bug-hunt
description: Reproduce, diagnose, and fix a reported bug via a triage → reproduce → diagnose → failing-test → fix → verify loop. Forbids speculative fixes that paper over symptoms. Files a tracker task on give-up.
---

# bug-hunt

You are running the **bug-hunt** skill against a reported bug (a tracker task, an error-monitoring issue, or a free-text report). Your job is to find the **confirmed root cause** and fix it at the **narrowest correct layer** — not to ship the first plausible-looking patch.

A green test achieved against a synthetic flow that doesn't exercise the real code path is a **failure of this skill**, not a success. So is a "fix" at a layer the bug never touched.

## Project specifics — read these first

This skill is repo-agnostic. Gather the concrete details from the repository you're running in:

- **How to run the app / reproduce** — the dev/test server command, and any worktree/port convention. Derive from the repo's `CLAUDE.md` / `AGENTS.md`.
- **Test commands** — how to run a single test for each touched layer/package (`CLAUDE.md` / `package.json` scripts).
- **Existing safety infrastructure** — middleware, decorators, request-context wrappers, transaction boundaries, auth guards the framework already provides. The repo's docs describe these; you need them for the "check existing infra before adding new prevention" rule.
- **Give-up tracker** — where to file an investigation task (the `## Skill profile` in the repo's root `CLAUDE.md`: a tracker database/project id + default status/priority/tags). If none is configured, ask the user where to file it.

## Arguments

The user invokes this skill with one of:

- **A tracker task URL** — read the task, treat its claimed cause as a hypothesis (see Phase 1).
- **An error-monitoring issue URL** (Sentry and similar) — pull the trace; treat the grouped error as a symptom, not a cause.
- **A free-text bug description** — proceed from triage with what you have.
- **Empty** — ask the user which bug to target. Do not guess.

## Hard rules

1. **Symptoms ≠ root cause.** A report describes what someone observed and what they *guessed* caused it. The guess starts at zero evidence. Do not edit code based on the guess.
2. **No fix without a reproduction that runs the real code path.** A unit test that fabricates state and calls a function directly does NOT reproduce a production bug routed through the real request/job/worker pipeline. Either you have a real-path repro, or you don't have one.
3. **No fix without a failing test on the base branch.** Run the test on the base branch (or revert your fix) and confirm red. Then implement the fix and confirm green. A test that's green before and after the fix guards nothing.
4. **Fix at the narrowest correct layer.** Sprinkling defensive code (forks, transactions, locks, retries, null-checks) across services to paper over an upstream problem is forbidden. The invariant lives at one layer — fix it there.
5. **Check existing infra before adding new prevention.** Before adding a fork/transaction/lock/idempotency-key/retry, search for an existing middleware, decorator, or boundary that already guarantees the property. Frameworks usually wrap requests and background jobs in a managed context already — read the repo's docs and confirm whether the property you're worried about is already guaranteed on the real path before adding anything. "Stale state in a worker" (and similar) is not a thing without evidence that the existing wrapper was bypassed.
6. **Three diagnose passes max.** If after three hypothesis-and-test cycles you still can't name a falsifiable root cause backed by evidence, **stop and Quarantine** (below). Do not ship a speculative fix.

## Forbidden fixes

Without an explicit confirmed reproduction pointing at this layer:

- New forks / transactions / locks added inside a read-side service to "ensure freshness"
- `try/catch` that swallows the error so the symptom disappears
- New caches, retries, debounces, or idempotency keys added to "prevent" a concurrency issue you never reproduced
- Test/CLI-only helpers used to force synchronous execution in production code (e.g. running queued jobs inline) — these bypass the real boundary
- Defensive validation for inputs that internal callers already guarantee
- Synthetic unit tests that don't exercise the real flow being passed off as a regression test
- Edits to code paths the bug report *guessed at* but you never confirmed are on the failing path
- Tightening a downstream symptom check to make the report go away while the upstream cause remains

## Phases

### 1. Triage

Read the report. On a scratch note, write two columns:

- **Symptoms** — what someone actually observed (UI showed X, API returned Y, error Z, screenshot).
- **Suspects** — what the report or your gut guesses *caused* it (stale state, race condition, missing await, wrong query).

Suspects start at zero evidence and stay there until Phase 4 produces some. Do not treat a report's "prime suspects" as a confirmed root cause — it's the reporter's hypothesis, often written before they tried to reproduce.

### 2. Trivial-fix exit ramp

If **all** of these hold, skip to Fix + Verify (Phases 6–7):

- The repro is fully described by the stack trace or error message (no investigation needed to find the failing line).
- The fix is a one-liner or near-one-liner at the location the stack trace points at.
- The fix is obviously correct from local context: a typo, an off-by-one with clear evidence in adjacent code, a wrong constant, a missing null-check on a path the trace already proves is hit, a swapped argument order with type-system or test evidence.
- You are not changing any cross-domain behavior, boundary, or invariant.

If you have to *guess* at any of those, it isn't trivial. Run the full loop. If in doubt, run the full loop — it's cheaper than shipping the wrong fix.

### 3. Reproduce

Get a real reproduction against the real code path. **No fix is allowed before this step succeeds.**

- Start the app the way the repo documents it (dev/test server, correct port/worktree convention).
- Drive the reproduction the same way a user would: the real entry point the bug report names (HTTP/GraphQL/REST call, UI action, CLI). Let background work (queues/workers) drain naturally — do **not** force synchronous execution with a test-only helper; that bypasses the real boundary.
- Capture the observed bad state by re-reading the data (a query/API read), **not** by inspecting an in-memory object inside the same request that created it.

For **frontend bugs**: reproduce in a browser pointing at the app; capture console errors, network failure response bodies, the visible UI state, the URL.

If you can only reproduce in a synthetic unit test that fabricates state and calls a service directly, that is **not** a reproduction — it's a fabrication. Either you produce the bug through the real entry point or you don't have a bug confirmed yet.

If you cannot reproduce after a reasonable attempt: stop, tell the user what you tried, and ask for repro steps. Don't skip ahead.

### 4. Diagnose (hypothesis before any edit)

Write a falsifiable hypothesis. It must:

- Name a **root-cause category**: data-model bug / logic bug / race / shared-state / boundary-violation / wrong-input / upstream-bug.
- Cite **evidence** from the reproduction: actual stored row state, log line, response payload, network trace, stack frame. "Probably stale state" with no evidence is rejected — keep diagnosing.
- Predict a **cheap diagnostic** that would falsify it (e.g. "if the hypothesis is wrong, logging here would show X instead of Y" — then actually run it).
- Explicitly check whether **existing infrastructure already prevents the hypothesized cause** before adding new prevention (per Hard rule 5). If the framework's existing wrapper/decorator/guard already covers the hypothesis on the real path, the hypothesis is **wrong** until you produce evidence that the infra was bypassed on the failing path.

You get **3 diagnose passes**. If after three hypothesis-and-test cycles you cannot pin the cause, **stop and Quarantine** (below).

### 5. Failing test first

Before editing the code under fix:

1. Write a test (or e2e spec for frontend) that exercises the **real flow** the reproduction uses — same entry point, same boundary crossings, same job path.
2. Run it on the base branch (or with your local changes reverted): **it must fail**, and fail with the same fingerprint as the reproduction. Confirm red.
3. Only then implement the fix and confirm the test goes green.

A test that's green on the base branch is not a regression test for this bug. Either rewrite it to exercise the real path or accept that you don't have a regression guard. Use the repo's documented test command for the touched layer.

### 6. Fix at the narrowest correct layer

List the candidate layers where the fix could live (request/resolver boundary; job/transaction boundary; domain service; repository/query; entity/schema invariant). Pick the **narrowest** layer where the violated invariant naturally lives: the fewest call sites changed, the most localized blast radius, the layer closest to where the invariant is defined.

Counter-examples to reject:

- Adding a fork/fresh-context in a read-side calculator because "maybe upstream has stale state" — if the worker boundary already manages context, the calculator isn't the right layer; if some path bypasses it, fix the boundary, not every read service.
- Adding null-checks across the resolver layer because one upstream service occasionally returns `null` — fix the upstream service.
- Wrapping every cross-domain event handler in `try/catch` because one of them flaked once — handle the one, or fix the flake.

Before saving any diff, re-read the **Forbidden fixes** list. If your fix touches any of those patterns, stop and reconsider.

### 7. Verify

- Re-run the failing test from Phase 5 → must be green.
- Run adjacent tests in the same domain/file → must still be green.
- Run the repo's documented lint + typecheck for the touched packages.
- Re-run the original real-path reproduction from Phase 3 → bug is gone.

If anything is not green, loop back to Diagnose. Do not ship.

### 8. Report

Short markdown summary — inline in your final message or as a PR comment via `gh pr comment <N>`:

```markdown
# Bug: <one-line description>

## Symptoms
- <observed>

## Reproduction (real path)
- <entry point, command, expected vs actual>

## Confirmed root cause
- Category: <data-model | logic | race | shared-state | boundary-violation | wrong-input | upstream>
- Evidence: <stored-state/log/trace citation>

## Fix
- Layer: <request | job-boundary | service | repository | entity>
- Files: <list>
- Why not <other candidate layer>: <one sentence>

## Regression guard
- Test: <path> — fails on the base branch, passes with fix.
```

## Quarantine (give-up flow)

Only when you've exhausted 3 diagnose passes without a falsifiable hypothesis backed by evidence. Steps:

1. **File an investigation task** in the project's configured tracker (from the `## Skill profile` — a Notion DB, Linear project, or GitHub issues; if none configured, ask the user). Include:
   - **Title**: `Bug investigation: <short description>`
   - **Status / Priority / Tags**: per the project's defaults (raise priority if the bug blocks a critical user flow or causes prod errors).
   - **Body**: full markdown of the symptoms, every reproduction attempt, every hypothesis tried and ruled out, every log/trace, the original report link. Include enough that another engineer can pick this up cold.
   - Link the current PR if one exists.
2. **Tell the user** explicitly: the bug is not yet root-caused, the task is filed, no fix was shipped.
3. **Do not** ship a speculative fix "just in case." A wrong fix at the wrong layer hides the real bug and adds debt.

## Things to remember

- A tracker task is a hypothesis, not a spec.
- A unit test that mutates fabricated state and calls a function directly is not a reproduction of a real-path bug.
- If the framework already manages request/job context, justify any fresh-context/fork against that fact before adding one.
- Test/CLI-only "run it synchronously" helpers never belong in production code.
- If the fix touches three files in three layers, you're probably at the wrong layer.
- Lint + typecheck before declaring done. CI will catch it; you should too.
- If a reproduction works locally but the user reports it only in a deployed environment, the diagnose phase must explain *what about the environment differs* before claiming a fix. Don't ship environment-specific fixes without environment-specific evidence.
