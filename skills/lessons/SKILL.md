---
name: lessons
description: Mine recent Claude Code transcripts for the corrections that repeated, and turn the ones that will recur into durable rules — project CLAUDE.md/AGENTS.md entries, memory files, or a skill fix. Use at the end of a working day or a long session, after a stretch of parallel agent work (several Conductor workspaces on one repo), when you notice you have given the same correction more than once, or when asked "what did we learn today", "capture the lessons from this session", "improve the docs from what just happened". Read-only until the user approves each proposed rule.
---

# lessons

You are running the **lessons** skill. The premise: a day of agent work produces
tens of MB of reasoning and, usually, nothing durable. The same correction gets
given in workspace after workspace because each session started fresh and
re-derived the same wrong default. Your job is to find those repeats and write
them down once, where the next session will actually read them.

**Hard rule: propose, don't apply.** Every rule is shown as a diff and applied
only on the user's approval. A rule they didn't agree to is worse than no rule —
it will steer sessions for months.

## 1. Scope — decide which transcripts

Claude Code writes one JSONL per session to
`~/.claude/projects/<encoded-abs-path>/`, where the directory name is the
absolute path with `/` and `.` replaced by `-`. Two consequences worth knowing
before you glob:

- **One repo spreads across many directories.** Conductor gives each workspace
  its own worktree, so a single repo's day lives under
  `-Users-<you>-conductor-workspaces-<repo>-<workspace>` (one per workspace) plus
  `-Users-<you>-src-<repo>` for the main checkout. Match on the repo name, never
  on one path.
- **Headless runs create directories too.** A tool that shells out to `claude -p`
  (cerber, CI jobs, other skills) writes transcripts whose "human" turns are
  machine-generated prompts. Recognize them by content — a 2 KB instruction
  block with a JSON schema in it — and drop them.

Default window: today. Confirm the window and the matched directories with the
user in one line before harvesting a wider range.

## 2. Harvest — human turns only

Run the bundled script:

```bash
skills/lessons/scripts/harvest-turns.py --match <repo> --since today
```

`--since` takes `today | yesterday | 7d | YYYY-MM-DD`; `--until` closes the range.

This is the step that makes the skill affordable: **corrections live in what the
human typed**, and the human turns are ~0.2% of the bytes. A 20 MB day across
seven workspaces reduces to about 40 turns — one screen, read in full. Do not
read raw transcripts to start; go back for the surrounding assistant turns only
for the handful of candidates in step 4, and only when the turn alone doesn't
tell you what was being corrected.

## 3. Cluster — find what repeated

Group the turns by the underlying instruction, not by wording. You are looking
for one thing: **an instruction the user had to give more than once.**

Rank candidates by the number of *distinct sessions* a correction appears in.
Cross-session repetition is the strongest signal in the data — each session
re-derived the same mistake from a clean context, which is exactly what a
written rule prevents. Five workspaces each hearing "that should be the default"
is one lesson with a score of five; five nags inside one thread is one lesson
with a score of one (see Hard rules).

Also flag, at lower weight:

- a correction given **once but with force** ("forget about X", "I don't like
  the idea of Y") — a stated preference with a reason behind it,
- a **decision whose rationale isn't in the code** — the code records what was
  chosen, never what was rejected or why,
- a **rework loop**: work built, then thrown away after feedback that could have
  been stated up front.

## 4. Filter — what deserves to be durable

Most of what you clustered should not be written down. Drop:

- **Anything the repo already records.** Code structure, what a function does,
  what a commit fixed, what's in the git history. A rule earns its place by
  changing a *future decision*, not by restating the codebase.
- **Anything already written.** Read the target files first —
  `CLAUDE.md`, `AGENTS.md`, the memory index — and check whether the lesson is
  already there in other words. Skipping this is what makes a daily habit
  re-propose the same three rules forever.
- **One-off nits** and anything true only of this task.
- **Corrections that were about your mistake, not a standing preference.** "No,
  that file is at src/, not lib/" is a fact you looked up wrong once.

Keep what a competent agent starting tomorrow with no memory of today would get
wrong again.

## 5. Route — one home per lesson

| Lesson | Home |
|---|---|
| Rule specific to this repo (a default, an invariant, a thing never to do) | project `CLAUDE.md` / `AGENTS.md`, in the section it belongs to |
| How the user wants to be worked with, across repos | a memory file, `type: feedback`, with **Why** and **How to apply** |
| Who the user is, standing constraints on the project | a memory file, `type: user` / `project` |
| A decision made but not yet built | a brief in the repo's specs/briefs directory, if it has one |
| A process failure that a skill should have prevented | an edit to that skill in this repo |

Prefer **editing an existing rule** over adding a near-duplicate next to it —
two rules saying almost the same thing is how a CLAUDE.md rots into noise. If a
lesson has no clear single home, it's probably not a lesson yet; say so.

Write rules the way the target file already reads: same voice, same density.
State the rule, then the reason it exists — a rule whose "why" is missing gets
argued with or quietly dropped by the next session.

## 6. Propose, then apply

Present each surviving lesson as: the proposed text, its home, and the evidence
— how many distinct sessions asked for it, quoting the shortest turn that shows
it. Order by that count.

Apply only what the user approves. Then report what you wrote and what you
deliberately skipped, so the filter itself stays reviewable.

## Hard rules

1. **Nothing is written without approval.** Not even an "obviously correct" rule.
2. **Transcripts never leave the machine.** They contain client code, command
   output with credentials, and other clients' names. Quote from them into the
   local files being edited and into your message to the user — never into a
   commit message, PR body, issue, or any external service.
3. **Distinct sessions, not repeated messages.** Weight a correction by how many
   independent contexts hit it. One user repeating themselves three times in one
   thread is one occurrence of one lesson.
4. **A rule that wouldn't change a future decision isn't a rule.** If you can't
   name the decision it would have changed today, drop it.
5. **Read the destination before proposing.** Every proposal is checked against
   what the target file already says.
6. **Don't mine other people's work.** Only transcripts on this machine, for the
   repos the user named.
