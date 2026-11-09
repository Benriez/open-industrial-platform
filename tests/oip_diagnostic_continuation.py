#!/usr/bin/env python3
"""The diagnostic continuation of the operator surface (G6, G8).

The persisted evidence of the diagnostics view is a page of the Core. The
Core cuts a long answer off and hands a cursor for the continuation. This
rehearsal proves the continuation in the browser against a real Core whose
page really is truncated:

  1. the collectors of the sources answer;
  2. one collector is cycled until the Core has documented more gaps than a
     page holds — every gap is a real interruption of a real collection;
  3. the browser journey loads the diagnostics workstation of the approved
     shell with an authorized session, follows the continuation and proves
     that the pages are merged without a duplicate and without a loss.

Nothing of the rehearsal touches the personal installation of the operator and
nothing leaves the machine.

Usage:
  python3 tests/oip_diagnostic_continuation.py [--evidence DIR] [--cycles 60]
"""
import argparse
import http.cookiejar
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
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "oip_ops.py"
SIMULATOR = ROOT / "target/debug/oip-simulated-server"


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def api(base, path, method="GET", body=None, headers=None, opener=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(base + path, data=data, method=method)
    request.add_header("Content-Type", "application/json")
    for key, value in (headers or {}).items():
        request.add_header(key, value)
    send = opener.open if opener else urllib.request.urlopen
    try:
        with send(request, timeout=60) as answer:
            return answer.status, json.loads(answer.read().decode() or "{}")
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read().decode() or "{}")


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
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-diagnostic-continuation"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    parser.add_argument("--cycles", type=int, default=60)
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-diagnostic-continuation-rehearsal-v1", "steps": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-continuation-", dir="/private/tmp")).resolve()
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

        for index, simulator_port in enumerate(source_ports):
            simulators.append(subprocess.Popen(
                [str(SIMULATOR), "--port", str(simulator_port), "--seed", str(42 + index * 7),
                 "--tick-ms", "250"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        time.sleep(2)
        tool("provision-plan", "--plan", str(work / "plan.json"))
        tool("start")
        time.sleep(3)
        report["steps"].append("the instance runs")

        minted = json.loads(subprocess.check_output(
            [args.binary, "--browser-login", "--ipc-socket", str(work / "s"),
             "--ipc-credential", str(credential)], text=True))
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        status, _ = api(base, "/api/v2/browser/login", "POST", {"code": minted["login_code"]},
                        {"Origin": base}, opener)
        assert status == 200, "the operator session was refused"
        report["steps"].append("the operator session is authorized")

        def sources():
            _, payload = api(base, "/api/v2/sources", opener=opener)
            items = payload if isinstance(payload, list) else payload.get("items", [])
            return {item.get("id"): item for item in items if isinstance(item, dict)}

        def wait_fresh(name, seconds=120):
            began = time.monotonic()
            while time.monotonic() - began < seconds:
                item = sources().get(name)
                if item and item.get("freshness") == "fresh":
                    return round(time.monotonic() - began, 1)
                time.sleep(0.5)
            return None

        wait_fresh("source-b")
        # The Core documents a gap for every interruption of a collection.
        # The collector of one source is cycled until the page of the Core
        # has to be truncated.
        cycles = 0
        while cycles < args.cycles:
            simulators[1].terminate()
            simulators[1].wait(timeout=30)
            time.sleep(0.5)
            simulators[1] = subprocess.Popen(
                [str(SIMULATOR), "--port", str(source_ports[1]), "--seed", "49",
                 "--tick-ms", "250"],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            wait_fresh("source-b")
            cycles += 1
            _, page = api(base, "/api/v2/diagnostics/gaps?limit=50", opener=opener)
            if isinstance(page, dict) and page.get("truncated"):
                break
        report["collector_cycles"] = cycles
        report["steps"].append("the Core has more gaps than a page holds")
        _, page = api(base, "/api/v2/diagnostics/gaps?limit=50", opener=opener)
        report["gap_page"] = {"items": len(page.get("items", [])),
                               "truncated": page.get("truncated"),
                               "has_cursor": bool(page.get("next_cursor"))}
        assert page.get("truncated"), "the page of the Core is not truncated"

        # The browser journey against the real Core.
        result = subprocess.run(
            ["node", str(ROOT / "apps/flutter/test/browser_diagnostic_continuation.mjs"),
             base, str(evidence)],
            cwd=ROOT, capture_output=True, text=True, timeout=1800,
            env=dict(os.environ,
                     OIP_REVISION=subprocess.check_output(
                         ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                     OIP_IPC_SOCKET=str(work / "s"),
                     OIP_BROWSER_CREDENTIAL=str(credential),
                     OIP_SERVER_BIN=args.binary,
                     PLAYWRIGHT_MODULE=playwright_module()))
        if result.returncode != 0:
            raise AssertionError(f"the browser journey failed: "
                                 f"{result.stderr.strip()[-600:] or result.stdout.strip()[-600:]}")
        receipt = json.loads((evidence / "diagnostic-continuation.json").read_text())
        report["browser_receipt"] = receipt
        assert receipt["errors"] == [], receipt["errors"]
        assert all(item["ok"] for item in receipt["checks"]), receipt["checks"]
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
    # The revision the receipt was measured on: a reader of the evidence must

    # be able to tell whether it is current.

    report["the_revision"] = subprocess.check_output(

        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()

    report["the_tree"] = subprocess.check_output(

        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip()

    report["the_working_tree_is_clean"] = not subprocess.check_output(

        ["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()

    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "diagnostic-continuation-rehearsal.json").write_text(
        json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items()
                      if k not in ("browser_receipt", "steps")}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
