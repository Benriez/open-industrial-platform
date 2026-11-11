#!/usr/bin/env python3
"""The read-only access to a Philips Hue Bridge, with a verified identity.

A Hue Bridge serves its public configuration over HTTPS with a certificate
that it issued itself: the certificate is signed by a *root* of the bridge
that the bridge does not present, so the chain of the bridge is **incomplete**
and no ordinary trust store can verify it. Two facts follow:

  * the identity of the bridge can only be verified by **pinning** its own
    certificate — exactly the way the SSH onboarding pins the host key of a
    host. The pin is the certificate of the bridge, its public material;
  * the path that reads the bridge must therefore verify the **presented**
    certificate against that pin. `curl` of this machine cannot build a chain
    for the pin (`--partial-chain` is not supported by its LibreSSL build),
    but `openssl s_client` can: it verifies the presented certificate against
    the pinned one with `-partial_chain` and refuses the connection when the
    verification fails (`-verify_return_error`).

The tool therefore reads the bridge over **one** verified TLS session and
never over an insecure one. It performs **read-only** requests: the public
configuration of the bridge and the state of its lights **without** a token —
the second one is refused by the bridge, and that refusal is the honest limit
of the capability: the lights and the groups need an application token, and
the creation of a token is a **write on the device** that belongs to the
operator.

Usage:
  python3 tools/oip_hue.py --host 192.168.1.131 --pin docs/release/hue/bridge-certificate.pem
  python3 tools/oip_hue.py --host 192.168.1.131 --measure > bridge-certificate.pem
"""
import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]


def run(command, input_text=None, timeout=60):
    """A command and its answer.

    The answer is read as **bytes**: the text mode of the subprocess would
    translate the line endings of an HTTP answer, and the answer of the
    bridge is parsed byte by byte.
    """
    payload = input_text.encode() if isinstance(input_text, str) else input_text
    result = subprocess.run(command, input=payload, capture_output=True, timeout=timeout)
    return {"the_command": " ".join(command), "the_code": result.returncode,
            "the_output": result.stdout.decode("utf-8", "replace"),
            "the_error": result.stderr.decode("utf-8", "replace")}


def the_presented_certificate(host: str, port: int, timeout: int = 30):
    """The certificate that the host presents, and its fingerprint."""
    answer = run(["openssl", "s_client", "-connect", f"{host}:{port}",
                  "-servername", host, "-showcerts"], input_text="\n", timeout=timeout)
    if answer["the_code"] != 0:
        return None, None, answer
    blocks = re.findall(
        r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----",
        answer["the_output"], re.DOTALL)
    if not blocks:
        return None, None, answer
    pem = blocks[0] + "\n"
    fingerprint = run(["openssl", "x509", "-noout", "-fingerprint", "-sha256"],
                      input_text=pem, timeout=30)
    subject = run(["openssl", "x509", "-noout", "-subject", "-issuer", "-dates"],
                  input_text=pem, timeout=30)
    return pem, fingerprint["the_output"].strip(), subject


def the_verified_read(host: str, port: int, path: str, pin: pathlib.Path,
                      timeout: int = 30):
    """One HTTP GET over a **verified** TLS session.

    The certificate that the host presents is verified against the pin with
    `-partial_chain`; a host that presents another certificate is refused by
    `openssl` itself, before a byte of the answer is read.
    """
    request = (f"GET {path} HTTP/1.1\r\n"
               f"Host: {host}:{port}\r\n"
               "User-Agent: oip-hue/1\r\n"
               "Accept: application/json\r\n"
               "Connection: close\r\n\r\n")
    answer = run(["openssl", "s_client", "-connect", f"{host}:{port}",
                  "-servername", host, "-CAfile", str(pin),
                  "-partial_chain", "-verify_return_error", "-quiet"],
                 input_text=request, timeout=timeout)
    body = answer["the_output"]
    # The verification is the guarantee of the read: `openssl` refuses the
    # connection itself when the presented certificate is not the pinned one,
    # so an answer that exists at all is an answer of the verified bridge.
    refused = "verify error" in answer["the_error"] or "certificate verify failed" in answer["the_error"]
    verified = answer["the_code"] == 0 and not refused and _the_status(body) is not None
    return {
        "the_code": answer["the_code"],
        "the_verification_succeeded": verified,
        "the_verification": [line for line in answer["the_error"].splitlines()
                             if "verify" in line.lower()][:4],
        "the_status": _the_status(body),
        "the_body": _the_body(body),
    }


def _the_status(raw: str):
    match = re.match(r"HTTP/1\.[01] (\d{3})", raw)
    return int(match.group(1)) if match else None


def _the_body(raw: str):
    """The body of the answer: the chunked encoding is unwound."""
    head, _, body = raw.partition("\r\n\r\n")
    if not body:
        return ""
    if "transfer-encoding: chunked" not in head.lower():
        return body
    out = []
    while body:
        size_line, _, rest = body.partition("\r\n")
        try:
            size = int(size_line.split(";")[0].strip(), 16)
        except ValueError:
            break
        if size == 0:
            break
        out.append(rest[:size])
        body = rest[size + 2:]
    return "".join(out)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", type=int, default=443)
    parser.add_argument("--pin", default=str(ROOT / "docs/release/hue/bridge-certificate.pem"))
    parser.add_argument("--measure", action="store_true",
                        help="write the certificate of the host to the standard output")
    parser.add_argument("--out", default=None)
    args = parser.parse_args()

    pin = pathlib.Path(args.pin)
    pem, fingerprint, subject = the_presented_certificate(args.host, args.port)
    if args.measure:
        if pem is None:
            print(json.dumps({"the_status": "FAIL",
                              "the_problem": "the host presents no certificate"}))
            return 1
        if args.out:
            pathlib.Path(args.out).write_text(pem)
        else:
            sys.stdout.write(pem)
        return 0

    report = {"schema": "oip-hue-v1", "the_host": args.host, "the_port": args.port}
    report["the_certificate_of_the_host"] = {
        "the_fingerprint": fingerprint,
        "the_subject": subject["the_output"].strip() if subject else None,
    }
    if pem is None:
        report["the_status"] = "FAIL"
        report["the_problems"] = ["the host presents no certificate"]
        print(json.dumps(report, indent=2))
        return 1
    if not pin.is_file():
        report["the_status"] = "FAIL"
        report["the_problems"] = [
            f"the pin {pin} does not exist: the identity of the bridge is only "
            "verified against a pin that the operator has confirmed"]
        print(json.dumps(report, indent=2))
        return 1
    pinned = run(["openssl", "x509", "-noout", "-fingerprint", "-sha256"],
                 input_text=pin.read_text(), timeout=30)
    report["the_pin"] = {
        "the_path": str(pin),
        "the_fingerprint": pinned["the_output"].strip(),
        "the_sha256_of_the_pin": hashlib.sha256(pin.read_bytes()).hexdigest(),
    }
    if report["the_pin"]["the_fingerprint"] != fingerprint:
        report["the_status"] = "FAIL"
        report["the_problems"] = [
            "the identity of the bridge changed: the host presents a certificate "
            "that is not the pinned one"]
        print(json.dumps(report, indent=2))
        return 1

    config = the_verified_read(args.host, args.port, "/api/config", pin)
    report["the_configuration"] = config
    problems = []
    if not config["the_verification_succeeded"]:
        problems.append("the verification of the identity of the bridge failed")
    if config["the_status"] != 200:
        problems.append(f"the configuration of the bridge answered {config['the_status']}")
    identity = {}
    if config["the_status"] == 200:
        try:
            payload = json.loads(config["the_body"])
        except ValueError:
            payload = {}
            problems.append("the configuration of the bridge is not a JSON answer")
        identity = {
            "the_name": payload.get("name"),
            "the_bridge_id": payload.get("bridgeid"),
            "the_model_id": payload.get("modelid"),
            "the_software_version": payload.get("swversion"),
            "the_api_version": payload.get("apiversion"),
            "the_mac": payload.get("mac"),
            "the_datastore_version": payload.get("datastoreversion"),
        }
    report["the_identity"] = identity

    # The honest limit: the lights need an application token, and the
    # creation of a token is a write on the device. The bridge answers the
    # data route of the version 1 with the refusal `unauthorized user`.
    lights = the_verified_read(args.host, args.port, "/api/oip-probe/lights", pin)
    report["the_lights_without_a_token"] = {
        "the_path": "/api/oip-probe/lights",
        "the_status": lights["the_status"],
        "the_body": lights["the_body"][:200],
        "the_verification_succeeded": lights["the_verification_succeeded"],
        "the_refused": "unauthorized user" in lights["the_body"],
    }
    if not report["the_lights_without_a_token"]["the_refused"]:
        problems.append("the bridge did not refuse the lights without a token")
    report["the_problems"] = problems
    report["the_status"] = "FAIL" if problems else "PASS"
    report["the_capability"] = {
        "the_read": "the public configuration of the bridge",
        "the_control": "not supported: the application token is a write on the "
                       "device and belongs to the operator",
    }
    print(json.dumps(report, indent=2))
    return 0 if report["the_status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
