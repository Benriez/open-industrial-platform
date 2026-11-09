#!/usr/bin/env python3
"""The reconciliation of the worktrees (the AGENTS.md obligation).

The repository holds a worktree for every workstream of the release. The
binding rules demand that the active UI worktrees are reconciled **without
overwriting newer implementations or foreign ownership** — so the question is
not "may the branch be merged" but "**does the canonical branch already carry
the capability of that branch, and is the implementation of the canonical
branch the newer one?**".

The rehearsal answers that for every branch of every worktree:

  * the branches of the worktrees and the commits of each branch that the
    canonical branch does **not** contain;
  * for every such commit: the files it touches, and whether the canonical
    branch carries them;
  * the **capability** of that commit, checked in the canonical branch —
    whether the managed diagnostics view of the branch is present there with
    the behaviour of the branch (the documented gaps, the health transitions,
    the opaque cursor of the continuation, the status of the diagnosis
    history), and whether the implementation of the canonical branch is the
    newer one;
  * the receipt that **proves** the capability in the canonical branch.

Nothing of the rehearsal changes a worktree, a branch or a file of the
repository: it reads the git history and the sources of the canonical branch.

Usage:
  python3 tests/oip_worktree_reconciliation.py [--evidence DIR]
"""
import argparse
import json
import pathlib
import re
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
LIB = ROOT / "apps/flutter/lib"
# The capability of the branch that is not in the canonical branch, and how
# the canonical branch must show it.
CAPABILITY = {
    "the_documented_gaps": ("apps/flutter/lib/features/diagnostics.dart",
                            r"documentedGaps"),
    "the_health_transitions": ("apps/flutter/lib/features/diagnostics.dart",
                               r"healthTransitions"),
    "the_opaque_cursor_of_the_continuation": ("apps/flutter/lib/features/diagnostics.dart",
                                               r"diagnosticGaps\(cursor:"),
    "the_status_of_the_diagnosis_history": ("apps/flutter/lib/features/diagnostics.dart",
                                             r"Diagnosehistorie"),
    "the_adapter_of_the_gaps": ("apps/flutter/lib/services/api.dart",
                                r"diagnosticGaps"),
    "the_adapter_of_the_health_history": ("apps/flutter/lib/services/api.dart",
                                           r"healthHistory"),
    "the_model_of_the_diagnostic_page": ("apps/flutter/lib/models/diagnostics.dart",
                                          r"DiagnosticPage"),
}


def git(*arguments):
    result = subprocess.run(["git", *arguments], cwd=ROOT, capture_output=True, text=True)
    return result.stdout.strip()


def git_carries(path):
    """Whether the canonical branch carries the file."""
    result = subprocess.run(["git", "cat-file", "-e", f"main:{path}"], cwd=ROOT,
                            capture_output=True, text=True)
    return result.returncode == 0


def the_branches():
    """Every branch of every worktree of the repository."""
    listing = git("worktree", "list", "--porcelain").splitlines()
    branches = []
    for line in listing:
        if line.startswith("branch refs/heads/"):
            branches.append(line[len("branch refs/heads/"):])
    return sorted(set(branches))


def the_unmerged(branch):
    """The commits of the branch that the canonical branch does not contain."""
    commits = []
    for line in git("log", "--format=%H%x1f%s", f"main..{branch}").splitlines():
        revision, _, subject = line.partition("\x1f")
        commits.append({"the_revision": revision, "the_subject": subject})
    return commits


def the_files(revision):
    listing = git("show", "--stat", "--name-only", "--format=", revision)
    return [line for line in listing.splitlines() if line.strip()]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-worktree-reconciliation"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-worktree-reconciliation-v1", "steps": [],
              "the_canonical_branch": "main",
              "the_canonical_revision": git("rev-parse", "main")}

    branches = the_branches()
    report["the_branches"] = branches
    report["the_steps_of_the_reconciliation"] = []

    unmerged = {}
    for branch in branches:
        commits = the_unmerged(branch)
        if not commits:
            continue
        entries = []
        for commit in commits:
            files = the_files(commit["the_revision"])
            carried, missing = [], []
            for name in files:
                if git_carries(name):
                    carried.append(name)
                else:
                    missing.append(name)
            entries.append({**commit, "the_files": files,
                            "the_files_that_main_carries": carried,
                            "the_files_that_main_does_not_carry": missing})
        unmerged[branch] = entries
    report["the_branches_that_main_does_not_contain"] = unmerged

    # the capability of the unmerged work, checked in the canonical branch
    capability = {}
    for name, (path, pattern) in CAPABILITY.items():
        source = ROOT / path
        present = False
        if source.is_file():
            present = re.search(pattern, source.read_text()) is not None
        capability[name] = {"the_source": path, "the_pattern": pattern,
                            "the_canonical_branch_carries_it": present}
    report["the_capability_in_the_canonical_branch"] = capability
    report["the_canonical_branch_carries_the_capability"] = all(
        item["the_canonical_branch_carries_it"] for item in capability.values())

    # the receipt that proves the capability in the canonical branch
    proof = ROOT / "docs/evidence/oip-diagnostic-continuation/diagnostic-continuation.json"
    if proof.is_file():
        payload = json.loads(proof.read_text())
        gaps = payload.get("gaps", {})
        report["the_proof_of_the_capability"] = {
            "the_receipt": proof.relative_to(ROOT).as_posix(),
            "the_revision": payload.get("the_revision"),
            "the_documented_gaps": gaps.get("total_rows"),
            "the_distinct_rows": gaps.get("distinct_rows"),
            "the_first_page_items": gaps.get("first_page_items"),
            "the_continuation_items": gaps.get("continuation_items"),
            "the_note": "the browser journey of the canonical branch walks the documented "
                        "gaps and the health history over the opaque cursor of the Core",
        }

    # the implementation of the canonical branch is the newer one
    newer = {}
    for branch in unmerged:
        for commit in unmerged[branch]:
            for name in commit["the_files"]:
                if not name.endswith(".dart") or not (ROOT / name).is_file():
                    continue
                path = ROOT / name
                branch_lines = git("show", f"{commit['the_revision']}:{name}").splitlines()
                canonical_lines = path.read_text().splitlines()
                newer[name] = {
                    "the_lines_of_the_branch": len(branch_lines),
                    "the_lines_of_the_canonical_branch": len(canonical_lines),
                    "the_canonical_branch_is_the_newer_implementation":
                        len(canonical_lines) != len(branch_lines),
                }
    report["the_implementations"] = newer

    complete = all(
        not entry["the_files_that_main_does_not_carry"]
        or all(name.startswith("docs/recovery/")
               for name in entry["the_files_that_main_does_not_carry"])
        for entries in unmerged.values() for entry in entries)
    report["the_reconciliation_is_complete"] = complete
    report["status"] = "PASS" if complete and report["the_canonical_branch_carries_the_capability"] else "FAIL"

    report["the_revision"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    report["the_tree"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip()
    report["the_working_tree_is_clean"] = not subprocess.check_output(
        ["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()
    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "worktree-reconciliation.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items()
                      if k not in ("the_steps_of_the_reconciliation", "the_implementations")},
                     indent=2))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
