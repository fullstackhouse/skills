---
name: docx-diff
description: Reconstruct a readable redline between two .docx versions when the counterparty edited a document without tracked changes — pandoc → sentence-level unified diff → a classification of which changes are material. Use when a client, lawyer, or partner returns a contract/spec as a clean .docx and you need to know what they actually changed.
---

# docx-diff

You are running the **docx-diff** skill. Someone returned an edited `.docx` — a contract, a spec, an SOW — as a *clean* file, with no tracked changes. Your job is to reconstruct what they changed and tell the user **which of it matters**.

The `.diff` file is an intermediate artifact. The deliverable is the classification: which edits shift risk, money, or scope, and in whose favour.

## 0. Check you need this skill at all

If the file *does* carry tracked changes, don't reconstruct anything — read them directly:

```bash
pandoc -f docx -t markdown --track-changes=all --wrap=none theirs.docx | grep -n 'insertion\|deletion'
```

This skill is for the case where that returns nothing.

## 1. Resolve the two versions

You need **our last sent version** and **their returned version**, each with a date and a sender. Get them from the user or the surrounding docs folder. Two rules:

- Never diff against a file you can't attribute — diffing their v2 against the wrong baseline invents changes that were always there and hides the real ones.
- Both files must live somewhere durable (the repo, not `~/Downloads`). Without both, the diff can't be refreshed on the next round — and there is always a next round.

State the pair you picked, with dates, in one line before running anything.

## 2. Generate the diff

Requires `pandoc` (`brew install pandoc`) and `python3`.

```bash
python3 scripts/docx-diff.py ours.docx theirs.docx > redline.diff
```

The script converts both files with pandoc, strips Word comment anchors, then breaks paragraphs into one sentence per line before running `diff -u` — so a hunk points at the changed *sentence*, not a 400-word clause. Sentence splitting needs to know which periods are abbreviations; the built-in list is Polish-legal (`ust.`, `art.`, `m.in.`). For any other language pass your own, or the diff fills with false line breaks — under the Polish default, `…subcontract, e.g. Acme Ltd. Fees remain unchanged.` splits into three "sentences":

```bash
python3 scripts/docx-diff.py --abbr 'No,Sec,Art,cf,e.g,i.e,etc,vs,Inc,Ltd' ours.docx theirs.docx
```

Store the result next to the source documents, with a short prose header above the first `---` line: what the two versions are, their dates, and the exact command to regenerate. A bare `.diff` six weeks later is unreadable.

**Confidentiality.** The diff is verbatim contract text belonging to two parties, and a `.diff` is far easier to commit carelessly than a `.docx`. It goes only where the source documents already live — a private repo or folder of the party that owns them. Never into a public repo, a repo owned by anyone else, or a channel/thread that includes a third party. If you can't confirm the destination's visibility and owner, write the diff to a local path and ask.

## 3. Read the diff — this is the actual work

Walk every hunk and sort it into one of two buckets:

- **Cosmetic** — reformatting, reordering, synonym swaps, typo fixes, numbering. Summarize as a count; don't enumerate.
- **Material** — anything that moves an obligation, a deadline, a liability cap, a payment term, an IP assignment, a termination right, or the scope of work. Each one gets: what it said, what it says now, and **who benefits**.

Two failure modes to guard against:

- **Deletions are easy to miss.** A removed clause is a `-` block with no matching `+` — visually quiet, often the most expensive change on the page. Scan for them deliberately.
- **The diff can lie about structure.** If a hunk looks like the whole document was rewritten, the counterparty probably moved a section. Open both `.docx` files and check before reporting a rewrite.

If the returned file carried Word comments, the script strips them from the diff — but read them separately. Comments state the counterparty's *intent*, which is usually more negotiable than the text they wrote.

## 4. Report

- One-line verdict: how many changes, how many material, and whether the document is still signable as-is.
- The material changes, ordered by how much they cost us — each with the before/after and its practical consequence.
- The cosmetic ones as a single line ("14 further edits, all formatting/wording").
- Anything you couldn't verify from the text (a referenced annex you don't have, a defined term that changed meaning elsewhere). Say so; don't paper over it.

Never negotiate on the user's behalf and never edit the counterparty's document. Recommending a response is fine — sending one is not.

## Limits

pandoc conversion is lossy for images, tables, headers/footers, and any formatting-carried meaning (a struck-through paragraph, a highlighted term). If a change touches one of those, open the `.docx` and confirm visually before reporting it.
