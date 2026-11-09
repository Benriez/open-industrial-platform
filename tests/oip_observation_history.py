#!/usr/bin/env python3
"""The persisted observation history of the real device (G6).

The gate G6 asks for **historical observations, freshness, diagnostics,
reconnect and failure recovery** — and the record claimed "measurements and
history proven against the fixture" while the history of a real device had no
receipt of its own: the canonical acceptance checks that the persisted
history of the connected device exists and that every stored sample is
stale, and nothing more.

This rehearsal measures the history of the measurements of a **real device**
against the real Core and an owned loopback SSH fixture:

  * the history **grows** with the polling of the device — the samples are
    persisted, not computed for the request;
  * every stored sample is **stale**: a stored sample is never drawn as a
    live value, while the current route of the same metric reports the live
    one;
  * the order is **ascending by the receive time**, and the receive time is
    present; the cursor walks the history forward, the pages are **disjoint**
    and no sample is lost or repeated;
  * the stable id of a sample **deduplicates** the history;
  * the history is **scoped**: a device of another organization and a device
    that does not exist are refused identically, so the answer does not
    disclose whether the target exists;
  * the history **survives the restart** of the instance and the collection
    resumes — the observations are persisted, not held in the memory.

Nothing of the rehearsal touches the personal installation of the operator, no
private endpoint is contacted and no hardware is invented: the host is an
owned SSH fixture on the loopback.

Usage:
  python3 tests/oip_observation_history.py [--evidence DIR] [--binary PATH]
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
THE_DEVICE = "history-device"
THE_FOREIGN_DEVICE = "foreign-device"
THE_MISSING_DEVICE = "missing-device"


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


def the_samples(page):
    """The observations of a page of the history, in the order of the Core."""
    out = []
    for item in page.get("items", []):
        if item.get("category") != "observation":
            continue
        record = item.get("record") or {}
        observation = record.get("observation") or {}
        out.append({
            "id": record.get("id"),
            "metric_id": observation.get("metric_id"),
            "data_source_id": observation.get("data_source_id"),
            "entity_id": observation.get("entity_id"),
            "freshness": observation.get("freshness"),
            "quality": observation.get("quality"),
            "received_ms": (observation.get("timestamps") or {}).get("received"),
            "source_ms": (observation.get("timestamps") or {}).get("source"),
            "value": observation.get("value"),
        })
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-observation-history"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-observation-history-v1", "steps": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-history-")).resolve()
    work.chmod(0o700)
    fixture = None
    try:
        fixture = SshFixture()
        report["ssh_fixture"] = {"port": fixture.port, "user": fixture.user,
                                 "loopback_only": True}
        http_port = free_port()
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
        plan = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        plan["sources"] = []
        plan["bindings"] = [item for item in plan["bindings"]
                            if item["scope"]["kind"] != "source"]
        plan["roles"].append({"id": "inventory-admin", "name": "Explicit scoped operator",
                               "permissions": ["inventory_manage", "devices_read",
                                               "telemetry_read"]})
        for principal, organization in (("reader-org-a", "org-a"),
                                        ("reader-org-b", "org-b")):
            plan["bindings"].append({"principal_id": principal,
                                     "role_id": "inventory-admin",
                                     "scope": {"kind": "organization", "id": organization}})
        (work / "plan.json").write_text(json.dumps(plan, indent=2))
        credentials = {}
        clients = []
        for principal in ("reader-org-a", "reader-org-b"):
            credential = work / f"{principal}.credential"
            credential.write_bytes(secrets.token_bytes(32))
            credential.chmod(0o600)
            credentials[principal] = credential
            clients.append({"uid": os.getuid(), "credential_file": str(credential),
                            "policy": {"principal": principal}})
        (work / "ipc.json").write_text(json.dumps({
            "socket": str(work / "s"), "max_sessions": 16, "clients": clients,
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

        def login(principal):
            minted = json.loads(subprocess.check_output(
                [args.binary, "--browser-login", "--ipc-socket", str(work / "s"),
                 "--ipc-credential", str(credentials[principal])], text=True))
            jar = http.cookiejar.CookieJar()
            opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
            status, session = request(base, "/api/v2/browser/login",
                                      {"code": minted["login_code"]},
                                      {"Origin": base}, opener)
            assert status == 200, session
            headers = {"Origin": base, "x-oip-csrf": session["csrf_token"]}
            return opener, headers

        tool("provision-plan", "--plan", str(work / "plan.json"))
        tool("start")
        time.sleep(3)
        report["steps"].append("the instance runs")

        opener, headers = login("reader-org-a")
        foreign_opener, foreign_headers = login("reader-org-b")

        # the device of the authorized scope and the device of the other
        # organization
        status, answer = request(base, "/api/v2/inventory/apply", {"changes": [{
            "operation": "register",
            "device": {"id": THE_DEVICE, "display_name": "History device",
                       "device_type": "single_board_computer", "site_id": "site-a1",
                       "metadata": {}}}]}, headers, opener)
        assert status == 200, f"the device was not registered: {answer}"
        status, answer = request(base, "/api/v2/inventory/apply", {"changes": [{
            "operation": "register",
            "device": {"id": THE_FOREIGN_DEVICE, "display_name": "Foreign device",
                       "device_type": "single_board_computer", "site_id": "site-b1",
                       "metadata": {}}}]}, foreign_headers, foreign_opener)
        assert status == 200, f"the foreign device was not registered: {answer}"

        # the connection with the confirmed host key
        endpoint = {"host": "127.0.0.1", "port": fixture.port, "user": fixture.user,
                    "identity_profile": "fixture"}
        target = {"kind": "existing", "id": THE_DEVICE, "expected_revision": 1}
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
        status, answer = request(base, "/api/v2/device-connections", {
            "operation": "trust_host_key", "plan_id": plan_id, "fingerprint": fingerprint},
            headers, opener)
        assert status == 200, f"the host key was not accepted: {answer}"
        status, answer = request(base, "/api/v2/device-connections", {
            "operation": "verify", "plan_id": plan_id}, headers, opener)
        assert status == 200, f"the verification failed: {answer}"
        wait_stage("verification_complete")
        status, answer = request(base, "/api/v2/device-connections", {
            "operation": "confirm", "plan_id": plan_id, "identity_confirmed": True,
            "enable_monitoring": True, "poll_seconds": 10}, headers, opener)
        assert status == 200, f"the confirmation failed: {answer}"
        report["steps"].append("the device is connected, verified and confirmed")

        def history(opener_, device, limit=100, cursor=None):
            query = f"device={device}&limit={limit}"
            if cursor:
                query += f"&cursor={cursor}"
            status, page = request(base, f"/api/v2/observations/history?{query}",
                                   opener=opener_)
            assert status == 200, f"the history is not readable: {page}"
            return page

        # 1. the history grows with the polling of the device
        deadline = time.monotonic() + 180
        first = None
        while time.monotonic() < deadline:
            page = history(opener, THE_DEVICE)
            samples = the_samples(page)
            moments = {item["received_ms"] for item in samples}
            if samples and len(moments) >= 2:
                first = (page, samples)
                break
            time.sleep(2)
        assert first, "the history of the device did not grow"
        page, samples = first
        report["the_history_grows"] = {
            "the_samples": len(samples),
            "the_moments": len({item["received_ms"] for item in samples}),
            "the_metrics": sorted({item["metric_id"] for item in samples}),
        }
        report["steps"].append("the history of the device grows with the polling")

        # 2. every stored sample is stale
        not_stale = [item for item in samples if item["freshness"] != "stale"]
        report["the_samples_that_are_not_stale"] = len(not_stale)
        assert not not_stale, f"a stored sample is not reported as stale: {not_stale[:3]}"

        # 3. the order is ascending by the receive time, and it is present
        moments = [item["received_ms"] for item in samples]
        assert all(moment is not None for moment in moments), "a sample has no receive time"
        report["the_order_is_ascending_by_the_receive_time"] = moments == sorted(moments)
        assert report["the_order_is_ascending_by_the_receive_time"], "the history is not ordered"

        # 4. the stable id deduplicates the history
        ids = [item["id"] for item in samples]
        report["the_ids_are_unique"] = len(set(ids)) == len(ids)
        report["the_ids_are_stable_keys"] = all(
            isinstance(value, str) and len(value) == 64 for value in ids)
        assert report["the_ids_are_unique"], "the history repeats a sample"
        assert report["the_ids_are_stable_keys"], "the id of a sample is not a stable key"

        # 5. the cursor walks the history forward: the pages are disjoint and
        #    no sample is lost
        walked = []
        cursor = None
        pages = 0
        while True:
            page = history(opener, THE_DEVICE, limit=1, cursor=cursor)
            walked.extend(the_samples(page))
            pages += 1
            if not page.get("truncated"):
                assert page.get("next_cursor") is None, "a last page offers a continuation"
                break
            cursor = page.get("next_cursor")
            assert cursor, "a truncated page offers no continuation"
            assert pages <= len(samples) + 2, "the cursor does not end"
        report["the_pages_of_the_continuation"] = pages
        report["the_walk_is_disjoint"] = len({item["id"] for item in walked}) == len(walked)
        assert report["the_walk_is_disjoint"], "the continuation repeats a sample"
        assert len(walked) == len(samples), \
            f"the continuation lost a sample: {len(walked)} of {len(samples)}"
        report["the_continuation_is_complete"] = True

        # 6. the current route of the same metric is live, the history is not
        _, value = request(base, "/api/v2/device-connections?device_id=" + THE_DEVICE,
                           opener=opener)
        source_id = (value.get("connection") or {}).get("source_id")
        assert source_id, "the connection has no source"
        status, current = request(base, f"/api/v1/metrics/current?source={source_id}",
                                  opener=opener)
        assert status == 200, f"the current observations are not readable: {current}"
        live = [item for item in current if item.get("metric_id") in
                {sample["metric_id"] for sample in samples}]
        report["the_current_observations"] = len(live)
        report["the_current_ones_are_not_stale"] = all(
            item.get("freshness") != "stale" for item in live)
        assert live, "the source of the device delivers no current observation"
        assert report["the_current_ones_are_not_stale"], \
            "a current observation is reported as stale"
        report["the_distinction_of_the_freshness"] = {
            "the_history": "stale", "the_current": live[0].get("freshness")}

        # 7. the scope: a foreign device and a device that does not exist are
        #    refused identically
        status_foreign, foreign = request(
            base, f"/api/v2/observations/history?device={THE_FOREIGN_DEVICE}",
            opener=opener)
        status_missing, missing = request(
            base, f"/api/v2/observations/history?device={THE_MISSING_DEVICE}",
            opener=opener)
        report["the_foreign_device"] = {"the_status": status_foreign,
                                        "the_code": foreign.get("code")}
        report["the_missing_device"] = {"the_status": status_missing,
                                        "the_code": missing.get("code")}
        report["the_answers_are_identical"] = (status_foreign == status_missing
                                               and foreign.get("code") == missing.get("code"))
        assert status_foreign == 404, f"the foreign device was not refused: {foreign}"
        assert foreign.get("code") == "RESOURCE_NOT_ACCESSIBLE", foreign
        assert report["the_answers_are_identical"], \
            "the answer discloses whether the device exists"

        # 8. the history survives the restart of the instance
        before = {item["id"] for item in samples}
        tool("stop")
        time.sleep(2)
        tool("start")
        time.sleep(4)
        opener, headers = login("reader-org-a")
        after_samples = the_samples(history(opener, THE_DEVICE))
        after = {item["id"] for item in after_samples}
        report["the_history_survives_the_restart"] = {
            "the_samples_before": len(before), "the_samples_after": len(after),
            "the_samples_that_stayed": len(before & after),
        }
        assert before <= after, "the restart lost the persisted observations"
        report["steps"].append("the history survives the restart of the instance")

        # 9. the collection resumes after the restart
        deadline = time.monotonic() + 180
        resumed = False
        while time.monotonic() < deadline:
            grown = the_samples(history(opener, THE_DEVICE))
            if len(grown) > len(after):
                resumed = True
                break
            time.sleep(2)
        report["the_collection_resumes_after_the_restart"] = resumed
        assert resumed, "the collection did not resume after the restart"
        report["steps"].append("the collection resumes after the restart")

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
    (evidence / "observation-history.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "steps"}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
