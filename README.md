# fullstackhouse/skills

Private collection of FullstackHouse Claude Code skills.

## Skills

| Skill | Purpose |
|-------|---------|
| [`mercato-bootstrap`](./skills/mercato-bootstrap/SKILL.md) | Bootstrap an [Open Mercato](https://github.com/open-mercato/open-mercato) app into a monorepo following FSH conventions (scaffold → ports → DB → verify → CI/infra). |
| [`explain`](./skills/explain/SKILL.md) | Explain an existing change (working tree / branch / PR / commit) in plain language with a clearly-hedged merge recommendation. Read-only. |
| [`deliver`](./skills/deliver/SKILL.md) | Front-load CI locally, open/update a PR, request a reviewer, address feedback, auto-merge if changes since invocation are minimal. |
| [`bug-hunt`](./skills/bug-hunt/SKILL.md) | Reproduce → diagnose → failing-test → fix a reported bug at the narrowest correct layer. Forbids speculative fixes; files a tracker task on give-up. |
| [`flake-hunt`](./skills/flake-hunt/SKILL.md) | Root-cause and fix a flaky Playwright e2e test. Forbids timeouts/retries/skip; files a tracker task on give-up. |
| [`project-status`](./skills/project-status/SKILL.md) | Draft a project status update for the project's Slack channel: gather Linear/Notion + GitHub activity since the last status, reconcile the roadmap with reality, draft progress / blockers / what's next. Never posts without approval. |

`explain`, `deliver`, `bug-hunt`, `flake-hunt`, and `project-status` are **repo-agnostic** — they derive
project-specific commands, paths, and policy at runtime (see [Skill profile](#skill-profile)
below). A repo with its own sharper, hardcoded variant can keep it in its `.claude/skills/`
alongside these (plugin skills are namespaced, so they don't collide — see Install).

## Install

### Local (personal scope) — for use right now on your machine

Symlink the skills you want into `~/.claude/skills/`:

```bash
mkdir -p ~/.claude/skills
ln -sfn ~/src/fullstackhouse/skills/skills/mercato-bootstrap ~/.claude/skills/mercato-bootstrap
```

They become invocable as `/<skill-name>` (e.g. `/mercato-bootstrap`) in any session.

### Team (marketplace) — for distribution

This repo is both a Claude Code plugin (`.claude-plugin/plugin.json`) and a
single-plugin marketplace (`.claude-plugin/marketplace.json`). Because the repo
is **private**, every consumer machine must already be able to clone it
(SSH key or `gh auth` with read access) — the install uses your local git
credentials.

The marketplace is named `fullstackhouse-skills`; the plugin inside it is named
**`fsh`** (so its skills invoke as `/fsh:<skill-name>`, e.g. `/fsh:bug-hunt`).

**Per-user (all repos on a machine):**

```
/plugin marketplace add fullstackhouse/skills
/plugin install fsh
```

Skills then resolve as `/fsh:<skill-name>` everywhere, pinned to a commit SHA.

**Per-repo (zero-touch for everyone who opens a given repo):** commit this to
the consuming repo's `.claude/settings.json`. The SSH source avoids HTTPS-token
ambiguity for the private repo:

```jsonc
{
  "extraKnownMarketplaces": {
    "fullstackhouse-skills": {
      "source": { "source": "git", "url": "git@github.com:fullstackhouse/skills.git" }
    }
  },
  "enabledPlugins": { "fsh@fullstackhouse-skills": true }
}
```

> Headless/CI runners (and fresh Conductor worktrees) need git access to this
> repo too, or the marketplace step fails. Gate it or add a deploy key if that
> matters.

**Plugin skills are namespaced** (`/fsh:<name>`), so they never collide with a
consuming repo's own `.claude/skills/<name>` (which keeps the bare `/<name>`).
A repo can therefore keep a sharper, hardcoded variant locally *and* get the
generic one from the plugin. The only thing to watch is intentional divergence
between the two copies — that's expected, not a bug.

## Skill profile

The repo-agnostic skills (`deliver`, `bug-hunt`, `flake-hunt`; `explain` to a lesser
extent) derive most specifics at runtime from the consuming repo's `CLAUDE.md` /
`AGENTS.md` / `package.json` scripts. For knobs that aren't derivable from docs, add a
**`## Skill profile`** section to the consuming repo's root `CLAUDE.md`. Recognized knobs:

- **Packages → check commands** — how to lint / typecheck / test / run codegen per workspace.
- **Single e2e spec command** + Playwright project root and any worker constraints
  (e.g. local must run `workers=1`).
- **Give-up tracker** — where `bug-hunt` / `flake-hunt` file a task: a Notion database
  (URL + data-source/collection id), a Linear project, or GitHub issues, plus default
  status / priority / tags.
- **PR reviewer bot** login (default `copilot-pull-request-reviewer`).
- **ownerCanSelfMerge** — whether `deliver` may `gh pr merge --admin` (default: no).
- **Dev-server / port convention** (e.g. a Conductor worktree port rule) for repro/local runs.
- **Status reporting** (`project-status`) — Slack status channel, tracker (Linear team/project
  IDs and/or Notion database), roadmap source (Linear projects/cycles or a Notion page),
  and audience (e.g. non-technical business owner).

Repo slug and default branch are derived from `git` / `gh`, not the profile. If a needed
knob is missing, the skills fall back to asking you.

## Conventions

- Skills are agent-facing procedures: concise, imperative, with exact commands and
  explicit decision points. Distill — don't paste docs verbatim.
- Bundled `scripts/` are POSIX `sh`/`bash`, idempotent, and safe to re-run.
- Bundled `templates/` use `{{PLACEHOLDER}}` tokens the skill substitutes.
