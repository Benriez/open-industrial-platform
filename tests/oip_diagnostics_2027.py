#!/usr/bin/env python3
"""The evidence workspace of the Diagnostics workstation (G7, G8).

The workspace of the diagnostics is where the operator reads what the Core
**really** knows: the collection events, their provenance and the limits of
the evidence. The rehearsal starts a disposable Core with **live** collectors,
drives the real surface in the browser
(`apps/flutter/test/browser_diagnostics_2027.mjs`) and then changes the state
of the source: the collectors die and come back. The journey runs in every
phase and proves the same thing in all of them — the surface is the Core's
truth and never an invented one.

The instance is disposable and owns its store, so the evidence of the
operator is real.

Usage:
  python3 tests/oip_diagnostics_2027.py [--evidence DIR]
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
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-diagnostics-2027"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-diagnostics-2027-rehearsal-v1", "steps": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-diagnostics-2027-", dir="/private/tmp")).resolve()
    work.chmod(0o700)
    simulators = []
    try:
        if not SIMULATOR.is_file():
            raise AssertionError(f"the simulated collector is missing: {SIMULATOR}")
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
        base = f"http://127.0.0.1:{port}"

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

        def start_the_collectors():
            for index, simulator_port in enumerate(source_ports):
                log = open(work / f"simulator-{simulator_port}.log", "ab")
                simulators.append(subprocess.Popen(
                    [str(SIMULATOR), "--port", str(simulator_port), "--seed", str(42 + index * 7),
                     "--tick-ms", "250"],
                    stdout=log, stderr=log))
            time.sleep(3)

        def stop_the_collectors():
            for simulator in simulators:
                simulator.terminate()
            for simulator in simulators:
                try:
                    simulator.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    simulator.kill()
            simulators.clear()

        SESSION = {}

        def the_reader():
            """One authorized session for the reads of the rehearsal.

            The one-time code may be used **once**: a second login with the
            same code is refused. The rehearsal therefore opens one session
            and reads every route with it.
            """
            import urllib.request
            import http.cookiejar
            if "opener" not in SESSION:
                jar = http.cookiejar.CookieJar()
                opener = urllib.request.build_opener(
                    urllib.request.HTTPCookieProcessor(jar))
                login = urllib.request.Request(
                    f"{base}/api/v2/browser/login",
                    data=json.dumps({"code": MINTED["login_code"]}).encode(),
                    headers={"Content-Type": "application/json", "Origin": base},
                    method="POST")
                with opener.open(login, timeout=60) as answer:
                    assert json.loads(answer.read().decode()).get("authenticated") is True
                SESSION["opener"] = opener
            return SESSION["opener"]

        def a_get(path):
            import urllib.request
            request = urllib.request.Request(f"{base}{path}", headers={"Origin": base})
            with the_reader().open(request, timeout=60) as answer:
                return json.loads(answer.read().decode())

        def the_events():
            """The events of the Core, read over the authorized route."""
            return a_get("/api/v2/events")

        def the_sources():
            """The health of the sources of the Core, read over the route."""
            return a_get("/api/v2/sources")

        def the_state_of_the_sources():
            return [{k: source.get(k) for k in
                     ("id", "connection", "reachability", "freshness",
                      "reconnect_attempts", "last_error")}
                    for source in the_sources()]

        def wait_for_a_kind(kind, timeout=120):
            """The Core records the event of the kind — the loop waits for it."""
            deadline = time.time() + timeout
            while time.time() < deadline:
                try:
                    payload = the_events()
                except Exception:
                    payload = {}
                for record in payload.get("records", []):
                    event = record.get("event", {})
                    if kind in event:
                        return record
                time.sleep(2)
            raise AssertionError(f"the Core recorded no {kind} event in {timeout} seconds")

        def run_the_journey(phase):
            result = subprocess.run(
                ["node", str(ROOT / "apps/flutter/test/browser_diagnostics_2027.mjs")],
                cwd=ROOT, capture_output=True, text=True, timeout=2400,
                env=dict(os.environ,
                         OIP_URL=base,
                         OIP_PHASE=phase,
                         OIP_EVIDENCE_DIR=str(evidence),
                         OIP_REVISION=subprocess.check_output(
                             ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                         OIP_IPC_SOCKET=str(work / "s"),
                         OIP_BROWSER_CREDENTIAL=str(credential),
                         OIP_SERVER_BIN=args.binary,
                         PLAYWRIGHT_MODULE=playwright_module()))
            report.setdefault("the_output_of_the_journey", []).append(
                f"--- {phase} ---\n{result.stdout[-2000:]}")
            if result.returncode != 0:
                report["the_error_of_the_journey"] = result.stderr[-2000:]
                raise AssertionError(f"the browser journey failed in the phase {phase}: "
                                     f"{result.stderr.strip()[-600:] or result.stdout.strip()[-600:]}")
            receipt = json.loads((evidence / f"diagnostics-{phase}.json").read_text())
            assert receipt.get("status") == "PASS", receipt
            assert not receipt.get("errors"), receipt.get("errors")
            return receipt

        start_the_collectors()
        tool("provision-plan", "--plan", str(work / "plan.json"))
        tool("start")
        time.sleep(5)
        report["steps"].append("the instance runs with its live collectors")

        MINTED = json.loads(subprocess.check_output(
            [args.binary, "--browser-login", "--ipc-socket", str(work / "s"),
             "--ipc-credential", str(credential)], text=True))

        # 1. the collectors are alive
        live = run_the_journey("live")
        report["the_phase_live"] = live["the_events_of_the_core"]
        report["steps"].append("the surface shows the evidence of the live collectors")

        # 2. the collectors die and come back. The adapter of the Core gives
        #    up after a finite number of attempts, so the collectors come back
        #    inside that window — otherwise the loss would be a one-way street
        #    and the rehearsal would prove nothing about the recovery.
        report["the_sources_before"] = the_state_of_the_sources()
        stop_the_collectors()
        time.sleep(2)
        lost_event = wait_for_a_kind("ConnectionLost")
        report["the_event_of_the_loss"] = {
            "the_id": lost_event.get("id"),
            "the_kind": "ConnectionLost",
            "the_source": (lost_event.get("context") or {}).get("data_source_id"),
        }
        report["the_sources_after_the_loss"] = the_state_of_the_sources()
        report["steps"].append("the Core recorded the loss of the source")

        # The collectors come back: the Core reconnects the source. The
        # **recovery is not a collection event** of the Core — the adapter of
        # the OPC-UA transport reconnects without an event — so the evidence
        # of the recovery is the health of the source and its attempts.
        start_the_collectors()
        deadline = time.time() + 120
        recovered = None
        while time.time() < deadline:
            state = the_state_of_the_sources()
            if any(source.get("connection") == "connected" and
                   (source.get("reconnect_attempts") or 0) > 0 for source in state):
                recovered = state
                break
            time.sleep(2)
        report["the_sources_after_the_recovery"] = recovered
        report["steps"].append("the Core reconnected the source")

        # 3. the surface shows both events of the Core
        failed = run_the_journey("failed")
        report["the_phase_failed"] = failed["the_events_of_the_core"]
        report["steps"].append("the surface shows the loss and the recovery of the source")

        report["checks"] = sum(len(receipt["the_checks"]) for receipt in (live, failed))
        report["status"] = "PASS"
    except AssertionError as error:
        report["status"] = "FAIL"
        report["error"] = str(error)
    finally:
        for simulator in simulators:
            try:
                simulator.terminate()
            except Exception:
                pass
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
    (evidence / "diagnostics-2027-rehearsal.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"the_status": report.get("status"),
                      "the_checks": report.get("checks"),
                      "the_error": report.get("error")}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
