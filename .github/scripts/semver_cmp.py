#!/usr/bin/env python3
"""Compare two SemVer 2.0.0 versions. Exit 0 and print -1/0/1 for a<b, a==b, a>b.

`sort -V` cannot do this job: it orders `2.0.0-rc.1` ABOVE `2.0.0`, so a
release-candidate promoted to its final version reads as a downgrade. SemVer
§11 says the opposite — a pre-release always has lower precedence than the
release it precedes — which is the whole point of the `fsh-rc` channel.
"""
import re
import sys

NUM = r"(?:0|[1-9]\d*)"              # §2/§9: no leading zeroes
SEMVER = re.compile(
    rf"^({NUM})\.({NUM})\.({NUM})"   # major.minor.patch
    r"(?:-((?:[0-9A-Za-z-]+)(?:\.[0-9A-Za-z-]+)*))?"   # -prerelease
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"      # +build (ignored, §10)
)
NUMERIC_ID = re.compile(rf"^{NUM}$")


def key(version):
    m = SEMVER.match(version)
    if not m:
        sys.exit(f"not a semver version: {version!r}")
    core = tuple(int(g) for g in m.group(1, 2, 3))
    pre = m.group(4)
    if pre is None:
        # §11.3: a release outranks any pre-release of the same core.
        return core, (1,)
    ids = []
    for part in pre.split("."):
        if NUMERIC_ID.match(part):
            # §11.4.1/11.4.3: numeric identifiers compare numerically and
            # always rank below alphanumeric ones — hence the leading 0.
            ids.append((0, int(part), ""))
        elif part.isdigit():
            sys.exit(f"pre-release identifier has a leading zero: {version!r}")
        else:
            # §11.4.2: alphanumeric identifiers compare in ASCII sort order.
            ids.append((1, 0, part))
    return core, (0, tuple(ids))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: semver_cmp.py <a> <b>")
    a, b = key(sys.argv[1]), key(sys.argv[2])
    print(-1 if a < b else (0 if a == b else 1))
