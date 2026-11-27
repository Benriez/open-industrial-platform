#!/usr/bin/env python3
"""Exercise the Rust License Center's synthetic --interop export in a fresh OIP."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time

from oip_license_e2e import assert_mcp_denied
from oip_license_issue import proof_request
from oip_local_operator import RELEASE, ROOT, WEB, session, stop, until
from oip_opcua_parity import McpClient, api, free_port


def exercise(args, directory):
    artifacts = args.issuer_artifacts
    oip_proof = (artifacts / "oip.license.json").read_bytes()
    odp_proof = (artifacts / "odp.license.json").read_bytes()
    policy = (artifacts / "oip-policy.json").resolve(strict=True)
    root = directory / "instance"
    port, simulator_port = free_port(), free_port()
    while port == simulator_port:
        simulator_port = free_port()
    base = f"http://127.0.0.1:{port}"
    command = [
        sys.executable, ROOT / "tools/oip_local.py", "--instance", root,
        "--core", args.core, "--simulator", args.simulator, "--web", args.web,
    ]
    subprocess.run([
        *command, "setup", "--organization", "Testbetrieb",
        "--infrastructure", "Testhalle", "--site", "Teststand",
        "--backup-directory", directory / "backup", "--port", str(port),
        "--simulator-port", str(simulator_port),
    ], check=True, timeout=45, stdout=subprocess.DEVNULL)
    install = [
        *command, "install-license-policy", "--license-policy", policy,
        "--commercial-license-kind", "commercial",
    ]
    approval = json.loads(subprocess.check_output(install, timeout=25))["confirmation"]
    subprocess.run([*install, "--confirm", approval], check=True, timeout=25, stdout=subprocess.DEVNULL)

    process = None
    client = None
    try:
        process = subprocess.Popen([*command, "run"], stdout=subprocess.PIPE, text=True)
        browser, csrf = session(command, process, base)
        path = "/api/v2/license"
        headers = {"Origin": base, "x-oip-csrf": csrf}
        assert api(base, path, opener=browser)[1]["proof_state"] == "missing"
        status, refusal = api(base, path + "/preview", "POST",
                              proof_request(odp_proof), headers, browser)
        assert status == 400 and refusal["code"] == "LICENSE_PROOF_INVALID"
        client = McpClient(args.core, root / "ipc.sock", root / "operator.credential", "operator")
        assert_mcp_denied(client, "license_proof_preview", proof_request(odp_proof), "LICENSE_PROOF_INVALID")
        review = client.call("license_proof_preview", proof_request(oip_proof))
        assert api(base, path, opener=browser)[1]["proof_state"] == "missing"
        code, license_status = api(base, path + "/apply", "POST",
                               {"confirmation": review["confirmation"]}, headers, browser)
        assert code == 200
        assert license_status["proof_state"] == "verified"
        assert license_status["commercial"] == "active" and license_status["support"] == "not_granted"
        assert client.call("license_status_read") == license_status
        client.close()
        client = None
        stop(process)
        process = subprocess.Popen([*command, "run"], stdout=subprocess.PIPE, text=True)
        browser, _ = session(command, process, base)
        assert api(base, path, opener=browser) == (200, license_status)
        assert (root / "core.license.json").read_bytes() == oip_proof
        restarted_at = time.time_ns() // 1_000_000

        def has_fresh_simulation():
            status, values = api(base, "/api/v2/observations?source=local-simulation", opener=browser)
            return status == 200 and any(
                (value["timestamps"]["received"] or 0) > restarted_at for value in values
            )

        until(has_fresh_simulation, "OIP failed to deliver fresh simulator data after restart")
    finally:
        if client is not None:
            client.close()
        stop(process)
    return {
        "status": "PASS",
        "oip_revision": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True,
        ).strip(),
        "oip_core_sha256": hashlib.sha256(args.core.read_bytes()).hexdigest(),
        "oip_proof_sha256": hashlib.sha256(oip_proof).hexdigest(),
        "odp_proof_sha256": hashlib.sha256(odp_proof).hexdigest(),
        "tests": ["odp_proof_denied", "mcp_preview_rest_confirmation", "byte_exact_storage",
                  "license_status_persisted", "simulator_data_after_restart"],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--issuer-artifacts", type=Path, required=True)
    parser.add_argument("--core", type=Path, default=RELEASE / "oip-server")
    parser.add_argument("--simulator", type=Path, default=RELEASE / "oip-simulated-server")
    parser.add_argument("--web", type=Path, default=WEB)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="oip-rust-issuer-", dir="/private/tmp") as temp:
        result = exercise(args, Path(temp))
    payload = json.dumps(result, indent=2) + "\n"
    args.evidence.parent.mkdir(parents=True, exist_ok=True)
    args.evidence.write_text(payload)
    print(payload, end="")


if __name__ == "__main__":
    main()
