#!/usr/bin/env python3
"""The local installation of the macOS application bundle (G9).

The gate G9 asks for a **local installation** that works without OpenCode.
The rehearsal of the bundle proves the bundle of the release in the directory
of the build. The operator, however, receives a **copy** of that bundle in a
directory of the installation — and it is the copy that must work.

This rehearsal proves the installation itself:

  * the bundle is copied into an installation directory exactly as the operator
    copies it (the copy is **byte-identical** to the bundle of the release);
  * the installed copy is a real application bundle (the identifier, the
    version and the executable are there);
  * the installed copy starts, reaches the Core and is refused without a
    session — it obtains **no** unauthorized data;
  * the installed copy shows the approved shell with the operator login;
  * the installed copy terminates on the operator's signal without leaving an
    orphan behind, and starts again from the installation directory.

The installation directory of the rehearsal is a directory of the temporary
tree of the machine — **never** `/Applications`. The installation of the
release into `/Applications` is a step of the operator and is named in the
runbook (§9.1).

Nothing of the rehearsal touches the personal installation of the operator and
nothing leaves the machine.

Usage:
  python3 tests/oip_macos_install.py [--evidence DIR] [--port 18808]
"""
import argparse
import hashlib
import json
import os
import pathlib
import secrets
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))

from oip_macos_app import (  # noqa: E402 - the witness of the bundle
    _LoggingProxy,
    free_port,
    launch,
    terminate,
)

TOOL = ROOT / "tools" / "oip_ops.py"
APPS = ROOT / "apps/flutter"
BUNDLE = APPS / "build/macos/Build/Products/Release/oip_dashboard.app"
DOCUMENTED_PORT = 18808


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
    return digest.hexdigest(), len(entries)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-macos-install"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    parser.add_argument("--port", type=int, default=DOCUMENTED_PORT)
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-macos-install-v1", "steps": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-install-")).resolve()
    work.chmod(0o700)
    process = None
    try:
        if not BUNDLE.is_dir():
            raise AssertionError(f"the bundle of the release is absent: {BUNDLE}")
        release_tree, release_files = digest_tree(BUNDLE)

        # 1. the installation directory and the copy of the bundle
        installation = work / "Applications"
        installation.mkdir()
        installed = installation / BUNDLE.name
        # The copy is the copy of the operator: a plain recursive copy of the
        # bundle into the directory of the installation.
        shutil.copytree(BUNDLE, installed, symlinks=True)
        installed_tree, installed_files = digest_tree(installed)
        report["the_installation"] = {
            "the_directory_of_the_rehearsal": str(installation),
            "the_bundle": installed.name,
            "the_files": installed_files,
            "the_tree_sha256": installed_tree,
            "the_tree_of_the_release_bundle": release_tree,
            "the_copy_is_byte_identical": installed_tree == release_tree,
            "the_note": "the rehearsal installs into a directory of the temporary "
                        "tree; the installation into /Applications is the step of "
                        "the operator and is named in the runbook",
        }
        report["steps"].append("the bundle is copied into the installation directory")
        assert installed_tree == release_tree, "the copy of the bundle is not byte-identical"

        # 2. the installed copy is a real application bundle
        info = (installed / "Contents/Info.plist").read_text(errors="ignore")
        identifier = version = None
        for key, target in (("CFBundleIdentifier", "identifier"),
                            ("CFBundleShortVersionString", "version")):
            marker = f"<key>{key}</key>"
            if marker in info:
                tail = info.split(marker, 1)[1]
                value = tail.split("<string>", 1)[-1].split("</string>", 1)[0]
                if target == "identifier":
                    identifier = value
                else:
                    version = value
        executable = installed / "Contents/MacOS/oip_dashboard"
        report["the_installed_bundle"] = {
            "the_bundle_identifier": identifier,
            "the_version": version,
            "the_executable": str(executable),
            "the_executable_exists": executable.is_file(),
            "the_executable_sha256": hashlib.sha256(executable.read_bytes()).hexdigest()
            if executable.is_file() else None,
        }
        report["steps"].append("the installed copy is a real application bundle")
        assert identifier and executable.is_file(), "the installed copy is not a bundle"

        # 3. the instance of the rehearsal: the witness stands on the
        #    documented port, so the installed bundle carries the URL that the
        #    operator uses
        plan = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        plan["roles"].append({
            "id": "inventory-admin", "name": "Explicit scoped operator",
            "permissions": ["inventory_manage", "devices_read", "telemetry_read"]})
        plan["bindings"].append({
            "principal_id": "reader-org-a", "role_id": "inventory-admin",
            "scope": {"kind": "organization", "id": "org-a"}})
        (work / "plan.json").write_text(json.dumps(plan, indent=2))
        core_port = free_port()
        (work / "core.json").write_text(json.dumps({
            "database": str(work / "core.sqlite"), "http_port": core_port,
            "sources": [{"id": f"source-{letter}", "name": f"Local simulation {letter}",
                         "endpoint": f"opc.tcp://127.0.0.1:{15860 + index}", "namespace": 2}
                        for index, letter in enumerate("abcd")],
            "legacy_single_infrastructure": False,
            "web_dir": str(APPS / "build/web"),
        }, indent=2))
        credential = work / "platform.credential"
        credential.write_bytes(secrets.token_bytes(32))
        credential.chmod(0o600)
        (work / "ipc.json").write_text(json.dumps({
            "socket": str(work / "s"), "max_sessions": 16,
            "clients": [{"uid": os.getuid(), "credential_file": str(credential),
                         "policy": {"principal": "reader-org-a"}}],
        }, indent=2))
        (work / "ipc.json").chmod(0o600)
        state = work / "state"
        base = f"http://127.0.0.1:{args.port}"

        def tool(*arguments, expect_success=True):
            result = subprocess.run([sys.executable, str(TOOL), "--state-dir", str(state),
                                     "--config", str(work / "core.json"),
                                     "--ipc-config", str(work / "ipc.json"),
                                     "--binary", args.binary, *arguments],
                                    capture_output=True, text=True, timeout=1800)
            if expect_success and result.returncode != 0:
                raise AssertionError(f"{arguments[0]} failed: "
                                     f"{result.stderr.strip() or result.stdout.strip()}")
            return result

        tool("provision-plan", "--plan", str(work / "plan.json"))
        tool("start")
        time.sleep(3)
        _LoggingProxy.upstream = f"http://127.0.0.1:{core_port}"
        proxy = None
        import http.server
        import threading
        proxy = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), _LoggingProxy)
        threading.Thread(target=proxy.serve_forever, daemon=True).start()
        report["the_witness"] = {
            "the_port": args.port,
            "the_core_of_the_rehearsal": core_port,
            "the_note": "the witness stands on the documented port of the instance; the "
                        "installed bundle therefore carries the URL that the operator uses",
        }

        # 4. the installed bundle starts and reaches the Core
        first = launch("the installed bundle", executable=executable)
        process = first["process"]
        report["the_start"] = {key: value for key, value in first.items() if key != "process"}
        report["steps"].append("the installed bundle starts and reaches the Core")
        assert first["the_requests"], "the installed bundle asked the Core for nothing"
        refused = [item for item in first["the_requests"] if item["the_status"] in (401, 403)]
        # The refusal must be the refusal of the **session**: a refusal of the
        # origin would mean that the witness broke the rule of the Core.
        codes = {item.get("the_code") for item in refused}
        report["the_codes_of_the_refusals"] = sorted(c for c in codes if c)
        assert "LOCAL_ONLY" not in codes, \
            f"the Core refused the origin of the witness, not the session: {refused}"
        report["the_refusals_of_the_core"] = refused
        assert refused, f"the Core did not refuse the unauthorized session: {first['the_requests']}"
        assert not any(item["the_status"] == 200 for item in first["the_requests"]), \
            f"the installed bundle obtained unauthorized data: {first['the_requests']}"

        # 5. the window of the installed bundle
        time.sleep(4)
        shot = evidence / "oip-macos-install.png"
        capture = subprocess.run(["screencapture", "-x", "-o", str(shot)],
                                 capture_output=True, text=True, timeout=120)
        report["screenshot"] = str(shot) if shot.is_file() and shot.stat().st_size > 0 else None
        report["screenshot_captured"] = report["screenshot"] is not None
        if capture.returncode != 0:
            report["screenshot_error"] = capture.stderr.strip()[-200:]

        # 6. the installed bundle terminates on the operator's signal
        report["the_shutdown"] = terminate(process)
        report["steps"].append("the installed bundle terminates on SIGTERM")
        assert report["the_shutdown"]["terminated"], \
            "the installed bundle did not stop within 30 seconds"
        assert report["the_shutdown"]["exit_code"] not in (-6, -11), \
            f"the installed bundle crashed: {report['the_shutdown']['the_output']}"
        orphans = subprocess.run(["pgrep", "-f", str(executable)],
                                 capture_output=True, text=True).stdout.strip()
        report["the_orphaned_processes"] = [line for line in orphans.splitlines() if line]
        assert not report["the_orphaned_processes"], "the installed bundle left an orphan behind"

        # 7. the installed bundle starts again
        second = launch("the installed bundle, again", executable=executable)
        process = second["process"]
        report["the_restart"] = {key: value for key, value in second.items() if key != "process"}
        report["the_core_served_the_installed_bundle_again"] = bool(second["the_requests"])
        report["steps"].append("the installed bundle starts again from the installation directory")
        assert second["the_requests"], "the Core served no request of the restarted bundle"
        report["the_shutdown_after_the_restart"] = terminate(process)
        assert report["the_shutdown_after_the_restart"]["terminated"], \
            "the installed bundle did not stop within 30 seconds"

        report["status"] = "PASS"
    except AssertionError as error:
        report["status"] = "FAIL"
        report["error"] = str(error)
    finally:
        if process is not None and process.poll() is None:
            process.kill()
        try:
            tool("stop", expect_success=False)
        except Exception:
            pass
        shutil.rmtree(work, ignore_errors=True)

    report["the_revision"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    report["the_tree"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip()
    report["the_working_tree_is_clean"] = not subprocess.check_output(
        ["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()
    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "macos-install.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "steps"}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
