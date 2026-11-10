#!/usr/bin/env python3
"""Re-measure the evidence of the release and publish it.

The receipts of the release live under `docs/evidence/`. Each of them is
measured by a **rehearsal** — a script that drives the real Core against a
disposable instance and writes a receipt into a directory of its own. The
handoff must not depend on a directory of a build, so every rehearsal has a
published place in the checkout.

This tool runs the rehearsals in the order of the release and copies every
receipt into its published place. It is the way to re-measure the evidence
after a change of the product: the freshness rule of the record demands that
no receipt predates the last change of the code it covers.

Nothing of the tool touches the personal installation of the operator, no
private endpoint is contacted and nothing leaves the machine. The tree must be
clean: a receipt that is measured on a dirty tree says so.

Usage:
  python3 tools/oip_refresh_evidence.py [--list] [--only NAME] [--skip NAME]
"""
import argparse
import json
import pathlib
import shutil
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "docs" / "evidence"

# The rehearsals of the release, in the order they are run, with the receipt
# that each one writes and the place where it is published. The order puts
# the quick ones first and the sustained runs last.
REHEARSALS = [
    ("oip_record_integrity", "tests/oip_record_integrity.py",
     {"record-integrity.json": "oip-record-integrity/record-integrity.json"}),
    ("oip_documented_plan", "tests/oip_documented_plan.py",
     {"documented-plan.json": "oip-documented-plan/documented-plan.json"}),
    ("oip_session_lifetime", "tests/oip_session_lifetime.py",
     {"session-lifetime.json": "oip-session-lifetime/session-lifetime.json"}),
    ("oip_native_session", "tests/oip_native_session.py",
     {"native-session.json": "oip-native-session/native-session.json"}),
    ("oip_settings_offline", "tests/oip_settings_offline.py",
     {"settings-offline.json": "oip-settings-offline/settings-offline.json"}),
    ("oip_offline_archive", "tests/oip_offline_archive.py",
     {"offline-archive.json": "oip-offline-archive/offline-archive.json"}),
    ("oip_extend_registry", "tests/oip_extend_registry.py",
     {"extend-registry.json": "oip-extend-registry/extend-registry.json"}),
    ("oip_activation_dry_run", "tests/oip_activation_dry_run.py",
     {"activation-dry-run.json": "oip-activation-dry-run/activation-dry-run.json"}),
    ("oip_transport_parity", "tests/oip_transport_parity.py",
     {"transport-parity.json": "oip-transport-parity/transport-parity.json"}),
    ("oip_opcua_parity", "tests/oip_opcua_parity.py",
     {"opcua-parity.json": "oip-opcua-parity/opcua-parity.json"}),
    ("oip_device_connection", "tests/oip_device_connection.py",
     {"device-connection-rehearsal.json": "oip-device-connection/rehearsal.json",
      "device-connection.json": "oip-device-connection/device-connection.json",
      "device-connection-surface.txt": "oip-device-connection/painted-surface.txt"}),
    ("oip_measurement_coverage", "tests/oip_measurement_coverage.py",
     {"measurement-coverage.json": "oip-measurement-coverage/measurement-coverage.json",
      "measurement-coverage-browser.json":
          "oip-measurement-coverage/measurement-coverage-browser.json",
      "device-connection-surface.txt":
          "oip-measurement-coverage/painted-surface.txt"}),
    ("oip_observation_history", "tests/oip_observation_history.py",
     {"observation-history.json": "oip-observation-history/observation-history.json"}),
    ("oip_scope_persistence", "tests/oip_scope_persistence.py",
     {"scope-persistence-rehearsal.json":
          "oip-scope-persistence/scope-persistence-rehearsal.json",
      "scope-persistence.json": "oip-scope-persistence/scope-persistence.json"}),
    ("oip_connection_states", "tests/oip_connection_states.py",
     {"connection-states-rehearsal.json":
          "oip-connection-states/connection-states-rehearsal.json",
      "connection-states.json": "oip-connection-states/connection-states.json"}),
    ("oip_settings_status", "tests/oip_settings_status.py",
     {"settings-status-rehearsal.json": "oip-settings-status/settings-status-rehearsal.json",
      "settings-status.json": "oip-settings-status/settings-status.json",
      "settings-status-surface.txt": "oip-settings-status/painted-surface.txt"}),
    ("oip_diagnostic_continuation", "tests/oip_diagnostic_continuation.py",
     {"diagnostic-continuation-rehearsal.json":
          "oip-diagnostic-continuation/rehearsal.json",
      "diagnostic-continuation.json":
          "oip-diagnostic-continuation/diagnostic-continuation.json"}),
    ("oip_workstation_data", "tests/oip_workstation_data.py",
     {"workstation-data-rehearsal.json": "oip-workstation-data/rehearsal.json",
      "workstation-data.json": "oip-workstation-data/workstation-data.json"}),
    ("oip_reconnect_recovery", "tests/oip_reconnect_recovery.py",
     {"reconnect-recovery-rehearsal.json": "oip-reconnect-recovery/rehearsal.json",
      "reconnect-recovery.json": "oip-reconnect-recovery/reconnect-recovery.json"}),
    ("oip_operations", "tests/oip_operations.py",
     {"operations.json": "oip-operations/operations.json"}),
    ("oip_storage_failure", "tests/oip_storage_failure.py",
     {"storage-failure.json": "oip-storage-failure/storage-failure.json"}),
    ("oip_upgrade_rollback", "tests/oip_upgrade_rollback.py",
     {"upgrade-rollback.json": "oip-upgrade-rollback/upgrade-rollback.json"}),
    ("oip_historical_daemon", "tests/oip_historical_daemon.py",
     {"historical-daemon.json": "oip-historical-daemon/historical-daemon.json"}),
    ("oip_macos_app", "tests/oip_macos_app.py",
     {"macos-app.json": "oip-macos-app/macos-app.json"}),
    ("oip_macos_install", "tests/oip_macos_install.py",
     {"macos-install.json": "oip-macos-install/macos-install.json"}),
    ("oip_performance", "tests/oip_performance.py",
     {"performance.json": "oip-performance/performance.json"}),
    ("oip_loopback_rate", "tests/oip_loopback_rate.py",
     {"loopback-rate.json": "oip-loopback-rate/loopback-rate.json"}),
    ("oip_stability", "tests/oip_stability.py",
     {"stability.json": "oip-stability/stability.json"}),
    ("oip_worktree_reconciliation", "tests/oip_worktree_reconciliation.py",
     {"worktree-reconciliation.json":
          "oip-worktree-reconciliation/worktree-reconciliation.json"}),
    ("oip_security_review", "tests/oip_security_review.py",
     {"security-review.json": "oip-security-review/security-review.json"}),
    ("oip_rust_regression", "tests/oip_rust_regression.py",
     {"rust-regression.json": "oip-rust-regression/rust-regression.json"}),
    ("oip_reproducible_build", "tests/oip_reproducible_build.py",
     {"reproducible-build.json": "oip-reproducible-build/reproducible-build.json"}),
]


def the_area(area):
    """The directory of the build that a rehearsal writes into."""
    return ROOT / "target" / area


def run(name, script, receipts):
    """One rehearsal and every receipt it writes.

    A rehearsal runs **once** and writes more than one receipt: the receipt of
    the rehearsal and the receipt of the browser journey it drives. Running
    the rehearsal twice would measure the same thing twice and give a second
    chance to a flake.
    """
    area = the_area(sorted(receipts.values())[0].split("/")[0])
    area.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    result = subprocess.run([sys.executable, str(ROOT / script), "--evidence", str(area)],
                            cwd=ROOT, capture_output=True, text=True, timeout=7200)
    seconds = round(time.monotonic() - started, 1)
    sources = {}
    missing = []
    payloads = []
    for produced, published in receipts.items():
        source = area / produced
        if not source.is_file():
            missing.append(published)
            continue
        sources[published] = str(source.relative_to(ROOT))
        if produced.endswith(".json"):
            payloads.append(json.loads(source.read_text()))
    if result.returncode != 0 or missing:
        detail = (result.stderr.strip() or result.stdout.strip())[-400:]
        return {"the_rehearsal": name, "the_status": "FAIL", "the_seconds": seconds,
                "the_detail": detail, "the_missing": missing}
    # The status is the state of the rehearsal. The receipt of a browser
    # journey carries no status of its own.
    statuses = [item.get("status") for item in payloads if "status" in item]
    the_status = "FAIL" if "FAIL" in statuses else "PASS"
    the_revision = next((item.get("the_revision") for item in payloads
                         if item.get("the_revision")), None)
    the_clean = next((item.get("the_working_tree_is_clean") for item in payloads
                      if "the_working_tree_is_clean" in item), None)
    return {
        "the_rehearsal": name,
        "the_status": the_status,
        "the_seconds": seconds,
        "the_published": sorted(receipts.values()),
        "the_sources": sources,
        "the_revision": the_revision,
        "the_working_tree_is_clean": the_clean,
        "the_detail": None if the_status == "PASS"
        else json.dumps([item for item in payloads if item.get("status") == "FAIL"])[:400],
    }


def publish(outcomes):
    """The receipts are published after the last rehearsal.

    A publication writes into the checkout — the tree would be dirty for every
    rehearsal that follows. The receipts are therefore measured on a clean
    tree and published together at the end.
    """
    published = []
    for item in outcomes:
        if item["the_status"] != "PASS" or "the_sources" not in item:
            continue
        for place, source in item["the_sources"].items():
            target = EVIDENCE / place
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / source, target)
            published.append(place)
    return published



def publish_only(name, receipts):
    """The receipts of the last run, published without measuring them again."""
    area = the_area(sorted(receipts.values())[0].split("/")[0])
    sources = {}
    missing = []
    for produced, published in receipts.items():
        source = area / produced
        if not source.is_file():
            missing.append(published)
            continue
        sources[published] = str(source.relative_to(ROOT))
    return {
        "the_rehearsal": name,
        "the_status": "PASS" if sources and not missing else "FAIL",
        "the_seconds": 0,
        "the_published": sorted(receipts.values()),
        "the_sources": sources,
        "the_missing": missing,
        "the_detail": None if sources and not missing else f"the missing receipts: {missing}",
    }

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--list", action="store_true",
                        help="the rehearsals and the receipts they publish")
    parser.add_argument("--only", action="append", default=[],
                        help="run only this rehearsal (repeatable)")
    parser.add_argument("--skip", action="append", default=[],
                        help="do not run this rehearsal (repeatable)")
    parser.add_argument("--report", default=str(ROOT / "target" / "oip-refresh-evidence.json"))
    parser.add_argument("--publish-only", action="store_true",
                        help="publish the receipts that the last run measured, "
                             "without measuring them again")
    args = parser.parse_args()

    if args.list:
        for name, script, receipts in REHEARSALS:
            print(f"{name:38s} {script:42s} -> {', '.join(receipts.values())}")
        return 0

    # A receipt that is measured on a dirty tree says so; the tool refuses to
    # publish a measurement of a tree that carries an uncommitted change.
    dirty = subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT,
                                    text=True).strip()
    if dirty:
        print("the tree is not clean — the receipts would name a dirty tree:")
        print(dirty[:800])
        return 2

    report = {"schema": "oip-refresh-evidence-v1", "the_rehearsals": []}
    for name, script, receipts in REHEARSALS:
        if args.only and name not in args.only:
            continue
        if name in args.skip:
            continue
        if args.publish_only:
            # The receipts of the last run are published without being
            # measured again.
            outcome = publish_only(name, receipts)
            report["the_rehearsals"].append(outcome)
            print(f"PUB {name}: {outcome['the_status']}", flush=True)
            continue
        print(f"RUN {name}", flush=True)
        outcome = run(name, script, receipts)
        report["the_rehearsals"].append(outcome)
        print(f"  {outcome['the_status']} {outcome['the_seconds']}s {name}", flush=True)
    report["the_published"] = publish(report["the_rehearsals"])
    failed = [item for item in report["the_rehearsals"] if item["the_status"] != "PASS"]
    report["the_failed"] = failed
    report["the_status"] = "PASS" if not failed else "FAIL"
    report["the_revision"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    pathlib.Path(args.report).write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"the_status": report["the_status"],
                      "the_rehearsals": len(report["the_rehearsals"]),
                      "the_published": len(report["the_published"]),
                      "the_failed": [item["the_rehearsal"] for item in failed]}, indent=2))
    return 0 if report["the_status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
