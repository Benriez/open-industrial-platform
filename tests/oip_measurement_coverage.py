#!/usr/bin/env python3
"""The coverage of the measurements of the real device (G6).

The gate G6 asks for **supported** CPU, RAM, storage, network and uptime
measurements, and the contract of the real device onboarding is explicit about
what the host report delivers and what it does not:

> GPU, temperature and CPU utilization are explicitly unavailable. … Interface-
> reported addresses are not reachability probes.

That honesty is in the code and in the contract. It had **no receipt**: the
receipt of the device connection showed that a device collects, not *which*
measurements it collects and which ones the release honestly refuses to
invent.

This rehearsal measures the coverage against the real Core and an owned
loopback SSH fixture:

  * every **supported** kind is delivered as an observation with its kind:
    CPU (the identity of the processor), RAM (total and used), storage (the
    local disks), network (the interface-reported addresses) and uptime;
  * every **unavailable** kind — GPU, temperature, CPU utilization — is
    **named** as unavailable in the connection record and is **not** delivered
    as an observation;
  * the report carries its **provenance**;
  * the surface **names** the measurements that are not available, so a
    measurement that is missing never looks like a measurement of zero.

Nothing of the rehearsal touches the personal installation of the operator, no
private endpoint is contacted and no hardware is invented: the host is an
owned SSH fixture on the loopback.

Usage:
  python3 tests/oip_measurement_coverage.py [--evidence DIR]
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
sys.path.insert(0, str(ROOT / "tests" / "real_device"))
sys.path.insert(0, str(ROOT / "tests"))

from ssh_fixture import SshFixture  # noqa: E402

TOOL = ROOT / "tools" / "oip_ops.py"
SIMULATOR = ROOT / "target/debug/oip-simulated-server"

# The kinds that the release supports, and the metric that carries each of
# them. The names are the metric identifiers of the Core.
SUPPORTED = {
    "cpu": ["host.cpu_info", "host.model"],
    "ram": ["host.memory_total_bytes", "host.memory_used_bytes"],
    "storage": ["host.disks"],
    "network": ["host.interfaces"],
    "uptime": ["host.uptime_seconds"],
}
# The kinds that the contract names as unavailable. They must be **named**,
# never delivered as a number.
UNAVAILABLE = ["gpu", "temperature", "cpu_utilization"]


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def request(base, path, method="GET", body=None, headers=None, opener=None):
    data = json.dumps(body).encode() if body is not None else None
    message = urllib.request.Request(base + path, data=data, method=method)
    message.add_header("Content-Type", "application/json")
    for key, value in (headers or {}).items():
        message.add_header(key, value)
    send = opener.open if opener else urllib.request.urlopen
    try:
        with send(message, timeout=60) as answer:
            return answer.status, json.loads(answer.read().decode() or "{}")
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read().decode() or "{}")


def playwright_module():
    for candidate in (ROOT / "apps/flutter/.dart_tool" / "package_config.json",):
        if candidate.is_file():
            return candidate
    return ROOT / "apps/flutter"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-measurement-coverage"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-measurement-coverage-v1", "steps": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-coverage-")).resolve()
    work.chmod(0o700)
    fixture = None
    simulators = []
    try:
        fixture = SshFixture()
        report["ssh_fixture"] = {"port": fixture.port, "user": fixture.user,
                                 "loopback_only": True}
        source_ports = [free_port() for _ in range(3)]
        port = free_port()
        plan = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        (work / "plan.json").write_text(json.dumps(plan, indent=2))
        (work / "core.json").write_text(json.dumps({
            "database": str(work / "core.sqlite"), "http_port": port,
            "sources": [{"id": f"source-{letter}", "name": f"Local simulation {letter}",
                         "endpoint": f"opc.tcp://127.0.0.1:{source_ports[index]}",
                         "namespace": 2}
                        for index, letter in enumerate("abc")],
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
                                    capture_output=True, text=True, timeout=900)
            if expect_success and result.returncode != 0:
                raise AssertionError(f"{arguments[0]} failed: "
                                     f"{result.stderr.strip() or result.stdout.strip()}")
            return result

        for index, simulator_port in enumerate(source_ports):
            simulator = subprocess.Popen(
                [str(SIMULATOR), "--port", str(simulator_port), "--seed", str(42 + index * 7),
                 "--tick-ms", "250"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            simulators.append(simulator)
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
        status, session = request(base, "/api/v2/browser/login", "POST",
                                  {"code": minted["login_code"]}, {"Origin": base}, opener)
        assert status == 200, session
        headers = {"Origin": base, "x-oip-csrf": session["csrf_token"]}

        status, _ = request(base, "/api/v2/inventory/apply", {"changes": [{
            "operation": "register",
            "device": {"id": "coverage-device", "display_name": "Coverage device",
                       "device_type": "single_board_computer", "site_id": "site-a1",
                       "metadata": {}}}]}, headers, opener)
        assert status == 200, "the device was not registered"

        endpoint = {"host": "127.0.0.1", "port": fixture.port, "user": fixture.user,
                    "identity_profile": "fixture"}
        target = {"kind": "existing", "id": "coverage-device", "expected_revision": 1}
        status, answer = request(base, "/api/v2/device-connections", {
            "operation": "start", "target": target, "endpoint": endpoint}, headers, opener)
        assert status == 200, answer
        plan_id = answer["plan"]["plan_id"]

        def wait_stage(stage, timeout=90):
            deadline = time.monotonic() + timeout
            while time.monotonic() < deadline:
                _, value = request(base, f"/api/v2/device-connections?plan_id={plan_id}",
                                   opener=opener)
                if value["plan"]["stage"] == stage:
                    return value["plan"]
                if value["plan"]["stage"] == "failed":
                    raise AssertionError(f"the connection failed: {value['plan']['error']}")
                time.sleep(0.5)
            raise AssertionError(f"the connection did not reach the stage {stage}")

        awaiting = wait_stage("awaiting_host_key")
        fingerprint = awaiting["host_key_fingerprint"]
        request(base, "/api/v2/device-connections", {
            "operation": "trust_host_key", "plan_id": plan_id, "fingerprint": fingerprint},
            headers, opener)
        request(base, "/api/v2/device-connections", {
            "operation": "verify", "plan_id": plan_id}, headers, opener)
        verified = wait_stage("verification_complete")
        identity = verified["identity"]
        request(base, "/api/v2/device-connections", {
            "operation": "confirm", "plan_id": plan_id, "identity_confirmed": True,
            "enable_monitoring": True, "poll_seconds": 5}, headers, opener)
        report["steps"].append("the device is connected, verified and confirmed")

        # the connection record: the identity, the provenance and the kinds
        # that are **not** delivered
        _, value = request(base, "/api/v2/device-connections?device_id=coverage-device",
                           opener=opener)
        connection = value.get("connection", {})
        record = connection.get("verified_identity") or identity
        report["the_connection"] = {
            "the_status": connection.get("status"),
            "the_host_key_fingerprint": fingerprint,
            "the_unavailable": record.get("unavailable"),
            "the_provenance": record.get("provenance"),
            "the_interfaces": record.get("interfaces"),
        }
        named = [item for item in UNAVAILABLE if item in (record.get("unavailable") or [])]
        report["the_unavailable_named"] = named
        report["the_every_unavailable_kind_is_named"] = sorted(named) == sorted(UNAVAILABLE)
        assert report["the_every_unavailable_kind_is_named"], \
            f"the kinds that are not available are not named: {record.get('unavailable')}"
        assert record.get("provenance"), "the report carries no provenance"

        # the observations of the source: the supported kinds
        deadline = time.monotonic() + 180
        observations = []
        source_id = None
        while time.monotonic() < deadline:
            _, sources = request(base, "/api/v2/sources", opener=opener)
            items = sources if isinstance(sources, list) else sources.get("items", [])
            ssh_source = next((item for item in items
                               if str(item.get("id", "")).startswith("c") and
                               item.get("kind") == "ssh_host"), None)
            if ssh_source is None:
                ssh_source = next((item for item in items
                                   if "SSH" in str(item.get("name", ""))), None)
            if ssh_source:
                source_id = ssh_source["id"]
                _, observations = request(
                    base, f"/api/v1/metrics/current?source_id={source_id}", opener=opener)
                if observations:
                    break
            time.sleep(2)
        assert observations, "the source of the device delivered no observation"

        delivered = {}
        for observation in observations:
            metric = observation.get("metric") or observation.get("metric_id") or {}
            name = metric.get("id") if isinstance(metric, dict) else metric
            value = observation.get("value")
            if name:
                delivered[name] = value
        coverage = {}
        for kind, metrics in SUPPORTED.items():
            present = [name for name in metrics if name in delivered]
            coverage[kind] = {"the_metrics": metrics, "the_delivered": present,
                              "the_covered": bool(present)}
        report["the_coverage"] = coverage
        report["the_every_supported_kind_is_covered"] = all(
            item["the_covered"] for item in coverage.values())
        report["the_delivered_metrics"] = sorted(delivered)
        report["the_steps"] = report["steps"]
        report["steps"].append("the supported kinds are measured")
        assert report["the_every_supported_kind_is_covered"], \
            f"a supported kind is not measured: {coverage}"

        # the kinds that are not available are **not** delivered as a number
        invented = [name for name in delivered
                    if any(item in str(name) for item in UNAVAILABLE)]
        report["the_measurements_that_were_invented"] = invented
        assert not invented, f"a measurement that is not available was delivered: {invented}"

        # the surface names the kinds that are not available
        result = subprocess.run(
            ["node", str(ROOT / "apps/flutter/test/browser_device_connection.mjs"),
             base, str(evidence)],
            cwd=ROOT, capture_output=True, text=True, timeout=2400,
            env=dict(os.environ,
                     OIP_REVISION=subprocess.check_output(
                         ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                     OIP_IPC_SOCKET=str(work / "s"),
                     OIP_BROWSER_CREDENTIAL=str(credential),
                     OIP_SERVER_BIN=args.binary,
                     OIP_EXPECTED_FINGERPRINT=fingerprint,
                     OIP_EXPECTED_CONNECTION_STATUS=report["the_connection"]["the_status"],
                     PLAYWRIGHT_MODULE=playwright_module()))
        if result.returncode != 0:
            raise AssertionError(f"the browser journey failed: "
                                 f"{result.stderr.strip()[-600:] or result.stdout.strip()[-600:]}")
        receipt = json.loads((evidence / "device-connection.json").read_text())
        report["browser_receipt"] = receipt
        report["the_surface_names_the_unavailable"] = any(
            "not available are named" in str(item.get("check", "")) and item.get("ok")
            for item in receipt.get("findings", []))
        assert report["the_surface_names_the_unavailable"], receipt.get("findings")
        report["steps"].append("the surface names the measurements that are not available")
        report["status"] = "PASS"
    except AssertionError as error:
        report["status"] = "FAIL"
        report["error"] = str(error)
    except Exception as error:  # noqa: BLE001 - the receipt names every failure
        report["status"] = "FAIL"
        report["error"] = f"{type(error).__name__}: {error}"
    finally:
        try:
            tool("stop", expect_success=False)
        except Exception:
            pass
        for simulator in simulators:
            simulator.terminate()
        if fixture is not None:
            fixture.stop()
        shutil.rmtree(work, ignore_errors=True)

    report["the_revision"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    report["the_tree"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip()
    report["the_working_tree_is_clean"] = not subprocess.check_output(
        ["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()
    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "measurement-coverage.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "steps"}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
