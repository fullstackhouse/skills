---
name: desktop-handoff
description: Offload one step that needs a desktop GUI to a separate agent session the user starts by hand. Use when this session cannot reach the GUI — non-interactive (Conductor, `-p`, cloud), no computer use, headless browser only — and the step needs a real logged-in browser or a native app: registering an OAuth app, a vendor console with no API, a native installer, a desktop-only settings pane. Writes a task file, prints one command for the user to paste in their own terminal, and takes the result back over whichever channel fits. Runtime-agnostic: the hand can be any agent that reads and writes files, on any OS.
---

# desktop-handoff

You are running the **desktop-handoff** skill. Goal: get one GUI-only step done by a session that *has* a desktop, without this session needing one.

The brief always goes out as a file — `TASK.md` in a temp dir — because it is long and quoting it into a shell command is a hazard.

**How the result comes back is a choice you make per handoff** (step 2). The floor is another file, `RESULT.md`: no IPC, no tmux, no MCP, so any agent that reads and writes files can be the hand, on any OS. Anything cleverer has to earn it, and sometimes nothing at all is right.

**The user starts the other session by hand.** That is the approval gate: nothing happens until a person pastes a command. Never spawn it yourself.

**If Claude Desktop is on this machine and the step is browser work, prefer `claude-desktop-handoff`.** It spends two things this skill cannot assume: a shared filesystem, which makes `ASK.md`/`REPLY.md` a real back-channel so a wrong assumption is resolved without a round trip through the user, and Desktop driving the user's already-logged-in Chrome. Come back here when the hand might be a different machine, a different runtime, or not Claude at all.

**The decision to hand off is already made.** Whoever invoked this skill — the user, or you, after finding no API, CLI, or browser tool that reaches the target — settled it. Don't re-open it, don't propose alternatives, don't ask whether it's really necessary. Start at step 1.

## 1. Create the handoff directory

```bash
HANDOFF="${TMPDIR:-/tmp}/desktop-handoff/$(date +%Y%m%d-%H%M%S)-<slug>"
mkdir -p "$HANDOFF"
```

Use a short kebab-case `<slug>` naming the task. Keep the absolute path — every later step needs it.

## 2. Choose the return channel

Two different things may need to come back: a **completion signal** (it's done) and the **content** (what happened). They don't have to arrive the same way, and sometimes neither is needed. Decide now, because it changes what `TASK.md` asks for.

Pick from what the result actually *is*:

| The result is… | Return via | Why |
|---|---|---|
| Something you can check yourself — a resource now exists, a config changed, a file appeared | **Nothing.** The user says "done"; you verify it directly | You'd verify anyway (step 6), so a written report adds a step and another place for a secret to land |
| Short, and the user is at the keyboard | **The user pastes it back** into this conversation | No files, no waiting, no cleanup |
| Long, structured, or the user will walk away mid-task | **`RESULT.md`** + the background wait in step 5 | Survives them stepping away; the default when you're unsure |
| Genuinely needed by *both* sides, and both sessions already run a runtime with working native messaging | **That channel** | Instant, no polling — but only if it already works. Don't build one, and don't assume the hand is the same runtime as you |

**State your choice in one line when you print the command** (step 4) so the user can override it — they know how they intend to continue and you don't.

## 3. Write TASK.md

Write the brief so a *fresh* session with no memory of this conversation can execute it. Include the why, not just the steps — it has to recognise when a page doesn't match what you described.

```markdown
# Task: <one line>

## Context
<2-4 sentences: what this is part of, why it needs a desktop.>

## Do this
1. <step, with the exact URL>
2. <step, with exact field values — spell out every value you already know>

## Guardrails
- Do not edit files in any repository. Another session owns those.
- Do not put secrets (tokens, client secrets, passwords) in your report.
  <If a secret is produced, name where it must go instead — a password
  manager, `gcloud secrets versions add`, an env file — and have the user
  move it by hand.>
- If the page does not match this description, stop and report what you saw.

## When done
<The reporting instruction for the channel chosen in step 2:
 - RESULT.md    → "Write your outcome to <HANDOFF>/RESULT.md."
 - user relays  → "Print your outcome; the user will relay it."
 - runtime channel → name it, and how to send on it, in one line.
 - nothing      → "Just say you're done — no report needed.">

Cover:
- What you did, and what the end state is.
- Anything that did not match these instructions.
- Any non-secret identifier the requesting session needs (an id, a URL, a name).
- If you could not finish: where you stopped and what blocked you.
```

## 4. Tell the user to start the session

The prompt is the same whatever agent runs it; only the launch command differs. Print one paste-ready line, substituting the CLI the user actually runs — this session's own runtime is the best default, and asking is better than guessing wrong:

```bash
<agent-cli> "Read <HANDOFF>/TASK.md and do what it says. <reporting instruction from step 2>"
```

Nearly every agent CLI takes a starting prompt as its first positional argument, so this shape holds. Two requirements on that session, whatever it is:

- **It has a desktop** — a GUI-capable machine, not a container, a remote box, or a cloud runner.
- **It is interactive** — not a print/batch/non-interactive mode. GUI capabilities are commonly gated off those.

Say in one line how you expect the result back, so the user can say otherwise.

Then add only the setup notes that apply:

- **Native GUI or screen control usually needs an explicit opt-in plus OS permission grants**, and is often the most restricted thing the runtime offers — check that runtime's own docs for what it's limited to before promising it works. For Claude Code specifically: `/mcp` → enable `computer-use`, then grant macOS Accessibility + Screen Recording when prompted; it is **macOS only**, needs a Pro or Max plan, and the enablement **persists per project path**, so a git worktree or a different directory needs enabling again even if the user has done it before.
- **Browser-only work** typically needs none of that — a GUI-capable session with a browser tool, or the user's own logged-in browser, is enough.
- The user must **stay at that terminal**: approval prompts appear there and only they can answer them.

## 5. Wait — only if you chose `RESULT.md`

If the user is relaying, or there's nothing to return, skip this: end your turn and let them come back to you. Don't arm a watcher for a file nobody will write. Skip it for a runtime channel too — that channel notifies you itself, so a file wait beside it only adds an hour-long timer nothing will ever trip.

Otherwise arm one background wait — do not poll, and do not ask "is it done yet?":

```bash
end=$(( $(date +%s) + 3600 ))
until [ -f "$HANDOFF/RESULT.md" ] || [ "$(date +%s)" -ge "$end" ]; do sleep 5; done
[ -f "$HANDOFF/RESULT.md" ] && echo "RESULT.md landed" || echo "timed out after 1h"
```

`date +%s`, not `$SECONDS`: that variable is a bash/ksh/zsh builtin, and under a POSIX
`sh` such as dash it expands to nothing, so the guard becomes `[ -ge 3600 ]` — a *syntax
error*, not a false condition. The loop then runs forever on a handoff nobody completed,
which is the one failure a timeout exists to prevent.

Run it in the background so you get exactly one notification when it exits. While waiting, do any part of the work that doesn't depend on the result.

If it times out, don't re-arm silently — tell the user, and confirm they still intend to run it.

## 6. Take in the result and continue

However it arrived — file, relayed by the user, over a runtime channel, or just "done":

- **Finished** → continue the original work. Tell the user they can close that session.
- **Blocked, or the page didn't match** → say so plainly and decide with the user whether to re-brief. To retry, append to `TASK.md` and have them tell the still-open session to re-read it, or start a fresh one.
- **Never trust it blind.** If the result is load-bearing, verify independently — check the resource exists via an API, re-read the config. A session reporting success is not proof of success. This is why "no return channel" is a real option: the verification is the part that counts.

## Hard rules

- **The user starts the session.** Never spawn one to dodge a prompt you'd otherwise have to ask for.
- **Never use the other session to do something your own permissions blocked.** A capability gap (this session has no GUI) is a fair reason to hand off. A denied permission is not — take that back to the user.
- **Secrets don't travel through transcripts.** A GUI session screenshots or reads the page to work, so any secret on screen lands in its context and log. Route secrets from the source straight to their destination (clipboard → secret manager) and keep them out of `TASK.md` and out of whatever comes back.
- **One writer per repo.** The handoff session does GUI work; this session owns the files. Concurrent writes across worktrees lose work.
- **Clean up.** When the work is accepted, `rm -rf "$HANDOFF"` — the brief may name internal URLs and account handles.
