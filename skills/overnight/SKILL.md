---
name: overnight
description: Take a whole backlog — a list of specs, tickets, or goals — and deliver it unattended as a stack of ready-for-review PRs, one per item. Opens with a single interactive round (the plan, the stack order, and every open question across every item batched together), then runs silent to the end. Use when asked to "do all of this overnight", "work through this list", "ship the whole audit while I sleep", or whenever the input is a list rather than one task. With `--track`, takes a goal instead of a list ("migrate every remaining page", "finish this track tonight"): scouts the whole goal first to find the questions, builds what needs no answer, and wakes the owner to one morning packet and a Deliver ask for the train. Never merges.
---

# overnight

You are running the **overnight** skill. Goal: the user hands over a *list*, answers one round of questions, goes away — and comes back to a **stack of ready-for-review PRs**, one per item, in an order they can merge bottom-up.

Every other skill here is single-unit: `kickoff` turns one input into one PR. That is the right shape for one task and the wrong shape for a backlog, because the human has to be present at every seam to start the next item. This skill removes the seams. It owns planning, ordering, the question round, the stacked bases, and the report — and nothing else: each item's implementation goes through `kickoff`, which goes through `deliver`, stopping at `ready`.

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
2. Invoke **kickoff** with that item's goal (plus its resolved artifact and answers) and `--base <that branch>`. It decides depth, implements, tests, and calls `deliver`, which reviews and fixes the change locally, opens the PR against the parent, works the CI loop, and stops at `ready` with that PR's Deliver ask.
3. Record the outcome: PR URL, base, assumptions made, and any follow-up the item surfaced but did not do.

**On failure, cut the branch, not the night.** When an item's gate cannot be made green, or it hits one of `deliver`'s hard stops, that item and **its descendants** stop — they are stacked on it and cannot be built. Every independent chain keeps running. Note where each chain stopped and why; never publish a half-finished item to keep a number up.

**Never ask.** An unanswerable blocker parks that chain cleanly and the run continues elsewhere. The user is asleep; a question is a stalled night.

Parking means *recording*, not publishing. Whatever `kickoff` and `deliver` already committed and pushed for that item stays as it is; this skill adds only the report line saying where the chain stopped and why. It never commits or pushes on its own — publishing has exactly one owner (hard rule 4), and an orchestrator pushing behind `deliver`'s back would bypass the confidentiality gate that lives there.

### 5. Report

The deliverable is a stack the user can act on in the order it was built:

- **The stack, in merge order**, per chain: item → PR URL → base → state (ready-for-review / blocked-on-parent-PR / awaiting-CI / stopped, with why). Say plainly that they merge **bottom-up**, and that **merging a parent must delete its branch** — the forge retargets a child only when the parent's branch is gone. `deliver` deletes it on merge, and a child's Deliver click (its buttons carry `--parent`) retargets and rebases the child onto the new base and proves its patch unchanged, so the user does neither by hand.
- **The Deliver asks** (outside track mode, which folds them into the train). Each ready PR ends with the Deliver ask `deliver` opened for it, one button per level the repo deploys to; it replaces any merge ask of this skill's own. Click them bottom-up: a stacked child's buttons carry `--parent`, and its click waits for the parent to land, then rebases onto the new base and proves the patch unchanged.
- **Every assumption made while they were asleep**, per item, with the reasoning — this is the first thing they should review, ahead of any diff.
- **Where each chain stopped**, and what unblocking it needs.
- **Follow-ups discovered and deliberately not done.**

## Track mode

For a goal rather than a list: "migrate every remaining screen onto the shared layer", "finish this track". Its questions surface only during the work, one per unit, so a plan round up front catches few of them, and asking as they appear turns the owner into the scheduler. Track mode finds them in one pass at night and asks them in one sitting in the morning.

**Plan round (evening).** This is track mode's Phase 3: agree the goal, what is out of scope, what the run may decide alone, and the latest time the morning packet may arrive (a deadline, not a start time: see T4). Run Phase 2's base-branch preflight here. Get an explicit go; after it, rule 3 applies.

**The item** is one unit of the goal (a screen, a module), or one change to shared code. Every unit the scout finds inside the agreed goal, and every shared-code change T2 keeps for them, is on the list, so rule 7 does not apply to them; anything outside the goal is a follow-up.

### T1. Scout

In throwaway local worktrees, never pushed, attempt the **whole** goal roughly: every remaining unit, not the first one. Record each gap: what is missing, which units need it, what was tried. Then remove the scout worktrees.

### T2. Challenge every gap

Check each gap in order. The first "yes" decides it:

1. **Can it be deleted instead?** Yes → it becomes a Park proposal to delete it (T3).
2. **Does an existing primitive already do it** (a field type, a config value, an existing option)? Yes → not a gap; the unit uses the primitive.
3. **Does it belong only to the unit that needs it?** Yes → it is fixed inside that unit's own item.
4. **Otherwise** it is a shared-code change: it survives, and T3 places it.

For every survivor, record the caller's code before and after. Cluster survivors by **root question**, the decision that settles the others once it is answered. Sub-questions go inside their root and are never asked on their own.

### T3. Build in three levels

Each Build and Assume-and-show item goes through Phase 4: `kickoff --base <parent>`, then `deliver`, which stops at `ready`. The night-time exception below replaces Phase 4's "Never ask" paragraph. The brief to `kickoff` includes the plan-round answers and the line *"no questions tonight: record an assumption instead"*. The owner's "may decide alone" list overrides the default placement below.

- **Build:** units that need no new shared code, test and tooling fixes, and bugs reproduced from the code. A normal PR on the base branch.
- **Assume and show:** reversible shared-code changes, and the units that need them. Each change is its own PR; its body opens with *"Proposal: approve or reject at merge"*, the assumption, and the caller's code before and after. A unit that needs it stacks on that PR, one level deep at most.
- **Park:** schema, the security model, new concepts, deletions. A written proposal in the morning packet, no code. Work continues on other units; one parked unit never stops the night.

Ask at night only about security, data loss or a broken base branch, and do not wait for the answer. Park the affected units and keep working on the rest.

**Cap work in progress.** Every open PR uses shared resources: CI, preview environments, review attention. At the limit agreed in the plan round (default 8), stop starting new items. List the rest in the packet as *not started (limit)*; they start once merges free slots.

**Keep a night log** of assumptions, held branches, and idle periods with their causes. The packet is built from it.

**Schedule the deadline wake-up before the turn ends.** An agent whose turn has ended sleeps until something wakes it, so "I'll post at <packet time>" never happens unless a schedule or heartbeat sends that prompt. The wake-up is a fallback for the deadline only. If the harness has neither, post the packet as the run's final message and say the wake-up could not be set.

### T4. Morning packet

**Post it as soon as the night is done, not at the agreed time.** The night is done when every item has a final state: ready, stopped with a reason, parked, or *not started (limit)*. Check this each time an item reports back. Once it holds, post the packet in that turn and cancel the deadline wake-up. The agreed time only caps the wait. If the deadline wake-up fires first, post the packet with what is finished, and list each item still running with its state and what it is waiting on. Then post one follow-up when they finish, instead of a second packet.

One message, with one ask per root decision, root question first. An ask is the harness's native ask where one exists; otherwise it is a numbered decision in the message. Each carries a recommendation, a confidence level (high, medium or low), the caller's code before and after, and screenshots for UI changes (from a local run when previews are down). Keep it answerable in one sitting, about 10 decisions. Fold PRs that share a root into one ask, and list the rest as parked, each with what would reopen it.

Add **one Deliver ask for the train**, instead of a merge ask. It lists every ready Build PR, each with its evidence, its PR number, its **current head SHA** and the levels `deliver` read for it, and folds in those PRs' own Deliver asks (close them as moved to the train, so each PR still has one live ask). Assume-and-show PRs, and the units stacked on them, join only after their root ask is approved, as a new train ask listing them bottom-up; each stacked unit also carries its parent's PR number and head SHA; a rejected root's PRs are listed for the owner to close. This skill merges nothing. The ask has one button per level the listed PRs share, as `deliver` builds them (a PR whose levels differ gets its own line). A click asks the agent to run, for each listed PR in order, `deliver --pr <N> --to <level>`, adding `--parent <P> --parent-head <psha>` for a stacked child; the button's prompt embeds that ordered list. The heads this session listed are the approved ones. If a PR does not deliver, its stacked children are skipped and every independent PR continues (rule 6). In a repo that requires up-to-date branches, each merge leaves the later PRs behind their base; `deliver` merges the base in and goes on when the PR's own change stays the same. A PR that reports `blocked: conflict with base` gets its branch updated through `deliver --pr <N>`, which stops at `ready`; then the train runs it again, and the approval stands if only docs/spec hunks changed. The rest (`blocked: base moved`, `changed since approval`) go into **one follow-up ask** offering a new train at their updated heads. Nothing is delivered whose change the owner has not seen. The agent reports each PR's outcome.

End with the night log. For stacked children, the train does the retarget and rebase from Phase 5's stack notes, so the owner does not repeat them by hand. The exception is a parent that needed a base update first: its children need a fresh train.

## Hard rules

1. **Never merge.** Not a single PR, not the trivially green one at the bottom of the stack. The stack exists so that a human's first look happens before anything lands. A click on a Deliver ask, the train's included, is the owner's request, carried out by `deliver --pr <N> --to <level>` at the heads the owner saw, or later heads carrying the same change, not by this skill. The train runs only after the owner's own click on it.
2. **One item, one PR.** Never fold two items into one PR because they were small, and never split one item across PRs to look productive. In track mode an item is one unit or one shared-code change.
3. **No questions after the plan round.** Everything that needs a human is paid in Phase 3 or becomes a recorded assumption. In track mode the plan round is the evening one; after it, questions wait for the morning packet, except security, data loss and a broken base branch, which are asked without stopping the run.
4. **Delegate.** `kickoff` implements; `deliver` publishes, checks, and enforces the confidentiality gate. This skill never opens a PR, pushes, or runs a check itself.
5. **Never work on or push to the base branch.**
6. **A failed item stops its descendants only** — never the independent chains, and never silently.
7. **Don't expand the list.** Work discovered mid-run becomes a follow-up in the report, not an extra PR nobody asked for. In track mode the list is every unit inside the agreed goal, plus the shared-code changes T2 keeps for them.
