---
name: design-phase
description: >-
  Decide which design phase a UI/UX question is actually in, then route it to the one method
  that settles it — before anyone draws. Probes where the uncertainty really sits (what the
  thing is, a number it must produce, a choice someone owes you, which screen first, or the
  pixels), names one skill with the artifact it needs on arrival, and refuses frames while a
  field the screen depends on cannot be filled without inventing a mechanism. Use when a design
  round keeps producing frames and a growing list of open questions, when asked "how do
  designers actually do this", "which comes first, the screen or the data", "jaka jest
  kolejność", "od czego zacząć projektowanie", when a mockup is requested with the domain still
  undecided, or before starting any multi-screen design effort. Read-only — it routes, it never
  designs.
---

# design-phase

**The failure this skill exists to fix:** four rounds of drawing an authoring screen produce
seventeen frames and a *longer* list of open questions than the first round had — because none
of the questions were ever about pixels. They were about what a field is. Frames cannot answer
that, so each round multiplies the unknown instead of reducing it.

Every design school on record — Double Diamond, Goal-Directed Design, OOUX, Contextual Design,
Lean UX, Design Sprint — disagrees about ceremony and agrees about one rule:

> **The fidelity has to match the uncertainty.** Pixels settle questions about pixels. A
> question about the data model is settled by text and a table. Drawing seventeen frames while
> the model is unsettled is not bad design — it is the **wrong phase**.

This skill is that rule, made executable. It measures where the uncertainty sits and names one
phase, one skill, one artifact.

## Not this skill

It **routes**. It does not design, draw, prototype, audit or write the model — however cheap
the next step looks once the verdict is in. Name the owning skill and stop. When that skill
isn't installed, say so plainly and describe its artifact; never improvise it here.

## 1. State the target

One line: what is being designed, and for whom. Four kinds, and they route differently —

- a **customer-facing** screen or flow (the people who buy, book, or configure);
- a **meta-tool** — an editor, an admin, a builder, a template designer: a thing whose users
  produce the configuration that drives the first kind;
- a **flow across screens**, where the question is sequence rather than any one screen;
- **the look** of something that already works.

Get this wrong and the rest of the routing is wrong: the two most common mis-routes in practice
are treating a meta-tool like a customer screen, and treating a sequencing question like a
layout question.

## 2. Probe — four tests, cheapest first

**The budget is the whole point: five fields, sources already on hand, acquire nothing new, and
done inside a few minutes.** A probe you cannot finish inside that budget has *failed* — and
the acquisition it would have needed is the phase you are routing to. Run them; don't intuit.

**Fill test — is the data writable?** Pick five fields and try to write **one real instance**
out as concrete rows: every field, a concrete value, a source. Which five:

- the screen exists or is specified → the five fields **the requester is least sure about**,
  named in the verdict. Not five easy ones; a probe you designed to pass measures nothing.
- there is no screen yet (the usual case when this skill is invoked) → the five inputs **the
  outcome needs** — whatever the thing must produce, worked backwards. Never invent a control
  list and then test your own invention.

A field you cannot fill without inventing a **mechanism** is a **crack**. Keep the attempt —
paste the rows into the verdict or write them to a scratch file the verdict cites. A bare
`fill: pass` is the feeling this test exists to replace.

Then sort the cracks twice, because both splits change the route:

- **does it block the screen in front of you, or not?** A crack that blocks nothing is recorded
  and passed over. Model work is never finished; waiting for a ledger with no open crack is how
  this skill turns into a permanent veto.
- **missing fact, or unmade choice?** A fact (somebody goes and reads the real source) belongs
  to `design-model`. A choice belongs to `decide`. Routing a decision into another modelling
  round is how a design effort spends a week re-deriving a question only the owner can answer.

**Outcome test — is there a number it must produce?** Many screens exist to produce one
checkable output: a price, a total, a quote, a delivery date, a document. Is there one, and has
it ever been measured against the real world? **Checking takes a minute; measuring does not** —
if the answer is no, that measurement *is* the route (`design-model`), not something to start
here. Until it exists, every frame is unfalsifiable: nobody can say whether the design works.

**Hand test — meta-tools only.** Has the thing this tool automates been done **by hand, for
real, at least three times**, with a record of what the hands actually did? If not, the tool is
being designed from imagination. Do it by hand (concierge / Wizard of Oz), keep the record, and
design the tool from the record. This single rule is what makes editors and admin tools cheap:
their screens are derived from a transcript instead of invented.

**Order test — is the sequence settled?** Several screens involved: **name the file that names
the first one.** A backbone with a chosen first slice, written down somewhere — not somebody's
recollection of a meeting. Nothing names it → the open question is the backbone, not any one
screen.

All four pass → the uncertainty genuinely **is** visual. Route to the craft and don't hold it up.

## 3. Route — one phase, one skill, one artifact

The **needs** column is load-bearing: when what you have doesn't satisfy it, the missing
artifact is the route, not the skill behind it.

| The uncertainty is in | Phase | Skill | Needs on arrival | The artifact |
|---|---|---|---|---|
| whether to build it at all | shaping | `om-ux-shape` (Shape) | a feature idea or product area | a decided direction |
| what the thing *is* — objects, fields, derived values, rules | content-first | `design-model` | one real, named instance | tables + a crack ledger. No frames |
| a number it must produce, never measured | measurement | `design-model` (its measurement pass) | the same instance + a reachable source | the figure, with its source and date |
| a choice a human owes you | decision | `decide` | the choice, its options, its stake | the answer, recorded where the project keeps decisions |
| no reachable instance at all | access | `om-synthetic-users` (`simulate`) | material carrying a real evidence tier | hypotheses tagged `[SYNTHETIC]` + the interview plan |
| which screen first | story map | `design-model --map` | at least one written instance | a backbone + a thin first slice |
| whether the flow can be operated at all | low-fi flow | `om-mockup-prototype` | a product brief with Key flows | neutral clickable screens |
| which structure is best | parallel variants | `design-explore` | the screen exists and runs | ~3 structurally different variants + a pick |
| what every state looks like | states | `design-storyboard` | a spec with role→goal→outcome stories and per-state acceptance criteria | one page, every state, the app's tokens |
| hierarchy, spacing, type, colour, motion | polish | `design-polish` | a running UI on settled data | before/after screenshots |
| whether a PR's increment serves the user | review | `om-ux-review-pr` | an open PR, or a branch diff | findings with evidence + acceptance criteria |
| whether a whole area serves the user | review | `om-ux-shape` (Review) | the area, running | the filled Review shape |

- **Before the first row**, when the idea itself has never been questioned, `brainstorm` is its
  own step with its own exits — run it first and come back; it does not hand over to shaping.
- **`impeccable`** instead of `design-polish` only when the ask is a new visual language rather
  than the correction of an existing one.
- **Six of these ship elsewhere** — the `om-*` skills with Open Mercato, `design-storyboard` on
  FSH's internal marketplace. Name the artifact anyway when one isn't installed.
- Two phases may genuinely be queued. Say which is first and **route only to that one**; a
  verdict that hands over a programme gets none of it done.

## 4. Blocked moves

Name these out loud when the request asks for one; they are where design budget dies.

- **Frames while a screen-blocking crack is open.** The crack outranks every visual question on
  that screen.
- **Personas while the users are reachable.** A synthetic panel is a prosthesis for *no access*.
  Two reachable customers beat six invented personas, and their artefacts beat both — route to
  `design-model`. "Reachable" is low: one obtainable artefact, and public material counts.
  `om-synthetic-users` earns its place when even that is missing, or to generate hypotheses
  between real rounds — never instead of a phone call that could happen.
- **The meta-tool before the hand.** See the hand test; this is the expensive one.
- **Workshop ceremony for a one-decider team.** From Design Sprint keep two mechanics — expert
  interviews on the way in, and one named decider while everyone else proposes. The five days
  are not the point.
- **Iterating one variant** where parallel cheap ones are both faster and measurably better.
- **A fidelity jump to please a reviewer.** "Make it look real so they can judge it" is how a
  model question gets re-asked in Figma.

## 5. The verdict

One screen, in the language the user is writing in:

```
**Target** — <what, for whom, which of the four kinds>
**Probe** — fill: pass/fail over <the five fields> (<attempt: path or inline>) ·
            outcome: <the number, measured / never measured / none> ·
            hand: <n real runs on record / n-a> · order: <the file that names the first screen / none>
**Cracks** — blocking: <ids + what each needs> · open but not blocking: <ids>
**Phase** — <the phase, and the fidelity ceiling: "tables and prose, no frames">
➡️ **Next** — `<one skill>` producing `<one artifact>`
**Moves on when** — <the crack that closes, or the fact that gets measured>
```

Then **write it down** — one line wherever this project keeps the design record (the specs
directory's index, the ticket, the spec's own header): date, phase, fidelity ceiling, exit
condition. A verdict that exists only in a chat log is gone by the next session, and the next
session draws. That write is the skill's only mutation.

**Unattended** (`-p`, cron): produce the verdict, write the line, start nothing.

## Hard rules

1. **Route, don't design.** Not one frame, not one token, not "a quick sketch to illustrate".
2. **A crack that blocks the screen outranks every visual question on it.** Cracks that block
   nothing are recorded and passed over — never a reason to send the work back.
3. **Respect the probe budget.** Five fields, sources on hand, nothing acquired. Over budget is
   a fail, and what it would have cost to finish is the phase.
4. **State the fidelity ceiling explicitly**, every verdict. Otherwise the next session draws.
5. **Don't block genuinely visual work.** All four probes passing is a real result; a router
   that always answers "go back further" will be ignored, and deserves to be.
6. **Show the probe.** The attempted rows, the measured number, the count of hand runs, the file
   that names the first screen. No verdict rests on an adjective.
7. **One phase per verdict**, with the exit condition that ends it, written down.
