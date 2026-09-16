#!/usr/bin/env python3
"""Read a yt-dlp info JSON and answer the two questions transcribe.sh has.

  probe_meta.py fields meta.json          -> title / uploader / duration, one per line
  probe_meta.py track  meta.json [lang] [--auto]
                                          -> "<sub-lang> manual|auto", or nothing

Track selection prefers human-written subtitles. Machine captions need --auto,
and even then only in the video's own language: YouTube lists auto-*translated*
tracks under plain language codes, identically to the real one, and a
translation of a transcription is two lossy steps stacked.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


def load(path: str) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def fields(meta: dict) -> None:
    for value in (
        meta.get("title"),
        meta.get("uploader") or meta.get("channel"),
        meta.get("duration"),
    ):
        text = str(value if value not in (None, "") else "-")
        print(text.replace("\n", " ").strip() or "-")


def track(meta: dict, want: str | None, allow_auto: bool) -> None:
    manual = {k for k in (meta.get("subtitles") or {}) if k != "live_chat"}
    auto = set(meta.get("automatic_captions") or {})
    wanted = [lang for lang in (want, meta.get("language")) if lang]

    for lang in wanted + sorted(manual):
        if lang in manual:
            print(lang, "manual")
            return
    if allow_auto:
        # "xx-orig" is the untranslated machine transcript where YouTube offers it.
        for lang in [f"{l}-orig" for l in wanted] + wanted:
            if lang in auto:
                print(lang, "auto")
                return


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    mode, meta = argv[0], load(argv[1])
    if mode == "fields":
        fields(meta)
    elif mode == "track":
        rest = [a for a in argv[2:] if a != "--auto"]
        track(meta, rest[0] if rest and rest[0] else None, "--auto" in argv[2:])
    else:
        print(f"unknown mode: {mode}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
