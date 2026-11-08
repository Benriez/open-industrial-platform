#!/usr/bin/env python3
"""The functional depth of the six workstations (G8).

The canonical gate proves that the six workstations of the approved shell
render and that they carry no legacy marker. This rehearsal proves that every
workstation shows **real** data of the authorized Core — the hierarchy, the
device, the placement, the nodes, the events and the settings — and that no
identifier of the other organization appears.

The instance is disposable and owns its collectors, so the address space of
the sources and the events of the collection are real.

Usage:
  python3 tests/oip_workstation_data.py [--evidence DIR]
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
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-workstation-data"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-workstation-data-rehearsal-v1", "steps": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-workstation-", dir="/private/tmp")).resolve()
    work.chmod(0o700)
    simulators = []
    try:
        source_ports = [free_port() for _ in range(4)]
        port = free_port()
        plan = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        # The reader role of the plan may not read the settings of the Core:
        # the settings view shows the refusal of the Core. The rehearsal gives
        # the principal the scoped permission, so the view can show the real
        # settings of the instance.
        plan["roles"].append({
            "id": "settings-reader", "name": "Explicit scoped settings reader",
            "permissions": ["settings_read"],
        })
        plan["bindings"].append({
            "principal_id": "reader-org-a", "role_id": "settings-reader",
            "scope": {"kind": "organization", "id": "org-a"},
        })
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
            ["node", str(ROOT / "apps/flutter/test/browser_workstation_data.mjs"),
             f"http://127.0.0.1:{port}", str(evidence)],
            cwd=ROOT, capture_output=True, text=True, timeout=2400,
            env=dict(os.environ,
                     OIP_IPC_SOCKET=str(work / "s"),
                     OIP_BROWSER_CREDENTIAL=str(credential),
                     OIP_SERVER_BIN=args.binary,
                     PLAYWRIGHT_MODULE=playwright_module()))
        if result.returncode != 0:
            raise AssertionError(f"the browser journey failed: "
                                 f"{result.stderr.strip()[-600:] or result.stdout.strip()[-600:]}")
        receipt = json.loads((evidence / "workstation-data.json").read_text())
        report["browser_receipt"] = receipt
        assert receipt["errors"] == [], receipt["errors"]
        assert all(item["ok"] for item in receipt["findings"]), receipt["findings"]
        report["checks"] = len(receipt["findings"])
        report["status"] = "PASS"
    except AssertionError as error:
        report["status"] = "FAIL"
        report["error"] = str(error)
    finally:
        for simulator in simulators:
            if simulator.poll() is None:
                simulator.terminate()
                try:
                    simulator.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    simulator.kill()
        try:
            tool("stop", expect_success=False)
        except Exception:
            pass
        if report.get("status") == "PASS":
            shutil.rmtree(work, ignore_errors=True)
        else:
            report["work_directory"] = str(work)

    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "workstation-data-rehearsal.json").write_text(
        json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items()
                      if k not in ("browser_receipt", "steps")}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
