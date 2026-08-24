#!/usr/bin/env python3
"""Audit a repository's agent instruction files (AGENTS.md / CLAUDE.md).

Coding agents concatenate agent docs from the repository root down to the
directory they are working in. Codex stops once the COMBINED size reaches
`project_doc_max_bytes` (default 32,768) and drops the rest silently; Claude
Code loads the root file into every turn of every session. Either way the
root-to-working-dir *chain* is the unit that matters, not the single file.

This script measures those chains, reports per-section sizes so an oversized
file can be triaged, and enforces limits in CI.

Usage:
  agent_docs_audit.py [--root DIR] [--json] [--check]
                      [--baseline PATH] [--update-baseline]
                      [--budget-bytes N] [--root-max-lines N] [--reserve-bytes N]

Exit codes: 0 = clean (or report-only), 1 = violations found with --check,
2 = usage/IO error.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

DOC_NAMES = ("AGENTS.md", "CLAUDE.md")

# Directories that never hold agent docs we care about, and that make a naive
# walk pathologically slow in a real monorepo.
SKIP_DIRS = {
    ".git", "node_modules", ".turbo", ".next", ".yarn", ".venv", "venv",
    "dist", "build", "out", "coverage", "vendor", "__pycache__", ".cache",
    ".pnpm-store", "target", ".gradle", ".idea", ".conductor", ".terraform",
}

# `@path` on its own line is Claude Code's import directive. Not a mention:
# it must start the line and carry no spaces in the path.
IMPORT_RE = re.compile(r"^@([^\s]+)\s*$", re.MULTILINE)

# A stub below this size that imports a sibling doc is an alias for it, not a
# second source of truth.
STUB_MAX_BYTES = 512

DEFAULT_BUDGET_BYTES = 32768   # Codex project_doc_max_bytes
DEFAULT_ROOT_MAX_LINES = 230   # om-create-agents-md: "Root MUST stay under 230 lines"
DEFAULT_RESERVE_BYTES = 1536   # leave the nested files some of the budget


# ---------------------------------------------------------------- discovery

def discover(root: str) -> list[str]:
    """Return repo-relative dirs containing at least one agent doc, root first."""
    found: list[str] = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP_DIRS)
        if any(name in filenames for name in DOC_NAMES):
            rel = os.path.relpath(dirpath, root)
            found.append("" if rel == "." else rel)
    return sorted(found, key=lambda p: (p.count(os.sep), p))


def split_sections(text: str) -> list[dict]:
    """Split markdown into top-level-ish sections, ignoring headings in fences.

    A `# Development` line inside a ```bash fence is a shell comment, not a
    heading. Counting it as one mis-attributes bytes and invents sections that
    do not exist -- tournee's root file has several.
    """
    sections: list[dict] = []
    current = {"heading": "(preamble)", "level": 0, "lines": 0, "bytes": 0}
    fence: str | None = None

    for line in text.splitlines(keepends=True):
        stripped = line.lstrip()
        if fence is None and (stripped.startswith("```") or stripped.startswith("~~~")):
            fence = stripped[:3]
        elif fence is not None and stripped.startswith(fence):
            fence = None
        elif fence is None and stripped.startswith("#"):
            hashes = len(stripped) - len(stripped.lstrip("#"))
            if 1 <= hashes <= 6 and stripped[hashes:hashes + 1] in (" ", "\t"):
                if current["bytes"]:
                    sections.append(current)
                current = {
                    "heading": stripped[hashes:].strip(),
                    "level": hashes,
                    "lines": 0,
                    "bytes": 0,
                }
        current["lines"] += 1
        current["bytes"] += len(line.encode("utf-8"))

    if current["bytes"]:
        sections.append(current)
    return sections


def read_doc(root: str, reldir: str, name: str) -> dict | None:
    path = os.path.join(root, reldir, name) if reldir else os.path.join(root, name)
    if not os.path.lexists(path):
        return None

    symlink_to = os.readlink(path) if os.path.islink(path) else None
    try:
        # Read through the symlink: what the agent loads is the target's bytes.
        with open(path, "rb") as fh:
            raw = fh.read()
    except (OSError, FileNotFoundError):
        return {
            "path": os.path.join(reldir, name) if reldir else name,
            "name": name, "symlink_to": symlink_to, "imports": [], "broken": True,
            "bytes": 0, "lines": 0, "sections": [],
        }

    text = raw.decode("utf-8", errors="replace")
    return {
        "path": os.path.join(reldir, name) if reldir else name,
        "name": name,
        "symlink_to": symlink_to,
        "imports": IMPORT_RE.findall(text),
        "broken": False,
        "bytes": len(raw),
        "lines": text.count("\n"),
        "sections": split_sections(text),
    }


def resolve_dir(root: str, reldir: str) -> dict:
    """Pick the canonical doc(s) an agent actually loads for one directory.

    Both filenames present is the norm, and usually one is a symlink to the
    other -- that is one file, counted once. Two *real* files is the case worth
    flagging: some agents read one, some the other, and they drift apart.
    """
    docs = [d for d in (read_doc(root, reldir, n) for n in DOC_NAMES) if d]
    if not docs:
        return {"dir": reldir, "docs": [], "canonical": [], "bytes": 0}

    real = [d for d in docs if not d["symlink_to"]]
    links = [d for d in docs if d["symlink_to"]]

    # A symlink whose target is the sibling doc collapses into that sibling.
    sibling_names = {d["name"] for d in real}
    independent_links = [
        d for d in links if os.path.basename(d["symlink_to"]) not in sibling_names
    ]

    # So does a small stub whose only job is `@AGENTS.md`.
    def is_alias_stub(doc):
        if doc["bytes"] > STUB_MAX_BYTES:
            return False
        targets = {os.path.basename(i) for i in doc["imports"]}
        return bool(targets & (sibling_names - {doc["name"]}))

    stubs = [d for d in real if is_alias_stub(d)]
    canonical = [d for d in real if d not in stubs] + independent_links

    return {
        "dir": reldir,
        "docs": docs,
        "canonical": canonical,
        "bytes": sum(d["bytes"] for d in canonical),
        "single_harness": len(docs) == 1,
        "duplicate_harness": len([d for d in real if d not in stubs]) > 1,
        "aliases": [d["path"] for d in stubs + links],
    }


def ancestors(reldir: str) -> list[str]:
    """Every dir from the repo root down to `reldir`, inclusive."""
    if reldir == "":
        return [""]
    parts = reldir.split(os.sep)
    return [""] + [os.sep.join(parts[: i + 1]) for i in range(len(parts))]


# ------------------------------------------------------------------ auditing

def audit(root: str, budget: int, root_max_lines: int, reserve: int,
          baseline: dict | None) -> dict:
    dirs = discover(root)
    resolved = {d: resolve_dir(root, d) for d in dirs}

    root_info = resolved.get("", {"canonical": [], "bytes": 0})
    root_bytes = root_info["bytes"]
    root_lines = sum(d["lines"] for d in root_info["canonical"])
    root_max_bytes = budget - reserve

    chains = []
    for reldir in dirs:
        members = [resolved[a] for a in ancestors(reldir) if a in resolved]
        total = sum(m["bytes"] for m in members)
        chains.append({
            "dir": reldir or "(root)",
            "bytes": total,
            "over_by": max(0, total - budget),
            "pct_of_budget": round(100 * total / budget, 1),
            "files": [d["path"] for m in members for d in m["canonical"]],
            "nested_bytes": total - root_bytes,
        })
    chains.sort(key=lambda c: -c["bytes"])

    findings = []

    def add(code, severity, message, **extra):
        findings.append({"code": code, "severity": severity, "message": message, **extra})

    if root_lines > root_max_lines:
        add("ROOT_OVER_LINES", "error",
            f"root agent doc is {root_lines} lines, limit {root_max_lines} "
            f"(+{root_lines - root_max_lines})",
            lines=root_lines, limit=root_max_lines)

    if root_bytes > root_max_bytes:
        add("ROOT_OVER_BYTES", "error",
            f"root agent doc is {root_bytes} B, limit {root_max_bytes} B "
            f"({budget} budget minus {reserve} reserved for nested files)",
            bytes=root_bytes, limit=root_max_bytes)

    for chain in chains:
        if chain["over_by"]:
            add("CHAIN_OVER_BUDGET", "error",
                f"chain for {chain['dir']} is {chain['bytes']} B, "
                f"{chain['over_by']} B past the {budget} B budget — that tail is "
                f"dropped silently",
                dir=chain["dir"], bytes=chain["bytes"], over_by=chain["over_by"])

    for reldir, info in sorted(resolved.items()):
        if info.get("duplicate_harness"):
            names = ", ".join(d["path"] for d in info["canonical"])
            add("DUPLICATE_HARNESS", "warn",
                f"{reldir or '(root)'} has two independent agent docs ({names}); "
                f"they will drift — symlink one to the other",
                dir=reldir)
        elif info.get("single_harness"):
            present = info["docs"][0]["name"]
            missing = [n for n in DOC_NAMES if n != present][0]
            add("SINGLE_HARNESS", "warn",
                f"{reldir or '(root)'} has {present} but no {missing}; agents "
                f"reading {missing} get nothing here",
                dir=reldir, present=present, missing=missing)
        for doc in info.get("docs", []):
            if doc["broken"]:
                add("BROKEN_SYMLINK", "error",
                    f"{doc['path']} is a broken symlink to {doc['symlink_to']}",
                    path=doc["path"])

    # Ratchet: an over-budget chain may only shrink. Chains under budget grow
    # freely -- the point is to freeze existing debt, not to block ordinary work.
    if baseline:
        recorded = {c["dir"]: c for c in baseline.get("chains", [])}
        for chain in chains:
            prev = recorded.get(chain["dir"])
            if not prev:
                continue
            was_over = prev["bytes"] > budget
            grew = chain["nested_bytes"] > prev.get("nested_bytes", prev["bytes"])
            if was_over and grew:
                add("CHAIN_RATCHET", "error",
                    f"chain for {chain['dir']} was already over budget and its "
                    f"nested files grew "
                    f"{prev.get('nested_bytes', prev['bytes'])} → {chain['nested_bytes']} B",
                    dir=chain["dir"])

    biggest = sorted(
        (
            {"path": d["path"], "bytes": d["bytes"], "lines": d["lines"],
             "sections": sorted(d["sections"], key=lambda s: -s["bytes"])[:8]}
            for info in resolved.values() for d in info["canonical"]
        ),
        key=lambda d: -d["bytes"],
    )

    return {
        "root": os.path.abspath(root),
        "budget_bytes": budget,
        "root_max_lines": root_max_lines,
        "root_max_bytes": root_max_bytes,
        "root_lines": root_lines,
        "root_bytes": root_bytes,
        "doc_count": sum(len(i["canonical"]) for i in resolved.values()),
        "total_bytes": sum(i["bytes"] for i in resolved.values()),
        "chains": chains,
        "files": biggest,
        "findings": findings,
        "ok": not any(f["severity"] == "error" for f in findings),
    }


# ------------------------------------------------------------------ report

def human(report: dict) -> str:
    out: list[str] = []
    n, total = report["doc_count"], report["total_bytes"]
    out.append(f"{n} agent doc(s), {total:,} B total, budget {report['budget_bytes']:,} B/chain")
    out.append("")

    out.append("Chains (root → working dir):")
    for chain in report["chains"][:12]:
        flag = f"  OVER by {chain['over_by']:,}" if chain["over_by"] else ""
        out.append(f"  {chain['pct_of_budget']:>5.1f}%  {chain['bytes']:>7,} B  {chain['dir']}{flag}")
    out.append("")

    out.append("Largest files:")
    for doc in report["files"][:6]:
        out.append(f"  {doc['bytes']:>7,} B  {doc['lines']:>4} lines  {doc['path']}")
        for sec in doc["sections"][:3]:
            out.append(f"            {sec['bytes']:>6,} B  {'#' * sec['level']} {sec['heading']}")
    out.append("")

    if not report["findings"]:
        out.append("No findings.")
    else:
        errors = [f for f in report["findings"] if f["severity"] == "error"]
        warns = [f for f in report["findings"] if f["severity"] == "warn"]
        for label, group in (("ERROR", errors), ("WARN", warns)):
            for f in group:
                out.append(f"{label:>5}  {f['code']}: {f['message']}")
    return "\n".join(out)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", default=".")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--check", action="store_true",
                    help="exit 1 when any error-severity finding is present")
    ap.add_argument("--baseline")
    ap.add_argument("--update-baseline", action="store_true")
    ap.add_argument("--budget-bytes", type=int, default=DEFAULT_BUDGET_BYTES)
    ap.add_argument("--root-max-lines", type=int, default=DEFAULT_ROOT_MAX_LINES)
    ap.add_argument("--reserve-bytes", type=int, default=DEFAULT_RESERVE_BYTES)
    args = ap.parse_args(argv)

    if not os.path.isdir(args.root):
        print(f"not a directory: {args.root}", file=sys.stderr)
        return 2

    baseline = None
    if args.baseline and os.path.exists(args.baseline) and not args.update_baseline:
        with open(args.baseline) as fh:
            baseline = json.load(fh)

    report = audit(args.root, args.budget_bytes, args.root_max_lines,
                   args.reserve_bytes, baseline)

    if args.update_baseline:
        if not args.baseline:
            print("--update-baseline requires --baseline PATH", file=sys.stderr)
            return 2
        payload = {
            "budget_bytes": report["budget_bytes"],
            "chains": [
                {"dir": c["dir"], "bytes": c["bytes"], "nested_bytes": c["nested_bytes"]}
                for c in report["chains"]
            ],
        }
        with open(args.baseline, "w") as fh:
            json.dump(payload, fh, indent=2)
            fh.write("\n")
        print(f"baseline written: {args.baseline}")
        return 0

    print(json.dumps(report, indent=2) if args.json else human(report))
    return 1 if (args.check and not report["ok"]) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
