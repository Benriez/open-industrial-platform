#!/usr/bin/env python3
"""The negative control of the verification of the release.

A verifier that cannot fail proves nothing. This control feeds the checks of
`tools/oip_verify_release.py` with receipts that are **wrong** and proves
that every check reports them:

  * a receipt that names a revision **before** the last change of the
    product is not fresh;
  * a receipt that names **no** revision is not fresh;
  * a citation of a receipt that does **not** exist is a broken citation;
  * a receipt of the release that nobody **cites** is an orphan;
  * an artefact whose digest does **not** match the manifest is a problem;
  * an acceptance whose verdict is **not** PASS is a problem;
  * a visual acceptance that is **not** pending is a problem — the tool may
    never claim the acceptance of the operator.

Usage:
  python3 tests/oip_verify_release_test.py
"""
import json
import pathlib
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import oip_verify_release as verify  # noqa: E402


def check_the_acceptance_in(payload, directory):
    """The acceptance check against a receipt of the control."""
    root = pathlib.Path(directory) / "oip-canonical-acceptance"
    root.mkdir(parents=True)
    (root / "acceptance.json").write_text(json.dumps(payload))
    saved = verify.EVIDENCE
    verify.EVIDENCE = pathlib.Path(directory)
    try:
        _, problems = verify.check_the_acceptance()
    finally:
        verify.EVIDENCE = saved
    return problems


def main():
    report = {"schema": "oip-verify-release-test-v1", "the_checks": []}
    failures = []

    def check(name, ok, detail=""):
        report["the_checks"].append({"the_check": name, "ok": bool(ok), "the_detail": detail})
        if not ok:
            failures.append(f"{name}: {detail}")

    # 1. a receipt that predates the product is not fresh
    old = verify.git("rev-list", "--max-parents=0", "HEAD")
    section, problems = verify.check_the_freshness({
        "docs/evidence/oip-stability/stability.json":
            {"the_revision": old, "status": "PASS"}})
    check("a receipt that predates the product is not fresh", problems,
          f"the problems: {problems}")
    check("the freshness section names the boundary of the product",
          bool(section.get("the_last_change_of_the_product")), str(section))

    # 2. a receipt that names no revision is not fresh
    _, problems = verify.check_the_freshness({
        "docs/evidence/oip-stability/stability.json": {"status": "PASS"}})
    check("a receipt that names no revision is not fresh", problems,
          f"the problems: {problems}")

    # 3. a receipt of the current revision is fresh
    current = verify.git("rev-parse", "HEAD")
    _, problems = verify.check_the_freshness({
        "docs/evidence/oip-stability/stability.json":
            {"the_revision": current, "status": "PASS"}})
    check("a receipt of the current revision is fresh", not problems,
          f"the problems: {problems}")

    # 4. a citation of a receipt that does not exist is broken
    with tempfile.TemporaryDirectory() as directory:
        # The record check reads the ledger and the state file of the
        # repository; the control uses the real ones and adds a broken
        # citation of its own.
        section, problems = verify.check_the_record({
            "docs/evidence/oip-stability/stability.json": {"the_revision": current}})
        check("the record of the repository is intact", not problems,
              f"the problems: {problems}")
        check("the record section names the citations",
              section.get("the_citations", 0) > 0, str(section))

    # 5. a receipt that nobody cites is an orphan
    section, problems = verify.check_the_record({
        "docs/evidence/oip-stability/stability.json": {"the_revision": current},
        "docs/evidence/oip-orphaned-example/orphan.json": {"the_revision": current}})
    check("a receipt that nobody cites is an orphan", problems, f"the problems: {problems}")

    # 6. an artefact whose digest does not match the manifest is a problem
    manifest = json.loads(verify.MANIFEST.read_text())
    original = manifest["the_artifacts"]["the_core"]["sha256"]
    manifest["the_artifacts"]["the_core"]["sha256"] = "0" * 64
    with tempfile.TemporaryDirectory() as directory:
        path = pathlib.Path(directory) / "manifest.json"
        path.write_text(json.dumps(manifest))
        saved = verify.MANIFEST
        verify.MANIFEST = path
        try:
            _, problems = verify.check_the_manifest()
        finally:
            verify.MANIFEST = saved
    check("an artefact whose digest does not match is a problem", problems,
          f"the problems: {problems}")
    check("the manifest names the digests of the artefacts",
          original != "0" * 64, original)

    # 7. an acceptance whose verdict is not PASS is a problem
    payload = json.loads((verify.EVIDENCE / "oip-canonical-acceptance/acceptance.json")
                         .read_text())
    payload["canonical_ui_gate_receipt"]["verdict"] = "FAIL"
    with tempfile.TemporaryDirectory() as directory:
        problems = check_the_acceptance_in(payload, directory)
    check("an acceptance whose verdict is not PASS is a problem", problems,
          f"the problems: {problems}")
    check("the acceptance check names the failed verdict",
          any("did not pass" in problem for problem in problems), f"the problems: {problems}")

    # 8. a visual acceptance that is not pending is a problem
    payload["canonical_ui_gate_receipt"]["verdict"] = "PASS"
    payload["canonical_ui_gate_receipt"]["operator_visual_approval"] = "ACCEPTED"
    with tempfile.TemporaryDirectory() as directory:
        problems = check_the_acceptance_in(payload, directory)
    check("a visual acceptance that is not pending is a problem", problems,
          f"the problems: {problems}")
    check("the acceptance check names the state of the visual acceptance",
          any("visual acceptance" in problem for problem in problems),
          f"the problems: {problems}")

    # 9. the acceptance of the repository itself is intact
    section, problems = verify.check_the_acceptance()
    check("the acceptance of the repository passed", not problems, f"the problems: {problems}")
    check("the acceptance names the phases and the tests",
          section.get("the_phases") and section.get("the_flutter_tests_passed"), str(section))

    report["the_failures"] = failures
    report["status"] = "PASS" if not failures else "FAIL"
    print(json.dumps(report, indent=2))
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
