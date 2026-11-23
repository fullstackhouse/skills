---
name: overnight
description: Take a whole backlog — a list of specs, tickets, or goals — and deliver it unattended as a stack of ready-for-review PRs, one per item. Opens with a single interactive round (the plan, the stack order, and every open question across every item batched together), then runs silent to the end. Use when asked to "do all of this overnight", "work through this list", "ship the whole audit while I sleep", or whenever the input is a list rather than one task. With `--track`, takes a goal instead of a list ("migrate every remaining page", "finish this track tonight"): scouts the whole goal first to find the questions, builds what needs no answer, and wakes the owner to one morning packet and one merge-train ask. Never merges.
---

# overnight

You are running the **overnight** skill. Goal: the user hands over a *list*, answers one round of questions, goes away — and comes back to a **stack of ready-for-review PRs**, one per item, in an order they can merge bottom-up.

Every other skill here is single-unit: `kickoff` turns one input into one PR. That is the right shape for one task and the wrong shape for a backlog, because the human has to be present at every seam to start the next item. This skill removes the seams. It owns planning, ordering, the question round, the stacked bases, and the report — and nothing else: each item's implementation goes through `kickoff`, which goes through `deliver --no-merge`.

**Interactive front, unattended back.** The user is at the keyboard when this starts and asleep for the rest. That asymmetry is the whole design: everything that needs a human is paid up front, in one sitting.

## Project specifics — read these first

Repo-agnostic, like the rest of the collection. From the consuming repo's `AGENTS.md` / `CLAUDE.md` (the `## Skill profile` section is the curated source):

- **Specs** — where specs live and what a finished one looks like. This is how items are found when the input names a directory, and where the Phase 3 answers are written back.
- **Tracker** — when items are tickets. `deliver` moves their statuses; this skill only reads them to build the list.
- **baseBranch** — the branch the *first* item in each chain stacks on. Everything else stacks on its parent.
- **Check commands** — not used directly (they are `deliver`'s), but Phase 2's preflight needs to know whether the base branch is currently green.

## Arguments

- **A list of items** in any of these shapes, mixed freely: spec paths, a specs directory to scan, tracker ticket IDs/URLs, a brainstorm brief, or plain prose bullets.
- **`--track <goal>`** — a goal whose questions don't exist yet, because they only appear while doing the work. Runs [Track mode](#track-mode) instead of the phases below.
- **Empty** — ask what the list is. Never assemble a backlog by guessing what the repo needs.

## Phases

### 1. Ingest & classify

Resolve the input into a concrete item list. For each item, read its source and record:

- **The goal**, in one sentence.
- **The verification** that will prove it works — defined now, before anything is built.
- **Its decision state**, which is the load-bearing classification and has exactly three values:
  - **Decided** — a spec (or a task so mechanical it needs none) whose open questions are all resolved.
  - **Open** — an artifact exists, but it still carries unresolved questions. Collect each one verbatim; they are Phase 3's agenda.
  - **Bare** — a goal with no artifact. Derive the questions that a spec would have asked; they join the same agenda.

**"Has a spec" is not "has decisions."** An unresolved open question forks the work no matter how well it is written down, and a fork resolved at 3am by an agent is the failure mode this phase exists to catch. Classify on the questions, never on the presence of a file.

### 2. Order the stack

Build the dependency graph: item B depends on item A when B reads something A creates, edits the same surface in a way that would conflict, or is meaningless until A lands.

- **A graph, not a chain.** Independent roots each start their own stack off the base branch; only real dependencies produce a stacked base. Do not serialise items that have no reason to be serialised — a needlessly deep stack means a needlessly deep rebase when one link is rejected.
- Order within a chain: the item everything else depends on goes first.
- **Preflight the base branch.** Every chain sits on it, so if it is red the whole night is blocked on the first item's checks. Query the base **by name** — a bare `gh pr checks` reports on the current branch's PR, which is a different question:

  ```bash
  gh run list --branch "<base branch>" --limit 1 --json conclusion,status,workflowName
  ```

  Read a `skipped` job as skipped, not failed: a notify-on-failure workflow is skipped on every green run, and treating it as red would cancel a healthy night. A genuinely red base is not a reason to refuse either — it is the first thing to say in Phase 3, along with the fix if it is known.

### 3. The plan round — the last interaction

Present, in one message: the items, their classification, the graph and resulting stack order, the preflight result, and — batched into a single list — **every open question from every item**. This is the only round; the questions from item 6 are asked now, not six hours from now.

For each answer the user gives, write it back into the item's source artifact as a dated resolution (the repo's own spec/ticket conventions), so it survives the run, ships with the PR, and is reviewable later. An answer that lives only in this conversation is lost the moment the session ends.

For any question the user skips or cannot settle: **pick the reasonable default and record the assumption** — in the artifact and, later, in the PR body, as *assumed X, because Y*. Nothing blocks the run and nothing is silently guessed. This is `kickoff`'s existing rule, widened from one item to the whole list.

Then get an explicit go. After that message, do not ask anything again.

### 4. The run

Per item, in stack order:

1. Resolve its base: the base branch for a chain's first item, the **previous item's branch** for every other.
2. Invoke **kickoff** with that item's goal (plus its resolved artifact and answers) and `--base <that branch>`. It decides depth, implements, tests, and calls `deliver --no-merge`, which reviews and fixes the change locally, opens the PR against the parent, and works the CI loop.
3. Record the outcome: PR URL, base, assumptions made, and any follow-up the item surfaced but did not do.

**On failure, cut the branch, not the night.** When an item's gate cannot be made green, or it hits one of `deliver`'s hard stops, that item and **its descendants** stop — they are stacked on it and cannot be built. Every independent chain keeps running. Note where each chain stopped and why; never publish a half-finished item to keep a number up.

**Never ask.** An unanswerable blocker parks that chain cleanly and the run continues elsewhere. The user is asleep; a question is a stalled night.

Parking means *recording*, not publishing. Whatever `kickoff` and `deliver` already committed and pushed for that item stays as it is; this skill adds only the report line saying where the chain stopped and why. It never commits or pushes on its own — publishing has exactly one owner (hard rule 4), and an orchestrator pushing behind `deliver`'s back would bypass the confidentiality gate that lives there.

### 5. Report

The deliverable is a stack the user can act on in the order it was built:

- **The stack, in merge order**, per chain: item → PR URL → base → state (ready-for-review / blocked-on-parent-PR / awaiting-CI / stopped, with why). Say plainly that they merge **bottom-up**, and that **merging a parent must delete its branch** — the forge retargets a child only when the parent's branch is gone. Leave the parent branch alive and the child stays based on a merged-but-still-existing branch, where it merges cleanly into a dead ref and ships nothing. And retargeting is not rebasing: `deliver` squashes, so a retargeted child still carries the parent's original commits and its diff replays them against the new base. After each parent lands, tell the user to confirm the child's `baseRefName` **and** rebase it onto the new base before reviewing or merging it.
- **Every assumption made while they were asleep**, per item, with the reasoning — this is the first thing they should review, ahead of any diff.
- **Where each chain stopped**, and what unblocking it needs.
- **Follow-ups discovered and deliberately not done.**

## Track mode

For a goal rather than a list: "migrate every remaining screen onto the shared layer", "finish this track". Its questions surface only during the work, one per module, so a plan round up front catches few of them, and asking as they appear turns the owner into the scheduler. Track mode finds them in one pass at night and asks them in one sitting in the morning.

Evening, with the owner: the goal, what is out of scope, what the run may decide alone, and the time the morning packet is due.

### T1. Scout

In throwaway worktrees (never pushed), attempt the **whole** goal roughly: every remaining module or screen, not the first one. Record each gap: what is missing, which units need it, what was tried. Then remove the scout worktrees.

### T2. Challenge every gap

Before a gap becomes a proposal, check in this order, and keep the answers for the packet:

1. Can it be deleted instead?
2. Does an existing primitive already do it (a field type, a config value, an existing option)?
3. Does the owning unit own it?
4. Will improving it later need per-unit edits?
5. What does the caller's code look like before and after?

Cluster the survivors by **root question**, meaning the decision that, once answered, settles the others. Sub-questions go inside their root and are never asked on their own.

### T3. Build in three levels

- **Decide:** work on top of what already exists, test and tooling fixes, bugs reproduced from the code. Ship each as an ordinary PR.
- **Assume and show:** reversible choices and small additions to shared code. Build each as its own **draft** PR with the caller's code before and after, stacked at most one level deep. Record the assumption.
- **Park:** schema, the security model, new concepts, deletions. Write a proposal only, with no code, and move on to other units. Never stop the night on one.

The only questions asked during the night are about security, data loss or a broken base branch. Report a bug only after reproducing it.

**Cap work in progress.** Each open PR uses shared resources: CI minutes, preview environments, review attention. Stop opening PRs at the repo's limit (its profile, else about 8). Hold finished work as pushed branches and list them in the packet.

**Schedule the morning wake-up before the turn ends.** An agent whose turn has ended sleeps until something wakes it, so "I'll post at 07:45" never happens unless a schedule or heartbeat (whatever the harness offers) is set to send that prompt.

### T4. Morning packet

One message, one ask per root decision, ordered root question first. Each carries a recommendation, a confidence level, the caller's code before and after, and screenshots for UI changes (from a local run when previews are down). Keep the packet small enough for one sitting, about 10 decisions. Fold drafts that share a root into one ask, and list the rest as parked with what would reopen them.

Then add **one merge-train ask** that names every ready PR with its evidence. Clicking it is the owner's explicit request to merge exactly those PRs, in that order, each when green. That keeps "never merge without an explicit request" intact while costing one click instead of one per PR.

Finish with the night's assumptions, the branches held without PRs, and the idle time with its causes.

## Hard rules

1. **Never merge.** Not a single PR, not the trivially green one at the bottom of the stack. The stack exists so that a human's first look happens before anything lands.
2. **One item, one PR.** Never fold two items into one PR because they were small, and never split one item across PRs to look productive.
3. **No questions after the plan round.** Everything that needs a human is paid in Phase 3 or becomes a recorded assumption. Track mode has no plan round: it parks the questions until the morning packet, except security, data loss and a broken base branch.
4. **Delegate.** `kickoff` implements; `deliver` publishes, checks, and enforces the confidentiality gate. This skill never opens a PR, pushes, or runs a check itself.
5. **Never work on or push to the base branch.**
6. **A failed item stops its descendants only** — never the independent chains, and never silently.
7. **Don't expand the list.** Work discovered mid-run becomes a follow-up in the report, not an extra PR nobody asked for.
