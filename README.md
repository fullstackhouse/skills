# fullstackhouse/skills

Full Stack House's collection of Claude Code skills — the agent workflow we actually use to
ship: deliver PRs, hunt bugs and flaky tests, explain changes, report status, polish UI, and
read what a counterparty changed in a contract.

## Skills

| Skill | Purpose |
|-------|---------|
| [`explain`](./skills/explain/SKILL.md) | Explain an existing change (working tree / branch / PR / commit) in plain language with a clearly-hedged merge recommendation. Read-only. |
| [`deliver`](./skills/deliver/SKILL.md) | Front-load CI locally, open/update a PR, request a reviewer, address feedback, auto-merge if changes since invocation are minimal. |
| [`upstream-pr`](./skills/upstream-pr/SKILL.md) | Open/update a cross-repository (fork) PR: resolve the fork/upstream/base/permission triangle explicitly, push to the fork, target the upstream's real base branch, close a now-duplicate fork PR as superseded, degrade to a single comment when you lack write access. Never merges. |
| [`pr-polish`](./skills/pr-polish/SKILL.md) | Rewrite a PR's title/description so they match the branch as it stands and read top-down: problem → fix → details → verification. Verifies every claim (incl. referenced PRs' current state) before writing. Metadata-only. |
| [`ticket-refresh`](./skills/ticket-refresh/SKILL.md) | `pr-polish` for a tracker ticket: re-verify its body against reality — resolve every linked PR/issue (following supersessions), check whether an "upstream" fix already ships in the installed version, and rewrite claims the world has overtaken, then post one comment so watchers learn what changed. Body + comment only; never touches Status/Assignee. |
| [`ticket-polish`](./skills/ticket-polish/SKILL.md) | `ticket-refresh`'s complement: refresh makes a body true, polish makes it legible. Restructure an accreted ticket — one canonical enumeration instead of parallel numbering, open work leads, history compressed to its surviving reasoning, a checkable DoD of only the remaining work, title re-trued. Form only, facts unchanged — it runs `ticket-refresh` itself when the body's facts have gone stale, so a neglected ticket needs one invocation, not two. |
| [`review-queue`](./skills/review-queue/SKILL.md) | Triage every PR awaiting your review: classify the queue, fan out one read-only reviewer subagent per PR, merge into a linked triage table (verdicts, draft comments, cross-PR conflicts). Posts nothing without explicit per-action approval. |
| [`bug-hunt`](./skills/bug-hunt/SKILL.md) | Reproduce → diagnose → failing-test → fix a reported bug at the narrowest correct layer. Forbids speculative fixes; files a tracker task on give-up. |
| [`flake-hunt`](./skills/flake-hunt/SKILL.md) | Root-cause and fix a flaky Playwright e2e test. Forbids timeouts/retries/skip; files a tracker task on give-up. |
| [`project-status`](./skills/project-status/SKILL.md) | Draft a project status update for the project's Slack channel: gather Linear/Notion + GitHub activity since the last status, reconcile the roadmap with reality, draft progress / blockers / what's next. Never posts without approval. |
| [`design-polish`](./skills/design-polish/SKILL.md) | Audit and improve a web app/prototype's visual design and UX (Refactoring UI + UX heuristics): screenshot via Playwright → prioritized audit → targeted fixes reusing design tokens → re-screenshot to verify. |
| [`design-explore`](./skills/design-explore/SKILL.md) | Divergent counterpart to `design-polish`: build ~3 structurally different working alternatives of a screen with the existing design system, screenshot them side by side, present trade-offs + a recommendation, and let the user pick. |
| [`docx-diff`](./skills/docx-diff/SKILL.md) | Reconstruct a redline between two `.docx` versions when the counterparty edited without tracked changes: pandoc → sentence-level unified diff → a classification of which changes are material and who they favour. Needs `pandoc`. |
| [`bro`](./skills/bro/SKILL.md) | Restate the last message in plain human language — no jargon, one human talking to another. Manual-invoke only. |
| [`zoom-out`](./skills/zoom-out/SKILL.md) | Break mid-task tunnel vision: restate the goal from the original request, mark sunk work ignorable, measure the decision space, get a fresh-context second opinion (subagent that never sees the current approach), present 2–3 options-in-kind + a recommendation. Analysis only until the user picks. |
| [`lessons`](./skills/lessons/SKILL.md) | Harvest the human turns from a day's Claude Code transcripts (all of a repo's Conductor workspaces at once), rank corrections by how many *distinct* sessions hit them, and propose the survivors as durable rules — CLAUDE.md/AGENTS.md entries, memory files, or a skill fix. Proposes only; transcripts never leave the machine. |

`explain`, `deliver`, `upstream-pr`, `pr-polish`, `ticket-refresh`, `ticket-polish`, `review-queue`, `bug-hunt`, `flake-hunt`, `project-status`, `design-polish`, `design-explore`, and `lessons` are **repo-agnostic** — they derive
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

The repo-agnostic skills (`deliver`, `upstream-pr`, `bug-hunt`, `flake-hunt`; `explain` to a
lesser extent) derive most specifics at runtime from the consuming repo's `CLAUDE.md` /
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
- **PR reviewer bot** login (default `copilot-pull-request-reviewer`).
- **Review landmines** (`review-queue`) — standing repo-specific checks every PR reviewer
  agent must apply (perf-sensitive paths, known CI false-fails, encryption/tenancy rules),
  plus the scratch dir for triage reports (default `.context/pr-review/` when present).
- **ownerCanSelfMerge** — whether `deliver` may `gh pr merge --admin` (default: no).
- **forkRemote** — the remote `upstream-pr` pushes to when contributing from a fork
  (default: auto-detected from the branch's remote / `@{push}` / remote classification).
- **baseBranch** — the PR base when it differs from the GitHub default branch
  (default: auto-detected — repo agent config → this profile → CONTRIBUTING/PR template →
  default branch).
- **Dev-server / port convention** (e.g. a Conductor worktree port rule) for repro/local runs.
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
