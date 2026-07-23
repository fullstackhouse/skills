---
name: design-explore
description: Generate ~3 genuinely different UI/UX alternatives for a screen or flow — build them with the existing design system, screenshot each, and present a side-by-side comparison with trade-offs. Use when asked to reimagine, riff on, improvise, or explore alternative designs (vs /design-polish, which refines the current design). Args: path to the app + target screen/flow, optionally a focus ("make adding items faster", "less dull").
---

# Design Explore

Divergent counterpart to `/design-polish`. Don't fix the current design — question it. Produce **3 structurally different, working alternatives**, show them side by side, let the user pick.

## Workflow

1. **See & understand.** Run the app, screenshot the target screen and its key states. Before designing anything, write down: who uses this screen, what is its **#1 job**, how often, and what does the current design make slow, hidden, or dull. Also map the **business rules** the screen must obey: the entity's lifecycle (draft/released/archived…), who may edit what and *when*, which values are derived vs authored, and which downstream modules consume this data. If the domain intent is unclear, check specs/docs and the real backend model — not just the prototype.
2. **Diverge.** Brainstorm along the axes below, then pick the 3 most promising directions. Each must differ from the original *and from each other* structurally — a variant that only restyles is polish, not exploration; replace it. Give each a name and a one-line hypothesis: "better because …".
3. **Build.** Implement each variant for real, using the existing design system (tokens, components, spacing scale — no new visual language). Plausible static data is fine; add depth only where the concept needs it to be judged. Keep variants cheap to discard: a temporary switcher (query param / dev-only toggle) or sequential build → screenshot → revert, saving each diff.
4. **Show.** Screenshot every variant at the same viewport (plus the original as baseline). Present: concept name, what changed, why it should be better (tie back to the #1 job), and honest trade-offs/risks — what gets worse.
5. **Decide.** Recommend one (or a hybrid: "layout of B + inline editing of C") and ask the user which to keep. Nothing merges or commits until they choose; discard the rest cleanly. After a pick, a `/design-polish` pass on the winner is the natural follow-up.

## Divergence axes — pick 3 *different* ones

- **Information architecture**: flip what's primary; master-detail ↔ inline expansion; merge screens that are always used together; split screens doing two jobs.
- **Interaction model**: modal forms → inline/in-place editing; click-through navigation → keyboard-first + command palette; buttons → drag-and-drop or direct manipulation; add-one-at-a-time → paste/bulk/spreadsheet-style entry.
- **Visualization**: table → tree, timeline, kanban, cards, or diagram; raw numbers → bars, sparklines, capacity gauges; show structure visually where users currently read it.
- **Task flow**: collapse the #1 task to the fewest possible actions — smart defaults, templates, "recently used", duplicate-and-edit, batch operations.
- **Progressive disclosure**: dense expert view ↔ guided steps; summary-first with expandable detail; zero-state that teaches by doing.
- **Context**: pull related data onto the screen (stock, cost, usage, history) — or strip everything but the essential.

## Rules

- **Same design system, new structure.** Creativity goes into layout, interaction, and flow — not fonts, colors, or decoration.
- **Honest to the domain.** Anchor every variant in the real job of the app's actual users and roles (check specs/docs; write UI copy in the app's language). Flashy-but-slower loses to plain-but-fast.
- **Fundamentals still apply.** Each variant must respect hierarchy, grouping, and the `/design-polish` anti-pattern list (no carousels, no tooltip-hidden essentials, one primary action).
- **Business rules beat layout.** An edit affordance on an immutable state (e.g. a released revision), a delete where the domain demands archive, or a total that silently excludes something (e.g. external lead time) is a design bug even if it looks clean. Variants must surface lifecycle: what's editable now, what path changes locked data (new revision / correction document), and flag derived values that can mislead.
- **Working > described.** A rendered screenshot beats a paragraph; users can't judge prose mockups.
- **User picks, not you.** Never auto-merge a variant; present, recommend, and stop.

## Output format

End with:
1. **Comparison table** — variant → core idea → strongest win → main trade-off.
2. **Screenshots** — baseline + each variant (paths).
3. **Recommendation** — which one (or hybrid) and why, in 2–3 sentences.
4. **The question** — ask which variant to keep; note where the discarded diffs live until then.
