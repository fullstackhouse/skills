---
name: project-status
description: Draft a periodic project status update for the project's Slack channel. Finds the last posted status, gathers everything since (Linear/Notion issues, roadmap changes, GitHub PRs/commits), verifies the roadmap still reflects reality (interactively fixing drift), then drafts a business-owner-readable update covering progress, blockers, and what's next. Never posts to Slack without explicit approval.
---

# project-status

You are running the **project-status** skill. Goal: produce a status update draft for the project's Slack channel that lets the team and business owner see, at a glance, what happened since the last status, what's blocked, and what's coming next — without reading the tracker themselves.

The draft is the deliverable. **Never post to the channel yourself** unless the user explicitly approves the final text.

## Project specifics — read these first

This skill is repo-agnostic. Gather from the consuming repo's `CLAUDE.md` / `AGENTS.md` (a **`## Skill profile`** section is the curated source):

- **Status channel** — Slack channel where statuses are posted (name or ID).
- **Tracker** — Linear team/project ID(s), and/or Notion database/page for tasks.
- **Roadmap source** — where priorities live: Linear projects/initiatives/cycles, a Notion roadmap page, or both.
- **Audience** — who reads the status (e.g. non-technical business owner). Default: mixed technical/non-technical.
- **Repo slug(s)** — `gh repo view --json nameWithOwner -q .nameWithOwner`; the profile may list extra repos to sweep.

If a needed value is missing and not inferable, ask the user before gathering — a status against the wrong channel or tracker is wasted work.

## Phases

### 1. Anchor — find the last status

Search the status channel for the most recent status post (search for distinctive markers of prior statuses: title format, the posting user, a recurring emoji/heading). From it, record:

- **Window start** = its timestamp. If no prior status exists, default to 7 days ago and tell the user.
- **Its "up next" section** — you will report on every item in it (see Continuity below).
- **Thread replies and reactions** — questions or follow-ups raised on the last status that this one should answer.

### 2. Gather — everything since the window start

Fan out subagents in parallel; each returns raw structured facts, not prose:

- **Tracker (Linear and/or Notion)**: issues completed, started, created, or reprioritized in the window; project/initiative updates and target-date changes; current cycle state. Capture identifiers and URLs.
- **GitHub**: merged PRs (`gh pr list --search "merged:>=<date>" --json ...`), open PRs and their review state, notable default-branch commits. Map PRs to tickets via branch names / ticket IDs in titles.
- **Roadmap source**: current top priorities and target dates, plus what changed in the window.
- **Slack channel** (optional, same channel only): decisions or blockers discussed since the last status.

### 3. Reconcile — verify the roadmap reflects reality

Cross-check before writing; this is what makes the status trustworthy:

- PRs merged but the linked ticket isn't done → stale ticket.
- Tickets marked done with no corresponding change → verify they actually shipped.
- Projects/milestones with passed target dates or no movement → slipped, or mis-dated.
- Roadmap priorities that contradict what the team actually worked on.

Present discrepancies to the user as a short checklist with proposed fixes (close ticket X, move date on project Y, …). Apply only what they approve — never silently mutate the tracker. If the user is unavailable, list the discrepancies in the draft's notes instead of fixing them.

### 4. Draft

Structure (adapt emoji/headers to the channel's existing style if prior statuses have one):

```
*Project status — <date range>*

<TLDR: 1–3 sentences, plain language: the single most important thing that happened and the current trajectory.>

*✅ Shipped*
• <outcome-first item, grouped by theme, with ticket/PR link>

*🔧 In progress*
• <item — state + expected landing, link>

*⏭️ Up next*
• <current priorities from the roadmap, in order>

*🚧 Blockers & decisions needed*
• <blocker — what's needed, from whom>
```

Omit empty sections except Blockers — if there are none, say so explicitly ("No blockers."); silence reads as "didn't check".

**Continuity** (the credibility test): every item the *previous* status listed under "up next" must appear in this draft — as shipped, in progress, or explicitly slipped with a reason. Never let promised work silently vanish.

### 5. Hand off

Output the full draft as the final message, plus: the window covered, item counts per source (so the user can sanity-check coverage), unresolved reconciliation items, and open questions from the last status's thread that this draft answers or still owes. Offer to post it (or create a Slack draft) — only act on explicit approval.

## Writing rules

- **Outcomes, not implementation.** "Practice-test search now loads instantly" — not "refactored the PT query layer". The reader decides whether to click the link for detail.
- **Summarize themes, don't enumerate commits.** Ten PRs on one feature are one bullet.
- **Quantify where it's honest** ("12 PRs merged, 9 issues closed") — never pad with vanity counts.
- **Be straight about slips.** A slipped item with a reason builds more trust than omitting it.
- **Slack mrkdwn**, not markdown: `*bold*`, bullets, no `#` headers, bare links or `<url|label>`. Keep it scannable — the whole status should fit on one screen.
- Match the audience knob: for a non-technical owner, lead every section with user/business impact.
