#!/usr/bin/env python3
"""The performance baseline of the release build.

The Core side of the baseline is measured by the acceptance harness. This
script measures the client side against a disposable managed instance of the
current release binary: the first paint of the delivered web release, the
operator login, the interactive shell with the six workstations and the
authorized projection of the infrastructure.

The numbers are a local measurement of this machine, not an SLA. The script
owns a disposable instance and never touches the personal installation of the
operator.

Usage:
  python3 tests/oip_performance.py [--evidence DIR] [--runs N]
"""
import argparse
import json
import os
import pathlib
import secrets
import shutil
import socket
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "oip_ops.py"


def playwright_module():
    """The Playwright module of the browser scripts.

    The module lives in the test tree of the Flutter application and is not
    part of the repository.
    """
    module = os.environ.get("PLAYWRIGHT_MODULE")
    if module:
        return module
    candidate = ROOT / "apps/flutter/test/node_modules/playwright/index.mjs"
    if not candidate.is_file():
        raise AssertionError(f"the Playwright module is missing: {candidate}")
    return str(candidate)


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def tool(state, config, ipc, binary, *arguments, expect_success=True):
    result = subprocess.run([sys.executable, str(TOOL), "--state-dir", str(state),
                             "--config", str(config), "--ipc-config", str(ipc),
                             "--binary", str(binary), *arguments],
                            capture_output=True, text=True, timeout=300)
    if expect_success and result.returncode != 0:
        raise AssertionError(f"{arguments[0]} failed: "
                             f"{result.stderr.strip() or result.stdout.strip()}")
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-performance"))
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-performance-baseline-v1", "runs": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-performance-")).resolve()
    work.chmod(0o700)
    try:
        plan = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        (work / "plan.json").write_text(json.dumps(plan, indent=2))
        port = free_port()
        (work / "core.json").write_text(json.dumps({
            "database": str(work / "core.sqlite"),
            "http_port": port,
            "sources": [
                {"id": f"source-{letter}", "name": f"Local simulation {letter}",
                 "endpoint": f"opc.tcp://127.0.0.1:{15860 + index}", "namespace": 2}
                for index, letter in enumerate("abcd")
            ],
            "legacy_single_infrastructure": False,
            "web_dir": str(ROOT / "apps/flutter/build/web"),
        }, indent=2))
        credential = work / "platform.credential"
        credential.write_bytes(secrets.token_bytes(32))
        credential.chmod(0o600)
        (work / "ipc.json").write_text(json.dumps({
            "socket": str(work / "s"),
            "max_sessions": 16,
            "clients": [{"uid": os.getuid(), "credential_file": str(credential),
                         "policy": {"principal": "reader-org-a"}}],
        }, indent=2))
        (work / "ipc.json").chmod(0o600)
        state = work / "state"

        tool(state, work / "core.json", work / "ipc.json", args.binary,
             "provision-plan", "--plan", str(work / "plan.json"))
        tool(state, work / "core.json", work / "ipc.json", args.binary, "start")
        time.sleep(2)

        pid = int((state / "oip.pid").read_text().strip())
        usage = subprocess.check_output(["ps", "-p", str(pid), "-o", "rss=,%cpu="],
                                         text=True).strip()
        report["core_rss_kib_cpu_percent"] = usage
        report["core_binary"] = args.binary

        for run in range(args.runs):
            target = evidence / f"run-{run + 1}"
            result = subprocess.run(
                ["node", str(ROOT / "apps/flutter/test/browser_performance.mjs"),
                 f"http://127.0.0.1:{port}", str(target)],
                cwd=ROOT, capture_output=True, text=True, timeout=1800,
                env=dict(os.environ,
                         OIP_IPC_SOCKET=str(work / "s"),
                         OIP_BROWSER_CREDENTIAL=str(credential),
                         OIP_SERVER_BIN=args.binary,
                         PLAYWRIGHT_MODULE=playwright_module()))
            if result.returncode != 0:
                raise AssertionError(f"the performance run failed: "
                                     f"{result.stderr.strip()[-400:]}")
            measured = json.loads((target / "performance.json").read_text())
            report["runs"].append(measured)

        for phase in ("first_paint_ms", "login_gate_ms",
                      "authenticated_shell_ms", "authorized_projection_ms"):
            values = sorted(run[phase] for run in report["runs"])
            report[f"{phase}_p50"] = values[len(values) // 2]
            report[f"{phase}_min"] = values[0]
            report[f"{phase}_max"] = values[-1]
        report["bundle_sha256"] = report["runs"][0]["bundle_sha256"]
        report["status"] = "PASS"
    except AssertionError as error:
        report["status"] = "FAIL"
        report["error"] = str(error)
    finally:
        try:
            tool(state, work / "core.json", work / "ipc.json", args.binary, "stop",
                 expect_success=False)
        except Exception:
            pass
        shutil.rmtree(work, ignore_errors=True)
    # The revision the receipt was measured on: a reader of the evidence must

    # be able to tell whether it is current.

    report["the_revision"] = subprocess.check_output(

        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()

    report["the_tree"] = subprocess.check_output(

        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip()

    report["the_working_tree_is_clean"] = not subprocess.check_output(

        ["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()

    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "performance.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "runs"}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
