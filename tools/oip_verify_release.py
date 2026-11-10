#!/usr/bin/env python3
"""The verification of the release — one command, one receipt.

A third party that receives this repository must be able to check the whole
handoff with **one command** and without trusting the prose of the record.
This tool is that command. It proves:

  1. **The manifest** of the release verifies: every digest of every artefact
     and of every receipt is recomputed and compared with the written manifest.
  2. **Every receipt is fresh**: no receipt of the release names a revision
     that predates the last change to the product it covers. A receipt that
     predates the product does not measure the product.
  3. **The record is intact**: every receipt that the ledger and the state
     file cite exists and is tracked by git, and every receipt of the release
     is cited — a broken citation and an orphaned receipt are both defects of
     the handoff.
  4. **The acceptance passed**: the receipt of the canonical gate says PASS,
     with its phases, its browser findings, its Flutter tests, its captures
     and its accessibility numbers — and the visual acceptance of the
     operator is still **pending**, never claimed.
  5. **The safety boundaries held**: no receipt claims that the schema 7 was
     activated on the personal store of the operator, and the personal store
     is untouched (its digest is the one of the runbook).

The tool reads; it never writes into the repository. With `--receipt` it
writes the receipt of the verification.

The verdict of the tool is **not** a production acceptance: the production
acceptance is the operator's (G12) and the scope of the production security is
the operator's decision (G10). The tool reports the gates that are open.

Usage:
  python3 tools/oip_verify_release.py [--receipt PATH] [--json]
"""
import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
LEDGER = ROOT / "docs/OIP_RELEASE_LEDGER.md"
PROGRESS = ROOT / "docs/OIP_RELEASE_PROGRESS.md"
EVIDENCE = ROOT / "docs/evidence"
MANIFEST = ROOT / "docs/release/oip-release-manifest.json"
# The source of the product: the Core and the client. A receipt that predates
# the last change of the product does not measure the product.
PRODUCT = (["crates"], ["apps/flutter/lib"])
CITATION = re.compile(r"docs/evidence/[A-Za-z0-9_./-]+")
# Every path that the record names. A path of the checkout must exist; the
# ledger must not present a path of the build tree as the evidence of a claim.
PATH_CITATION = re.compile(
    r"`((?:docs|apps|crates|tests|tools|target)/[A-Za-z0-9_./-]*)`")
# The areas that hold the receipts of the earlier eras: they are the history
# of the measurement and not the evidence of this release. The record must
# name every one of them — the checker looks for the name.
ERA_AREAS = {
    "oip-real-device", "git-baseline", "oip003", "oip004", "oip004-ui", "oip005",
    "oip006", "oip0061", "oip007", "oip008", "oip0082", "oip0084", "oip0085",
}
# The digest of the personal store of the operator. It must never change.
PERSONAL_STORE = "9f988c01c7115631db3b5bfd2b9228ecc24255b8b9905932a987a89c78e6a24e"


def the_release_source():
    """The revision of the source of the release."""
    return git("log", "-1", "--format=%H", "--", "crates", "apps/flutter/lib")


def git(*arguments):
    result = subprocess.run(["git", *arguments], cwd=ROOT, capture_output=True, text=True)
    return result.stdout.strip()


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def digest_tree(root):
    entries = []
    for path in sorted(root.rglob("*")):
        if path.is_file():
            entries.append((path.relative_to(root).as_posix(), sha256_file(path)))
    digest = hashlib.sha256()
    for name, value in entries:
        digest.update(name.encode())
        digest.update(b"\0")
        digest.update(value.encode())
        digest.update(b"\0")
    return digest.hexdigest()


def the_release_receipts():
    """The receipts of the current release under `docs/evidence/`.

    The receipts of the earlier eras are the history of the measurement and
    not the evidence of this release; the record names every one of their
    areas. They are not the receipts of the release.
    """
    receipts = {}
    for path in sorted(EVIDENCE.rglob("*.json")):
        relative = path.relative_to(ROOT).as_posix()
        area = relative.split("/")[2]
        if area in ERA_AREAS:
            continue
        try:
            receipts[relative] = json.loads(path.read_text())
        except json.JSONDecodeError:
            continue
    return receipts


def check_the_manifest():
    """Every digest of the manifest is recomputed."""
    problems = []
    if not MANIFEST.is_file():
        return {"the_manifest_is_absent": True}, ["the manifest of the release is absent"]
    manifest = json.loads(MANIFEST.read_text())
    for name, artifact in manifest.get("the_artifacts", {}).items():
        path = ROOT / artifact["path"]
        if not artifact.get("present"):
            problems.append(f"the artefact {name} is absent")
            continue
        if not path.exists():
            problems.append(f"the artefact {name} is absent: {artifact['path']}")
            continue
        digest = sha256_file(path) if path.is_file() else digest_tree(path)
        if digest != artifact.get("sha256"):
            problems.append(f"the artefact {name} does not match its digest")
    for name, receipt in manifest.get("the_receipts", {}).items():
        path = ROOT / receipt["path"]
        if not receipt.get("sha256"):
            continue
        if not path.is_file():
            problems.append(f"the receipt {name} is absent: {receipt['path']}")
            continue
        if sha256_file(path) != receipt["sha256"]:
            problems.append(f"the receipt {name} does not match its digest")
    return {
        "the_revision": manifest.get("the_revision"),
        "the_revision_of_the_source": manifest.get("the_revision_of_the_source"),
        "the_source_manifest": manifest.get("the_source_manifest"),
        "the_artifacts": {name: artifact.get("sha256")
                          for name, artifact in manifest.get("the_artifacts", {}).items()},
        "the_receipts": len(manifest.get("the_receipts", {})),
        "the_visual_acceptance": manifest.get("the_visual_acceptance", {}).get("the_state"),
        # The property of the release is that the Core is byte-reproducible
        # for its revision; the manifest states it together with the fact that
        # the sources of the Core are unchanged since the measurement. The
        # strict comparison of the bytes is reported as well: a later build of
        # another revision names its own revision and therefore differs.
        "the_core_is_the_reproducible_one":
            manifest.get("the_core_is_the_reproducible_one", {}).get(
                "the_property_holds_for_the_release"),
        "the_manifest_names_the_reproducible_binary":
            manifest.get("the_core_is_the_reproducible_one", {}).get(
                "the_manifest_names_the_reproducible_binary"),
        "the_sources_of_the_core_are_unchanged_since_the_receipt":
            manifest.get("the_core_is_the_reproducible_one", {}).get(
                "the_sources_of_the_core_are_unchanged_since_the_receipt"),
    }, problems


def check_the_freshness(receipts):
    """No receipt predates the last change of the product it covers."""
    problems = []
    boundaries = {}
    for scope in PRODUCT:
        revision = git("log", "-1", "--format=%H", "--", *scope)
        boundaries["/".join(scope)] = revision
    # The revision of the source of the release: the last commit that changed
    # the product. A receipt that was measured on it covers the release as it
    # is; a receipt that was measured earlier is fresh because the code it
    # covers did not change since that measurement.
    release_source = the_release_source()
    on_the_release = []
    fresh_by_scope = []
    for relative, payload in receipts.items():
        revision = payload.get("the_revision") or payload.get("revision")
        if not revision:
            problems.append(f"the receipt {relative} names no revision")
            continue
        for scope, boundary in boundaries.items():
            if not boundary:
                continue
            result = subprocess.run(["git", "merge-base", "--is-ancestor", boundary, revision],
                                     cwd=ROOT, capture_output=True)
            if result.returncode != 0:
                problems.append(
                    f"the receipt {relative} names the revision {revision[:12]}, which "
                    f"predates the last change of {scope} ({boundary[:12]})")
        # A receipt that was measured on a tree that **carries** the source of
        # the release covers the release as it is; a receipt that was measured
        # before the last change of the code it covers is fresh only because
        # that code did not change since. The record states both, so that a
        # reader can see which is which.
        carries = subprocess.run(["git", "merge-base", "--is-ancestor",
                                  release_source, revision],
                                 cwd=ROOT, capture_output=True)
        if carries.returncode == 0:
            on_the_release.append(relative)
        else:
            fresh_by_scope.append(relative)
    return {
        "the_last_change_of_the_product": {name: revision[:12] for name, revision
                                           in boundaries.items()},
        "the_revision_of_the_source": release_source[:12],
        "the_receipts": len(receipts),
        "the_receipts_measured_on_a_tree_that_carries_the_source": len(on_the_release),
        "the_receipts_measured_before_the_last_change_of_the_code_they_cover":
            len(fresh_by_scope),
        "the_note": "a receipt that was measured on an earlier revision is fresh because "
                    "the code it covers did not change since that measurement; the "
                    "freshness rule of the record is exactly that",
    }, problems


def check_the_record(receipts):
    """Every citation exists and is tracked; every receipt is cited."""
    problems = []
    text = LEDGER.read_text() + "\n" + PROGRESS.read_text()
    cited = set()
    for match in CITATION.finditer(text):
        name = match.group(0).rstrip(".,;:)`*")
        if name.endswith("*"):
            name = name[:-1]
        cited.add(name)
    tracked = set(git("ls-files", "--").splitlines())
    missing = sorted(name for name in cited if not (ROOT / name).exists())
    untracked = []
    for name in sorted(cited):
        path = ROOT / name
        if name in tracked or not path.exists():
            continue
        if path.is_dir():
            # A cited directory of an era: the history of the measurement is
            # not the evidence of this release and it is not tracked as such.
            if name.split("/")[2] in ERA_AREAS:
                continue
            files = [item for item in path.rglob("*") if item.is_file()]
            if not files or not all(item.relative_to(ROOT).as_posix() in tracked
                                    for item in files):
                untracked.append(name)
        else:
            untracked.append(name)
    # The whole evidence tree is walked: every file of the release that the
    # record does not cite is a gap of the record.
    prefixes = tuple(name for name in cited if name.endswith("/"))
    exact = {name for name in cited if not name.endswith("/")}
    present = set()
    for path in sorted(EVIDENCE.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(ROOT).as_posix()
        if relative.split("/")[2] in ERA_AREAS:
            continue
        present.add(relative)
    # The receipts that were handed in are part of the release: a receipt that
    # nobody cites is an orphan, whether it stands on the disk or not.
    handed = {name for name in receipts if name.split("/")[2] not in ERA_AREAS}
    orphans = sorted(name for name in set(present) | handed
                     if name not in exact and not name.startswith(prefixes))
    problems.extend(f"the cited receipt {name} does not exist" for name in missing)
    problems.extend(f"the cited receipt {name} is not tracked" for name in untracked)
    problems.extend(f"the receipt {name} is cited by nobody" for name in orphans)

    # every path that the record names must exist; the ledger must not present
    # a path of the build tree as the evidence of a claim
    dangling = []
    for name in sorted(set(PATH_CITATION.findall(text))):
        name = name.rstrip(".,;:)*")
        if name.endswith("*") or name.startswith("target/"):
            continue
        if not (ROOT / name).exists():
            dangling.append(name)
    ledger_build_tree = sorted(set(
        name.rstrip(".,;:)*") for name in PATH_CITATION.findall(LEDGER.read_text())
        if name.rstrip(".,;:)*").startswith("target/")
        and not name.rstrip(".,;:)*").startswith("target/release/")))
    problems.extend(f"the cited path {name} does not exist" for name in dangling)
    problems.extend(f"the ledger presents the path of a build tree as evidence: {name}"
                    for name in ledger_build_tree)
    return {
        "the_citations": len(cited),
        "the_receipts_of_the_release": len(receipts),
        "the_missing": missing,
        "the_untracked": untracked,
        "the_orphaned": orphans,
        "the_dangling_paths": dangling,
        "the_paths_of_the_build_tree_in_the_ledger": ledger_build_tree,
    }, problems


def check_the_acceptance():
    """The receipt of the canonical gate says PASS — and the operator has not accepted."""
    problems = []
    path = EVIDENCE / "oip-canonical-acceptance/acceptance.json"
    if not path.is_file():
        return {"the_acceptance_is_absent": True}, ["the receipt of the acceptance is absent"]
    payload = json.loads(path.read_text())
    gate = payload.get("canonical_ui_gate_receipt", {})
    phases = payload.get("phases", [])
    passed = sum(1 for phase in phases if phase.get("status") == "PASS")
    if gate.get("verdict") != "PASS":
        problems.append(f"the gate did not pass: {gate.get('verdict')}")
    if phases and passed != len(phases):
        problems.append(f"only {passed} of {len(phases)} phases passed")
    if gate.get("browser_failures"):
        problems.append(f"{gate['browser_failures']} browser findings failed")
    approval = gate.get("operator_visual_approval")
    if approval != "VISUAL_PENDING_OPERATOR_ACCEPTANCE":
        problems.append(f"the visual acceptance of the operator is {approval!r}")
    return {
        "the_verdict": gate.get("verdict"),
        "the_phases": f"{passed} of {len(phases)}",
        "the_browser_findings": gate.get("browser_findings"),
        "the_browser_failures": gate.get("browser_failures"),
        "the_flutter_tests_passed": gate.get("flutter_tests_passed"),
        "the_flutter_tests_failed": gate.get("flutter_tests_failed"),
        "the_screenshots": gate.get("screenshots"),
        "the_revision_of_the_acceptance": payload.get("the_revision_of_the_acceptance"),
        "the_visual_acceptance_of_the_operator": approval,
    }, problems


def the_schema_of_the_store(path):
    """The schema of the store of the operator, read without writing."""
    try:
        import sqlite3
        connection = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        try:
            return connection.execute("pragma user_version").fetchone()[0]
        finally:
            connection.close()
    except Exception:  # noqa: BLE001 - a store that cannot be read is reported
        return None


def check_the_boundaries(receipts):
    """The personal store of the operator is untouched and was never activated.

    The boundary is **measured**, not asserted: the digest and the schema of
    the store of the operator are read now — read only — and compared with
    the digest that the record and the rehearsal of the activation name. A
    check that cannot measure the store says so; it never passes silently.
    """
    problems = []
    activation = EVIDENCE / "oip-activation-dry-run/activation-dry-run.json"
    recorded = None
    recorded_after = None
    if activation.is_file():
        payload = json.loads(activation.read_text())
        store = payload.get("the_store")
        if isinstance(store, dict):
            recorded = store.get("the_sha256_before") or store.get("the_sha256")
        recorded_after = payload.get("the_sha256_after")
    store_path = pathlib.Path.home() / "Library/Application Support/OIP/real/core.sqlite"
    current = sha256_file(store_path) if store_path.is_file() else None
    schema = the_schema_of_the_store(store_path) if store_path.is_file() else None
    if current is None:
        problems.append("the personal store of the operator is not readable")
    elif current != PERSONAL_STORE:
        problems.append(f"the digest of the personal store of the operator changed: {current}")
    if recorded is not None and recorded != PERSONAL_STORE:
        problems.append(f"the rehearsal recorded another digest of the personal store: {recorded}")
    if schema is not None and schema != 6:
        problems.append(f"the schema of the personal store of the operator is {schema}, not 6")
    for relative, payload in receipts.items():
        text = json.dumps(payload)
        if "schema 7" in text and "the_personal" in text and "unchanged" not in text:
            problems.append(f"the receipt {relative} speaks of the schema 7 of the personal store")
    return {
        "the_digest_of_the_personal_store": current,
        "the_expected_digest_of_the_personal_store": PERSONAL_STORE,
        "the_personal_store_is_untouched": current == PERSONAL_STORE,
        "the_schema_of_the_personal_store": schema,
        "the_rehearsal_recorded_the_same_digest": recorded == PERSONAL_STORE,
        "the_rehearsal_left_the_store_unchanged":
            recorded is not None and recorded == recorded_after,
        "the_activation_was_rehearsed_on_a_copy": activation.is_file(),
    }, problems


def check_the_canonical_state():
    """The canonical state of the record must name the release.

    The table of §1 of the state file names the revision of the product, the
    revision of the acceptance, the revision of the Core binary of the release
    and the number of the tracked files. Every one of them is checked against
    the manifest and the receipts: a table that drifts away from the release is
    a false statement in the record.
    """
    problems = []
    values = {}
    section = (ROOT / "docs/OIP_RELEASE_PROGRESS.md").read_text()
    section = section.split("## 1. Canonical state", 1)[-1].split("## 2.", 1)[0]
    for line in section.splitlines():
        if not line.startswith("| ") or "---" in line:
            continue
        cells = [cell.strip() for cell in line.strip("|").split("|")]
        if len(cells) == 2:
            values[cells[0]] = cells[1]
    manifest = json.loads((ROOT / "docs/release/oip-release-manifest.json").read_text())
    acceptance = json.loads(
        (ROOT / "docs/evidence/oip-canonical-acceptance/acceptance.json").read_text())
    source = git("log", "-1", "--format=%H", "--", "crates", "apps/flutter/lib")
    core = manifest.get("the_artifacts", {}).get("the_core", {}).get(
        "the_revision_the_binary_names")
    expected = {
        "Canonical source revision (the product: `apps/flutter/lib/`, `crates/`)": source,
        "The revision of the final acceptance": acceptance.get("the_revision"),
        "The revision of the Core binary of the release": core,
    }
    for label, wanted in expected.items():
        if not wanted:
            continue
        found = re.search(r"`([0-9a-f]{7,40})`", values.get(label, ""))
        if not found or not found.group(1).startswith(wanted[:len(found.group(1))]):
            problems.append(f"the canonical state names "
                            f"{found.group(1) if found else 'nothing'} for {label}, "
                            f"the release names {wanted[:12]}")
    files = manifest.get("the_source_manifest", {}).get("the_files")
    if files is not None:
        found = re.search(r"(\d+)", values.get("Tracked files in the canonical source revision", ""))
        if not found or int(found.group(1)) != files:
            problems.append(f"the canonical state names "
                            f"{found.group(1) if found else 'nothing'} tracked files, "
                            f"the manifest names {files}")
    uncommitted = git("status", "--porcelain", "--", "crates", "apps/flutter")
    if uncommitted:
        problems.append(f"the product of the release is not committed: {uncommitted[:200]}")
    return {
        "the_source_revision": source,
        "the_acceptance_revision": acceptance.get("the_revision"),
        "the_core_binary_revision": core,
        "the_tracked_files": files,
        "the_product_is_committed": not uncommitted,
    }, problems


def check_the_numbers_of_the_record():
    """The numbers of the record must be the numbers of the receipts.

    The record quotes the **properties** of the release; the receipts quote
    the **numbers** of a run. A number that a gate row quotes is a claim
    that the receipt it names carries that number — and a claim that drifts
    when the receipt is measured again is a false claim in the record.
    """
    problems = []
    result = subprocess.run(
        [sys.executable, str(ROOT / "tests/oip_record_numbers.py"),
         "--evidence", str(ROOT / "target" / "oip-record-numbers")],
        cwd=ROOT, capture_output=True, text=True, timeout=600)
    measured = {}
    try:
        measured = json.loads(result.stdout or "{}")
    except json.JSONDecodeError:
        problems.append("the numbers of the record could not be checked")
    problems.extend(measured.get("the_problems", []))
    return {
        "the_rows": measured.get("the_rows"),
        "the_measurements": measured.get("the_measurements"),
    }, problems


def the_gates():
    """The gate table of the ledger."""
    gates = []
    for line in LEDGER.read_text().splitlines():
        match = re.match(r"^\|\s*(G\d+)\s*([^|]*)\|\s*([^|]*)\|", line)
        if match:
            gates.append({"the_gate": match.group(1), "the_subject": match.group(2).strip(),
                          "the_status": match.group(3).strip()})
    return gates


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--receipt", default=None,
                        help="the path of the receipt of the verification")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    receipts = the_release_receipts()
    problems = []
    sections = {}
    for name, checker in (("the_manifest", check_the_manifest),
                          ("the_freshness", None),
                          ("the_record", None),
                          ("the_canonical_state", check_the_canonical_state),
                          ("the_numbers_of_the_record", check_the_numbers_of_the_record),
                          ("the_acceptance", check_the_acceptance),
                          ("the_boundaries", None)):
        if name == "the_freshness":
            section, found = check_the_freshness(receipts)
        elif name == "the_record":
            section, found = check_the_record(receipts)
        elif name == "the_boundaries":
            section, found = check_the_boundaries(receipts)
        else:
            section, found = checker()
        sections[name] = section
        problems.extend(found)

    gates = the_gates()
    open_gates = [gate for gate in gates if "BLOCKED_OPERATOR" in gate["the_status"]]
    verdict = "OIP_PRODUCTION_NOT_READY" if open_gates or problems else "OIP_PRODUCTION_READY_PASS"
    report = {
        "schema": "oip-release-verification-v1",
        "the_verdict": verdict,
        "the_note": "the verification of the tool is not a production acceptance: the "
                    "acceptance of the operator (G12) and the scope of the production "
                    "security (G10) are the operator's",
        "the_sections": sections,
        "the_gates": gates,
        "the_gates_that_need_the_operator": [gate["the_gate"] for gate in open_gates],
        "the_problems": problems,
        "the_revision": git("rev-parse", "HEAD"),
        "the_tree": git("rev-parse", "HEAD^{tree}"),
        "the_working_tree_is_clean": not git("status", "--porcelain"),
        "status": "PASS" if not problems else "FAIL",
    }
    if args.receipt:
        path = pathlib.Path(args.receipt)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(report, indent=2) + "\n")
    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(json.dumps({
            "the_verdict": verdict,
            "the_status_of_the_verification": report["status"],
            "the_problems": problems,
            "the_gates_that_need_the_operator": report["the_gates_that_need_the_operator"],
            "the_receipts_of_the_release": len(receipts),
            "the_note": "the receipts of the release: the JSON receipts of the areas "
                        "of the release; the checker of the record counts every file of "
                        "the evidence tree, the captures and the painted surfaces as well",
        }, indent=2))
    return 0 if not problems else 1


if __name__ == "__main__":
    raise SystemExit(main())
