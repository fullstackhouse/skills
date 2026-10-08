---
name: patch
description: Carry a dependency's unreleased change in this repo as a local patch, and record it in the repo's patch index — what it changes, where it came from, and the condition under which it may be deleted. Use when asked to "patch in <PR link>", "apply that fix locally", "we can't wait for the release", or when the index itself needs reading: `--audit` says, per patch, whether a version bump may now drop it. Args: a PR/commit/diff link, or `--audit`.
---

# patch

A local patch on a dependency is debt. It is re-applied on every install, and at the next version
bump it will either conflict or — worse — silently mask the upstream fix that replaced it. So the
patch and the record of it are one deliverable, never two. The index is where "drop this when X"
lives, not a tracker: the index is what someone actually reads at the bump.

## Apply

1. **Resolve the change.** Pull the diff from the link (`gh pr diff <n> --repo <owner>/<repo>`, or
   the forge's `.diff`/`.patch` URL). Record its state — open, merged, closed — and which release,
   if any, already carries it.
2. **Check it isn't already installed.** Compare against the version the lockfile resolves, not the
   range in the manifest. Prerelease channels are the trap: a build is a build of one commit, so
   anything merged after that commit is not in it, and anything merged before it may already be.
   Already installed → stop and say so. A patch over a shipped fix hides it.
3. **Apply it the way this repo already patches dependencies** — same mechanism, same layout as the
   patches it carries. None yet → use what the project's package manager or runtime provides, and
   say which you picked. Two things to get right:
   - **Patch every artifact the app loads.** When a dependency ships sources *and* build output,
     the change belongs in both — a source-only patch applies cleanly and changes nothing.
   - **Take only what this repo calls.** Leave the change's tests, routes and exports that nothing
     here reaches; every extra hunk is one more thing to re-port at the bump. Note what you left out.
4. **Prove it from the other side.** A test that fails when the patch is removed, then the repo's
   own gate (`AGENTS.md` / `CLAUDE.md`). A green suite on the patched tree alone proves nothing.
5. **Confirm the patch files are tracked** — `git check-ignore -v` each one. Patch directories are a
   common casualty of a global gitignore, and a patch nobody commits works only on your machine.
6. **Record the row**, then commit. Hand to `deliver` if the user wants it shipped.

## The index

One file beside the patches — `templates/patches-index.md` when the repo has none. Each patch is one
table row plus one section of prose. The row:

- **label** — the next unused one. **Never reuse, never renumber.** A reader at the bump follows a
  label to its row; a moved label sends them to the wrong patch. Gaps are correct.
- **change** — what behaviour changes, not which lines move. Written for whoever hits the bug.
- **target** — the packages and files patched.
- **source** — the upstream PR, issue or commit, with its state and date. Nothing upstream yet is a
  fine answer; say so. The row exists either way.
- **drop when** — the condition, in full.

**"Drop when" is the field worth arguing about.** "When #1234 merges" is right only where the patch
*is* that PR's diff. The rows a version number cannot retire are the ones that go wrong: a
deliberate divergence from what upstream merged (upstream carries a fix, just not the behaviour we
want), a closed PR waiting on a successor, a patch whose removal needs a config flip per environment
first. Write the real condition — and when local code must outlive the patch, say which.

The section carries what a table cell can't: why the unpatched behaviour is a problem, what the patch
does instead, what you deliberately left out, and how it collides with the other patches on the same
files.

## `--audit`

Run before a version bump. For each row, top to bottom: resolve the source's current state and
whether the version being bumped *to* actually contains it — merged is not shipped. Report per row
**drop**, **re-port**, or **read the drop-when cell** (its condition isn't met, however the PR
looks). Change nothing. This is the bump's input, not the bump.
