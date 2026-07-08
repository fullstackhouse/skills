---
name: generate-doc
description: Generate branded FullstackHouse client documents (implementation contracts and technical specs) as a final PDF and an editable DOCX from Markdown, using the FSH monorepo's `render-doc` CLI. Use when asked to produce/render a client contract or spec, turn a draft `.md` into a branded PDF/DOCX, or set up documents for a new client. Args: path to the source `.md` (or a client folder), optionally template (contract|spec) and format (pdf|docx).
---

# Generate FSH client documents

Turn a Markdown draft into a **branded FSH PDF** (final / send / sign) and an **editable DOCX**
(for the client's redline). The rendering engine is the `render-doc` command in the FSH internal
monorepo's `accounting` package — this skill locates it, scaffolds new docs from templates, and
runs it. Do **not** reimplement rendering here.

## When to use
- "Render the contract/spec for <client>", "make a branded PDF from this `.md`", "set up docs for a new client".
- NOT for writing the legal/technical **content** — that's yours to draft or reuse. This skill formats and renders it.

## Locate the renderer (do this first)
The `render-doc` CLI lives in the FSH internal tooling monorepo, `accounting/` package. Find it, in order:
1. If the current repo is that monorepo (has `accounting/src/commands/render-doc.ts`), use `accounting/`.
2. Else try, in order: `~/src/fsh/fsh-monorepo/accounting`, `~/src/fullstackhouse/fsh-monorepo/accounting`.
3. Else ask the user for the monorepo path.

Sanity-check it exists: `test -f "<accounting>/src/commands/render-doc.ts"`. First run in a fresh
checkout may need `pnpm install` + `pnpm exec playwright install chromium` (see that package's CLAUDE.md).
`pandoc` must be on PATH for DOCX.

## Two templates × two formats
- **`contract`** (default) — sober letterhead, no per-heading accents. A legal doc.
- **`spec`** — cover page + cherry accents. A technical specification.
- **`pdf`** (default) — final, branded, non-editable. **`docx`** — editable, for redlining.

Recommended per document: **contract → DOCX for negotiation + PDF for signing; spec → PDF** (add DOCX if the client edits it).

## Workflow
1. **Locate the renderer** (above).
2. **Get the source `.md`.**
   - Existing draft → use it.
   - New doc → copy a bundled template (`templates/contract.md` / `templates/spec.md`) into the client folder and fill it. Keep client docs together, e.g. `docs/leads/<client>/{umowa,spec}.md` plus a `makiety/` subfolder for screenshots.
3. **Set metadata** via YAML frontmatter (preferred — self-contained) or CLI flags (override frontmatter):
   ```yaml
   ---
   title: Umowa wdrożeniowa
   subtitle: System ERP dla Acme      # optional
   client: Acme Sp. z o.o.            # spec cover / title block
   date: 2026-08-01
   template: contract                 # contract | spec
   format: pdf                        # pdf | docx (or pass --format)
   confidential: true                 # footer "Poufne" note
   ---
   ```
   For a **contract**, keep `client`/`date` out of frontmatter — the parties belong in the body; the title block stays clean. For a **spec**, include them (they render on the cover).
4. **Render** — absolute paths, run from the `accounting` dir:
   ```bash
   cd "<accounting>"
   pnpm cli render-doc --input "<abs>/umowa.md"  --template contract --format docx --output "<abs>/umowa.docx"
   pnpm cli render-doc --input "<abs>/umowa.md"  --template contract              --output "<abs>/umowa.pdf"
   pnpm cli render-doc --input "<abs>/spec.md"   --template spec  --title "Załącznik nr 1 — Specyfikacja techniczna" \
       --subtitle "System ERP dla <Client>" --client "<Client>" --date "<YYYY-MM-DD>" --output "<abs>/spec.pdf"
   ```
   Flags: `--template`, `--format`, `--title`, `--subtitle`, `--client`, `--date`, `--no-confidential`, `--output`.
5. **Verify** before handing off: page count sane, images present, no literal `## §` leaked, `[TBD]` fields visible. Rasterize a couple of pages (`pdftoppm -png -r 80 -f 1 -l 2 spec.pdf /tmp/p`) and look.
6. **Report** the output paths and any remaining `[TBD]` fields the user must fill before sending.

## Content conventions the renderer handles
- **Section numbering** — `## § 1. …` (contract) or `## 1. …` (spec). Nested `<ol>` renders 1. → a. → i.
- **Lettered sub-points** — write `a. … b. …` indented under a numbered item; they render as an a/b/c sub-list.
- **Mockups / images** — `![Caption](makiety/screen.png)`; relative paths resolve against the `.md`'s folder. Put a bold caption line above each image. Images render framed and never split across a page.
- **Fill-in fields** — mark unknowns as `` `[TBD: …]` `` (inline code). They stand out visually so nothing ships unfilled.
- The renderer inserts blank lines before headings and lets lists interrupt paragraphs, so tight source Markdown still renders correctly.

## Notes
- The leading `# H1` is dropped when a title block / cover renders — don't duplicate the title in the body.
- Keep the source `.md` as the single source of truth; re-run render after any edit. Regenerate **both** formats so PDF and DOCX stay in sync.
- Outputs and sources are client-confidential — keep them in the client folder, not committed to shared repos.
