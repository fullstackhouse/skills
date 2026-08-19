#!/usr/bin/env python3
"""Extract the human turns from Claude Code transcripts in a time window.

Transcripts are JSONL under ~/.claude/projects/<encoded-abs-path>/, one file per
session, plus <session-id>/subagents/agent-*.jsonl for subagent runs. A busy day
across parallel workspaces is tens of MB; the human turns alone are a few hundred
lines, and that is where corrections live.

  ./harvest-turns.py --match cerber --since today
  ./harvest-turns.py --match fsh-monorepo --since 2026-08-12 --until 2026-08-16

Prints markdown to stdout, oldest first, one block per turn:

  ### [14:31] <project-dir> (<session-id prefix>)
  <what the human typed>
"""

import argparse
import datetime as dt
import glob
import json
import os
import re
import sys

# Turns that are plumbing rather than something a human typed at the prompt.
NOISE_PREFIXES = ("<system-reminder", "<system_instruction", "<task-notification",
                  "<local-command", "<command-name", "<command-message",
                  "Caveat: The messages below", "[Image:", "[Request interrupted")
# A skill or slash-command body is pasted in as a user turn; keep the invocation
# line the harness emits, drop the multi-KB payload that follows it.
SKILL_PREAMBLE = re.compile(r"^Base directory for this skill:", re.M)


def parse_when(s, end_of_day=False):
    if s is None:
        return None
    s = s.strip().lower()
    today = dt.date.today()
    if s == "today":
        d = today
    elif s == "yesterday":
        d = today - dt.timedelta(days=1)
    elif re.fullmatch(r"\d+d", s):
        d = today - dt.timedelta(days=int(s[:-1]))
    else:
        try:
            d = dt.date.fromisoformat(s)
        except ValueError:
            sys.exit(f"harvest-turns: cannot parse date {s!r} "
                     "(use today | yesterday | 7d | YYYY-MM-DD)")
    return f"{d.isoformat()}T{'23:59:59' if end_of_day else '00:00:00'}"


def text_of(message):
    content = message.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(b.get("text", "") for b in content
                         if isinstance(b, dict) and b.get("type") == "text")
    return ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--match", default="",
                    help="substring of the encoded project dir (usually the repo name); "
                         "empty matches every project")
    ap.add_argument("--since", default="today", help="today | yesterday | 7d | YYYY-MM-DD")
    ap.add_argument("--until", default=None, help="YYYY-MM-DD (inclusive)")
    ap.add_argument("--max-chars", type=int, default=1500,
                    help="truncate each turn (0 = no limit)")
    ap.add_argument("--include-subagents", action="store_true",
                    help="also read <session>/subagents/*.jsonl (rarely has human turns)")
    ap.add_argument("--root", default=os.path.expanduser("~/.claude/projects"))
    args = ap.parse_args()

    since, until = parse_when(args.since), parse_when(args.until, end_of_day=True)

    projects = sorted(d for d in glob.glob(os.path.join(args.root, "*"))
                      if os.path.isdir(d) and args.match in os.path.basename(d))
    if not projects:
        sys.exit(f"harvest-turns: no project dir under {args.root} matching {args.match!r}. "
                 "Dirs are the absolute path with / and . replaced by -; "
                 "list them with: ls ~/.claude/projects")

    turns = []
    for project in projects:
        label = os.path.basename(project).replace("-Users-", "").replace("-home-", "")
        pattern = "**/*.jsonl" if args.include_subagents else "*.jsonl"
        for path in glob.glob(os.path.join(project, pattern), recursive=True):
            session = os.path.basename(path).split(".")[0][:8]
            try:
                fh = open(path, errors="replace")
            except OSError:
                continue
            with fh:
                for line in fh:
                    try:
                        entry = json.loads(line)
                    except ValueError:
                        continue
                    if entry.get("type") != "user":
                        continue
                    ts = entry.get("timestamp", "")
                    if not ts or ts < since or (until and ts > until):
                        continue
                    body = text_of(entry.get("message", {})).strip()
                    if not body or body.startswith(NOISE_PREFIXES):
                        continue
                    # Tool results arrive as user-role turns with no text block;
                    # anything left carrying a tool id is plumbing too.
                    if "tool_use_id" in body:
                        continue
                    body = SKILL_PREAMBLE.split(body)[0].strip()
                    if not body:
                        continue
                    turns.append((ts, label, session, body))

    turns.sort()
    seen, kept = set(), 0
    for ts, label, session, body in turns:
        # The same turn is replayed into resumed/compacted sessions; dedupe on
        # (project, opening) so one instruction is counted once per workspace.
        key = (label, body[:120])
        if key in seen:
            continue
        seen.add(key)
        kept += 1
        if args.max_chars and len(body) > args.max_chars:
            body = body[:args.max_chars] + f"\n… [+{len(body) - args.max_chars} chars]"
        print(f"\n### [{ts[11:16]}] {label} ({session})\n{body}")

    print(f"\n---\n{kept} human turns across {len(projects)} project dir(s), "
          f"{args.since} → {args.until or 'now'}.", file=sys.stderr)


if __name__ == "__main__":
    main()
