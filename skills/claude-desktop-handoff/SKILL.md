---
name: claude-desktop-handoff
description: Hand one GUI-only step to Claude Desktop running on the same machine, over a shared temp directory, so this session can keep working autonomously instead of stopping. Use when the step needs the user's own logged-in browser — a vendor console with no API, an OAuth app registration, an SSO-gated admin page, anything behind a password manager or passkey — and this session is non-interactive (Conductor, `-p`, cloud) or has only a headless browser. Prints one prompt for the user to paste into Claude Desktop; the two sessions then talk through files, so Desktop can ask a question mid-task and get an answer without the user relaying it. Use `desktop-handoff` instead when the hand might be a different machine, a different runtime, or not Claude at all.
---

# claude-desktop-handoff

Same machine, two Claude sessions, one shared directory. That single fact is what this
skill trades on:

- **The filesystem is shared**, so files are a real bidirectional channel — not a
  best-effort drop. Desktop can ask; you can answer; neither blocks on the user.
- **The clipboard is shared**, which gives you a side channel for secrets that enters
  *neither* transcript.
- **Claude Desktop drives the user's real Chrome** through the Claude in Chrome
  extension — their sessions, their password manager, their passkeys. There is no login
  step to engineer. That is the whole reason this beats standing up your own browser.

**The user pastes the prompt.** That is the approval gate. Never spawn Desktop yourself.

**The decision to hand off is already made** — by the user, or by you after finding no
API or CLI that reaches the target. Don't re-open it. Start at step 1.

## 1. Create the shared directory

```bash
HANDOFF="${TMPDIR:-/tmp}/claude-desktop-handoff/$(date +%Y%m%d-%H%M%S)-<slug>"
mkdir -p "$HANDOFF"
```

Short kebab-case `<slug>`. Keep the absolute path — the prompt and every later step need
it. Use `$TMPDIR`, not a repo path: one writer per repo, and this brief will name
internal URLs.

## 2. Decide what must never reach Desktop's context

Before writing anything, sort the task's outputs:

| Output | Route |
|---|---|
| Public identifiers (an app id, a URL, a record id) | Desktop reports them in `RESULT.md`. Fine. |
| A secret that does not exist yet | **Stop Desktop before it exists.** Have it do the structural work and leave the page open; you or the user generate and store the secret. Cleanest option — prefer it. |
| A secret already on screen | **The user clicks the copy button**, not Desktop — then you run `pbpaste \| <store>` and verify. See the warning below. |
| A secret Desktop must handle itself | Only if it has a shell: have it pipe the value into the store in one command, never into a file or a reply. |

**Do not ask a browser agent to click a copy button "without looking".** It cannot. To
find the control it reads the page, and the accessibility snapshot carries the value
sitting next to it — so the secret lands in its context in the same breath. This skill
shipped with that mistake and its first real run proved it: the agent generated a GitHub
client secret, read the page to check state, and captured the value verbatim. It then
correctly refused to copy it onward, and the credential had to be rotated.

The shared clipboard is still the right channel — but a **human** has to load it. So the
rule is: **Desktop does the structural work and stops at the threshold; a person crosses
it.** Anything on screen may land in a GUI session's context and logs, and a mid-task
re-auth wall makes it worse, because the pending action can complete while the agent is
away and it comes back to a page it didn't expect.

## 3. Write TASK.md

Write for a session with no memory of this conversation. Include the *why*, so it can
tell when a page doesn't match.

```markdown
# Task: <one line>

## Context
<2-4 sentences: what this is part of, why it needs your browser.>

## Do this
1. <step, exact URL>
2. <step, exact field values — spell out everything you already know>

## Guardrails
- Do not edit files in any git repository. Another session owns those.
- Do not change any other setting, account, or resource.
- Do not read, copy, or repeat any secret, token, or password.
- If a page does not match this description, stop and report what you saw.
- If something already exists, stop and report it — do not create a duplicate.

## Talking to me
We share a directory. <HANDOFF>

- **Blocked or unsure?** Write your question to `ASK.md` and wait — poll for
  `REPLY.md` every 15s for up to 5 minutes. I am watching and will answer. Delete
  both when you have your answer, then carry on.
- **Done or stopped?** Write `RESULT.md`. That ends the handoff.

`RESULT.md` must cover: what you did and the end state; anything that did not match
these instructions; any non-secret identifier I need; and if you could not finish,
where you stopped and what blocked you.
```

The `ASK.md` loop is what makes this worth its own skill. Without it a wrong assumption
costs a whole round trip through the user.

## 4. Print the prompt

Claude Desktop takes a pasted prompt, so give one block, ready to copy:

```
Read <HANDOFF>/TASK.md and do what it says, using my logged-in Chrome.
Follow its "Talking to me" section — write ASK.md if you get stuck, RESULT.md when done.
If you cannot read or write files in that directory, say so in this chat instead and
I will relay.
```

Then say in one line what you'll do when it lands, so the user can redirect you.

Two requirements to note only if they might not hold: the **Claude in Chrome extension
must be connected** (Desktop cannot drive a browser without it — computer-use grants
browsers a read-only tier that cannot fill forms), and Desktop needs **filesystem access
to `$TMPDIR`** for the file channel. If it has neither, this is the wrong skill — fall
back to `desktop-handoff` and have the user relay.

## 5. Watch both channels

One background loop, watching for either file. Do not poll in the foreground and do not
ask "is it done yet?":

```bash
end=$((SECONDS + 3600))
until [ -f "$HANDOFF/RESULT.md" ] || [ -f "$HANDOFF/ASK.md" ] || [ $SECONDS -ge $end ]; do sleep 5; done
[ -f "$HANDOFF/ASK.md" ] && echo "ASK" || { [ -f "$HANDOFF/RESULT.md" ] && echo "RESULT" || echo "timeout"; }
```

On `ASK`: answer into `REPLY.md`, delete `ASK.md`, re-arm the loop. Answer from what you
know — going back to the user defeats the point. Escalate only if the question reveals
the brief was wrong about something you cannot decide.

On timeout: tell the user, don't silently re-arm.

**Expect re-auth walls, and name them as stop conditions in the brief.** Vendor consoles
gate secret generation, deletion and ownership changes behind a fresh identity check
(GitHub calls it sudo mode; AWS, Google and Stripe all have equivalents). No `REPLY.md`
can unblock that — only the user can. A brief that anticipates it gets a clean "stopped
here, a human must authenticate" instead of a session improvising around a password
prompt. The resume is cheap: those grants persist for hours, so once the user clears it,
re-running the *same* brief usually goes straight through. Archive the first
`RESULT.md` rather than deleting it, so the second run starts on a clear channel.

**Re-brief before re-running, though.** Clearing the wall can *submit the pending
action*, so the second run may open on a page where the work is already done. Say so
explicitly — "the secret may already exist; verify before clicking anything" — or the
session will inspect the page to orient itself, which is exactly when it reads what it
was told not to.

While waiting, do any part of the work that doesn't depend on the result.

## 6. Verify, then continue

**Never trust the report.** A session saying it worked is not proof. Check the resource
yourself through an API that doesn't need a GUI, and prefer a check that *distinguishes*
success from failure rather than merely not erroring — an endpoint that answers
differently for a real id and a bogus one, a readback, a status query. If a secret came
through the clipboard, verify it authenticates before you rely on it.

Then continue the original work autonomously — that is what this skill buys. Tell the
user they can close the Desktop conversation, and `rm -rf "$HANDOFF"`.

## Guardrails

- **The user starts Desktop.** Never route around a permission you were denied — a
  capability gap is a fair reason to hand off, a denied permission is not.
- **Don't send a secret through either transcript** when step 2 offers a route that
  avoids it.
- **One writer per repo.** Desktop does GUI work; this session owns the files.
- **Clean up**, including any `SECRET` file, with `rm -P`.
