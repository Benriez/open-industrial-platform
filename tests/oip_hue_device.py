#!/usr/bin/env python3
"""The Philips Hue Bridge as a real device of the operator, measured.

The bridge of the operator is a real device in the network of the operator.
It is **onboarded** like the other devices of the operator: its identity is
**verified** (the certificate of the bridge is pinned, exactly the way the
host key of an SSH host is pinned), the identity is written into the
inventory of the Core through the **authorized session**, and the limits of
the capability are **named** instead of being simulated.

The rehearsal measures:

  1. the **verified read** of the bridge: the public configuration over one
     TLS session in which the presented certificate is verified against the
     pin (`tools/oip_hue.py`);
  2. the **honest limit**: the bridge refuses the lights without an
     application token, and the creation of a token is a **write on the
     device** that belongs to the operator — the capability is therefore
     **read-only**, and nothing is simulated;
  3. the **negative control**: a bridge that presents another certificate is
     refused by the same path (the identity of a device may not change
     unnoticed);
  4. the **onboarding**: the device is registered in a disposable Core
     through the authorized session, the record is read back, and a principal
     of **another organization** does not see it;
  5. the **collector**: the Core reads the bridge through a pinned profile and
     persists the verified identity as measurements of the registered device —
     and, when the operator supplies a token, the state and the brightness of
     every light;
  6. the **negative control of the collector**: a profile whose pin is not the
     certificate of the bridge produces no measurement at all.

The rehearsal never writes on the bridge: every request is a `GET`.

Usage:
  python3 tests/oip_hue_device.py [--evidence DIR] [--host 192.168.1.131]
"""
import argparse
import hashlib
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
TOOL = ROOT / "tools" / "oip_hue.py"
PIN = ROOT / "docs/release/hue/bridge-certificate.pem"


def free_port() -> int:
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def request(base, path, method="GET", payload=None, headers=None, opener=None):
    data = json.dumps(payload).encode() if payload is not None else None
    head = {"Content-Type": "application/json"}
    head.update(headers or {})
    head.setdefault("Origin", base)
    call = urllib.request.Request(base + path, data=data, headers=head, method=method)
    try:
        with (opener or urllib.request).open(call, timeout=30) as answer:
            body = answer.read().decode("utf-8", "replace")
            try:
                return answer.status, json.loads(body)
            except ValueError:
                return answer.status, {"the_body": body[:400]}
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", "replace")
        try:
            return error.code, json.loads(body)
        except ValueError:
            return error.code, {"the_body": body[:400]}


def measure(host: str, pin: pathlib.Path):
    result = subprocess.run([sys.executable, str(TOOL), "--host", host, "--pin", str(pin)],
                            capture_output=True, text=True, timeout=300)
    try:
        payload = json.loads(result.stdout)
    except ValueError:
        payload = {"the_status": "FAIL", "the_problems": ["the tool answered nothing"]}
    return payload


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-hue-device"))
    parser.add_argument("--host", default="192.168.1.131")
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    parser.add_argument("--pin", default=str(PIN))
    parser.add_argument("--token-file", default=None,
                        help="the application token of the operator; without it the "
                             "rehearsal measures the honest limit of the capability")
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence).resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-hue-device-v1", "steps": [], "the_problems": []}
    pin = pathlib.Path(args.pin)

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-hue-", dir="/private/tmp")).resolve()
    work.chmod(0o700)
    core = False
    try:
        # 1. the verified read of the bridge
        assert pin.is_file(), f"the pin of the bridge is missing: {pin}"
        bridge = measure(args.host, pin)
        report["the_bridge"] = bridge
        report["steps"].append("the identity of the bridge is verified against the pin")
        assert bridge.get("the_status") == "PASS", bridge.get("the_problems")
        identity = bridge["the_identity"]
        assert identity.get("the_bridge_id"), "the bridge names no bridge id"
        assert bridge["the_configuration"]["the_verification_succeeded"], \
            "the read of the bridge was not verified"

        # 2. the honest limit of the capability
        assert bridge["the_lights_without_a_token"]["the_refused"], \
            "the bridge did not refuse the lights without a token"
        report["the_capability"] = bridge["the_capability"]
        report["steps"].append("the limit of the capability is measured: no control without a token")
        # The certificate that was verified is part of the evidence: the pin
        # is the public material of the device, and the receipt names its
        # digest.
        (evidence / "bridge-certificate.pem").write_text(pin.read_text())
        report["the_certificate"] = {
            "the_file": "bridge-certificate.pem",
            "the_sha256": hashlib.sha256(pin.read_bytes()).hexdigest(),
            "the_fingerprint": bridge["the_certificate_of_the_host"]["the_fingerprint"],
        }

        # 3. the negative controls: another certificate is refused
        #
        # (a) the pin does not match the certificate of the bridge: the tool
        #     refuses before it reads anything;
        # (b) the TLS session itself refuses: the presented certificate is
        #     verified against the pin, and a bridge that presents another
        #     certificate never delivers an answer.
        wrong = work / "wrong-certificate.pem"
        generated = subprocess.run(
            ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-keyout",
             str(work / "wrong-key.pem"), "-out", str(wrong), "-days", "2", "-nodes",
             "-subj", "/CN=not-the-bridge-of-the-operator"],
            capture_output=True, text=True, timeout=120)
        assert generated.returncode == 0, generated.stderr
        refused = measure(args.host, wrong)
        report["the_negative_control"] = {
            "the_status": refused.get("the_status"),
            "the_problems": refused.get("the_problems"),
        }
        assert refused.get("the_status") == "FAIL", \
            "a bridge that presents another certificate was not refused"
        session = subprocess.run(
            ["openssl", "s_client", "-connect", f"{args.host}:443",
             "-servername", args.host, "-CAfile", str(wrong), "-partial_chain",
             "-verify_return_error", "-quiet"],
            input=b"GET /api/config HTTP/1.1\r\nHost: " + args.host.encode()
                  + b":443\r\nConnection: close\r\n\r\n",
            capture_output=True, timeout=60)
        report["the_negative_control"]["the_tls_exit_code"] = session.returncode
        report["the_negative_control"]["the_tls_answer"] = session.stdout.decode(
            "utf-8", "replace")[:120]
        report["the_negative_control"]["the_tls_error"] = [
            line for line in session.stderr.decode("utf-8", "replace").splitlines()
            if "verify" in line.lower()][:3]
        assert session.returncode != 0, \
            "the TLS session accepted a bridge with another certificate"
        assert not session.stdout, \
            "the TLS session delivered an answer of an unverified bridge"
        report["steps"].append("a bridge with another certificate is refused")

        # 4. the onboarding in a disposable Core through the authorized session
        port = free_port()
        plan = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        plan["sources"] = []
        plan["bindings"] = [binding for binding in plan["bindings"]
                            if binding["scope"].get("kind") != "source"]
        plan["roles"].append({"id": "inventory-admin", "name": "Inventory administrator",
                              "permissions": ["inventory_manage", "devices_read",
                                              "core_read", "hierarchy_read"]})
        plan["bindings"].append({"principal_id": "platform-reader", "role_id": "inventory-admin",
                                 "scope": {"kind": "platform"}})
        plan["bindings"].append({"principal_id": "reader-org-b", "role_id": "inventory-admin",
                                 "scope": {"kind": "organization", "id": "org-b"}})
        (work / "plan.json").write_text(json.dumps(plan, indent=2))
        (work / "core.json").write_text(json.dumps({
            "database": str(work / "core.sqlite"), "http_port": port,
            "sources": [], "legacy_single_infrastructure": False,
        }, indent=2))
        credential = work / "platform.credential"
        credential.write_bytes(secrets.token_bytes(32))
        credential.chmod(0o600)
        # The second principal belongs to the **other** organization: it is
        # the negative control of the scope.
        other_credential = work / "other.credential"
        other_credential.write_bytes(secrets.token_bytes(32))
        other_credential.chmod(0o600)
        (work / "ipc.json").write_text(json.dumps({
            "socket": str(work / "s"), "max_sessions": 16,
            "clients": [{"uid": os.getuid(), "credential_file": str(credential),
                         "policy": {"principal": "platform-reader"}},
                        {"uid": os.getuid(), "credential_file": str(other_credential),
                         "policy": {"principal": "reader-org-b"}}],
        }, indent=2))
        (work / "ipc.json").chmod(0o600)
        state = work / "state"

        def tool(*arguments, expect_success=True):
            result = subprocess.run(
                [sys.executable, str(ROOT / "tools/oip_ops.py"), "--state-dir", str(state),
                 "--config", str(work / "core.json"), "--ipc-config", str(work / "ipc.json"),
                 "--binary", args.binary, *arguments],
                capture_output=True, text=True, timeout=600)
            if expect_success and result.returncode != 0:
                raise AssertionError(f"{arguments[0]} failed: "
                                     f"{result.stderr.strip() or result.stdout.strip()}")
            return result

        tool("provision-plan", "--plan", str(work / "plan.json"))
        tool("start")
        core = True
        base = f"http://127.0.0.1:{port}"
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            probe = subprocess.run(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
                                    "--max-time", "5", base + "/health/live"],
                                   capture_output=True, text=True)
            if probe.stdout.strip() not in ("000", ""):
                break
            time.sleep(0.5)

        # the session of the operator: the one-time code over the local IPC
        def login(credential_file):
            minted = subprocess.run([args.binary, "--browser-login", "--ipc-socket",
                                     str(work / "s"), "--ipc-credential", str(credential_file)],
                                    capture_output=True, text=True, timeout=60)
            assert minted.returncode == 0, minted.stderr
            code = json.loads(minted.stdout)["login_code"]
            jar = http.cookiejar.CookieJar()
            client = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
            status, _ = request(base, "/api/v2/browser/login", "POST", {"code": code}, opener=client)
            assert status == 200, f"login returned HTTP {status}"
            status, session = request(base, "/api/v2/browser/session", opener=client)
            assert status == 200 and session["authenticated"], f"session returned HTTP {status}"
            return client, {"x-oip-csrf": session["csrf_token"]}

        opener, csrf = login(credential)

        # the device of the bridge with the identity that was verified
        fingerprint = bridge["the_certificate_of_the_host"]["the_fingerprint"]
        device = {
            "id": "hue-bridge",
            "display_name": f"Philips Hue Bridge {identity['the_model_id']}",
            "device_type": "network_device",
            "site_id": "site-a1",
            "metadata": {
                "manufacturer": "Philips Hue",
                "model": identity["the_model_id"],
                "operating_system": (f"Hue firmware {identity['the_software_version']}, "
                                     f"API {identity['the_api_version']}"),
                "hostname": "hue-bridge",
                "ip_address": args.host,
                "mac_address": identity["the_mac"],
                "serial_number": identity["the_bridge_id"],
                "description": ("Die Identität der Bridge ist gegen das gepinnte "
                                f"Zertifikat geprüft ({fingerprint})."),
                "tags": ["hue-bridge", "read-only"],
                "notes": ("Die Lichter, Gruppen und Szenen brauchen ein Applikationstoken. "
                          "Das Token ist ein Schreibzugriff auf dem Gerät und gehört dem "
                          "Betreiber. Die Fähigkeit ist lesend; es wird nichts simuliert."),
            },
        }
        status, answer = request(base, "/api/v2/inventory/apply", "POST",
                                 {"changes": [{"operation": "register", "device": device}]},
                                 headers=csrf, opener=opener)
        report["the_registration"] = {"the_status": status}
        assert status == 200, answer
        status, page = request(base, "/api/v2/inventory/devices?id=hue-bridge", opener=opener)
        report["the_record"] = {"the_status": status}
        assert status == 200, page
        items = page.get("items") or []
        assert len(items) == 1, f"the Core holds {len(items)} devices of the bridge"
        record = items[0]
        report["the_record"]["the_device"] = record
        held = (record.get("record") or {}).get("device") or {}
        assert held.get("display_name") == device["display_name"], record
        assert held.get("device_type") == "network_device", record
        metadata = held.get("metadata") or {}
        assert metadata.get("serial_number") == identity["the_bridge_id"], metadata
        assert metadata.get("mac_address") == identity["the_mac"], metadata
        assert metadata.get("model") == identity["the_model_id"], metadata
        report["steps"].append("the bridge is onboarded and its verified identity is readable")

        # the scope: a principal of another organization does not see it
        other_opener, _ = login(other_credential)
        status, page = request(base, "/api/v2/inventory/devices?id=hue-bridge",
                                opener=other_opener)
        report["the_scope"] = {"the_status": status,
                               "the_items": len(page.get("items") or []),
                               "the_answer": page}
        # The answer does not disclose whether the target exists: a foreign
        # device is refused like a device that does not exist.
        assert status in (200, 404), page
        assert not (page.get("items") or []), \
            "a principal of another organization sees the device of the bridge"
        report["steps"].append("a principal of another organization does not see the bridge")

        # 5. the collector: the Core reads the bridge through the pinned profile
        profile = {
            "id": "lan",
            "label": "The bridge of the operator in the LAN",
            "principals": ["platform-reader"],
            "device_id": "hue-bridge",
            "host": args.host,
            "port": 443,
            "poll_seconds": 10,
            "pin_file": str(pin),
        }
        if args.token_file:
            token_file = pathlib.Path(args.token_file).resolve()
            assert token_file.is_file(), f"the token file does not exist: {token_file}"
            assert token_file.stat().st_mode & 0o077 == 0, "use a private token file"
            profile["token_file"] = str(token_file)
        tool("stop")
        core = False
        config = json.loads((work / "core.json").read_text())
        config["hue"] = {"profiles": [profile]}
        (work / "core.json").write_text(json.dumps(config, indent=2))
        tool("start")
        core = True
        opener, csrf = login(credential)
        observed = {}
        for _ in range(60):
            status, detail = request(base, "/api/v2/devices/hue-bridge", opener=opener)
            assert status == 200, f"collector device returned HTTP {status}"
            assert detail["device"]["connection"] == "Hue HTTPS", detail["device"]["connection"]
            observed = {
                o["metric_id"]: next(iter(o["value"].values()))
                for o in detail["metrics"] if o["value"] is not None and o["quality"] == "good"
            }
            if {"bridge.bridge_id", "bridge.model_id", "bridge.api_version", "bridge.mac"} <= observed.keys():
                if not args.token_file or any(m.startswith("light.") for m in observed):
                    break
            time.sleep(1)
        report["the_collector"] = {
            "the_profile": {k: v for k, v in profile.items() if k != "token_file"},
            "the_token_configured": bool(args.token_file),
            "the_metrics": observed,
            "the_read": any(metric.startswith("bridge.") for metric in observed),
        }
        assert observed.get("bridge.bridge_id") == identity["the_bridge_id"], observed
        assert observed.get("bridge.model_id") == identity["the_model_id"], observed
        assert observed.get("bridge.api_version") == identity["the_api_version"], observed
        assert observed.get("bridge.mac") == identity["the_mac"], observed
        for metric, value in observed.items():
            assert metric.startswith(("bridge.", "lights.", "light.")), metric
            assert value is not None, (metric, value)
        if args.token_file:
            assert (observed.get("lights.total") or 0) > 0, "no light was read with the token"
            assert any(metric.startswith("light.") for metric in observed), observed
            report["steps"].append(
                "the lights of the bridge are read with the token of the operator")
        else:
            assert not any(metric.startswith(("light.", "lights.")) for metric in observed), \
                "the collector reported a light without a token of the operator"
            report["steps"].append(
                "the collector reads the identity of the bridge and names the limit of the token")

        other_opener, _ = login(other_credential)
        hidden, _ = request(base, "/api/v2/devices/hue-bridge", opener=other_opener)
        missing, _ = request(base, "/api/v2/devices/nonexistent-bridge", opener=other_opener)
        assert hidden in (403, 404) and hidden == missing, (hidden, missing)
        report["the_scope"]["the_collected_device_status"] = hidden

        lights_path = "/api/v2/hue/lights"
        read_status, lights = request(base, lights_path + "?source=hue-lan", opener=opener)
        if args.token_file:
            assert read_status == 200 and lights["can_control"] is False and lights["can_setup"] is False
            assert len(lights["lights"]) == observed["lights.total"]
        else:
            assert read_status == 503 and lights["code"] == "HUE_PAIRING_AVAILABLE"
        hidden_status, _ = request(base, lights_path + "?source=hue-lan", opener=other_opener)
        assert hidden_status == 404
        # An impossible resource id is sufficient to prove that these requests
        # are refused before any bridge write.
        action = {"source": "hue-lan", "light_id": 4294967295, "change": {"kind": "power", "on": True}}
        disabled, _ = request(base, lights_path, "POST", action, headers=csrf, opener=opener)
        missing_csrf, _ = request(base, lights_path, "POST", action, opener=opener)
        assert disabled == missing_csrf == 403
        report["dashboard"] = {"read": read_status, "foreign_read": hidden_status,
                               "monitor_only_write": disabled, "missing_csrf": missing_csrf}
        # Setup must not reach the bridge without the CSRF token or for a
        # profile configured for monitoring only when searching for devices.
        setup_path = "/api/v2/hue/setup"
        search = {"source": "hue-lan", "action": "search_lights"}
        no_csrf, _ = request(base, setup_path, "POST", search, opener=opener)
        read_only, _ = request(base, setup_path, "POST", search, headers=csrf, opener=opener)
        assert no_csrf == read_only == 403


        # 6. the negative control of the collector: a pin that is not the
        # certificate of the bridge reads nothing.
        status, answer = request(base, "/api/v2/inventory/apply", "POST",
                                 {"changes": [{"operation": "register", "device": {
                                     "id": "hue-bridge-unverified",
                                     "display_name": "A bridge with an unverified identity",
                                     "device_type": "network_device",
                                     "site_id": "site-a1",
                                     "metadata": {"tags": ["negative-control"]},
                                 }}]}, headers=csrf, opener=opener)
        assert status == 200, answer
        tool("stop")
        core = False
        config["hue"] = {"profiles": [profile, {
            "id": "unverified",
            "label": "A bridge whose certificate is not the pinned one",
            "principals": ["platform-reader"],
            "device_id": "hue-bridge-unverified",
            "host": args.host,
            "port": 443,
            "poll_seconds": 10,
            "pin_file": str(wrong),
        }]}
        (work / "core.json").write_text(json.dumps(config, indent=2))
        tool("start")
        core = True
        opener, _ = login(credential)
        pin_fault = False
        for _ in range(25):
            status, detail = request(base, "/api/v2/devices/hue-bridge-unverified", opener=opener)
            assert status == 200, f"wrong-pin device returned HTTP {status}"
            assert detail["device"]["data_source_id"] == "hue-unverified", detail["device"]
            assert not detail["metrics"], "an unverified bridge produced measurements"
            pin_fault = any("hue-unverified" in line and "HUE_IDENTITY_CHANGED" in line
                            for line in (state / "oip.log").read_text().splitlines())
            if pin_fault:
                break
            time.sleep(1)
        assert pin_fault, "collector did not report a certificate rejection for hue-unverified"
        report["the_collector"]["the_unverified_profile"] = {
            "the_metrics": {}, "the_reads": 0, "the_fault": "HUE_IDENTITY_CHANGED",
        }
        report["steps"].append(
            "a collector whose pin is not the certificate of the bridge reads nothing")

        # the Core stops and nothing of the rehearsal stays behind
        tool("stop")
        core = False
        orphans = subprocess.run(["pgrep", "-f", str(work)],
                                 capture_output=True, text=True).stdout.strip()
        report["the_orphaned_processes"] = [line for line in orphans.splitlines() if line]
        assert not report["the_orphaned_processes"], \
            f"the rehearsal left a process behind: {report['the_orphaned_processes']}"
        report["steps"].append("the Core stops and no process of the rehearsal stays behind")
        report["the_status"] = "PASS"
    except AssertionError as error:
        report["the_status"] = "FAIL"
        report["the_problems"].append(str(error))
    except Exception as error:  # a fact of the machine, not a claim
        report["the_status"] = "FAIL"
        report["the_problems"].append(f"{type(error).__name__}: {error}")
    finally:
        if core:
            subprocess.run([sys.executable, str(ROOT / "tools/oip_ops.py"),
                            "--state-dir", str(work / "state"),
                            "--config", str(work / "core.json"),
                            "--ipc-config", str(work / "ipc.json"),
                            "--binary", args.binary, "stop"],
                           capture_output=True, text=True, timeout=300)
        shutil.rmtree(work, ignore_errors=True)

    report["the_revision"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    report["the_tree"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip()
    report["the_working_tree_is_clean"] = not subprocess.run(
        ["git", "status", "--porcelain"], cwd=ROOT, capture_output=True,
        text=True).stdout.strip()
    report["the_read_only"] = "every request to the bridge during this rehearsal was a GET"
    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "hue-device.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"the_status": report["the_status"],
                      "the_steps": len(report["steps"]),
                      "the_problems": report["the_problems"]}, indent=2))
    return 0 if report["the_status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
