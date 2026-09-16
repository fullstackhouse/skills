#!/usr/bin/env python3
"""Turn a .vtt or .srt subtitle file into timestamped plain text.

Two jobs beyond stripping markup:

1. **De-duplicate rolling captions.** YouTube auto-subs repeat each line as it
   scrolls up the screen, so a naive strip yields every sentence 2-3x.
2. **Merge cues into paragraphs**, each prefixed `[HH:MM:SS]`, so a summary can
   cite a timestamp without anyone reading the cue file.

Usage: subs_to_text.py [--window SECONDS] INPUT.(vtt|srt) > transcript.txt
"""

from __future__ import annotations

import argparse
import html
import re
import sys
from pathlib import Path

TIMING = re.compile(
    r"(\d{1,2}:\d{2}:\d{2}[.,]\d{3})\s*-->\s*(\d{1,2}:\d{2}:\d{2}[.,]\d{3})"
)
TAG = re.compile(r"<[^>]+>")           # <c>, <00:00:01.234>, <i> ...
CUE_SETTING = re.compile(r"\b(align|position|size|line|region):\S+")
SPEAKER = re.compile(r"^-?\s*\[[^\]]+\]\s*")  # [Music], [Applause]


def to_seconds(stamp: str) -> float:
    h, m, rest = stamp.split(":")
    s, ms = re.split(r"[.,]", rest)
    return int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000


def hhmmss(total: float) -> str:
    total = int(total)
    return f"{total // 3600:02d}:{total % 3600 // 60:02d}:{total % 60:02d}"


def parse_cues(text: str) -> list[tuple[float, str]]:
    """[(start_seconds, text)] in file order, markup stripped, blanks dropped."""
    cues: list[tuple[float, str]] = []
    start: float | None = None
    buf: list[str] = []

    def flush() -> None:
        if start is None:
            return
        line = " ".join(buf).strip()
        line = re.sub(r"\s+", " ", line)
        if line:
            cues.append((start, line))

    for raw in text.splitlines():
        line = raw.rstrip()
        m = TIMING.search(line)
        if m:
            flush()
            start, buf = to_seconds(m.group(1)), []
            continue
        if start is None:
            continue                      # header / WEBVTT / NOTE block
        if not line.strip():
            flush()
            start, buf = None, []
            continue
        if line.strip().isdigit():
            continue                      # srt sequence number
        cleaned = CUE_SETTING.sub("", TAG.sub("", html.unescape(line)))
        cleaned = SPEAKER.sub("", cleaned).strip()
        if cleaned:
            buf.append(cleaned)
    flush()
    return cues


def is_rolling(cues: list[tuple[float, str]]) -> bool:
    """True for scrolling captions, where each cue re-emits the previous one.

    Worth detecting rather than always assuming: un-overlapping is lossy on a
    file that doesn't need it — a cue legitimately starting with the words the
    last one ended with gets them eaten.
    """
    pairs = list(zip(cues, cues[1:]))[:200]
    if len(pairs) < 10:
        return False
    repeats = sum(1 for (_, a), (_, b) in pairs if a in b or b in a)
    return repeats > len(pairs) * 0.3


def dedupe(cues: list[tuple[float, str]], rolling: bool) -> list[tuple[float, str]]:
    out: list[tuple[float, str]] = []
    tail = ""
    for start, text in cues:
        if out and text == out[-1][1]:
            continue                      # same cue twice — never information
        if rolling:
            if tail and text in tail:
                continue
            if tail:
                # longest suffix of `tail` that prefixes `text` is the repeat
                overlap = min(len(tail), len(text))
                while overlap > 0 and tail[-overlap:] != text[:overlap]:
                    overlap -= 1
                text = text[overlap:].strip()
                if not text:
                    continue
            tail = (tail + " " + text)[-400:].strip()
        out.append((start, text))
    return out


def paragraphs(cues: list[tuple[float, str]], window: float) -> list[str]:
    blocks: list[str] = []
    anchor: float | None = None
    buf: list[str] = []
    for start, text in cues:
        if anchor is None:
            anchor = start
        buf.append(text)
        if start - anchor >= window:
            blocks.append(f"[{hhmmss(anchor)}] " + " ".join(buf))
            anchor, buf = None, []
    if buf and anchor is not None:
        blocks.append(f"[{hhmmss(anchor)}] " + " ".join(buf))
    return blocks


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("input", type=Path)
    ap.add_argument(
        "--window",
        type=float,
        default=45.0,
        help="seconds of speech per timestamped paragraph (default: 45)",
    )
    ap.add_argument(
        "--rolling",
        choices=("auto", "on", "off"),
        default="auto",
        help="un-overlap scrolling captions (default: auto-detect)",
    )
    args = ap.parse_args()

    raw = parse_cues(args.input.read_text(encoding="utf-8", errors="replace"))
    if not raw:
        print(f"no cues parsed from {args.input}", file=sys.stderr)
        return 1
    rolling = is_rolling(raw) if args.rolling == "auto" else args.rolling == "on"
    cues = dedupe(raw, rolling)
    print("\n\n".join(paragraphs(cues, args.window)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
