---
name: competitor-teardown
description: Take a competing product apart hands-on — sign into it with an agentic browser, work the buyer's actual jobs through its UI, screenshot what it really does, find the plan gate under the feature they need, and quote the vendor's own scope disclaimer — then land a verdict on what we stop competing for and what we take. Use when invoked as "/competitor-teardown", when a prospect is trialling or quoting an alternative ("they're testing X", "they got a quote from Y"), when asked to analyse a competitor or rival product, before pricing a bid against an incumbent or a SaaS, or when positioning our product against a named alternative. Writes only into its own evidence directory — it never pays, never signs, never posts.
---

# competitor-teardown

Someone is about to be compared to a product that is already open in the buyer's other tab.

**Two failures own this task, and they look like opposites.** The first is the *fluent summary* — ask an LLM what a competitor does and it returns the marketing page in different words, feature-complete, confident, and true of nothing in particular. The second is the *undigested archive*: a capture pass of nine competitors, ~690 screenshots, sat unsynthesised in a repo of ours for eight months, and the companies in the screenshots barely overlapped the companies in the written analyses. Both halves were real work. Neither was a deliverable.

This skill is the two halves welded: you click the product yourself, and you write the verdict in the same pass.

**Sibling skill:** `/prior-art` answers *"how do systems solve this problem"* — a design question, settled in docs and source. This one answers *"what is this product, that we are up against, actually going to do to us"* — a commercial question, settled by using it. Reach for `/prior-art` when the output is an architecture decision, this one when the output is a position, a price, or a scope line.

**Read-only outside the evidence directory.** Don't buy, don't upgrade a plan, don't contact sales under a pretext, don't post anything.

## 1. Name the decision the teardown serves

A competitor analysis with no decision attached always becomes a feature list, because a feature list is what you can always produce. State which of these you're serving — they want different runs:

- **A prospect is evaluating them instead of us.** You need the seams and the price at *their* headcount. Deepest run.
- **Build-vs-buy for a client.** You need what buying actually costs over the same horizon as building, and what buying leaves unsolved.
- **Positioning our own product.** You need their strengths honestly, and one axis where the answers diverge.
- **Roadmap gap-filling.** You need the *shape* of their solution, not their marketing — and this is nearly `/prior-art`; consider running that instead.

Write the decision down first. Everything below gets cut against it.

## 2. Pick who, by the buyer's shortlist — not by fame

The list that matters is the one the buyer has open, not the market leaders. Get it from the meeting notes, the transcript, the RFP, the tracker — the names they said out loud, including the incumbent they're replacing and the option they already rejected (the rejected one carries their price ceiling, stated as a fact rather than a negotiating position).

Famous adjacent products are a **contrast class**: included to show where the axis runs, never as the thing we're measured against.

**One list, and everything downstream covers it.** If a name is worth capturing it is worth appearing in the verdict; if it appears in the verdict it needs capture behind it. The archive failure above was exactly this drift.

## 3. Get in through the front door

Preference order: **a real trial account** (best — the UI under a working account is the only place the product stops being a brochure), then a public sandbox/demo instance, then recorded demos and docs, then review-site screenshots.

- **Credentials come from the operator at runtime and never enter a file.** Not the evidence dir, not a commit, not a screenshot. If a credential was pasted into the session, it stays in the session.
- **Sign up as ourselves.** Our own name and email, no invented company, no pretext. A teardown that needed a lie to happen is one a client can't be shown.
- **Read what the trial's terms actually say** about evaluation and benchmarking, and note it in the evidence file. Some forbid publishing comparisons; that changes what the verdict may be used for, not whether you may look.
- **No trial, no demo?** Say so and run the documentary version — and **label the whole verdict `documentary`**. Absence of a feature you could not look for is not a finding.

## 4. Click it like the buyer, not like a tourist

Drive the session with whatever agentic browser the session has (Playwright MCP `browser_*`, or the repo's configured browser provider). The difference between this and a nav-bar crawl is entirely in what you attempt.

**Work the jobs, not the menu.** Take the top 3–5 things the buyer said they need — in their words, from their transcript — and try to do each one, end to end, as the person who'd do it. Where you can't finish, that is the finding.

Capture as you go:

- **Numbered, slugged screenshots**: `012-budget-line-single-amount-field.png`. The number is the order you walked; the slug is what a reader is looking at. A directory of `screenshot-3.png` is the archive failure in miniature.
- **The failure states, deliberately.** The validation error, the empty state, the permission wall, the "contact sales", the greyed-out control. These are worth more than the happy path — the happy path is on their website already.
- **The upgrade wall is the single most valuable screenshot in the run.** It is the exact point where the price model touches the feature the buyer needs, and it is what step 5 is built on.
- **The data model showing through the UI.** What fields exist, which are required, which are derived, which are free text pretending to be structure. One field where our buyer needs a versioned one (a budget that can't hold an amendment, a date with no baseline) is a structural finding, not a UI nit — and it's invisible to anyone reading the feature list.
- **Click-count the #1 job.** A number the buyer can feel beats an adjective.
- **What's fast, what's polished, what's obviously loved.** Record it now, while you're annoyed at it. See rule 7.

Write **one line of note per screenshot as you take it**. Notes written afterwards are written from the thumbnails, which is how a teardown ends up agreeing with the marketing page.

**Purposeful beats exhaustive**: 40 screenshots along the buyer's jobs are worth more than 400 from crawling every menu, and cost a fraction of the review. Downscale images before committing them; a screenshot is evidence, not an asset.

## 5. Price it at the buyer's real scale

The list price is not the number. Three moves, each of which has flipped a verdict:

1. **Find the gate, not the price.** Which plan holds the feature they actually need? A product is cheap at the tier that doesn't do the job. Cite the plan comparison page verbatim for the feature's tier.
2. **Compute at the scale they stated, not the scale they'll start at.** Per-seat pricing scales with the *success* of the rollout: the number that matters is list × the headcount they told you they're growing to. A tool that looks like a rounding error at the pilot can land on the same line as the enterprise ERP they already rejected on price.
3. **Put it on the same horizon as our number.** One-time build vs recurring subscription, three years, both with promo pricing expired. Add what they'll still be paying for alongside it — the system this doesn't replace (see step 6) is a line item, not a footnote.

Output a small table: plan / gated feature / cost at pilot size / cost at stated target / same-horizon total. Cite where each number came from.

## 6. Find where the vendor draws its own boundary

**The most credible sentence in the whole analysis will be theirs, not yours.** A vendor saying "this does not replace an ERP" ends an argument that no amount of our own analysis can. Hunt for it:

- the "**is it for me / who is this not for**" page, and the FAQ's awkward question;
- **the integrations page** — what a product integrates with is a precise map of what it has decided not to do;
- the **changelog and roadmap**: what's been promised for two years is a boundary with a bow on it;
- **support docs for the workaround** ("to handle X, export to Excel and…");
- **job ads** for what they're building next;
- **review sites**, read only for the recurring complaint, never for the star rating.

Quote verbatim, with URL and the date you read it. And apply the same rule you'd apply to a source: **a claim about a competitor's limits that you cannot quote or screenshot doesn't go in the verdict.**

## 7. Two artifacts

**The verdict** — one page, pasteable into a deck or an email:

- **What it is and who it's for**, in their own words;
- **The half they win**, stated plainly and without hedging (see rule 7);
- **The seam** — what it structurally won't do, each line carrying a quote or a screenshot number;
- **The price at the buyer's real scale**, the table from step 5;
- **What this means for us** — what we stop competing for, what we take instead, and what that costs us in deal size. A recommendation to concede ground is a normal output of this skill and often the correct one;
- **What we couldn't reach** and what would settle it — a plan we couldn't see, a flow we couldn't finish, a price we couldn't confirm.

**The evidence** — a directory, as long as it needs to be: screenshots with their notes, the pricing worksheet with sources, every URL with the date read, the terms note from step 3, and what you tried and failed to reach.

Keep them separate. A document that is both becomes the evidence file, and nobody pastes an evidence file into a deck.

## Hard rules

1. **Capture and verdict ship together.** A screenshot directory with no synthesis is not a deliverable, it's a debt — and the observed repayment rate is zero.
2. **One competitor list.** Everything captured appears in the verdict; everything in the verdict has capture behind it.
3. **Quote or screenshot, don't characterise.** Every claim about what the product does or doesn't do carries a verbatim phrase or a numbered screenshot. "It doesn't really handle X" is an opinion wearing a fact's clothes.
4. **Date every state-bearing claim.** Products ship weekly; "the free plan includes" and "there's no API" rot silently, and stale is harder for a reader to catch than wrong.
5. **Credentials at runtime only**, never in a file or a commit. Scrub the trial account's identity out of anything that leaves the repo.
6. **Unreached is not absent.** A tier you couldn't buy into and a flow that wouldn't complete are recorded as missing measurements, in their own section.
7. **Never claim we win without stating where we lose.** The buyer has their trial open; a teardown that finds only weaknesses reads as marketing and loses the room. If the honest answer is that they're better at the thing being compared, that is the finding — take it to step 1's decision and re-scope.
8. **Nothing outbound.** No purchases, no plan upgrades, no sales contact under a pretext, no posting the comparison anywhere. Publishing is a separate, human decision.
