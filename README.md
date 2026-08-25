# fullstackhouse/skills

Full Stack House's collection of Claude Code skills — the agent workflow we actually use to
ship: deliver PRs, hunt bugs and flaky tests, explain changes, report status, polish UI, and
read what a counterparty changed in a contract.

## Skills

| Skill | Purpose |
|-------|---------|
| [`explain`](./skills/explain/SKILL.md) | Explain an existing change (working tree / branch / PR / commit) in plain language with a clearly-hedged merge recommendation. Read-only. |
| [`om-test-drive`](./skills/om-test-drive/SKILL.md) | `explain`'s hands-on counterpart, for Open Mercato: boot the change on a throwaway instance (`mercato test:ephemeral`) → prove login with a real HTTP round-trip → seed the data that makes it visible through the app's own API → hand back a click route with a live URL and credentials. Carries the bootstrap ordering and the production-mode config traps that make a first boot fail. No browser, so it proves routing and data, not rendering — and says so. Posts nothing. |
| [`brainstorm`](./skills/brainstorm/SKILL.md) | Divergent conversation before any artifact exists: question the idea, weigh alternatives incl. building nothing, reality-check the tracker, survive a fresh-context challenger — then converge on one routed next step (drop it / park as ticket / `kickoff` / `bug-hunt`) with a handoff brief. Read-only until the routing is confirmed. |
| [`kickoff`](./skills/kickoff/SKILL.md) | Idea / brainstorm brief / ticket → ready-for-review PR: decides plan depth itself (spec in the repo's spec location, or straight to code), implements with tests, then runs `deliver --no-merge` for checks, PR, reviewer, and the feedback loop. Never merges. |
| [`overnight`](./skills/overnight/SKILL.md) | A backlog → a stack of ready-for-review PRs, one per item: classify each item's *decision state*, order them into a dependency graph, batch every open question across every item into one interactive round, then run unattended — each item through `kickoff --base <parent branch>`. A failed item stops its descendants only. Never merges. |
| [`deliver`](./skills/deliver/SKILL.md) | Front-load CI locally, open/update a PR, request a reviewer, address feedback, auto-merge if changes since invocation are minimal (or stop at ready-for-review with `--no-merge`). `--base <branch>` targets a parent branch instead of the repo default, so a stacked PR shows only its own increment. |
| [`upstream-pr`](./skills/upstream-pr/SKILL.md) | Open/update a cross-repository (fork) PR: resolve the fork/upstream/base/permission triangle explicitly, push to the fork, target the upstream's real base branch, close a now-duplicate fork PR as superseded, degrade to a single comment when you lack write access. Never merges. |
| [`pr-polish`](./skills/pr-polish/SKILL.md) | Rewrite a PR's title/description so they match the branch as it stands and read top-down: problem → fix → details → verification. Verifies every claim (incl. referenced PRs' current state) before writing. Metadata-only. |
| [`ticket-refresh`](./skills/ticket-refresh/SKILL.md) | `pr-polish` for a tracker ticket: re-verify its body against reality — resolve every linked PR/issue (following supersessions), check whether an "upstream" fix already ships in the installed version, and rewrite claims the world has overtaken, then post one comment so watchers learn what changed. Body + comment only; never touches Status/Assignee. |
| [`ticket-polish`](./skills/ticket-polish/SKILL.md) | `ticket-refresh`'s complement: refresh makes a body true, polish makes it legible. Restructure an accreted ticket — one canonical enumeration instead of parallel numbering, open work leads, history compressed to its surviving reasoning, a checkable DoD of only the remaining work, title re-trued. Form only, facts unchanged — it runs `ticket-refresh` itself when the body's facts have gone stale, so a neglected ticket needs one invocation, not two. |
| [`spec-polish`](./skills/spec-polish/SKILL.md) | `ticket-polish` for a spec or design doc: a first screen a newcomer can stop after, the decision the doc asks of its reader up front, the argument before the evidence, catalogues and traceability ids moved to appendices, mandated sections kept but in reader order. Form only, facts unchanged — spot-checks the spec's evidence against the code first and refuses to polish stale claims. |
| [`docs-audit`](./skills/docs-audit/SKILL.md) | Audit a repo's documentation and agent instructions against the house conventions, then fix the mechanical and propose the rest: instruction-budget overflow (the rules an agent never receives), `CLAUDE.md`/`AGENTS.md` drift, commands that no longer resolve, dead links, unindexed docs, spec-convention breaks, state docs narrating their own history. Ships a CI gate so the rules hold without re-running it. `--audit-only` writes nothing. |
| [`review-queue`](./skills/review-queue/SKILL.md) | Triage every PR awaiting your review: classify the queue, fan out one read-only reviewer subagent per PR, merge into a linked triage table (verdicts, draft comments, cross-PR conflicts). Posts nothing without explicit per-action approval. |
| [`review-loop`](./skills/review-loop/SKILL.md) | Drive a change to "nobody finds anything anymore": review → fix → re-review, with a **fresh reviewer each round that never sees why the fix was made**, across five lenses; dedupe against every finding ever raised (rejected ones included, or it never goes dry), refute each fresh finding before fixing it, and exit on N *consecutive* empty rounds rather than a fixed count. Reports the findings-per-round curve and claims exactly what that proves. Local only — posts nothing, merges nothing. |
| [`bug-hunt`](./skills/bug-hunt/SKILL.md) | Reproduce → diagnose → failing-test → fix a reported bug at the narrowest correct layer. Forbids speculative fixes; files a tracker task on give-up. |
| [`flake-hunt`](./skills/flake-hunt/SKILL.md) | Root-cause and fix a flaky Playwright e2e test. Forbids timeouts/retries/skip; files a tracker task on give-up. |
| [`project-status`](./skills/project-status/SKILL.md) | Draft a project status update for the project's Slack channel: gather Linear/Notion + GitHub activity since the last status, reconcile the roadmap with reality, draft progress / blockers / what's next. Never posts without approval. |
| [`design-polish`](./skills/design-polish/SKILL.md) | Audit and improve a web app/prototype's visual design and UX (Refactoring UI + UX heuristics): screenshot via Playwright → prioritized audit → targeted fixes reusing design tokens → re-screenshot to verify. |
| [`design-explore`](./skills/design-explore/SKILL.md) | Divergent counterpart to `design-polish`: build ~3 structurally different working alternatives of a screen with the existing design system, screenshot them side by side, present trade-offs + a recommendation, and let the user pick. |
| [`docx-diff`](./skills/docx-diff/SKILL.md) | Reconstruct a redline between two `.docx` versions when the counterparty edited without tracked changes: pandoc → sentence-level unified diff → a classification of which changes are material and who they favour. Needs `pandoc`. |
| [`bro`](./skills/bro/SKILL.md) | Restate the last message in plain human language — no jargon, one human talking to another. Manual-invoke only. |
| [`zoom-out`](./skills/zoom-out/SKILL.md) | Break mid-task tunnel vision: restate the goal from the original request, mark sunk work ignorable, measure the decision space, get a fresh-context second opinion (subagent that never sees the current approach), present 2–3 options-in-kind + a recommendation. Analysis only until the user picks. |

`explain`, `brainstorm`, `kickoff`, `overnight`, `deliver`, `upstream-pr`, `pr-polish`, `ticket-refresh`, `ticket-polish`, `spec-polish`, `docs-audit`, `review-queue`, `review-loop`, `bug-hunt`, `flake-hunt`, `project-status`, `design-polish`, and `design-explore` are **repo-agnostic** — they derive
project-specific commands, paths, and policy at runtime (see [Skill profile](#skill-profile)
below). A repo with its own sharper, hardcoded variant can keep it in its `.claude/skills/`
alongside these (plugin skills are namespaced, so they don't collide — see Install).

## Install

### Local (personal scope) — for use right now on your machine

Symlink the skills you want into `~/.claude/skills/`:

```bash
mkdir -p ~/.claude/skills
ln -sfn ~/src/fullstackhouse/skills/skills/bug-hunt ~/.claude/skills/bug-hunt
```

They become invocable as `/<skill-name>` (e.g. `/bug-hunt`) in any session.

### Team (marketplace) — for distribution

This repo is both a Claude Code plugin (`.claude-plugin/plugin.json`) and a
single-plugin marketplace (`.claude-plugin/marketplace.json`).

The marketplace is named `fullstackhouse-skills`; the plugin inside it is named
**`fsh`** (so its skills invoke as `/fsh:<skill-name>`, e.g. `/fsh:bug-hunt`).

**Per-user (all repos on a machine):**

```
/plugin marketplace add fullstackhouse/skills
/plugin install fsh
```

Skills then resolve as `/fsh:<skill-name>` everywhere, pinned to a commit SHA.

**Per-repo (zero-touch for everyone who opens a given repo):** commit this to
the consuming repo's `.claude/settings.json`:

```jsonc
{
  "extraKnownMarketplaces": {
    "fullstackhouse-skills": {
      "source": { "source": "git", "url": "https://github.com/fullstackhouse/skills.git" }
    }
  },
  "enabledPlugins": { "fsh@fullstackhouse-skills": true }
}
```

**Plugin skills are namespaced** (`/fsh:<name>`), so they never collide with a
consuming repo's own `.claude/skills/<name>` (which keeps the bare `/<name>`).
A repo can therefore keep a sharper, hardcoded variant locally *and* get the
generic one from the plugin. The only thing to watch is intentional divergence
between the two copies — that's expected, not a bug.

## Skill profile

The repo-agnostic skills (`deliver`, `upstream-pr`, `bug-hunt`, `flake-hunt`;
`explain` to a lesser extent) derive most specifics at runtime from the consuming repo's `CLAUDE.md` /
`AGENTS.md` / `package.json` scripts. For knobs that aren't derivable from docs, add a
**`## Skill profile`** section to the consuming repo's root `CLAUDE.md`. Recognized knobs:

- **Packages → check commands** — how to lint / typecheck / test / run codegen per workspace.
- **Single e2e spec command** + Playwright project root and any worker constraints
  (e.g. local must run `workers=1`).
- **Tracker** — where `bug-hunt` / `flake-hunt` file a give-up task: a Notion database
  (URL + data-source/collection id), a Linear project, or GitHub issues, plus default
  status / priority / tags. Name the **status vocabulary** too — which states mean *in
  progress*, *in review*, *done* — and `deliver` moves the PR's task along with the PR.
  Without it `deliver` reports the task's state instead of guessing at state names.
  `ticket-refresh` and `ticket-polish` read the same knob to find and rewrite a ticket's
  body, and to post the comment recording the rewrite — but never move its status. Say if the tracker's
  comments are unusable (no API, or nobody reads them); the skill skips the comment
  rather than folding the narration back into the body.
- **Specs** — where feature specs and design docs live: a repo directory + naming pattern
  (e.g. `docs/specs/YYYY-MM-DD-slug.md`) or a tracker/Notion location, plus how deep a spec
  is expected to go. `kickoff` writes its spec there when the work warrants one, and
  `brainstorm` keeps its handoff briefs beside them (`<specs dir>/briefs/`); `spec-polish`
  reads the same knob to find the specs on a branch and the sections the repo mandates; `docs-audit` uses it to locate the spec directory it grades for template, index and naming. Without the
  knob or a discoverable convention, `kickoff` writes the plan into the tracker ticket
  itself (when a Tracker is configured) or the PR description, and `brainstorm` falls back
  to `.context/briefs/` when `.context/` exists (otherwise it asks where briefs go).
- **PR reviewer bot** login (default `copilot-pull-request-reviewer`).
- **Review landmines** (`review-queue`) — standing repo-specific checks every PR reviewer
  agent must apply (perf-sensitive paths, known CI false-fails, encryption/tenancy rules),
  plus the scratch dir for triage reports (default `.context/pr-review/` when present).
- **ownerCanSelfMerge** — whether `deliver` may `gh pr merge --admin` (default: no).
- **forkRemote** — the remote `upstream-pr` pushes to when contributing from a fork
  (default: auto-detected from the branch's remote / `@{push}` / remote classification).
- **baseBranch** — the PR base when it differs from the GitHub default branch
  (default: auto-detected — repo agent config → this profile → CONTRIBUTING/PR template →
  default branch). This is the repo's standing default; for a single run, `deliver --base
  <branch>` and `kickoff --base <branch>` override it, which is how a stacked PR targets
  its parent instead of the base branch.
- **Dev-server / port convention** (e.g. a Conductor worktree port rule) for repro/local runs.
- **Throwaway instance** (`om-test-drive`) — how to stand up a disposable app + database, and
  how to talk to it. Four fields: the **boot command**; where it **records its base URL**; the
  **credentials** it guarantees; and the **auth contract** — login route, method, payload shape,
  and whether it returns a bearer token or sets a session cookie. That last field is not
  optional on a non-Mercato repo: the skill's verification and seeding phases are written around
  Open Mercato's `POST /api/auth/login` → `{token}`, so without it the skill boots and then
  stops rather than guessing at a login route. Open Mercato repos need no entry at all
  (`yarn test:integration:ephemeral:start` → `.ai/qa/ephemeral-env.json` → `admin@acme.com` /
  `secret`). If the only available environment is long-lived or shared, say so here —
  `om-test-drive` then refuses to seed it and drives read-only, rather than asking for
  permission it shouldn't act on.
- **Status reporting** (`project-status`) — Slack status channel, tracker (Linear team/project
  IDs and/or Notion database), roadmap source (Linear projects/cycles or a Notion page),
  and audience (e.g. non-technical business owner).

Repo slug and default branch are derived from `git` / `gh`, not the profile. If a needed
knob is missing, the skills fall back to asking you.

## Releasing (bump the version — this is not optional)

**Any PR that adds, removes, renames, or changes a skill MUST bump `version` in
[`.claude-plugin/plugin.json`](./.claude-plugin/plugin.json) in the same PR.**

Why it matters — the failure mode this repo already hit: Claude Code decides
whether an installed plugin is up to date by comparing the **version string**,
not the git SHA. `autoUpdate` on the marketplace refreshes the *listing*, but an
existing install of `fsh@0.1.0` stays frozen at `0.1.0` until the version
changes. Three skills (`design-explore`, `design-polish`, `project-status`) were
merged without a bump, so everyone who installed earlier silently never received
them — the skills were on `main` but invisible to consumers.

Rules:

- Bump per [SemVer](https://semver.org/): **patch** for wording/fix-only edits to
  an existing skill, **minor** for a new skill or a new capability, **major** for
  a breaking change to a skill's contract or the profile knobs.
- One bump per PR is enough — don't bump per-commit.
- CI enforces this: [`.github/workflows/version-check.yml`](./.github/workflows/version-check.yml)
  fails a PR that touches `skills/**` or `.claude-plugin/**` without raising the
  version above the base branch's.

After a version bump lands on `main`, consumers pick it up on their next
marketplace refresh. To force it immediately:

```
/plugin marketplace update fullstackhouse-skills
/plugin uninstall fsh@fullstackhouse-skills
/plugin install fsh@fullstackhouse-skills
```

(New/updated skills take effect in the *next* session, not mid-session.)

## Client confidentiality

Anything a skill publishes outside FSH — a PR to a repo we don't own, a public repo's diff
and commit messages, a status posted in one client's Slack channel — must carry **no
non-public detail of any FSH client**: names, staff, repo names, local paths, internal
spec/ticket IDs, name-carrying identifiers (module or env-var prefixes, service names),
infrastructure, or their data. The only exception is a detail already public in the client's
own material, verified rather than assumed.

The trap is provenance. Crediting where a pattern was proven ("upstreams client X's
field-proven module") reads as generous engineering and leaks a client name into a permanent
public record; the fix is to keep the engineering claim and drop the address ("upstreams a
pattern already running in production downstream"). This has happened once, in a public
upstream PR — hence the gates.

Enforcement lives in the skills that publish: `upstream-pr` (Phase 2 guardrail + Phase 5 body
re-scan + hard rule), `deliver` (Phase 2b, gated on repo visibility/owner + hard rule),
`pr-polish` (verification step, incl. leaks inherited from the old body), `project-status`
(one client per status). Each carries its own copy so a single-skill symlink install still
enforces it — keep them in sync when editing one.

## Conventions

- Skills are agent-facing procedures: concise, imperative, with exact commands and
  explicit decision points. Distill — don't paste docs verbatim.
- Bundled `scripts/` are POSIX `sh`/`bash`, idempotent, and safe to re-run.
- Bundled `templates/` use `{{PLACEHOLDER}}` tokens the skill substitutes.
- **Bump `plugin.json` `version` in the same PR as any skill change** (see
  [Releasing](#releasing-bump-the-version--this-is-not-optional)) — CI enforces it.
- **A skill that publishes anything outside FSH carries the confidentiality gate** (see
  [Client confidentiality](#client-confidentiality)).

The same rules, in the form an agent reads before editing: [`AGENTS.md`](./AGENTS.md)
(`CLAUDE.md` imports it).
