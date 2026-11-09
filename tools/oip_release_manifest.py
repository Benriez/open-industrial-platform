#!/usr/bin/env python3
"""The release manifest of the current release.

The operator decides which artefacts may be signed and distributed. The
decision needs a list: every artefact of the release, its digest, the
provenance of its build and the receipt that proved it.

This tool writes that list and proves it:

  * `target/release/oip-server` — the Core;
  * `target/release/examples/mcp_probe` — the official MCP probe;
  * `apps/flutter/build/macos/Build/Products/Release/oip_dashboard.app` — the
    macOS application bundle (a digest over every file of the bundle);
  * `apps/flutter/build/web/` — the delivered web release (the digest of
    `main.dart.js` and the digest over every asset).

The manifest names the revision and the tree it was built from, the digest
over the tracked sources of that revision, the build commands, the toolchain
versions, the digests of the acceptance receipts and the state of the
operator's visual acceptance.

`--verify` recomputes every digest and compares it with the written manifest:
the manifest is a receipt, not a promise.

Usage:
  python3 tools/oip_release_manifest.py [--out DIR] [--verify]
"""
import argparse
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
ARTIFACTS = {
    "the_core": ROOT / "target/release/oip-server",
    "the_official_mcp_probe": ROOT / "target/release/examples/mcp_probe",
    "the_macos_application_bundle": ROOT / "apps/flutter/build/macos/Build/Products/Release/oip_dashboard.app",
    "the_web_release": ROOT / "apps/flutter/build/web",
}
def newest_gate_receipts():
    """The receipts of the newest canonical gate run.

    The gate writes its receipts into a directory of its own; the manifest
    names the newest run so that it never points at an older acceptance.
    """
    candidates = sorted((path for path in (ROOT / "target").glob("oip-canonical-regression*")
                         if path.is_dir()),
                        key=lambda path: path.stat().st_mtime)
    base = candidates[-1] if candidates else ROOT / "target/oip-canonical-regression"
    return {
        "the_canonical_gate": base / "oip_canonical_ui_gate/browser/browser-canonical-ui-gate.json",
        "the_canonical_ui_gate": base / "oip_canonical_ui_gate/canonical-ui/canonical-ui-gate.json",
        "the_acceptance_report": base / "oip_canonical_ui_gate/report.json",
    }


RECEIPTS = {
    "the_global_context": ROOT / "docs/evidence/oip-global-context/global-context.json",
    "the_accessibility": ROOT / "docs/evidence/oip-accessibility/accessibility.json",
    "the_performance": ROOT / "docs/evidence/oip-performance/performance.json",
    "the_security_review": ROOT / "docs/evidence/oip-security-review/security-review.json",
    "the_macos_application": ROOT / "docs/evidence/oip-macos-app/macos-app.json",
    "the_transport_parity": ROOT / "docs/evidence/oip-transport-parity/transport-parity.json",
    # The acceptance of the release itself, tracked with the release so that
    # the handoff does not depend on a directory of a build that is not part
    # of the checkout.
    "the_acceptance": ROOT / "docs/evidence/oip-canonical-acceptance/acceptance.json",
    "the_acceptance_browser_gate": ROOT / "docs/evidence/oip-canonical-acceptance/browser-gate.json",
    "the_acceptance_ui_gate": ROOT / "docs/evidence/oip-canonical-acceptance/ui-gate.json",
    "the_device_administration": ROOT / "docs/evidence/oip-device-administration/device-administration.json",
    "the_session_lifetime": ROOT / "docs/evidence/oip-session-lifetime/session-lifetime.json",
    "the_stability": ROOT / "docs/evidence/oip-stability/stability.json",
    "the_reproducible_build": ROOT / "docs/evidence/oip-reproducible-build/reproducible-build.json",
    "the_upgrade_rollback": ROOT / "docs/evidence/oip-upgrade-rollback/upgrade-rollback.json",
    "the_activation_dry_run": ROOT / "docs/evidence/oip-activation-dry-run/activation-dry-run.json",
    "the_rust_regression": ROOT / "docs/evidence/oip-rust-regression/rust-regression.json",
    "the_reconnect_recovery": ROOT / "docs/evidence/oip-reconnect-recovery/reconnect-recovery.json",
    "the_operations": ROOT / "docs/evidence/oip-operations/operations.json",
    "the_documented_plan": ROOT / "docs/evidence/oip-documented-plan/documented-plan.json",
    "the_storage_failure": ROOT / "docs/evidence/oip-storage-failure/storage-failure.json",
    "the_operations_rehearsal": ROOT / "docs/evidence/oip-operations/operations.json",
    "the_settings_offline": ROOT / "docs/evidence/oip-settings-offline/settings-offline.json",
    "the_offline_archive": ROOT / "docs/evidence/oip-offline-archive/offline-archive.json",
    "the_opcua_parity": ROOT / "docs/evidence/oip-opcua-parity/opcua-parity.json",
    "the_extend_registry": ROOT / "docs/evidence/oip-extend-registry/extend-registry.json",
    "the_historical_daemon": ROOT / "docs/evidence/oip-historical-daemon/historical-daemon.json",
    "the_diagnostic_continuation": ROOT / "docs/evidence/oip-diagnostic-continuation/diagnostic-continuation.json",
    "the_device_connection": ROOT / "docs/evidence/oip-device-connection/device-connection.json",
    "the_workstation_data": ROOT / "docs/evidence/oip-workstation-data/workstation-data.json",
}


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def digest_tree(root):
    """The digest over every file of a directory and its file list.

    The digest is over the sorted list of the relative paths and their
    contents, so it is independent of the order of the file system.
    """
    entries = []
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(root).as_posix()
        entries.append({"path": relative, "bytes": path.stat().st_size,
                        "sha256": sha256_file(path)})
    digest = hashlib.sha256()
    for entry in entries:
        digest.update(entry["path"].encode())
        digest.update(b"\0")
        digest.update(entry["sha256"].encode())
        digest.update(b"\0")
    return digest.hexdigest(), entries


def tool_version(command):
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=120)
        return (result.stdout or result.stderr).strip().splitlines()[0]
    except Exception:
        return "unknown"


def git(*arguments):
    result = subprocess.run(["git", *arguments], cwd=ROOT, capture_output=True, text=True)
    return result.stdout.strip()


def source_revision():
    """The revision of the product source.

    The commits that change only the record — the ledger, the receipts, the
    manifest — do not change the product. The manifest therefore names the
    revision of the product separately from the revision of the branch: the
    artefacts of the release belong to the former.
    """
    result = subprocess.run(
        ["git", "log", "-1", "--format=%H %s", "--", "apps", "crates"],
        cwd=ROOT, capture_output=True, text=True)
    line = result.stdout.strip()
    if not line:
        return None
    revision, _, subject = line.partition(" ")
    return {"the_revision": revision, "the_subject": subject}


def tree_is_clean(exclude=("docs/release/",)):
    """The cleanliness of the working tree without the files of the manifest.

    The manifest writes itself into the tree, so the tree can never be clean
    while the manifest is written. The state that matters is the state of
    everything else.
    """
    status = git("status", "--porcelain")
    lines = [line for line in status.splitlines()
             if line and not any(line[3:].startswith(prefix) for prefix in exclude)]
    return not lines, lines


def source_manifest():
    """The digest over the tracked sources of the revision.

    `git ls-files -s` writes the mode, the blob and the path of every tracked
    file of the index, in the order of the index. The digest over that list
    identifies the sources of the release; a reader recomputes it with the
    same command.
    """
    listing = git("ls-files", "-s")
    digest = hashlib.sha256(listing.encode()).hexdigest()
    files = len([line for line in listing.splitlines() if line.strip()])
    return {"the_command": "git ls-files -s", "the_files": files,
            "the_sha256": digest}


def build_manifest():
    manifest = {
        "schema": "oip-release-manifest-v1",
        "the_revision": git("rev-parse", "HEAD"),
        "the_tree": git("rev-parse", "HEAD^{tree}"),
        "the_branch": git("rev-parse", "--abbrev-ref", "HEAD"),
        "the_revision_of_the_source": source_revision(),
        "the_working_tree_is_clean": tree_is_clean()[0],
        "the_toolchain": {
            "rustc": tool_version(["rustc", "--version"]),
            "cargo": tool_version(["cargo", "--version"]),
            "flutter": tool_version(["flutter", "--version"]),
            "dart": tool_version(["dart", "--version"]),
        },
        "the_build_commands": {
            "the_core": "cargo build --locked --release --workspace --bin oip-server "
                       "--example mcp_probe",
            "the_web_release": ("flutter build web --release --web-renderer canvaskit "
                                "--no-web-resources-cdn --pwa-strategy=none"),
            "the_macos_application_bundle": ("flutter build macos --release "
                                              "--dart-define=OIP_API_URL=<url of the instance>"),
        },
        "the_source_manifest": source_manifest(),
        "the_artifacts": {},
        "the_receipts": {},
        "the_gate_run_of_the_acceptance": str(
            newest_gate_receipts()["the_acceptance_report"].parent.parent),
        "the_digests_are_verifiable_in": (
            "the build environment of the release: the artefacts live in the "
            "build tree (target/ and apps/flutter/build/), the receipts live in "
            "the checkout (docs/evidence/). In a checkout without the build "
            "tree the artefacts are absent and `--verify` reports that."),
        "the_working_tree_without_the_manifest": tree_is_clean()[1],
    }
    for name, path in ARTIFACTS.items():
        if not path.exists():
            manifest["the_artifacts"][name] = {"present": False, "path": str(path)}
            continue
        if path.is_file():
            manifest["the_artifacts"][name] = {
                "present": True, "path": str(path.relative_to(ROOT)),
                "bytes": path.stat().st_size, "sha256": sha256_file(path),
            }
            continue
        digest, entries = digest_tree(path)
        entry = {
            "present": True, "path": str(path.relative_to(ROOT)),
            "files": len(entries), "bytes": sum(item["bytes"] for item in entries),
            "sha256": digest,
        }
        if name == "the_web_release":
            main = path / "main.dart.js"
            entry["the_main_bundle_sha256"] = sha256_file(main) if main.is_file() else None
            entry["the_main_bundle_bytes"] = main.stat().st_size if main.is_file() else None
        manifest["the_artifacts"][name] = entry
        if name == "the_macos_application_bundle":
            manifest["the_artifacts"][name]["the_executable_sha256"] = next(
                (item["sha256"] for item in entries
                 if item["path"] == "Contents/MacOS/oip_dashboard"), None)
        if name == "the_core":
            # The Core names the revision it was built from in its own binary.
            # The rehearsal of the reproducible builds reads that revision out
            # of the binary; the manifest states the revision of the binary
            # that it digests.
            payload = path.read_bytes()
            revision = git("rev-parse", "HEAD")
            for candidate in (revision, revision + "-dirty"):
                if candidate and candidate.encode() in payload:
                    manifest["the_artifacts"][name]["the_revision_the_binary_names"] = candidate
                    break
    # The receipts of the acceptance are **tracked** files; the receipts of a
    # run in the build tree are named by the run, not by the manifest, because
    # a manifest must be verifiable against the files of the checkout.
    receipts = dict(RECEIPTS)
    for name, path in receipts.items():
        if path.is_file():
            manifest["the_receipts"][name] = {
                "path": str(path.relative_to(ROOT)), "sha256": sha256_file(path),
            }
        else:
            manifest["the_receipts"][name] = {"present": False, "path": str(path)}
    # The revision the acceptance proved. The artefacts of the manifest are the
    # ones of that run; the tree may carry documentation commits after it.
    gate = receipts.get("the_canonical_ui_gate")
    if gate is not None and gate.is_file():
        payload = json.loads(gate.read_text())
        manifest["the_revision_of_the_acceptance"] = payload.get("source_revision")
        manifest["the_tree_of_the_acceptance"] = payload.get("source_tree")
        manifest["the_acceptance_was_run_on_a_clean_tree"] = payload.get("source_dirty") is False
    # The Core that the manifest names must be the reproducible one: the
    # rehearsal of the reproducible builds builds it twice and records the
    # digest of both builds.
    reproducible = (ROOT / "docs/evidence/oip-reproducible-build/reproducible-build.json")
    core = manifest["the_artifacts"].get("the_core", {})
    if reproducible.is_file() and core.get("sha256"):
        payload = json.loads(reproducible.read_text())
        measured = payload.get("the_core", {})
        manifest["the_core_is_the_reproducible_one"] = {
            "the_receipt": reproducible.relative_to(ROOT).as_posix(),
            "the_digest_of_the_reproducible_build": measured.get("the_core_of_the_second_build"),
            "the_core_is_identical_across_the_two_builds": measured.get("the_core_is_identical"),
            "the_manifest_names_the_reproducible_binary":
                measured.get("the_core_of_the_second_build") == core.get("sha256"),
            "the_revision_the_binary_names": measured.get("the_revision_the_binary_names"),
        }
        if manifest["the_core_is_the_reproducible_one"]["the_manifest_names_the_reproducible_binary"]:
            manifest["the_artifacts"]["the_core"]["the_revision_the_binary_names"] = \
                measured.get("the_revision_the_binary_names")
    # The state of the visual acceptance of the operator. It is recorded by the
    # gate itself and it is never a claim of this tool. The tracked receipt of
    # the acceptance is the source of the state, so the handoff does not
    # depend on a directory of a build that is not part of the checkout.
    for browser in (RECEIPTS["the_acceptance_browser_gate"],
                    receipts.get("the_canonical_gate")):
        if browser is not None and browser.is_file():
            payload = json.loads(browser.read_text())
            manifest["the_visual_acceptance"] = {
                "the_state": payload.get("operator_visual_approval"),
                "the_source": str(browser.relative_to(ROOT)),
                "the_revision_of_the_acceptance": payload.get("revision")
                or payload.get("the_revision_of_the_acceptance"),
                "the_note": ("the operator alone accepts the visible result; "
                             "the gate records the state, it never grants it"),
            }
            break
    return manifest


def write_manifest(manifest, out):
    out.mkdir(parents=True, exist_ok=True)
    (out / "oip-release-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    lines = []
    for name, artifact in sorted(manifest["the_artifacts"].items()):
        if artifact.get("present") and artifact.get("sha256"):
            lines.append(f"{artifact['sha256']}  {artifact['path']}")
    for name, receipt in sorted(manifest["the_receipts"].items()):
        if receipt.get("sha256"):
            lines.append(f"{receipt['sha256']}  {receipt['path']}")
    (out / "SHA256SUMS").write_text("\n".join(lines) + "\n")


def verify(manifest, out):
    """Every digest of the written manifest is recomputed."""
    problems = []
    for name, artifact in manifest["the_artifacts"].items():
        path = ROOT / artifact["path"]
        if not artifact.get("present"):
            problems.append(f"{name}: the artefact is absent")
            continue
        if path.is_file():
            digest = sha256_file(path)
        else:
            digest, _ = digest_tree(path)
        if digest != artifact.get("sha256"):
            problems.append(f"{name}: {digest} != {artifact.get('sha256')}")
    for name, receipt in manifest["the_receipts"].items():
        path = ROOT / receipt["path"]
        if not receipt.get("sha256"):
            continue
        if not path.is_file():
            problems.append(f"{name}: the receipt is absent")
            continue
        if sha256_file(path) != receipt["sha256"]:
            problems.append(f"{name}: the receipt changed")
    written = (out / "SHA256SUMS").read_text().splitlines()
    for line in written:
        digest, name = line.split("  ", 1)
        path = ROOT / name
        if not path.exists():
            problems.append(f"{name}: the file of the checksum list is absent")
            continue
        if path.is_file():
            recomputed = sha256_file(path)
        else:
            recomputed, _ = digest_tree(path)
        if recomputed != digest:
            problems.append(f"{name}: the checksum does not match")
    return problems


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=str(ROOT / "docs/release"))
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    out = pathlib.Path(args.out)

    if args.verify:
        manifest = json.loads((out / "oip-release-manifest.json").read_text())
        problems = verify(manifest, out)
        print(json.dumps({"verified": not problems, "problems": problems}, indent=2))
        return 0 if not problems else 1

    manifest = build_manifest()
    write_manifest(manifest, out)
    problems = verify(manifest, out)
    manifest["the_manifest_verifies"] = not problems
    manifest["the_problems"] = problems
    (out / "oip-release-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({
        "the_revision": manifest["the_revision"],
        "the_tree": manifest["the_tree"],
        "the_artifacts": {name: artifact.get("sha256")
                          for name, artifact in manifest["the_artifacts"].items()},
        "the_manifest_verifies": manifest["the_manifest_verifies"],
        "the_problems": problems,
    }, indent=2))
    return 0 if manifest["the_manifest_verifies"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
