#!/usr/bin/env python3
"""The disposable instance of the Core on the Raspberry Pi, measured.

The intended architecture is a **Rust OIP Core on `bodi-pi`** and the Flutter
client on the Mac. The cross build of the workspace for the target of the Pi
and the bundle of the instance are measured already; what was missing is the
**runtime**: a Core that really runs on the host, answers through a tunnel of
the loopback and serves an authorized session.

This rehearsal measures exactly that, end to end:

  1. the cross build of the workspace for the target of the Pi (the artefacts
     are rebuilt when they do not carry the current revision);
  2. the bundle of the instance (the binaries, the tool, the generator, the
     scripts, the digest of every file);
  3. the facts of the host **before** the instance (the running services of
     the operator, the listeners);
  4. the copy of the bundle to the host and the **start by hand** — no
     service, no published port, nothing outside the directory of the
     instance;
  5. the verification **through a tunnel of the loopback**: the Core answers
     on the loopback of the Mac, the session of the operator is authorized
     with a code that was minted on the Pi, and the authorized projection is
     delivered;
  6. the **stop** of the instance and the facts of the host **after** it: the
     services of the operator are the same list, the instance answers
     nothing anymore.

The rehearsal needs the host of the operator: it is not part of the
reproducible refresh of the release, it is the measurement of the deployment.

Usage:
  python3 tests/oip_pi_instance.py [--evidence DIR] [--host bodi-pi]
                                   [--skip-build]
"""
import argparse
import http.cookiejar
import json
import os
import pathlib
import re
import shutil
import signal
import socket
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILDER = ROOT / "tools" / "oip_pi_build.sh"
BUNDLER = ROOT / "tools" / "oip_pi_bundle.sh"
TARGET = "aarch64-unknown-linux-gnu"
REMOTE_DIRECTORY = "~/oip-bundle"
CORE_PORT = 18808
SOURCE_PORT = 18809


def run(command, timeout=600, input_bytes=None):
    result = subprocess.run(command, capture_output=True, input=input_bytes,
                            timeout=timeout)
    return {"the_command": command if isinstance(command, str) else " ".join(command),
            "the_code": result.returncode,
            "the_output": result.stdout.decode("utf-8", "replace").strip(),
            "the_error": result.stderr.decode("utf-8", "replace").strip()}


def ssh(host, script, timeout=600):
    return run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", host, script],
               timeout=timeout)


def free_port() -> int:
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def the_services(host):
    """The running services of the host: the property of the operator."""
    answer = ssh(host, "systemctl list-units --type=service --state=running "
                       "--no-pager --no-legend 2>/dev/null | awk '{print $1}' | sort")
    return [line for line in answer["the_output"].splitlines() if line]


def the_listeners(host):
    answer = ssh(host, "ss -ltn 2>/dev/null | tail -n +2 | awk '{print $4}' | sort")
    return [line for line in answer["the_output"].splitlines() if line]


def request(base, path, method="GET", payload=None, headers=None, opener=None):
    data = json.dumps(payload).encode() if payload is not None else None
    head = {"Content-Type": "application/json"}
    head.update(headers or {})
    head.setdefault("Origin", base)
    req = urllib.request.Request(base + path, data=data, headers=head, method=method)
    try:
        with (opener or urllib.request).open(req, timeout=20) as answer:
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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-pi-instance"))
    parser.add_argument("--host", default="bodi-pi")
    parser.add_argument("--skip-build", action="store_true")
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-pi-instance-v1", "steps": [], "the_problems": []}
    tunnel = None
    local_port = free_port()

    try:
        # 1. the cross build for the target of the host
        artefacts = ROOT / "target" / "pi" / TARGET / TARGET / "release"
        revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT,
                                           text=True).strip()
        if not args.skip_build:
            built = run(["sh", str(BUILDER), TARGET], timeout=1800)
            report["the_cross_build"] = {"the_code": built["the_code"],
                                         "the_output": built["the_output"][-600:]}
            assert built["the_code"] == 0, built["the_error"]
            report["the_revision_of_the_artefacts"] = revision
            report["steps"].append("the workspace is cross built for the target of the host")
        digests = {}
        for name in ("oip-server", "oip-simulated-server"):
            path = artefacts / name
            assert path.is_file(), f"the cross build is missing {path}"
            digests[name] = subprocess.check_output(["shasum", "-a", "256", str(path)],
                                                    text=True).split()[0]
        report["the_artefacts"] = digests

        # 2. the bundle of the instance
        bundle = ROOT / "target" / "pi-bundle" / TARGET
        packed = run(["sh", str(BUNDLER), TARGET, "--out", str(bundle)], timeout=900)
        report["the_bundle"] = {"the_code": packed["the_code"],
                                "the_output": packed["the_output"][-600:]}
        assert packed["the_code"] == 0, packed["the_error"]
        report["the_bundle_digest"] = subprocess.check_output(
            ["shasum", "-a", "256", str(bundle / "MANIFEST.sha256")],
            text=True).split()[0]
        report["steps"].append("the bundle of the instance is assembled")

        # 3. the facts of the host before the instance
        services_before = the_services(args.host)
        listeners_before = the_listeners(args.host)
        report["the_services_before"] = services_before
        report["the_steps"] = []

        # 4. the copy and the start by hand
        with tempfile.TemporaryDirectory() as scratch:
            archive = pathlib.Path(scratch) / "bundle.tar.gz"
            with tarfile.open(archive, "w:gz") as tar:
                tar.add(bundle, arcname=".")
            with archive.open("rb") as handle:
                copied = run(["ssh", "-o", "BatchMode=yes", args.host,
                              f"mkdir -p {REMOTE_DIRECTORY} && tar -xzf - -C {REMOTE_DIRECTORY}"],
                             timeout=600, input_bytes=handle.read())
            report["the_copy"] = {"the_code": copied["the_code"],
                                   "the_error": copied["the_error"][-300:]}
            assert copied["the_code"] == 0, copied["the_error"]
        # The rehearsal owns the directory of the instance on the host: an
        # instance that was prepared by an earlier run (with an older
        # configuration) must not be reused.
        cleaned = ssh(args.host, f"rm -rf {REMOTE_DIRECTORY}/instance", timeout=300)
        report["the_cleanup"] = {"the_code": cleaned["the_code"]}
        assert cleaned["the_code"] == 0, cleaned["the_error"]
        started = ssh(args.host, f"cd {REMOTE_DIRECTORY} && ./bin/start.sh", timeout=900)
        report["the_start"] = {"the_code": started["the_code"],
                                "the_output": started["the_output"][-1200:],
                                "the_error": started["the_error"][-400:]}
        assert started["the_code"] == 0, started["the_error"]
        report["steps"].append("the instance is started by hand on the host")

        # 5. the verification through a tunnel of the loopback
        tunnel = subprocess.Popen(
            ["ssh", "-o", "BatchMode=yes", "-N",
             "-L", f"127.0.0.1:{local_port}:127.0.0.1:{CORE_PORT}", args.host],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        base = f"http://127.0.0.1:{local_port}"

        # the session: the code is minted on the host, over its local IPC, and
        # the session is opened through the tunnel. Every route of an instance
        # with a session needs one — the health routes included — so the
        # session is the proof that the Core of the host answers.
        minted = ssh(args.host, f"cd {REMOTE_DIRECTORY} && ./bin/login-code.sh", timeout=300)
        report["the_code_of_the_session"] = {"the_code": minted["the_code"]}
        assert minted["the_code"] == 0, minted["the_error"]
        code = json.loads(minted["the_output"])["login_code"]
        jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
        deadline = time.monotonic() + 60
        session = {"the_status": 0}
        while time.monotonic() < deadline:
            status, session = request(base, "/api/v2/browser/login", "POST",
                                      {"code": code}, opener=opener)
            if status == 200:
                break
            time.sleep(0.5)
        report["the_login"] = {"the_status": session.get("the_status", status)}
        assert status == 200, session
        report["steps"].append(
            "the Core of the host answers through the loopback of the client")
        status, answer = request(base, "/api/v2/browser/session", opener=opener)
        report["the_session"] = {"the_status": status,
                                 "the_authenticated": answer.get("authenticated")}
        assert status == 200 and answer.get("authenticated") is True, answer
        status, organizations = request(base, "/api/v2/organizations", opener=opener)
        report["the_organizations"] = {"the_status": status,
                                       "the_answer": organizations}
        assert status == 200, organizations
        status, nodes = request(base, "/api/v1/opcua/nodes?q=&folder=all&offset=0&limit=40",
                                 opener=opener)
        report["the_address_space"] = {"the_status": status,
                                       "the_total": nodes.get("total"),
                                       "the_folders": nodes.get("folders")}
        assert status == 200 and nodes.get("total"), nodes
        report["steps"].append("the session of the operator is authorized and the projection is delivered")

        # the tunnel is the only way in: nothing of the host is published
        published = [line for line in the_listeners(args.host)
                     if f":{CORE_PORT}" in line and not line.startswith("127.0.0.1")]
        report["the_published_listeners_of_the_instance"] = published
        assert not published, f"the instance published a port: {published}"
        report["steps"].append("the instance publishes no port of the host")

        # 6. the stop and the facts of the host after it
        stopped = ssh(args.host, f"cd {REMOTE_DIRECTORY} && ./bin/stop.sh", timeout=600)
        report["the_stop"] = {"the_code": stopped["the_code"],
                               "the_output": stopped["the_output"][-400:]}
        assert stopped["the_code"] == 0, stopped["the_error"]
        services_after = the_services(args.host)
        listeners_after = the_listeners(args.host)
        report["the_services_after"] = services_after
        report["the_services_are_unchanged"] = services_before == services_after
        assert services_before == services_after, \
            "the services of the operator changed while the instance ran"
        still_listening = [line for line in listeners_after
                           if f":{CORE_PORT}" in line or f":{SOURCE_PORT}" in line]
        report["the_listeners_of_the_instance_after_the_stop"] = still_listening
        assert not still_listening, "the instance still listens after the stop"
        report["the_steps"] = []
        report["steps"].append("the instance stops and the services of the operator are unchanged")
    except AssertionError as error:
        report["the_problems"].append(str(error))
    except Exception as error:  # a host that is not reachable is a fact
        report["the_problems"].append(f"{type(error).__name__}: {error}")
    finally:
        if tunnel is not None and tunnel.poll() is None:
            tunnel.send_signal(signal.SIGTERM)
            try:
                tunnel.wait(timeout=10)
            except subprocess.TimeoutExpired:
                tunnel.kill()
        # The instance is stopped in every case: the loop leaves no process
        # of its own on the host of the operator.
        try:
            ssh(args.host, f"cd {REMOTE_DIRECTORY} && ./bin/stop.sh", timeout=300)
        except Exception:
            pass

    report["the_status"] = "FAIL" if report["the_problems"] else "PASS"
    report["the_revision"] = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    report["the_tree"] = subprocess.run(
        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, capture_output=True,
        text=True).stdout.strip()
    report["the_working_tree_is_clean"] = not subprocess.run(
        ["git", "status", "--porcelain"], cwd=ROOT, capture_output=True,
        text=True).stdout.strip()
    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "pi-instance.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"the_status": report["the_status"],
                      "the_steps": len(report["steps"]),
                      "the_problems": report["the_problems"]}, indent=2))
    return 0 if report["the_status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
