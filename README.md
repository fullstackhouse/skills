# fullstackhouse/skills

Private collection of FullstackHouse Claude Code skills.

## Skills

| Skill | Purpose |
|-------|---------|
| [`mercato-bootstrap`](./skills/mercato-bootstrap/SKILL.md) | Bootstrap an [Open Mercato](https://github.com/open-mercato/open-mercato) app into a monorepo following FSH conventions (scaffold → ports → DB → verify → CI/infra). |

## Install

### Local (personal scope) — for use right now on your machine

Symlink the skills you want into `~/.claude/skills/`:

```bash
mkdir -p ~/.claude/skills
ln -sfn ~/src/fullstackhouse/skills/skills/mercato-bootstrap ~/.claude/skills/mercato-bootstrap
```

They become invocable as `/<skill-name>` (e.g. `/mercato-bootstrap`) in any session.

### Team (marketplace) — for distribution

This repo is a Claude Code plugin (`.claude-plugin/plugin.json`). Once pushed to
`github.com/fullstackhouse/skills`, install across machines with:

```
/plugin marketplace add fullstackhouse/skills
/plugin install fullstackhouse-skills
```

> The `marketplace.json` manifest is finalized when we publish — see the issue tracker.

## Conventions

- Skills are agent-facing procedures: concise, imperative, with exact commands and
  explicit decision points. Distill — don't paste docs verbatim.
- Bundled `scripts/` are POSIX `sh`/`bash`, idempotent, and safe to re-run.
- Bundled `templates/` use `{{PLACEHOLDER}}` tokens the skill substitutes.
