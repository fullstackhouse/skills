---
name: design-polish
description: Audit and improve the visual design and UX of a web app/prototype using Refactoring UI principles and UX heuristics. Use when asked to polish, improve, or review the design/UI/UX of a screen, prototype, or app (e.g. /design-polish prototype-plm). Args: path to the app, optionally specific screens or a focus area.
---

# Design Polish

Improve an existing UI iteratively: **see it → audit it → fix the highest-impact issues → verify visually**. Never restyle blindly from code alone.

## Workflow

1. **Run & look.** Start the app (`npm run dev` / project skill). Use Playwright MCP to screenshot every screen and key states (empty, filled, dialogs, hover targets). Also resize to ~390px width to check mobile if relevant.
2. **Audit.** Walk each screenshot against the checklist below. Write findings as a prioritized list: what, where, which principle, proposed fix. High impact first (hierarchy, grouping, noise) — not nitpicks.
3. **Confirm scope** with the user if the list is long or changes are opinionated; otherwise apply the top items.
4. **Fix.** Small, targeted edits. Reuse the app's design tokens/components (e.g. shadcn/ui variants, Tailwind scale) — don't invent one-off values.
5. **Verify.** Re-screenshot the same screens. Compare before/after. Present a summary with the screenshots.

## Audit checklist

### Hierarchy — the #1 lever
- Every screen has **one** primary action; it's the only solid/bold button. Secondary = outline/ghost, destructive = quiet until confirmed.
- Emphasize by **de-emphasizing everything else** (softer color, smaller weight) rather than making the hero bigger/louder.
- Use font **weight and color** for hierarchy, not size alone. 2–3 text colors max (strong / default / muted). Data > labels: the value is primary, the label supporting.
- Don't use grey text on colored backgrounds — use a tint of the background color instead.

### Grouping & layout
- **Proximity = relationship.** Everything about one concept sits together (e.g. all customer info on an invoice in one block). Space *between* groups > space *within* groups.
- Start with generous whitespace, remove only where density is a real requirement (data tables in an ERP can be dense — forms and headers shouldn't be).
- Stick to a spacing/size scale (Tailwind steps); no arbitrary values. Align everything to a grid; constrain text to readable line lengths (~65–75ch).
- Don't stretch content to fill wide screens — cap widths, or give tables room while keeping forms narrow.

### Remove noise
- Cut needless words: labels obvious from context ("Name:" next to an obvious name), redundant headings, "please", chatty microcopy. Buttons say the verb: "Save changes", not "OK"/"Submit".
- Fewer borders: separate with whitespace, subtle background shifts, or shadows before reaching for lines. No boxes inside boxes inside boxes.
- Don't repeat units/prefixes in every table cell (put unit in the header). Empty values render as "–", not "0" or blank.
- Icons only when they add meaning; never unlabeled icons for primary actions.

### Color & depth
- Small palette, used consistently: one primary, neutrals, and semantic colors (success/warn/danger) reserved for meaning — status badges shouldn't compete with the primary action.
- Shadows communicate elevation (dialogs > dropdowns > cards). Ensure WCAG-ish contrast for text, especially muted-on-muted.

### Typography & data
- Right-align numbers in tables, tabular-nums for columns of figures, consistent decimal precision.
- Tables: header row visually distinct but quiet, row hover, sticky header if it scrolls, key column first.
- Line-height: smaller text → looser; big headings → tighter.

### Interaction economy
- **Fewest clicks to the common task.** Sensible defaults, most-used items surfaced, inline edit where a modal isn't needed, no confirmation for safe/undoable actions (but confirm destructive ones).
- Essential info is never hidden behind hover: **no tooltips for critical content**, no hover-only actions (breaks touch), **no carousels**.
- Every list/table has designed **empty, loading, and error states** — empty states say what the thing is and offer the first action.
- Forms: labels above fields (not placeholder-as-label), field width hints at expected content (postcode short, description long), related fields grouped, validation inline and specific.
- Disabled controls explain why (or stay enabled and validate on submit).
- Keyboard basics work: focus visible, Enter submits, Esc closes dialogs.

### Business rules & lifecycle
- Edit affordances match the entity's state: an immutable status (released, closed, posted…) shows **no** add/edit/delete controls — only the sanctioned path (new revision, correction document, ECN).
- Destructive actions match domain semantics: archive vs delete; block or warn when the record is referenced elsewhere (where-used, open orders).
- Identifiers that downstream documents reference (revision labels, numbers) are not editable after issue.
- Derived/inferred values (make-vs-buy, computed totals) say what they're based on and what they exclude — a total that silently omits external lead time or scrap misleads its readers.
- State-changing actions validate readiness (don't release an empty BOM) and say what else changes ("revision A will be archived").

### Copy
- Sentence case everywhere. Write in the app's language and use the domain terms its users know (check the UI / i18n — some apps are non-English-first). Say what happened, not codes: "Can't delete — this BOM is used in 3 orders", not "Error 409".

## Anti-patterns — flag on sight
Carousels; tooltips carrying essential info; unlabeled icon buttons; placeholder-as-label; modal opening another modal; more than one solid primary button per view; grey-on-color text; border-overload; ALL CAPS body text; centered long-form text; "Are you sure?" on harmless actions; truncation without a way to see the full value.

## Output format

End with:
1. **Changed** — bullet list: screen → what changed → principle.
2. **Before/after screenshots** (paths).
3. **Deferred** — findings not applied (needs product decision, out of scope), so nothing is silently dropped.
