#!/usr/bin/env python3
"""The reproducibility of the builds of the release (G9).

The gate G9 asks for a **reproducible** macOS application build. The web
release is compared with the local build by the design regression gate — but
that is the *same* build. This rehearsal builds the release **twice** and
compares the artefacts:

  * the web release: two builds of `flutter build web --release` must deliver
    the byte-identical `main.dart.js` and the byte-identical asset tree;
  * the macOS application bundle: two builds of `flutter build macos --release`
    from an emptied build directory must deliver the byte-identical bundle.

The digests are taken over the sorted list of the paths and their contents, so
they do not depend on the order of the file system.

Nothing of the rehearsal touches the personal installation of the operator and
nothing leaves the machine.

Usage:
  python3 tests/oip_reproducible_build.py [--evidence DIR] [--skip-macos]
"""
import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
APPS = ROOT / "apps/flutter"
WEB = APPS / "build/web"
MACOS = APPS / "build/macos/Build/Products/Release/oip_dashboard.app"
WEB_COMMAND = ["flutter", "build", "web", "--release", "--web-renderer", "canvaskit",
               "--no-web-resources-cdn", "--pwa-strategy=none"]
# The release bundle is built for the port of the documented configuration of
# an instance (18808). The reproducibility is proved for **that** bundle, so
# the artefact of the rehearsal is the artefact of the release.
RELEASE_PORT = 18808
MACOS_COMMAND = ["flutter", "build", "macos", "--release",
                  f"--dart-define=OIP_API_URL=http://127.0.0.1:{RELEASE_PORT}"]


def digest_tree(root):
    """The digest over every file of a directory and the digests of the files."""
    entries = {}
    for path in sorted(root.rglob("*")):
        if path.is_file():
            entries[path.relative_to(root).as_posix()] = hashlib.sha256(
                path.read_bytes()).hexdigest()
    digest = hashlib.sha256()
    for name, value in entries.items():
        digest.update(name.encode())
        digest.update(b"\0")
        digest.update(value.encode())
        digest.update(b"\0")
    return digest.hexdigest(), entries


def build(command, timeout=3600, cwd=None):
    began = time.monotonic()
    result = subprocess.run(command, cwd=cwd or APPS, capture_output=True, text=True,
                            timeout=timeout)
    if result.returncode != 0:
        raise AssertionError(f"the build failed: {result.stderr[-400:] or result.stdout[-400:]}")
    return round(time.monotonic() - began, 1)


def sha256_of(path):
    """The digest of a file, or None when it is absent."""
    if not path.is_file():
        return None
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def empty(path):
    """Empties a directory without removing the directory itself."""
    if not path.exists():
        return
    for child in path.iterdir():
        if child.is_dir():
            shutil.rmtree(child)
        else:
            child.unlink()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-reproducible-build"))
    parser.add_argument("--skip-macos", action="store_true")
    parser.add_argument("--skip-core", action="store_true")
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-reproducible-build-v1", "steps": []}

    try:
        # 1. the web release, twice
        seconds = build(WEB_COMMAND)
        first_main = hashlib.sha256((WEB / "main.dart.js").read_bytes()).hexdigest()
        first_web, first_entries = digest_tree(WEB)
        report["the_web_release"] = {"the_command": " ".join(WEB_COMMAND),
                                     "the_first_build_seconds": seconds,
                                     "the_main_bundle_sha256": first_main,
                                     "the_tree_sha256": first_web,
                                     "the_files": len(first_entries)}
        empty(WEB)
        seconds = build(WEB_COMMAND)
        second_main = hashlib.sha256((WEB / "main.dart.js").read_bytes()).hexdigest()
        second_web, second_entries = digest_tree(WEB)
        report["the_web_release"].update({
            "the_second_build_seconds": seconds,
            "the_main_bundle_of_the_second_build": second_main,
            "the_tree_of_the_second_build": second_web,
            "the_main_bundle_is_identical": first_main == second_main,
            "the_tree_is_identical": first_web == second_web,
            "the_files_that_differ": [name for name, value in second_entries.items()
                                      if first_entries.get(name) != value],
        })
        assert first_main == second_main, "the web release is not reproducible"
        assert first_web == second_web, "the asset tree of the web release is not reproducible"
        report["steps"].append("the web release is reproducible")

        if not args.skip_macos:
            # 2. the macOS bundle, twice and from an emptied build directory
            empty(APPS / "build/macos")
            seconds = build(MACOS_COMMAND)
            first_macos, first_entries = digest_tree(MACOS)
            report["the_macos_bundle"] = {
                "the_command": " ".join(MACOS_COMMAND),
                "the_first_build_seconds": seconds,
                "the_tree_sha256": first_macos, "the_files": len(first_entries)}
            empty(APPS / "build/macos")
            seconds = build(MACOS_COMMAND)
            second_macos, second_entries = digest_tree(MACOS)
            report["the_macos_bundle"].update({
                "the_second_build_seconds": seconds,
                "the_tree_of_the_second_build": second_macos,
                "the_tree_is_identical": first_macos == second_macos,
                "the_files_that_differ": [name for name, value in second_entries.items()
                                          if first_entries.get(name) != value],
            })
            assert first_macos == second_macos, "the macOS bundle is not reproducible"
            report["steps"].append("the macOS bundle is reproducible")

            # 3. the reproducible bundle is the bundle of the release. The
            # rehearsal of the bundle of the release recorded the digest of
            # its tree; the tree of the reproduction must be that tree.
            released = ROOT / "docs/evidence/oip-macos-app/macos-app.json"
            if released.is_file():
                receipt = json.loads(released.read_text())
                expected = receipt.get("bundle_tree_sha256")
                report["the_release_bundle"] = {
                    "the_receipt": released.relative_to(ROOT).as_posix(),
                    "the_revision_of_the_receipt": receipt.get("the_revision"),
                    "the_tree_sha256_of_the_release_bundle": expected,
                    "the_reproduction_is_the_release_bundle": expected == first_macos,
                }
                if expected:
                    assert first_macos == expected, (
                        "the reproducible bundle is not the bundle of the release")

        # 4. the Core of the release, built twice. The operator signs the
        # binaries of the release; a binary that changes from build to build
        # cannot be signed by its digest. The build is forced by removing the
        # artefacts, not by touching the sources.
        if not args.skip_core:
            core = ROOT / "target/release/oip-server"
            probe = ROOT / "target/release/examples/mcp_probe"
            before = (sha256_of(core), sha256_of(probe))
            for artefact in (core, probe):
                if artefact.exists():
                    artefact.unlink()
            seconds = build(["cargo", "build", "--locked", "--release",
                             "--bin", "oip-server", "--example", "mcp_probe"],
                            cwd=ROOT)
            after = (sha256_of(core), sha256_of(probe))
            report["the_core"] = {
                "the_command": "cargo build --locked --release --bin oip-server "
                               "--example mcp_probe",
                "the_rebuild_seconds": seconds,
                "the_core_before": before[0],
                "the_core_after": after[0],
                "the_probe_before": before[1],
                "the_probe_after": after[1],
                "the_core_is_identical": before[0] == after[0],
                "the_probe_is_identical": before[1] == after[1],
            }
            assert before[0] == after[0], "the Core of the release is not reproducible"
            assert before[1] == after[1], "the probe of the release is not reproducible"
            report["steps"].append("the Core of the release is reproducible")

        report["status"] = "PASS"
    except AssertionError as error:
        report["status"] = "FAIL"
        report["error"] = str(error)
    finally:
    # The revision the receipt was measured on: a reader of the evidence must
        # be able to tell whether it is current.
        report["the_revision"] = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        report["the_tree"] = subprocess.check_output(
            ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip()
        report["the_working_tree_is_clean"] = not subprocess.check_output(
            ["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()
        report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        (evidence / "reproducible-build.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps({k: v for k, v in report.items() if k != "steps"}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
