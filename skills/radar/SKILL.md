---
name: radar
description: >-
  Take one artifact that arrived from outside — a blog post, a product launch, a Slack
  thread, a newsletter, a competitor's announcement, a link someone sent with no comment —
  read it properly, and decide whether you, or the project or company behind the current
  context, needs to do anything about it. Produces a one-screen note with a verdict and at
  most one routed next step. Use when invoked as "/radar", when handed a link with no
  question attached, or when asked "what does this mean for us", "should we use this",
  "research this post and see if we should do anything about it", "is this worth reacting
  to". Read-only apart from the note until the verdict is confirmed.
---

# radar

Something arrived from outside, and the only question that matters is whether anything
**here** should change because of it. **Most of the time the answer is no.** This skill
exists to make that "no" cheap, explicit and durable, and to make the rare "yes" specific
enough that someone can act on it.

"Here" is whatever the current context is: a company, a client's product, one repo, or the
user's own life. Working out **whose decision this is** before judging the artifact is the
whole point — see step 3.

**The failure it prevents is the long session that commits nothing.** Research an
interesting artifact with no forced verdict and you get a hundred messages, a feeling of
having thought about it, and no record — so the same link arrives in six months and costs
the same hours. The deliverable is not the research. It is a one-screen note with a
verdict, and, when the verdict earns it, exactly one routed next step.

Everything except the note and its index row is **read-only until the user confirms the
verdict**.

## Context specifics — read these first

Repo-agnostic. Derive from the consuming repo's `AGENTS.md` / `CLAUDE.md` (the
`## Skill profile` section is the curated source), and ask the user only for what no file
answers:

- **Whose decision this is, and their shape** — the company, product or person the verdict
  is for: how the work gets done, how money is earned, who eats the cost of a mistake.
  Read the repo's agent docs, its company/product docs, its README. In a personal context
  there is no repo to read: ask, and keep it to the three or four facts a verdict would
  actually turn on.
- **Where notes live** — a `radar` knob in `## Skill profile`; else `docs/radar/` when the
  repo has a `docs/`; else `.context/radar/` when `.context/` exists; else ask. Create the
  directory and its index `README.md` on first use.
- **Tracker** and **Specs** — the usual knobs. Radar only reads them, and only to route.

When the context is a client's repo, the note is a client artifact: it lives in their repo,
in the language their docs use, and carries no detail belonging to anyone else.

## Not this skill

- **`prior-art`** — a decision is already on the table and the question is how the rest of
  the world decided it. Here an artifact arrives and the first question is whether there is
  a decision at all. **When the verdict turns on "is this technically the right choice",
  hand that survey to `prior-art`** rather than half-doing it inside this note.
- **`brainstorm`** — an idea of ours. Radar's input always comes from outside.

One artifact per run. A newsletter with five links is five runs, and usually four of them
die at step 3 without a note.

## 0. Check whether this was already answered

Read the radar index, then search the specs directory and the docs area the artifact
touches. **An existing internal decision beats an external post**: it was made here, under
these constraints, and someone remembers the consequences. If a note already covers this,
add a dated line to it instead of writing a second one.

## 1. Read the artifact — actually read it

- **Open it.** If it is paywalled, JS-only, or the fetch fails, say so and stop. A summary
  written from a title and a URL is the single worst output this skill can produce, and it
  arrives looking exactly like a real one.
- **A chat link is a thread, not a link.** Read the replies and reactions. What people said
  about the artifact is usually more decision-relevant than the artifact, and it tells you
  who already holds an opinion.
- **Quote the load-bearing claims verbatim.** Every action proposed later has to trace back
  to one of these quotes (hard rule 2). A claim you can only paraphrase is one you will not
  be able to defend in the note.
- **Date the state-bearing claims** — versions, prices, "no stable API yet", "still
  unmaintained". These were true on the day you read them and rot silently afterwards.
- **A vendor post is a pitch.** Its claims are the ones to check, not the ones to relay. So
  are a consultant's, a newsletter author's, and anyone whose business model *is* the
  advice.

## 2. Classify it — each kind has a different "so what"

| Kind | The question that decides it | Where the evidence is |
|---|---|---|
| **Practice / opinion** — how to hire, review, staff, work, live | Does this context's shape make it apply at all? (step 3) | This context's own docs and history, not more reading |
| **Product / tool** — a launch, a library, a platform | What would it replace here, what does it cost to leave, has anyone run it in anger | Primary docs, source, field reports → `prior-art` |
| **Market move** — a competitor, a pricing shift, a positioning change | Does it change what a customer will ask for, or what can be charged | Sales/marketing docs, live deals, the pipeline |
| **Hard fact** — licence change, deprecation, regulation, a price | What breaks, and by when | The vendor's own notice, checked against what is actually installed or used here |

Hard facts most often force a real action and are most often filed as "interesting".
Opinion essays are the reverse.

## 3. Name the assumption that has to hold here

**This is the whole intellectual move of the skill.** The author wrote for someone with a
shape: a team of a certain size, a bench or no bench, a way revenue is earned, a specific
person who eats the cost of a mistake. Reconstruct **this** context's shape from its own
documents — never from what the artifact assumes its reader looks like — then name the one
assumption that, if false here, kills the advice regardless of whether the artifact is
right.

Cite where each fact about the shape came from: a path, a doc, or "the user said so". A
shape inferred from vibes bends toward whatever verdict the artifact is pushing.

The move looks the same at every scale:

- A studio where one senior owns a product end to end and AI takes the first pass reads
  "hire juniors to scale the team" against *there is no bench to absorb unbilled ramp-up* —
  the premise is missing, so the argument's quality is beside the point.
- A person reads a productivity system against *what am I actually short of* — time,
  attention, money, or none of them. Most such posts assume a shortage their reader
  doesn't have.

**"The artifact is correct" and "the artifact applies here" are different findings, and
only the second one is being asked for.** A well-argued piece whose premise this context
doesn't share is a `Nothing`, and saying so *is* the output — not a failure to extract
value. Where it does transfer, name the specific local fact that makes it transfer, and
where that fact is written down.

## 4. Check it against what is actually done here

Read the repo, the tracker and the docs. Do not recall. **"We already do this" is one of
the two most common true verdicts**, and the note is only reusable if it says *where* —
with a path, a spec number, or a PR.

The other is "we deliberately decided against this", which is usually also recorded
somewhere: a rejected or superseded spec, a doc's "deliberately not" section, a closed
ticket. Finding the existing decision is worth more than re-deriving it.

## 5. Decide — one verdict, one action

| Verdict | Means | Handoff |
|---|---|---|
| **Nothing** | Doesn't transfer, or the premise is wrong here | note only |
| **Already covered** | This is done, or was decided against | note links to the spec/doc/PR holding the decision |
| **Watch** | It could matter, but a fact nobody has decides it | note + a named trigger; a `/loop` or schedule only if the user asks |
| **Change in place** | A doc, a rule or an agent instruction should change, and it's small | do it in the same commit as the note |
| **Build or adopt** | Real work, spec- or ticket-shaped | brief → `brainstorm`, `kickoff`, or a spec in the configured specs location |
| **Publish** | There is a take here backed by something only this context can show | brief → wherever this context publishes; its voice/style doc is canon |

**The default is `Nothing`.** Defend any other verdict against it.

**Every verdict except `Change`, `Build` and `Publish` carries a reopen trigger** — the
concrete fact that would change it. A no without a trigger is indistinguishable from not
having looked, and it is what makes a future reader redo the work.

**At most one routed action.** If three things look actionable you haven't decided yet;
pick the one and name the others as what they are — things nobody is doing.

## 6. Write the note

`<notes dir>/{YYYY-MM-DD}-{kebab-slug}.md`, plus its row in the index `README.md`, in one
commit. **The note ships even when the verdict is `Nothing`** — that case is the reason the
directory exists.

```markdown
# {What it is} — {verdict in four to six words}

- **Source**: <url> · {author} · published {date} · read {YYYY-MM-DD}
- **Kind**: practice | product | market | fact
- **Verdict**: Nothing | Already covered | Watch | Change | Build | Publish
- **Next**: {the one routed step, or `none`}

## What it claims

{2–4 bullets. Each is a load-bearing claim with a verbatim quote — the claims an action
would rest on, not a summary of the piece.}

## Does it transfer

{The assumption the advice needs. Whether it holds here, with a path to where this
context's own practice is written down.}

## Verdict

{Three to six sentences: what is being done about it and why. On `Nothing`, say what is
done instead — that is the part worth re-reading.}

## Reopens if

{The fact that would change the verdict: a measurement, a customer asking for it, a price,
a version, a hire.}
```

**Keep it under a page.** If the research ran long, the transcript goes to a scratch
location (`.context/` when it exists), uncommitted — never into the notes directory. A note
that grew into an evidence file is one nobody will open, and the verdict is the only part
anyone needs.

## 7. Route

End with the machine-parseable lines, same convention as `brainstorm`:

```
Verdict: <one of the six>
Note: <path>
Next: none | /kickoff "<goal> — note: <path>" | /brainstorm "<question>" | /prior-art "<decision>"
```

Only invoke the next skill if the user says to. Two traps on the ramps:

- **The publishing surface is often a different repo or a submodule.** The article, the
  site change or the post happens there, not in the repo you are standing in.
- **On `Publish`, the context's voice or style guide is canon** — read it before drafting a
  word. Claims backed by something this context can actually show; nothing generic, and
  nothing that hedges away a claim it can stand behind.

## Hard rules

1. **Never summarize an artifact you could not open.** Report the failure instead.
2. **Every proposed action traces to a quoted claim.** No quote, no action.
3. **The default verdict is `Nothing`, and every non-acting verdict names its reopen
   trigger.**
4. **One routed action, at most.** Name the rest as declined.
5. **The note ships regardless of the verdict** — a `Nothing` that can be found again is
   the product.
6. **Read-only outside the note and its index row**, until the user confirms. The `Change`
   ramp's edit happens after that confirmation, in the same commit.
7. **Hand the technical survey to `prior-art`**, don't improvise one.
8. **This context's own docs, code and history outrank the artifact** — including when the
   artifact is better written.
