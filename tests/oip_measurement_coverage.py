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
  * every **unavailable** kind — GPU, temperature, CPU utilisation — is
    **named** as unavailable in the connection record and is **not** delivered
    as an observation;
  * the report carries its **provenance**;
  * the surface **names** the measurements that are not available, so a
    measurement that is missing never looks like a measurement of zero.

Nothing of the rehearsal touches the personal installation of the operator, no
private endpoint is contacted and no hardware is invented: the host is an
owned SSH fixture on the loopback.

Usage:
  python3 tests/oip_measurement_coverage.py [--evidence DIR] [--binary PATH]
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
import traceback
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests" / "real_device"))
sys.path.insert(0, str(ROOT / "tests"))

from ssh_fixture import SshFixture  # noqa: E402

TOOL = ROOT / "tools" / "oip_ops.py"

# The kinds that the release supports, and the metrics of the Core that carry
# each of them. The names are the metric identifiers of the Core.
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


def request(base, path, body=None, headers=None, opener=None, method=None):
    """The request helper of the proven rehearsals (the same signature)."""
    headers = dict(headers or {})
    data = json.dumps(body).encode() if body is not None else None
    if data is not None:
        headers["Content-Type"] = "application/json"
    call = urllib.request.Request(base + path, data=data, headers=headers,
                                  method=method or ("POST" if data else "GET"))
    try:
        with (opener.open(call, timeout=60) if opener
              else urllib.request.urlopen(call, timeout=60)) as answer:
            return answer.status, json.loads(answer.read().decode() or "{}")
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read().decode() or "{}")


def scalar(value):
    """The scalar of a tagged metric value (``{"unsigned_integer": 42}``)."""
    if not isinstance(value, dict):
        return value
    if len(value) == 1:
        return next(iter(value.values()))
    return value


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
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-measurement-coverage"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-measurement-coverage-v1", "steps": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-coverage-")).resolve()
    work.chmod(0o700)
    fixture = None
    try:
        fixture = SshFixture()
        report["ssh_fixture"] = {"port": fixture.port, "user": fixture.user,
                                 "loopback_only": True}
        http_port = free_port()
        # The configuration of the proven rehearsal of the device connection,
        # with the SSH profile of the owned fixture.
        config = json.loads((ROOT / "examples/multi-infrastructure-core.json").read_text())
        config.update(database=str(work / "core.sqlite"), http_port=http_port,
                      sources=[], stale_after_ms=2000, shutdown_timeout_ms=6000,
                      web_dir=str(ROOT / "apps/flutter/build/web"))
        config["ssh"] = {"profiles": [{
            "id": "fixture", "label": "Owned loopback SSH fixture",
            "principals": ["reader-org-a"], "allowed_hosts": ["127.0.0.1"],
            "allowed_ports": [fixture.port],
            "identity_file": str(pathlib.Path(fixture.directory) / "client"),
            "agent_socket": None, "known_hosts_file": None, "aliases": {}}]}
        (work / "core.json").write_text(json.dumps(config, indent=2))
        # The hierarchy without the simulated sources: the measurement of the
        # real device is the subject of this rehearsal.
        plan = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        plan["sources"] = []
        plan["bindings"] = [item for item in plan["bindings"]
                            if item["scope"]["kind"] != "source"]
        plan["roles"].append({"id": "inventory-admin", "name": "Explicit scoped operator",
                               "permissions": ["inventory_manage", "devices_read",
                                               "telemetry_read"]})
        plan["bindings"].append({"principal_id": "reader-org-a",
                                 "role_id": "inventory-admin",
                                 "scope": {"kind": "organization", "id": "org-a"}})
        (work / "plan.json").write_text(json.dumps(plan, indent=2))
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
        base = f"http://127.0.0.1:{http_port}"

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

        tool("provision-plan", "--plan", str(work / "plan.json"))
        tool("start")
        time.sleep(3)
        report["steps"].append("the instance runs")

        minted = json.loads(subprocess.check_output(
            [args.binary, "--browser-login", "--ipc-socket", str(work / "s"),
             "--ipc-credential", str(credential)], text=True))
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        status, session = request(base, "/api/v2/browser/login",
                                  {"code": minted["login_code"]}, {"Origin": base}, opener)
        assert status == 200, session
        headers = {"Origin": base, "x-oip-csrf": session["csrf_token"]}

        # 1. the device of the authorized inventory
        status, answer = request(base, "/api/v2/inventory/apply", {"changes": [{
            "operation": "register",
            "device": {"id": "coverage-device", "display_name": "Coverage device",
                       "device_type": "single_board_computer", "site_id": "site-a1",
                       "metadata": {}}}]}, headers, opener)
        assert status == 200, f"the device was not registered: {answer}"
        report["steps"].append("the device is registered")

        # 2. the connection with the confirmed host key
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
        assert fingerprint.startswith("SHA256:"), fingerprint
        report["host_key_fingerprint"] = fingerprint
        status, answer = request(base, "/api/v2/device-connections", {
            "operation": "trust_host_key", "plan_id": plan_id, "fingerprint": fingerprint},
            headers, opener)
        assert status == 200, f"the host key was not accepted: {answer}"
        status, answer = request(base, "/api/v2/device-connections", {
            "operation": "verify", "plan_id": plan_id}, headers, opener)
        assert status == 200, f"the verification failed: {answer}"
        verified = wait_stage("verification_complete")
        report["steps"].append("the host key is confirmed and the identity is verified")

        status, answer = request(base, "/api/v2/device-connections", {
            "operation": "confirm", "plan_id": plan_id, "identity_confirmed": True,
            "enable_monitoring": True, "poll_seconds": 10}, headers, opener)
        assert status == 200, f"the confirmation failed: {answer}"

        deadline = time.monotonic() + 90
        connection = {}
        while time.monotonic() < deadline:
            _, value = request(base, "/api/v2/device-connections?device_id=coverage-device",
                               opener=opener)
            connection = value.get("connection") or {}
            if connection.get("status") == "collecting":
                break
            time.sleep(0.5)
        report["connection_status"] = connection.get("status")
        assert report["connection_status"] == "collecting", report["connection_status"]
        report["steps"].append("the device collects")

        # 3. the connection record: the identity, the provenance and the kinds
        # that are **not** delivered
        record = connection.get("verified_identity") or verified["identity"]
        report["the_connection"] = {
            "the_status": connection.get("status"),
            "the_source_id": connection.get("source_id"),
            "the_host_key_fingerprint": fingerprint,
            "the_unavailable": record.get("unavailable"),
            "the_provenance": record.get("provenance"),
            "the_interfaces": record.get("interfaces"),
            "the_disks": record.get("disks"),
        }
        named = [item for item in UNAVAILABLE if item in (record.get("unavailable") or [])]
        report["the_unavailable_named"] = named
        report["the_every_unavailable_kind_is_named"] = sorted(named) == sorted(UNAVAILABLE)
        assert report["the_every_unavailable_kind_is_named"], \
            f"the kinds that are not available are not named: {record.get('unavailable')}"
        assert record.get("provenance"), "the report carries no provenance"
        assert record.get("interfaces"), "the report carries no interface"
        assert record.get("disks"), "the report carries no disk"

        # 4. the observations of the source: the supported kinds
        deadline = time.monotonic() + 180
        observations = []
        source_id = connection.get("source_id")
        published = None
        while time.monotonic() < deadline:
            status, value = request(base, "/api/v2/sources", opener=opener)
            assert status == 200, f"the sources are not readable: {value}"
            items = value if isinstance(value, list) else value.get("items", [])
            ssh_source = next((item for item in items
                               if str(item.get("name", "")).startswith("SSH host ")
                               or (item.get("simulated") is False
                                   and item.get("entity_id") == "coverage-device")), None)
            if ssh_source:
                source_id = ssh_source.get("id") or source_id
                report["the_source_in_the_hierarchy"] = {
                    "the_id": ssh_source.get("id"), "the_name": ssh_source.get("name"),
                    "the_entity_id": ssh_source.get("entity_id"),
                    "the_simulated": ssh_source.get("simulated"),
                    "the_reachability": ssh_source.get("reachability"),
                }
                status, value = request(
                    base, f"/api/v1/metrics/current?source={source_id}", opener=opener)
                assert status == 200, f"the observations are not readable: {value}"
                published = value if isinstance(value, list) else value.get("items", [])
                observations = published or connection.get("observations") or []
                if observations:
                    break
            time.sleep(2)
        assert observations, "the source of the device delivered no observation"

        delivered = {}
        for observation in observations:
            name = observation.get("metric_id")
            if name:
                delivered[name] = scalar(observation.get("value"))
        report["the_delivered_metrics"] = sorted(delivered)
        report["the_observations_are_published"] = bool(published)

        coverage = {}
        for kind, metrics in SUPPORTED.items():
            present = [name for name in metrics if name in delivered]
            coverage[kind] = {"the_metrics": metrics, "the_delivered": present,
                              "the_covered": bool(present)}
        report["the_coverage"] = coverage
        report["the_every_supported_kind_is_covered"] = all(
            item["the_covered"] for item in coverage.values())
        assert report["the_every_supported_kind_is_covered"], \
            f"a supported kind is not measured: {coverage}"

        # the kinds that are not available are **not** delivered as a number
        invented = [name for name in delivered
                    if any(item in str(name) for item in UNAVAILABLE)]
        report["the_measurements_that_were_invented"] = invented
        assert not invented, f"a measurement that is not available was delivered: {invented}"
        report["steps"].append("the supported kinds are measured")

        # the readings of the kinds that carry a number
        report["the_readings"] = {
            "host.memory_total_bytes": delivered.get("host.memory_total_bytes"),
            "host.memory_used_bytes": delivered.get("host.memory_used_bytes"),
            "host.uptime_seconds": delivered.get("host.uptime_seconds"),
            "host.cpu_info": delivered.get("host.cpu_info"),
            "host.model": delivered.get("host.model"),
            "the_disks": len(json.loads(delivered.get("host.disks", "[]"))),
            "the_interfaces": len(json.loads(delivered.get("host.interfaces", "[]"))),
        }

        # 5. the surface names the kinds that are not available
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
                     OIP_EXPECTED_CONNECTION_STATUS=report["connection_status"],
                     OIP_DEVICE_ID="coverage-device",
                     OIP_BROWSER_RECEIPT_NAME="measurement-coverage-browser.json",
                     PLAYWRIGHT_MODULE=playwright_module()))
        if result.returncode != 0:
            raise AssertionError(f"the browser journey failed: "
                                 f"{result.stderr.strip()[-600:] or result.stdout.strip()[-600:]}")
        receipt = json.loads((evidence / "measurement-coverage-browser.json").read_text())
        report["browser_receipt"] = receipt
        assert receipt["errors"] == [], receipt["errors"]
        assert all(item["ok"] for item in receipt["findings"]), receipt["findings"]
        report["the_surface_names_the_unavailable"] = any(
            "not available are named" in str(item.get("check", "")) and item.get("ok")
            for item in receipt["findings"])
        assert report["the_surface_names_the_unavailable"], receipt["findings"]
        report["checks"] = len(receipt["findings"])
        report["steps"].append("the surface names the measurements that are not available")
        report["status"] = "PASS"
    except AssertionError as error:
        report["status"] = "FAIL"
        report["error"] = str(error)
        report["the_traceback"] = traceback.format_exc().splitlines()[-12:]
    except Exception as error:  # noqa: BLE001 - the receipt names every failure
        report["status"] = "FAIL"
        report["error"] = f"{type(error).__name__}: {error}"
        report["the_traceback"] = traceback.format_exc().splitlines()[-12:]
    finally:
        try:
            tool("stop", expect_success=False)
        except Exception:
            pass
        if fixture is not None:
            try:
                fixture.stop()
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
    (evidence / "measurement-coverage.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items()
                      if k not in ("steps", "browser_receipt")}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
