#!/usr/bin/env python3
"""End-to-end tests for docs_audit.py.

Fixtures are built in a temp dir rather than committed, so the repo carries no
20 KB filler files and each test states the shape it needs in one place.

Run: python3 skills/docs-audit/tests/test_docs_audit.py
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "scripts", "docs_audit.py")

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


# ------------------------------------------------------- specs / index / links

def spec(name: str, sections=("TLDR", "Problem Statement", "Changelog")) -> str:
    return f"# {name}\n\n" + "".join(f"## {h}\n\ntext\n\n" for h in sections)


def test_spec_number_collision_is_an_error():
    files = {f"docs/specs/SPEC-00{i}-2026-01-0{i}-thing-{i}.md": spec(f"s{i}")
             for i in (1, 2, 3)}
    files["docs/specs/SPEC-003-2026-02-09-other.md"] = spec("dupe")
    root = build(files)
    report, code = run(root, "--only", "specs", "--check")
    hits = [f for f in report["findings"] if f["code"] == "SPEC_NUMBER_COLLISION"]
    check("spec collision: flagged", len(hits) == 1, str(codes(report)))
    check("spec collision: exit 1", code == 1, f"exit {code}")
    shutil.rmtree(root)


def test_lettered_variant_is_not_a_collision():
    """covo's SPEC-022a is a deliberate follow-up to SPEC-022, not a clash.

    A checker that strips the suffix reports 2 false positives out of 10 there,
    which is how a convention checker gets muted instead of acted on.
    """
    files = {f"docs/specs/SPEC-00{i}-2026-01-0{i}-thing-{i}.md": spec(f"s{i}")
             for i in (1, 2, 3)}
    files["docs/specs/SPEC-002a-2026-01-09-follow-up.md"] = spec("variant")
    root = build(files)
    report, _ = run(root, "--only", "specs")
    check("lettered variant: not a collision",
          "SPEC_NUMBER_COLLISION" not in codes(report), str(codes(report)))
    shutil.rmtree(root)


def test_undated_numbered_convention_is_recognised():
    """tournee numbers specs without a date -- a third convention."""
    files = {f"docs/specs/SPEC-00{i}-thing-{i}.md": spec(f"s{i}") for i in (1, 2, 3)}
    files["docs/specs/SPEC-003-other-thing.md"] = spec("dupe")
    root = build(files)
    report, _ = run(root, "--only", "specs")
    conv = report["spec_dirs"][0]
    check("undated: convention derived", conv["convention"] == "numbered",
          conv["convention"])
    check("undated: all conforming", conv["conforming"] == 4, str(conv))
    check("undated: collision found", "SPEC_NUMBER_COLLISION" in codes(report))
    shutil.rmtree(root)


def test_dated_convention_has_no_numbering_check():
    """open-mercato dates specs; there is no number to collide."""
    files = {f"docs/specs/2026-01-0{i}-thing-{i}.md": spec(f"s{i}") for i in (1, 2, 3)}
    root = build(files)
    report, _ = run(root, "--only", "specs")
    check("dated: convention derived",
          report["spec_dirs"][0]["convention"] == "dated",
          report["spec_dirs"][0]["convention"])
    check("dated: no collision check", "SPEC_NUMBER_COLLISION" not in codes(report))
    shutil.rmtree(root)


def test_unrecognised_naming_asserts_no_convention():
    """Never report 'numbered convention (0 conforming)'."""
    files = {f"docs/specs/whatever-{i}.md": spec(f"s{i}") for i in (1, 2, 3)}
    root = build(files)
    report, _ = run(root, "--only", "specs")
    check("no convention: flagged", "SPEC_NO_CONVENTION" in codes(report),
          str(codes(report)))
    check("no convention: nothing asserted", not report.get("spec_dirs"),
          str(report.get("spec_dirs")))
    shutil.rmtree(root)


def test_template_gaps_aggregate_to_one_finding():
    files = {f"docs/specs/SPEC-00{i}-2026-01-0{i}-t{i}.md": spec(f"s{i}")
             for i in (1, 2, 3, 4)}
    files["docs/specs/SPEC-005-2026-01-05-t5.md"] = spec("s5", ("TLDR",))
    files["docs/specs/SPEC-000-template.md"] = spec("tmpl")
    root = build(files)
    report, _ = run(root, "--only", "specs")
    hits = [f for f in report["findings"] if f["code"] == "SPEC_TEMPLATE_GAP"]
    check("template: one aggregated finding", len(hits) == 1, str(hits))
    check("template: names the outlier", hits and hits[0]["count"] == 1, str(hits))
    shutil.rmtree(root)


def test_unadopted_template_section_is_not_enforced():
    """A section nobody uses is a dead template, not N broken specs."""
    files = {f"docs/specs/SPEC-00{i}-2026-01-0{i}-t{i}.md": spec(f"s{i}", ("TLDR",))
             for i in (1, 2, 3, 4)}
    files["docs/specs/SPEC-000-template.md"] = spec("tmpl", ("TLDR", "Nobody Uses This"))
    root = build(files)
    report, _ = run(root, "--only", "specs")
    check("template: unadopted section ignored",
          "SPEC_TEMPLATE_GAP" not in codes(report), str(codes(report)))
    shutil.rmtree(root)


def test_dead_relative_link_is_an_error():
    root = build({"docs/a.md": "# A\n\nSee [B](./b.md).\n",
                  "README.md": "# R\n\n[A](docs/a.md)\n"})
    report, code = run(root, "--only", "links", "--check")
    check("dead link: flagged", "DEAD_LINK" in codes(report))
    check("dead link: exit 1", code == 1, f"exit {code}")
    shutil.rmtree(root)


def test_placeholders_and_code_refs_are_not_links():
    root = build({"docs/a.md": (
        "# A\n\n[View](…/pull/N) [Br](<branch>/x.md) [T]({{SLUG}}.md)\n"
        "[Code](src/lib/x.ts:191) [Home](~/Downloads/f.docx)\n"
        "[Web](https://example.com/x.md) [Anchor](#section)\n")})
    report, _ = run(root, "--only", "links")
    check("placeholders: no dead links", "DEAD_LINK" not in codes(report),
          str([f["message"] for f in report["findings"]]))
    shutil.rmtree(root)


def test_orphaned_doc_is_warned_only_under_docs():
    root = build({
        "README.md": "# R\n\n[A](docs/a.md)\n",
        "docs/a.md": "# A\n\ntext\n",
        "docs/lonely.md": "# Lonely\n\ntext\n",
        "tasks/scratch.md": "# Scratch\n\ntext\n",
    })
    report, code = run(root, "--only", "index", "--check")
    orphans = [f["path"] for f in report["findings"] if f["code"] == "DOC_ORPHANED"]
    check("orphan: docs/ file flagged", orphans == ["docs/lonely.md"], str(orphans))
    check("orphan: warn only", code == 0, f"exit {code}")
    shutil.rmtree(root)


def test_only_filters_families():
    root = build({"CLAUDE.md": "# Root\n" + "\nfiller\n" * 300,
                  "docs/a.md": "# A\n\n[gone](./nope.md)\n"})
    report, _ = run(root, "--only", "chain")
    check("--only chain: no link findings", "DEAD_LINK" not in codes(report))
    check("--only chain: chain findings kept", "ROOT_OVER_LINES" in codes(report),
          str(codes(report)))
    report, _ = run(root, "--only", "links")
    check("--only links: no chain findings", "ROOT_OVER_LINES" not in codes(report))
    shutil.rmtree(root)


def test_unknown_family_is_a_usage_error():
    root = build({"README.md": "# R\n"})
    proc = subprocess.run([sys.executable, SCRIPT, "--root", root, "--only", "bogus"],
                          capture_output=True, text=True)
    check("unknown family: exit 2", proc.returncode == 2, f"exit {proc.returncode}")
    shutil.rmtree(root)


def test_untracked_files_are_ignored_in_a_git_repo():
    """Conductor's .context/ scratch is not part of the repo's contract."""
    root = build({"README.md": "# R\n\n[A](docs/a.md)\n", "docs/a.md": "# A\n"})
    for cmd in (["init", "-q"], ["add", "."], ["-c", "user.email=t@t", "-c",
                "user.name=t", "commit", "-qm", "x"]):
        subprocess.run(["git", "-C", root] + cmd, capture_output=True)
    with open(os.path.join(root, "docs", "untracked.md"), "w") as fh:
        fh.write("# Untracked\n")
    report, _ = run(root, "--only", "index")
    orphans = [f["path"] for f in report["findings"] if f["code"] == "DOC_ORPHANED"]
    check("untracked: ignored", orphans == [], str(orphans))
    shutil.rmtree(root)


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
    print(f"{passes} checks passed, {len(failures)} failed")
    for f in failures:
        print(f"  FAIL  {f}")
    sys.exit(1 if failures else 0)
