---
name: prior-issue
description: >-
  Answer "is there an issue/PR about this?" — find existing issues, tickets and pull
  requests (open, closed or merged) about a bug, error, behaviour or feature request
  before anyone files a new one or starts work. Searches the owning project's tracker:
  GitHub issues + PRs by default for a third-party library or tool, the repo's configured
  tracker (Linear, Notion, Jira, GitHub…) for our own project. Reports each hit with its
  real state and, when none, exactly what was searched. Use when asked "is there an
  issue/PR about this?", "has anyone reported this?", "is this already tracked?", "is
  there a fix upstream?", or before filing a ticket or an upstream issue. Read-only.
---

# prior-issue

Goal: one short answer to "is this already tracked somewhere?" — with links and real states,
or a negative someone can check.

**Read-only.** Never file, comment, react, or change a status. Route that to the user or to
the skill that owns it (§5).

## 1. Pin the subject

"This" usually points at the conversation. Restate it in one line before searching: the
symptom or request, the component, and **whose code it is** — ours, or a dependency's
(library, framework, CLI, SaaS). Ask only if the conversation genuinely doesn't say.

Collect search terms:

- **Verbatim strings** — error messages (strip paths, IDs, numbers), log lines, flags,
  config keys, function/class names.
- **Plain wording** — how a reporter would describe it, plus 2–3 synonyms. Titles rarely
  use the words you'd use ("totals are off" vs "rounding in summary aggregation").
- **Version** — what's installed here (lockfile, `--version`), so you can judge whether a
  fix has shipped.

## 2. Pick where to search

| Subject | Search | Default |
|---|---|---|
| Third-party library / tool | Its upstream tracker | GitHub issues + PRs of its repo |
| Our own project | The repo's **Tracker** knob, plus the code host's PRs | GitHub issues + PRs of this repo |
| Our bug caused by a dependency | Both — our workaround ticket and the upstream issue | — |

- **Finding the upstream repo** — `package.json` `repository`, `npm view <pkg> repository.url`,
  `pip show`/PyPI project URLs, `go.mod` module path, the docs site's "GitHub" link. A
  monorepo package's issues live in the monorepo. If the project tracks elsewhere (GitLab,
  Jira, a forum, GitHub Discussions), say so and search there.
- **Our tracker** — the `## Skill profile` **Tracker** knob in `AGENTS.md`/`CLAUDE.md`;
  else whatever the agent docs name; else whichever tracker MCP the session has (Linear,
  Notion, Jira); else GitHub issues. PRs always live on the code host — search them too.
- A tracker you can't reach (MCP unauthenticated, no access): say which, and search the rest.

## 3. Search — meaning first, then exact strings, all states

GitHub's default search is **lexical**: every word must appear, so a reporter's different
wording or an error code you didn't type hides the issue. Run three kinds of query per
place, and **include closed and merged**: a closed issue often holds the answer, the
workaround, or the "won't fix".

1. **Hybrid (semantic + keyword) on plain wording.** This is the main query. `gh search`
   can't do it; call the API:

   ```sh
   gh api -X GET search/issues -f search_type=hybrid -f per_page=10 \
     -f q='repo:<owner/repo> is:issue <plain description of the problem>' \
     --jq '.search_type, (.items[] | "#\(.number) [\(.state)] \(.title) \(.html_url)")'
   ```

   Run it again with `is:pr` for PRs. Use `search_type=semantic` when hybrid still pulls in
   keyword noise. Quotes, `OR`, or a query that is only filters silently drop it back to
   lexical, and the response's `search_type` field shows which one ran. Limit: 10 req/min.
2. **Lexical on verbatim strings**, i.e. error codes, symbols, config keys:

   ```sh
   gh search issues --repo <owner/repo> --include-prs --limit 20 \
     --json number,title,state,isPullRequest,url '"<exact error text>"'
   ```

   Add `in:comments` when a stack trace is likely pasted in a thread.
3. **Web search**, when the repo turns up nothing or you don't know which repo owns the
   problem: `site:github.com "<error text>"` (other repos, forks, Discussions), then the
   error text on its own (Stack Overflow, forums, the project's Discourse/Discord archive).
   It also catches a fix that landed in a *different* project, e.g. a transitive dependency.

Org-wide: `org:<org>` in `q` / `--owner <org>`. Linear/Notion/Jira: their search tool
on the wording, plus a structured filter (project, label) when the knob names one.

## 4. Read the hits — never judge by title

Open the top candidates (usually ≤5) and read body + latest comments:

- **Same thing?** Same root cause, not just the same symptom words. Mark *match*,
  *related*, or drop it.
- **Follow the trail** — "duplicate of", "superseded by", "fixed in #N", linked PRs,
  cross-referenced issues. Report where it ends, not where it starts.
- **Real state** — open / closed-fixed / closed-wontfix / stale; a PR merged, open, or
  closed unmerged. For a merged fix: which release contains it
  (`gh api repos/<o>/<r>/releases`, tags, changelog) vs the version installed here.
  Merged is not released; released is not installed.

## 5. Report

Lead with the verdict in one line — **tracked** / **related only** / **nothing found** —
then one line per hit, best first:

```
- <owner/repo#N or TICKET-ID> <title> — <state; release vX.Y / installed vA.B> — <why it matches, one clause>
  <url>
```

- **Nothing found** — list the places, the exact queries and their search type (hybrid/lexical/web), so the negative is checkable
  and cheap to re-run.
- **One next step**, suggested not taken: upvote/comment on the match, bump the dependency
  to the release with the fix, carry the unreleased fix locally (`patch`), file new
  (`upstream-pr` for an upstream fix, the repo's own issue skill or tracker otherwise),
  or refresh a stale ticket (`ticket-refresh`).

Keep it to one screen. No narrative of the search beyond the query list on a negative.
