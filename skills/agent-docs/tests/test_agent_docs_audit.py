#!/usr/bin/env python3
"""End-to-end tests for agent_docs_audit.py.

Fixtures are built in a temp dir rather than committed, so the repo carries no
20 KB filler files and each test states the shape it needs in one place.

Run: python3 skills/agent-docs/tests/test_agent_docs_audit.py
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "scripts", "agent_docs_audit.py")

failures: list[str] = []
passes = 0


def build(spec: dict) -> str:
    """spec maps relative path -> str content, ('symlink', target), or int size."""
    root = tempfile.mkdtemp(prefix="agentdocs-")
    for rel, value in spec.items():
        path = os.path.join(root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        if isinstance(value, tuple) and value[0] == "symlink":
            os.symlink(value[1], path)
        elif isinstance(value, int):
            with open(path, "w") as fh:
                fh.write("# Filler\n" + ("x" * 60 + "\n") * (value // 61))
        else:
            with open(path, "w") as fh:
                fh.write(value)
    return root


def run(root: str, *args: str) -> tuple[dict, int]:
    proc = subprocess.run(
        [sys.executable, SCRIPT, "--root", root, "--json", *args],
        capture_output=True, text=True,
    )
    if proc.returncode == 2:
        raise AssertionError(f"script error: {proc.stderr}")
    return json.loads(proc.stdout), proc.returncode


def check(name: str, condition: bool, detail: str = "") -> None:
    global passes
    if condition:
        passes += 1
    else:
        failures.append(f"{name}{': ' + detail if detail else ''}")


def codes(report: dict) -> set[str]:
    return {f["code"] for f in report["findings"]}


# --------------------------------------------------------------------- tests

def test_healthy_repo_is_silent():
    root = build({
        "AGENTS.md": "# Root\n\n## Always\n\nUse yarn.\n",
        "CLAUDE.md": ("symlink", "AGENTS.md"),
        "pkg/AGENTS.md": "# Pkg\n\n## Always\n\nRun tests.\n",
        "pkg/CLAUDE.md": ("symlink", "AGENTS.md"),
    })
    report, code = run(root, "--check")
    check("healthy: no findings", not report["findings"], str(report["findings"]))
    check("healthy: exit 0", code == 0, f"exit {code}")
    check("healthy: symlink collapsed", report["doc_count"] == 2,
          f"counted {report['doc_count']}")
    shutil.rmtree(root)


def test_root_over_line_limit():
    root = build({"AGENTS.md": "# Root\n" + "\nfiller line\n" * 200,
                  "CLAUDE.md": ("symlink", "AGENTS.md")})
    report, code = run(root, "--check")
    check("over-lines: flagged", "ROOT_OVER_LINES" in codes(report))
    check("over-lines: exit 1", code == 1, f"exit {code}")
    shutil.rmtree(root)


def test_chain_over_budget():
    root = build({
        "AGENTS.md": 20000, "CLAUDE.md": ("symlink", "AGENTS.md"),
        "pkg/AGENTS.md": 20000, "pkg/CLAUDE.md": ("symlink", "AGENTS.md"),
    })
    report, _ = run(root)
    check("chain: flagged", "CHAIN_OVER_BUDGET" in codes(report))
    over = [c for c in report["chains"] if c["dir"] == "pkg"]
    check("chain: sums root+nested", over and over[0]["bytes"] > 39000,
          str(over[:1]))
    shutil.rmtree(root)


def test_import_stub_is_an_alias_not_a_duplicate():
    """The dominant FSH pattern: CLAUDE.md is `@AGENTS.md`, not a symlink."""
    root = build({
        "AGENTS.md": "# Root\n\n## Always\n\nUse yarn.\n",
        "CLAUDE.md": "# CLAUDE.md\n\nGuidance for Claude Code.\n\n@AGENTS.md\n",
    })
    report, _ = run(root)
    check("import stub: not a duplicate", "DUPLICATE_HARNESS" not in codes(report),
          str(codes(report)))
    check("import stub: not counted twice", report["doc_count"] == 1,
          f"counted {report['doc_count']}")
    shutil.rmtree(root)


def test_two_real_docs_are_a_duplicate():
    root = build({
        "AGENTS.md": "# Root\n\n" + "Substantial guidance.\n" * 60,
        "CLAUDE.md": "# Root\n\n" + "Different substantial guidance.\n" * 60,
    })
    report, _ = run(root)
    check("duplicate: flagged", "DUPLICATE_HARNESS" in codes(report),
          str(codes(report)))
    shutil.rmtree(root)


def test_single_harness_warns():
    root = build({"CLAUDE.md": "# Only Claude\n\nSome rules.\n"})
    report, code = run(root, "--check")
    check("single: flagged", "SINGLE_HARNESS" in codes(report))
    check("single: warn only, exit 0", code == 0, f"exit {code}")
    shutil.rmtree(root)


def test_broken_symlink_is_an_error():
    root = build({"AGENTS.md": "# Root\n\nRules.\n",
                  "CLAUDE.md": ("symlink", "NOPE.md")})
    report, code = run(root, "--check")
    check("broken link: flagged", "BROKEN_SYMLINK" in codes(report))
    check("broken link: exit 1", code == 1, f"exit {code}")
    shutil.rmtree(root)


def test_headings_inside_fences_are_not_sections():
    """`# Development` inside a ```bash fence is a comment. tournee has several."""
    root = build({"AGENTS.md": (
        "# Root\n\n## Real Section\n\n```bash\n# Development\nyarn dev\n"
        "# Building\nyarn build\n```\n\n## Second Real\n\ntext\n"
    )})
    report, _ = run(root)
    headings = [s["heading"] for s in report["files"][0]["sections"]]
    check("fences: comment not a section", "Development" not in headings, str(headings))
    check("fences: real sections kept",
          {"Real Section", "Second Real"} <= set(headings), str(headings))
    shutil.rmtree(root)


def test_vendored_dirs_are_skipped():
    root = build({
        "AGENTS.md": "# Root\n\nRules.\n",
        "node_modules/dep/AGENTS.md": "# Vendored\n\nNot ours.\n",
        "infra/.terraform/modules/x/AGENTS.md": "# Vendored\n\nNot ours.\n",
    })
    report, _ = run(root)
    check("skip: vendored ignored", report["doc_count"] == 1,
          f"counted {report['doc_count']}: {[f['path'] for f in report['files']]}")
    shutil.rmtree(root)


def test_ratchet_freezes_existing_debt():
    spec = {"AGENTS.md": 20000, "pkg/AGENTS.md": 20000}
    root = build(spec)
    baseline = os.path.join(root, "baseline.json")
    subprocess.run([sys.executable, SCRIPT, "--root", root,
                    "--baseline", baseline, "--update-baseline"],
                   capture_output=True, text=True, check=True)

    # Unchanged -> ratchet silent.
    report, _ = run(root, "--baseline", baseline)
    check("ratchet: stable is clean", "CHAIN_RATCHET" not in codes(report))

    # Growing an already-over-budget chain -> error.
    with open(os.path.join(root, "pkg", "AGENTS.md"), "a") as fh:
        fh.write("more guidance\n" * 100)
    report, code = run(root, "--baseline", baseline, "--check")
    check("ratchet: growth flagged", "CHAIN_RATCHET" in codes(report), str(codes(report)))
    check("ratchet: exit 1", code == 1, f"exit {code}")
    shutil.rmtree(root)


def test_under_budget_chain_may_grow():
    spec = {"AGENTS.md": 2000, "pkg/AGENTS.md": 2000}
    root = build(spec)
    baseline = os.path.join(root, "baseline.json")
    subprocess.run([sys.executable, SCRIPT, "--root", root,
                    "--baseline", baseline, "--update-baseline"],
                   capture_output=True, text=True, check=True)
    with open(os.path.join(root, "pkg", "AGENTS.md"), "a") as fh:
        fh.write("more guidance\n" * 100)
    report, code = run(root, "--baseline", baseline, "--check")
    check("ratchet: under-budget growth allowed",
          "CHAIN_RATCHET" not in codes(report), str(codes(report)))
    check("ratchet: exit 0", code == 0, f"exit {code}")
    shutil.rmtree(root)


def test_empty_repo_does_not_crash():
    root = build({"README.md": "# Nothing to see\n"})
    report, code = run(root, "--check")
    check("empty: no docs", report["doc_count"] == 0)
    check("empty: exit 0", code == 0, f"exit {code}")
    shutil.rmtree(root)


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
    print(f"{passes} checks passed, {len(failures)} failed")
    for f in failures:
        print(f"  FAIL  {f}")
    sys.exit(1 if failures else 0)
