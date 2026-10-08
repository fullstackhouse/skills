# Local patches on {{DEPENDENCY}}

This app runs a patched {{DEPENDENCY}} **{{INSTALLED_VERSION}}**. Every patch here is re-applied
blindly on install and will either conflict or — worse — silently mask an upstream fix at the next
version bump.

**This file is the single source of truth for what we patch and when each row may be deleted.**

> **Read it before every {{DEPENDENCY}} bump.** Work the table top to bottom: for each row, check
> whether its source has merged *and* shipped in the version you are bumping to. If it has, delete
> the hunk instead of re-porting it.

## Status at a glance

{{How many rows, on which packages. What the baseline actually contains — a prerelease build is a
build of one commit, so anything merged upstream after it is not in it. Which rows a version number
cannot retire, and why.}}

| # | Change | Target | Source | State | Drop when |
|---|--------|--------|--------|-------|-----------|
| {{LABEL}} | {{what behaviour changes, for whoever hits the bug}} | {{packages}} | {{link}} ({{ours/theirs}}) | {{open/merged/closed/local}} | {{the condition, in full}} |

**Labels are labels, not identifiers.** They are never renumbered to close a gap: a reader deciding
what to delete at a bump follows the row, and a moved label sends them to the wrong one. Go by the
change text and the linked source.

---

## The changes

### {{LABEL}} — {{one-line title}} · {{ticket}} · {{source link}} ({{state}})

{{Unpatched, the dependency does X — and the consequence we actually hit.}}

{{What the patch does instead. Which files and artifacts the hunks touch.}}

{{Left out: the parts of the upstream change nothing here calls.}}

{{Where this patch meets {{other labels}} — the rows that touch the same files, and how they were
reconciled.}}
