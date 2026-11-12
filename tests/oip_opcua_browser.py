#!/usr/bin/env python3
"""The address space of the operator in the browser (G8).

The Core delivers the address space of its collectors, and the surface shows
it. The rehearsal proves both in the browser against a **real** Core with a
live collector: the journey reads the address space from the API and proves
that the surface renders exactly that — the nodes, their folders, the identity
of a node and the attributes that the Core does **not** deliver. The journey
names no node and no folder of its own: every name it looks for is the name
the API delivered, so the claim "the surface derives the folder, the node and
the identity of the node from the API" is measured and not asserted.

The instance is disposable and owns its store and its collectors, so the
address space of the sources is real.

Usage:
  python3 tests/oip_opcua_browser.py [--evidence DIR]
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
SIMULATOR = ROOT / "target/debug/oip-simulated-server"


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def playwright_module():
    """The Playwright module of the browser scripts."""
    module = os.environ.get("PLAYWRIGHT_MODULE")
    if module:
        return module
    candidate = ROOT / "apps/flutter/test/node_modules/playwright/index.mjs"
    if not candidate.is_file():
        raise AssertionError(f"the Playwright module is missing: {candidate}")
    return str(candidate)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-opcua-browser"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-opcua-browser-rehearsal-v1", "steps": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-opcua-browser-", dir="/private/tmp")).resolve()
    work.chmod(0o700)
    simulators = []
    try:
        source_ports = [free_port() for _ in range(4)]
        port = free_port()
        plan = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        (work / "plan.json").write_text(json.dumps(plan, indent=2))
        (work / "core.json").write_text(json.dumps({
            "database": str(work / "core.sqlite"), "http_port": port,
            "sources": [{"id": f"source-{letter}", "name": f"Local simulation {letter}",
                          "endpoint": f"opc.tcp://127.0.0.1:{source_ports[index]}",
                          "namespace": 2}
                         for index, letter in enumerate("abcd")],
            "legacy_single_infrastructure": False,
            "web_dir": str(ROOT / "apps/flutter/build/web"),
        }, indent=2))
        credential = work / "reader-org-a.credential"
        credential.write_bytes(secrets.token_bytes(32))
        credential.chmod(0o600)
        (work / "ipc.json").write_text(json.dumps({
            "socket": str(work / "s"), "max_sessions": 16,
            "clients": [{"uid": os.getuid(), "credential_file": str(credential),
                         "policy": {"principal": "reader-org-a"}}],
        }, indent=2))
        (work / "ipc.json").chmod(0o600)
        state = work / "state"

        def tool(*arguments, expect_success=True):
            result = subprocess.run([sys.executable, str(TOOL), "--state-dir", str(state),
                                     "--config", str(work / "core.json"),
                                     "--ipc-config", str(work / "ipc.json"),
                                     "--binary", args.binary, *arguments],
                                    capture_output=True, text=True, timeout=600)
            if expect_success and result.returncode != 0:
                raise AssertionError(f"{arguments[0]} failed: "
                                     f"{result.stderr.strip() or result.stdout.strip()}")
            return result

        for index, simulator_port in enumerate(source_ports):
            simulators.append(subprocess.Popen(
                [str(SIMULATOR), "--port", str(simulator_port), "--seed", str(42 + index * 7),
                 "--tick-ms", "250"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        time.sleep(2)
        tool("provision-plan", "--plan", str(work / "plan.json"))
        tool("start")
        time.sleep(5)
        report["steps"].append("the instance runs with its collectors")

        result = subprocess.run(
            ["node", str(ROOT / "apps/flutter/test/browser_opcua_address_space.mjs")],
            cwd=ROOT, capture_output=True, text=True, timeout=2400,
            env=dict(os.environ,
                     OIP_URL=f"http://127.0.0.1:{port}",
                     OIP_EVIDENCE_DIR=str(evidence),
                     OIP_REVISION=subprocess.check_output(
                         ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                     OIP_IPC_SOCKET=str(work / "s"),
                     OIP_BROWSER_CREDENTIAL=str(credential),
                     OIP_SERVER_BIN=args.binary,
                     PLAYWRIGHT_MODULE=playwright_module()))
        report["the_output_of_the_journey"] = result.stdout[-4000:]
        if result.returncode != 0:
            report["the_error_of_the_journey"] = result.stderr[-2000:]
            raise AssertionError(f"the browser journey failed: "
                                 f"{result.stderr.strip()[-600:] or result.stdout.strip()[-600:]}")
        receipt = json.loads((evidence / "address-space.json").read_text())
        report["browser_receipt"] = receipt
        assert receipt["status"] == "PASS", receipt
        assert receipt["errors"] == [], receipt["errors"]
        assert receipt["external"] == [], receipt["external"]
        report["checks"] = len(receipt["the_checks"])
        report["the_address_space"] = receipt["the_address_space"]
        report["status"] = "PASS"
    except AssertionError as error:
        report["status"] = "FAIL"
        report["error"] = str(error)
    finally:
        for simulator in simulators:
            simulator.terminate()
        try:
            tool("stop", expect_success=False)
        except Exception:
            pass
        if report.get("status") == "PASS":
            shutil.rmtree(work, ignore_errors=True)
        else:
            report["work_directory"] = str(work)

    report["the_revision"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    report["the_tree"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip()
    report["the_working_tree_is_clean"] = not subprocess.check_output(
        ["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()
    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "opcua-browser.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"the_status": report.get("status"),
                      "the_checks": report.get("checks"),
                      "the_error": report.get("error")}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
