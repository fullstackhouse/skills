---
name: cerber
description: Drive cerber (@fullstackhouse/cerber) — the AI code-review cockpit — from a Claude session. Use when asked to "/fsh:cerber", review a PR "with cerber", review everything awaiting the user's review, walk through a cerber artifact in chat, check review-queue status, or send a finished cerber review. Reviews are local artifacts; NOTHING is sent to GitHub without the user's explicit approval in this session.
---

# cerber

Wrapper around the `cerber` CLI (npm: `@fullstackhouse/cerber`, repo:
github.com/fullstackhouse/cerber). Cerber has Claude review PRs into local
JSON artifacts (summary, chaptered walkthrough, draft inline comments,
verdict + confidence) stored in `~/.cerber/reviews/`. A local cockpit
(`cerber serve`, port 4820) renders them.

Resolve the binary in this order: `cerber` on PATH → `npx @fullstackhouse/cerber`.

## Commands

```bash
cerber review <pr-url|owner/repo#n> [-m sonnet] [--force]   # AI-review one or more PRs
cerber review --awaiting-me [-R owner/repo] [-P 3]          # everything awaiting the user's review
cerber list                                                 # queue + verdicts
cerber export <pr>                                          # artifact as markdown (stdout)
cerber stats                                                # calibration: verdict agreement, comment survival
cerber send <pr> [-e APPROVE|COMMENT|REQUEST_CHANGES] --yes # THE ONLY GitHub write
cerber serve [--daemon ...]                                 # cockpit; daemon polls & pre-reviews
```

Reviews cost ~$0.60–0.90 and take 1–3 min each; they run via the user's
`claude` login. `review` is idempotent: same head SHA → instant skip.

## Workflows

**Review a PR and walk it through in chat.** Run `cerber review <pr>`, then
read the artifact JSON (`~/.cerber/reviews/<owner>__<repo>__<n>.json`) and
present: verdict + confidence, the summary, then chapter by chapter (title,
explanation, its comments). Offer edits — apply them by editing the artifact
JSON directly (comments[].body / status: "draft"|"approved"|"dropped";
bump updatedAt) or tell the user to open `cerber serve`.

**Queue triage.** `cerber review --awaiting-me`, then `cerber list` and
summarize: per PR — verdict, confidence, comment count; recommend which to
look at first (request_changes first, then lowest confidence).

**Send.** Only after the user has seen the review (in chat or cockpit) and
explicitly says to send in this session. Then `cerber send <pr> --yes`
(add `-e <EVENT>` if the user overrides the verdict). Never run `send` on
your own initiative; never use `--auto-send` on the user's behalf.

## Hard rules

- NEVER send, approve, or request changes on GitHub without the user's
  explicit go in the current session. Drafting and reviewing is free;
  sending is the user's decision.
- Don't re-review fresh artifacts (`--force`) unless asked — it costs money.
- Artifact JSONs are user-editable state — edit surgically, never rewrite
  wholesale; unknown fields must survive (write only what you changed).
