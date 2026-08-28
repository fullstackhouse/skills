<!--
ORIGINATING BODY — use when no live artifact elsewhere states the problem.

The emoji and their order are fixed. The words after the emoji are yours: write the
heading this ticket needs. Drop every section you have nothing real to say under, and
delete every comment including this one. Only 🎯 and ✅ are mandatory.
-->

### 🎯 {HEADLINE_NAMING_WHAT_IS_BROKEN}

{{OBSERVABLE_SYMPTOMS_AND_THEIR_COST}}

<!--
What is broken or missing, in the terms of whoever feels it: who is blocked, how often,
what it costs, numbers where known. No code identifiers here.
A reader must be able to disagree with the plan below and still agree with this section.
Nothing broken? Then this is the goal instead — same slot.
Heading: "### 🎯 A failed backfill reads as success", not "### 🎯 The problem",
unless nothing sharper fits.
-->

### 🔧 {HEADLINE_NAMING_WHAT_WE_DO_ABOUT_IT}

{{THE_PLAN_IN_A_PARAGRAPH_OR_A_SHORT_LIST}}

<!--
The open work, ordered, each item worth having even if the next never happens.
One canonical enumeration — never a second list that maps onto this one.
Someone in a hurry stops reading here.
-->

### 🔍 {HEADLINE_NAMING_THE_DETAIL_THAT_MATTERS}

{{EVIDENCE_MEASUREMENTS_REASONING_THAT_MUST_SURVIVE}}

<!--
Technical narration: names, measurements, repro, the reason behind the approach,
directions rejected so nobody re-raises them, anything counter-intuitive.
May appear twice in a long body — once for open detail, once for what is already
settled and must not be redone. That is deliberate; do not invent a slot for history.
-->

### ⚠️ {HEADLINE_NAMING_THE_RISK_OR_THE_EXCLUSION}

{{RISK_DEPENDENCY_OR_WHAT_IS_DELIBERATELY_NOT_IN_SCOPE}}

<!-- Skip it when there is none. -->

### ✅ Done when

- [ ] {{INDEPENDENTLY_CHECKABLE_CONDITION}}
- [ ] {{INDEPENDENTLY_CHECKABLE_CONDITION}}

<!--
Remaining work only — nothing already satisfied. Each condition checkable on its own, by
someone who didn't write it. Conditions owned by a sibling ticket link there instead.
A single sentence is a valid DoD; a list is not mandatory.
-->

{{LINKS_SIBLING_TICKETS_SOURCE_MATERIAL}}

*Facts checked: {{YYYY-MM-DD}}.*
