# AGENTS.md

This repo is a Claude Code plugin (**`fsh`**) and a single-plugin marketplace
(`fullstackhouse-skills`). It contains no application code — the deliverable is the
skills themselves, in `skills/<name>/SKILL.md` (+ optional `scripts/`, `templates/`,
`references/`).

## Bump the version — this is not optional

**Any change under `skills/**` or `.claude-plugin/**` MUST bump `version` in
`.claude-plugin/plugin.json` in the same PR.** Do it as part of the edit, not as an
afterthought at PR time.

Why: Claude Code decides whether an installed plugin is up to date by comparing the
**version string**, not the git SHA. `autoUpdate` refreshes the marketplace *listing*,
but an existing install of `fsh@0.1.0` stays frozen at `0.1.0` until the version
changes. This repo already hit it — three skills (`design-explore`, `design-polish`,
`project-status`) merged without a bump and were invisible to everyone who had
installed earlier. The skills were on `main` and still nobody had them.

- **patch** — wording/fix-only edits to an existing skill.
- **minor** — a new skill, or a new capability in an existing one.
- **major** — a breaking change to a skill's contract or to the profile knobs.
- One bump per PR is enough. Don't bump per-commit.
- Editing only `README.md` / `AGENTS.md` / `LICENSE` / `.github/**` needs no bump.

CI enforces this (`.github/workflows/version-check.yml`): a PR touching `skills/**` or
`.claude-plugin/**` fails unless `version` is strictly above the base branch's. Treat
CI as the backstop, not the reminder.

New skill? Also add a row to the README's skill table.

## Client confidentiality

Anything a skill publishes outside FSH — a PR to a repo we don't own, a public diff or
commit message, a status in a client's Slack — must carry **no non-public detail of any
FSH client**: names, staff, repo names, local paths, internal spec/ticket IDs,
name-carrying identifiers (module or env-var prefixes, service names), infrastructure,
or their data. Only exception: a detail already public in the client's own material,
verified rather than assumed.

The trap is provenance. "Upstreams client X's field-proven module" reads as generous
engineering and leaks a client name into a permanent public record. Keep the
engineering claim, drop the address: "upstreams a pattern already running in production
downstream."

The gate lives in each skill that publishes — `upstream-pr`, `deliver`, `pr-polish`,
`project-status`. Each carries its own copy so a single-skill symlink install still
enforces it: **when you edit one copy, sync the others.**

## Conventions

- Skills are agent-facing procedures: concise, imperative, exact commands, explicit
  decision points. Distill — don't paste docs verbatim.
- Most skills are **repo-agnostic**: derive project specifics at runtime from the
  consuming repo's `CLAUDE.md` / `AGENTS.md` / `package.json`, or from its
  `## Skill profile` section. Don't hardcode a client's paths, commands, or policy.
- Bundled `scripts/` are POSIX `sh`/`bash`, idempotent, safe to re-run.
- Bundled `templates/` use `{{PLACEHOLDER}}` tokens the skill substitutes.
- A skill's `description:` frontmatter is its only trigger — it must say *when* to use
  the skill, not just what it does.

See [README.md](./README.md) for install, the skill table, and the `Skill profile` knobs.
