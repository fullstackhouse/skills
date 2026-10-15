---
name: design-model
description: >-
  Content-first design: write the thing out as data for one real, named instance before any
  screen exists — collect what the customer uses today (price sheet, a quote they sent, their
  shop pages), fill the objects, fields, derived values and rules as rows against the real
  schema, then go back and measure every figure against its source. Produces tables, a numbered
  crack ledger, a falsifiable number and a story map — never a frame. Use when a design question
  turns out to be about what a field *is*, when `design-phase` routes here, when asked to
  "write it out as data", "model this domain before we draw", "co to właściwie jest za
  parametr", or when a mockup round keeps generating open questions instead of closing them.
---

# design-model

**OOUX, Contextual Design and content-first, in one pipeline.** Before a screen, a table or a
line of engine code: take **one real customer**, collect what they use today, and write their
case out as data. The screen is afterwards a projection of a model that exists, instead of an
invention that the model then has to be bent around.

What this produces, and nothing else:

- **rows** — objects, attributes, relations, derived values, rules, filled with concrete values;
- a **crack ledger** — every field that could not be filled without inventing a mechanism,
  numbered, and never silently dropped;
- **golden numbers** — the output the design must later be measured against;
- a **story map** with a thin slice, which is what answers *which screen first*.

Two passes, and the second is the one that earns the skill: you **write** it, then you **go and
measure it**. In the run this skill is derived from, the measurement pass closed four cracks of
six, deleted a rule that turned out to have been invented, opened three new cracks, and caught
the single figure the draft had labelled *real* being unreproducible. An invented figure that
nobody goes back for becomes a fact by sitting still.

## Not this skill

- **`design-phase`** decides whether you should be here at all. If you arrived without it and
  the screen's data is already written out and sourced, you are in the wrong phase.
- **`om-app-spec-writing` / spec-writing skills** own the spec. This document is the material a
  spec is written *from*; writing the spec here produces two sources of truth.
- **`design-storyboard`, `om-mockup-prototype`, `design-explore`** own everything with a frame
  in it, and each wants an artefact this document is not: stories with per-state acceptance
  criteria, a product brief with Key flows, a screen that already runs. So the model does not
  hand to them directly — it hands to the spec, and the spec feeds them. What this document
  decides is *when* that is allowed: no open crack that blocks the screen in question.
- **`decide`** owns the decisions this surfaces. Collect them here, hand them over there.

## Arguments

- `{instance}` (required) — the one real, **named** case: a customer, a tenant, a site, a
  branch. Not "a print house", not a persona.
- `--second <instance>` (optional) — write that next named instance against the existing model
  and report what it breaks. This is the generality test; the model is not trustworthy until a
  second instance has run through it.
- `--map` (optional) — the story-map step alone. Needs at least one written instance.
- `--artifacts` (optional) — stop after the artefact inventory, when the ask is "what do we need
  from the client".

## Where the output lives

The directory the **Specs** knob names in the consuming repo's `## Skill profile`, in a
subdirectory of its own (`phase-0/`, or whatever that repo already calls pre-spec material):
one file per instance, `NN-<instance-slug>.md`, from `templates/instance.md`.

**Create the directory's `README.md` on first use** and keep it current — it carries the order
of instances and one state row each (`written` / `written and measured` / the date), and §4
updates that row. Without it the second reader cannot tell a draft figure from a measured one.
No knob and no discoverable convention → ask; never scatter these into the repo root.

**Whose material this is.** The instance document is a named customer's commercial data — their
prices, their margins, the way they quote. It lives in the repo that belongs to that work, cites
non-public artefacts by name and date rather than quoting them wholesale, and in a public repo
carries public sources only. A PR diff is forever.

## 1. One real instance, named

Refuse an archetype. **Reachable is a low bar and deliberately so: one obtainable artefact,
and public material counts** — their shop, their catalogue, their published price list. The run
this skill is derived from never contacted the customer; it read their public pages. If not even
that exists, say so and **stop**: that is an access problem (`design-phase` routes it to a
synthetic panel), and inventing a plausible customer here poisons every row downstream.

Several instances to do? Order them deliberately and write the order down:

| Position | Pick | Why |
|---|---|---|
| first | the simplest that is still fully real | it establishes the shape cheaply |
| second | the one that **breaks** the model most | taken early on purpose — late is where it costs |
| later | the remaining ones | by then these are verification passes, not design |

## 2. The artefacts, before the fields

Contextual Design's artifact model, and the step most often skipped: **the new UI is a
formalisation of the artefacts they already use.** Collect them before writing a single field.

What to get, in rough order of value: the spreadsheet with the formula in it; a real quote or
order they sent a customer; their price list; their public catalogue or shop pages; the mails
where edge cases get handled by hand; screenshots of whatever tool they use today.

Inventory each: what it is, where it came from, when it was read. An artefact that has only
been *asked for* is a row too, marked `requested`, with who was asked — a gap you can see beats
a field quietly filled from memory. **This is the step the derived run skipped**, reading public
pages instead, and the cracks it carried to the end are the argument for not skipping it.

Then read them for the four things an interview does not give you — **the fields they actually
keep**, **the names they use for them**, **the rules hidden inside a formula**, and **the cases
they handle by hand** (which is the real list of what the tool must support, or deliberately
won't).

**Never dictate the customer's data from memory while an artefact is obtainable.** Where it is
public — their shop, their catalogue, their price list — go and read it now. Where it is not,
name the exact ask, and keep going on what is public meanwhile.

## 3. Write it out as data

Rows, against the **real** target schema where one exists: read the platform's own tables and
columns and verify the names as you go. A model written against imagined columns is a second
invention stacked on the first, and the mismatch surfaces at implementation, after the screens.

Cover, each as its own section of rows: the objects and their identity; their attributes with
concrete values; relations; **which values are authored and which are derived** (and by what);
measures and units; rules and constraints; and how one case splits into lines.

Mark every value you could not source `invented` — inline, in the row, not in a preamble. A
field you cannot fill without inventing a **mechanism** is not an invented value: stop, open a
crack, and leave the field empty.

## 4. Measure — not optional

Go back to the real source and re-true every row. **Every figure carries a URL (or document and
page) and the date it was read, or says plainly that it has none.**

Report the four outcomes separately, because they mean different things: **unchanged**,
**corrected** (with both values), **deleted** (the thing does not exist), **newly impossible**
(the source contradicts the model). A measurement pass that only reports corrections is hiding
its deletions, and the deletions are the valuable half.

Re-base the golden numbers on measured parts afterwards. A target computed from invented inputs
is not a test.

## 5. The crack ledger

Stable ids (`C1`, `C2`, …) that keep their meaning across revisions, in four states:

- **closed** — say *by what*: a measurement (with its source) or a decision (with who made it);
- **deleted** — the thing the crack guarded does not exist; say how that was established;
- **still open** — with what would close it, and **which screens it blocks**;
- **opened by the measurement** — the pass's own output, and usually the most useful rows in the
  document.

A crack is never silently dropped, and never "resolved" by a sentence that only restates it.
An open crack that blocks a screen is also the exit condition `design-phase` is waiting on.

## 6. The golden numbers, and one case end to end

Name the **falsifiable output** — the price, total, quote or document the design must produce —
and its measured value with its provenance. A golden number is usually **derived**, so its
provenance is the list of rows it comes from, each of those sourced: *"sum of §2 rows 1–3"*. Say
that, rather than attaching a URL the figure does not have — inventing provenance for a derived
total is the exact failure the measurement pass exists to catch.

Then trace **one** real case end to end through the rows above, arriving at that number.

That trace is the acceptance test for every screen built later. Without it the design is
unfalsifiable, which is the real reason mockup rounds never converge.

## 7. What is needed from outside — two queues, never one list

- **Decisions** — a human has to choose. Hand these to `decide`; one list of five decisions in
  a closing paragraph is how they all stay open.
- **Measurements** — facts somebody has to go and get: what, from which source, who asks.

Mixing them stalls the whole list on its hardest item, and makes a decision look like it is
waiting on research.

## 8. The second instance, then the map

When §1 ordered a second instance, run `--second <instance>` and report what it breaks: a field
that does not fit, a rule that is not general, a crack the first instance never showed. When
there is only one instance, **stop here and name the second as the next run** — do not invent it
to complete the pipeline.

Then, once a second has run or been consciously deferred, the **story map**: the user's
activities left to right as the backbone, variants beneath each, and a **thin horizontal
slice** as the first release. *Which screen first* comes out of this and out of nothing else.

One ordering rule, established the hard way: **the customer's screen before the authoring
screen.** The customer's half has a falsifiable test — the number. The authoring screen is a
form that produces *this document's data*, so it is the cheapest thing to draw once the data is
settled, and the most expensive thing to guess at before.

## Hard rules

1. **No frames.** No wireframes, no layouts, no "rough sketch of the screen". Tables and prose.
2. **One real named instance.** Archetypes and personas are refused, not substituted.
3. **Source and date on every figure** — or, for a derived one, the sourced rows it comes from
   — or an explicit "none". Every unsourced value labelled `invented`, in the row.
4. **Measure after writing.** A written-only document is a draft, says so in its header, and
   says so in the index's state row until the pass is done.
5. **A crack is closed, deleted, or open** — with the reason. Never dropped, never paraphrased.
6. **Decisions and measurements stay in separate queues.**
7. **Customer's screen before the author's; the meta-tool last and derived.**
8. **Don't write the spec.** When the ledger has no screen-blocking crack, hand over and stop.
