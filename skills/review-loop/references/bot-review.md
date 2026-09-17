# The `bot` and `human` sources

Both attach to a **pull request**, and both **publish** — thread replies and resolutions.
Everything here is GitHub mechanics the loop in `SKILL.md` needs in order to run a round
against a reviewer that lives on the other side of a network boundary. Every rule below is
here because a run got it wrong.

Read `SKILL.md`'s hard rules first; nothing here relaxes them. In particular: the findings
from these sources go through the same verification (Phase 5) as any other, a refuted bot
finding gets a reply explaining why, and this skill still never merges.

**These two sources do push, and only these two** (hard rule 7). Everything they wait on is
read from the *remote*: the poll gates on `gh pr view --json headRefOid`. A round that fixes
locally and does not push re-requests a review of byte-identical code — the same findings
come back, dedupe reads them as "the fix didn't take", and the source either grinds to its
cap or records convergence against a HEAD that predates every fix it made. So: **commit,
fast-forward push, and only then reply, resolve, and re-request.** Never force-push; if the
push is rejected as non-fast-forward, stop and report it — someone else moved the branch.

## Before the round

Resolve three values, and **assign all of them up front** — an unset variable interpolates
to `""`, which matches no review and fails in exactly the silent-empty way this section
exists to prevent:

```bash
SLUG=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
export REVIEWER=$PROFILE_REVIEWER      # requested AND matched; no default — see below
export AUTHOR=$(gh pr view <N> --json author --jq .author.login)     # excluded everywhere
```

`PROFILE_REVIEWER` is the `## Skill profile` **`reviewer`** key (a bot login), not
`reviewers` (the human list). **It has no default.** Unset, and with no login passed
explicitly, this source has nothing to request: write `sources.bot.exit: no-review` with
that reason and stop. Falling back to `copilot-pull-request-reviewer` on a repo that never
configured it buys a ten-minute poll per round for a review that will never arrive, and
makes the opt-in framing of the knob a fiction. **It must be the login, never an alias**:
`copilot-pull-request-reviewer` is the only spelling that both lands a
`gh pr edit --add-reviewer` request *and* matches `.author.login` on the review it produces.
`@copilot` requests fine and then matches nothing — a poll that outlives a review which
landed two minutes in. (`Copilot` works only on the REST reviewers endpoint, which this
skill does not use.) A bot whose alias and login genuinely differ needs two profile values;
say so rather than let one half-work.

**Record a baseline.** On a re-request the bot's previous review is already on the PR, so
without this the first poll returns instantly with the *old* review and the round addresses
feedback written against an earlier HEAD:

```bash
export PRIOR=$(gh pr view <N> --json reviews \
  --jq '[.reviews[] | select(.author.login == env.REVIEWER)] | sort_by(.submittedAt) | last | .submittedAt // ""')
```

Two details in that filter are load-bearing. **`env.REVIEWER` inside a single-quoted
filter**: an interpolated `\"$REVIEWER\"` breaks on the re-quoting a loop or background
watcher applies, and then matches nothing, silently. And **the `// ""`**: without it an
empty array prints the literal `null`, and `"2026-…" > "null"` is false, so the first
review on a fresh PR never matches.

## Requesting

Request and re-request with the same command — `gh pr edit --add-reviewer` both adds a
reviewer and re-requests one who has already reviewed, and a re-request is what triggers a
fresh review against the new HEAD:

```bash
gh pr edit <N> --add-reviewer "$REVIEWER"
```

**Count the round here**, before the request goes out, not when the review comes back
(`SKILL.md` Phase 7): a request that times out is spent.

**Do not verify by reading `reviewRequests` back — neither API can answer the question.**
REST `requested_reviewers` returns only `{users, teams}` and omits bot reviewers entirely;
the GraphQL form (`gh pr view <N> --json reviewRequests`) does see them, but a landed
request **disappears from it the instant the reviewer submits**. Copilot often reviews
within a minute or two, so the faster it works, the more certainly a read-back shows
nothing. The success signal is a review arriving, which the poll is already watching for.

**A failed request is not a missing review.** Many repos have the bot reviewing
automatically on open, with no request from anyone. Report the failure, keep polling.

## Polling

```bash
export HEAD_OID=$(gh pr view <N> --json headRefOid --jq .headRefOid)
gh pr view <N> --json reviews \
  --jq '[.reviews[] | select(.author.login == env.REVIEWER and .submittedAt > env.PRIOR and .commit.oid == env.HEAD_OID)] | sort_by(.submittedAt) | last'
```

Every ~60s for up to ~10 minutes. Same single-quoted `env.` filter, for the reason above.

**`submittedAt` alone does not answer "reviewed at this HEAD".** A review requested before
a push lands *after* it — newer than `$PRIOR`, and still written against superseded code.
Each review carries the commit it read (`.commit.oid`), so gate on that; a "no new
comments" verdict on the commit your fix replaced says nothing about the fix. Read such a
review anyway — its findings may still apply — but don't let it satisfy the gate, and
re-request against the new HEAD.

**Distinguish jq's `null` (no match yet) from an empty result (a failed call, a broken
filter).** `[ "$R" != "null" ]` alone treats the empty string as a hit, exits the loop on
the first hiccup, and reports no review while the bot is still working. Test for both.

**A quota refusal is not a review.** "Copilot was unable to review this pull request
because the user … has reached their quota" arrives *as a review*, within seconds. Match it
(`.body | test("unable to review")`), stop polling at once, and take the no-bot path.
Waiting the full ten minutes on it is the one cost the poll can avoid outright.

**Check for an existing human review before polling, and accept one whenever it lands.** A
previous run that timed out requested a human and stopped; a poll that only ever matched
`REVIEWER` could never be satisfied by that person's approval, and the loop would
re-request the bot forever on a PR someone had already read:

```bash
gh pr view <N> --json reviews \
  --jq '[.reviews[] | select(.author.login != env.AUTHOR and .commit.oid == env.HEAD_OID and (.state == "APPROVED" or .state == "COMMENTED"))] | sort_by(.submittedAt) | last'
```

A hit from anyone, bot or human, **is** the round's review: read its findings, record its
`.commit.oid` as `reviewed_oid`, and don't spend a round re-requesting.

Nothing by the timeout → set `sources.bot.exit` to `awaiting-review`, report that the bot
never answered, and **stop this source**. The bot earns a ten-minute poll; a human does not.

**Do not escalate to the `human` source on your own.** Its defining action is `gh pr edit
--add-reviewer` against a login derived from the repo's merged-PR history — it pages a real
colleague, on an unattended overnight run as readily as an interactive one, and the result
is unrecallable. Requesting a person is the caller's decision: `SKILL.md` already refuses to
improvise a source nobody asked for, and `deliver` states that its branch-protection path is
the only place it requests one. Recommend `--source human` in the report; let whoever reads
it decide.

## Reading the findings

Most feedback is line comments, not the review body:

```bash
gh api "repos/$SLUG/pulls/<N>/comments" --paginate
```

Filter to comments authored by the reviewer and posted at or after the review's
`submittedAt`.

**A round's findings are its inline comments plus the "Suppressed comments" the review body
folds into `<details>` — read both.** A body saying "Comments generated: 0" routinely sits
above three to five suppressed findings; a loop reading only inline comments calls such a
round clean and merges over them.

**The verdict header is not a finding.** Copilot opens every review with 🟢 *Approval
recommended* / 🟡 *Changes recommended* / 🔵 *Needs a closer look*. The yellow one counts
*unresolved threads*, so a PR whose fixes are all pushed but whose threads are still open
stays 🟡 forever; the blue one on a broad change means "a human should read this", and no
code fix turns it green. **Judge the round by its findings alone**: no actionable finding is
`verdict: clean` whatever the colour. On 🔵, record the round, request the human, and don't
spend a round asking the bot again.

Write `sources.bot.last_round_severity` as `blocking` only when the round raised a
correctness bug, a security or data-loss risk, a breaking change, or a failing test — that
is what the 3-vs-5 cap turns on. It is per round and per source, not sticky: a round
returning only nits writes `nits` and the cap falls back to 3. Judge it while you are
reading, and write it down; a later invocation sees only `state.json` and cannot re-derive
it.

## Replying and resolving

Every finding gets both — after the fix is committed **and pushed**, in that order, so that
the thread you are answering and the code GitHub holds agree with each other:

```bash
gh api -X POST "repos/$SLUG/pulls/<N>/comments/<comment-id>/replies" -f body='…'
```

…and a resolution via the GraphQL `resolveReviewThread` mutation. **Resolve before any
re-request** — the bot's verdict counts unresolved threads, so a fixed-but-open thread buys
another 🟡 and another lap.

A finding that comes back on the same line in a later round is a thread you didn't close,
not a new finding: fix it or refute it on the thread now. One PR carried the same unanswered
comment through seven rounds.

A finding you *refute* still gets the reply — with the reason — and the resolution. One you
*disagree* with on judgement (design, scope, taste) gets the reply and stays **open** for
the user to settle; it goes into `state.json`'s `open` array as `handed up`.

Everything you post here passes `SKILL.md`'s hard rule 11 first. A reply quoting a client's
internal identifier into a public repo is the one failure in this file that a later commit
cannot undo.

## The `human` source

Same PR mechanics, one difference that changes everything: **request, then don't wait.**

Pick the reviewer from the `## Skill profile` **`reviewers`** key when the repo sets one.
Otherwise derive a candidate from who actually reviews in this repo — and then **request
them**, which is the step whose absence makes this source a no-op:

```bash
HUMAN=$(gh pr list --state merged --limit 20 --json reviews \
  --jq '[.[].reviews[].author.login] | map(select(. != env.AUTHOR and . != env.REVIEWER)) | group_by(.) | max_by(length)[0] // empty')

if [ -n "$HUMAN" ]; then
  gh pr edit <N> --add-reviewer "$HUMAN"
else
  : # no candidate — report it and ask the user who should review; do not guess
fi
```

Note the `env.` form inside a single-quoted filter — the rule from the top of this file. An
interpolated `"$AUTHOR"` breaks under the re-quoting a loop applies and then matches
nothing, silently, which here means reporting "no candidate" on a repo with an obvious one.
`// empty` guards the empty candidate list — a bare `max_by(length)[0]` prints `null`,
exits 0, and the run requests a reviewer literally named `null`. Excluding the author is
required too: requesting the PR author returns `422`.

Then read whatever threads already exist on the PR, run them through the normal loop
(verify → fix → reply → resolve), and finish with `sources.human.exit` set to `awaiting-review` if no review has
landed. Never treat "no human review yet" as "no review needed", and never poll for one.
