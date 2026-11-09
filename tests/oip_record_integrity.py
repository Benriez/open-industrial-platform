#!/usr/bin/env python3
"""The integrity of the release record (the handoff).

The record of the release — the ledger and the state file — cites the
receipts of the evidence. A citation that names a file that does not exist, or
a file that is not part of the checkout, is a broken handoff: the operator
cannot follow it. A receipt of the current release that nobody cites is an
orphaned receipt: it was measured, but nobody can find it.

The checker proves both directions:

  * every receipt path that the record cites exists **and is tracked** by git;
  * every receipt of the current release under `docs/evidence/` is cited by the
    ledger or by the state file.

The receipts of the earlier eras are excluded: they are the history of that
era and are cited by the documents of that era.

Usage:
  python3 tests/oip_record_integrity.py [--evidence DIR]
"""
import argparse
import json
import pathlib
import re
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
LEDGER = ROOT / "docs/OIP_RELEASE_LEDGER.md"
PROGRESS = ROOT / "docs/OIP_RELEASE_PROGRESS.md"
EVIDENCE = ROOT / "docs/evidence"
# The receipts of the eras: they are the history of their era and are cited by
# the documents of that era. The areas of the current release are the
# directories that begin with "oip-"; `oip-real-device` belongs to the
# milestone era.
# The areas that hold the receipts of the earlier eras: they are the history
# of the measurement and not the evidence of this release. The record must
# name every one of them — the checker looks for the name.
ERA_AREAS = {
    "oip-real-device", "git-baseline", "oip003", "oip004", "oip004-ui", "oip005",
    "oip006", "oip0061", "oip007", "oip008", "oip0082", "oip0084", "oip0085",
}
CITATION = re.compile(r"docs/evidence/[A-Za-z0-9_./-]+")
# Every path that the record names in a backtick. A path of the checkout must
# exist; a path of the build tree must not be used as the receipt of a claim.
PATH_CITATION = re.compile(
    r"`((?:docs|apps|crates|tests|tools|target)/[A-Za-z0-9_./-]*)`")
# The paths of the build tree that the record may name as the place of a run.
BUILD_TREE = ("target/oip-canonical-regression", "target/oip-canonical-ui",
              "target/oip-canonical-e2e", "target/oip-release-binary",
              "target/oip-conformance-e2e", "target/oip008-ui-canonical",
              "target/oip-ui-missing-archive-receipt.json")


def tracked(paths):
    result = subprocess.run(["git", "ls-files", "--"], cwd=ROOT,
                            capture_output=True, text=True, timeout=300)
    return set(line for line in result.stdout.splitlines() if line)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-record-integrity"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-record-integrity-v1", "steps": []}

    text = LEDGER.read_text() + "\n" + PROGRESS.read_text()
    cited = set()
    for match in CITATION.finditer(text):
        name = match.group(0).rstrip(".,;:)`*")
        # a citation may end with a glob
        if name.endswith("*"):
            name = name[:-1]
        cited.add(name)
    report["the_cited_paths"] = len(cited)

    tracked_paths = tracked(sorted(cited))
    missing = sorted(name for name in cited
                     if not (ROOT / name).exists())
    untracked = []
    for name in sorted(cited):
        if name in tracked_paths:
            continue
        path = ROOT / name
        if not path.exists():
            continue
        if path.is_dir():
            # A cited directory of an era: the history of the measurement is
            # not the evidence of this release and it is not tracked as such.
            if name.split("/")[2] in ERA_AREAS:
                continue
            # A cited directory of the release: the files in it must be tracked.
            files = [item for item in path.rglob("*") if item.is_file()]
            if not files or not all(item.relative_to(ROOT).as_posix() in tracked_paths
                                    for item in files):
                untracked.append(name)
        else:
            untracked.append(name)
    report["the_citations"] = {
        "the_cited": len(cited),
        "the_missing_on_disk": missing,
        "the_present_but_untracked": untracked,
    }
    report["steps"].append("every cited receipt exists")
    problems = []

    # every path that the record names must exist in the checkout
    dangling = []
    build_tree = []
    for name in sorted(set(PATH_CITATION.findall(text))):
        name = name.rstrip(".,;:)*")
        if name.endswith("*"):
            continue
        if name.startswith("target/"):
            build_tree.append(name)
            continue
        if not (ROOT / name).exists():
            dangling.append(name)
    # The authoritative ledger must not present a path of the build tree as the
    # evidence of a claim; the state file may name the paths of the earlier
    # eras, which are the history of those eras.
    ledger_text = LEDGER.read_text()
    ledger_build_tree = sorted(set(
        name.rstrip(".,;:)*") for name in PATH_CITATION.findall(ledger_text)
        if name.rstrip(".,;:)*").startswith("target/")
        and not name.rstrip(".,;:)*").startswith("target/release/")))
    report["the_paths"] = {
        "the_dangling": dangling,
        "the_paths_of_the_build_tree": build_tree,
        "the_paths_of_the_build_tree_in_the_ledger": ledger_build_tree,
        "the_note": "a path of the build tree is not a receipt: the ledger must not "
                    "present a directory of a build as the evidence of a claim. The "
                    "artefacts of the release live in the build tree by nature and "
                    "are named by the manifest.",
    }
    report["steps"].append("every path that the record names exists")
    problems.extend(f"the cited path {name} does not exist" for name in dangling)
    problems.extend(f"the ledger presents the path of a build tree as evidence: {name}"
                    for name in ledger_build_tree)

    # Every file of the evidence tree that nobody cites. The tree is walked
    # whole: the receipts of the eras are the history of the measurement and
    # not the evidence of this release — the record names every one of their
    # areas, and every other file must be cited by the record.
    present = set()
    era_files = set()
    for path in sorted(EVIDENCE.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(ROOT).as_posix()
        area = relative.split("/")[2]
        if area in ERA_AREAS:
            era_files.add(relative)
        else:
            present.add(relative)
    prefixes = tuple(name for name in cited if name.endswith("/"))
    exact = {name for name in cited if not name.endswith("/")}
    cited_files = {name for name in present
                   if name in exact or name.startswith(prefixes)}
    orphans = sorted(present - cited_files)
    unnamed_eras = sorted(area for area in ERA_AREAS
                           if (EVIDENCE / area).is_dir()
                           and f"docs/evidence/{area}/" not in text)
    report["the_receipts_of_the_release"] = {
        "the_present": len(present),
        "the_cited": len(cited_files),
        "the_orphaned": orphans,
        "the_files_of_the_eras": len(era_files),
        "the_areas_of_the_eras_that_the_record_does_not_name": unnamed_eras,
    }
    report["steps"].append("every file of the evidence tree is cited")

    problems.extend(f"the cited receipt {name} does not exist" for name in missing)
    problems.extend(f"the cited receipt {name} is not tracked by git" for name in untracked)
    problems.extend(f"the file {name} of the evidence tree is cited by nobody" for name in orphans)
    problems.extend(f"the record does not name the era area {area}" for area in unnamed_eras)
    report["the_problems"] = problems
    report["status"] = "PASS" if not problems else "FAIL"

    report["the_revision"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    report["the_tree"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip()
    report["the_working_tree_is_clean"] = not subprocess.check_output(
        ["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()
    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "record-integrity.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "the_cited_paths"}, indent=2))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
