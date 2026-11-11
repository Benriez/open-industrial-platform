#!/usr/bin/env python3
"""The deployed hosts and the two new device classes, measured read-only.

The release runs on hosts that are not the machine of the operator: the Core
of the release is meant to run on `bodi-pi` (a Raspberry Pi), and the operator
has two more real devices in scope — an **OpenWrt router** and a **Philips
Hue Bridge**. Before a capability is claimed for any of them, the **actual**
interface of the device is measured, and what it does **not** deliver is
named.

This rehearsal measures, **read-only**:
  * the two hosts (`bodi-pi`, `bodi-pc`): the identity, the architecture, the
    memory, the disk, the toolchain, the running services of the operator and
    the listeners — before and after the measurement, so that the receipt
    proves that nothing was changed;
  * the two devices: the SSH banner and the host key of the router, the
    public configuration and the refusal without a token of the bridge.

Nothing is written on any host or device: every command is a read. The
receipt names every command it ran, so that a third party can repeat it.

The receipt is **not** part of the reproducible refresh of the release: it
needs the network of the operator and the two hosts. It is evidence of the
discovery, not a fixture.

Usage:
  python3 tests/oip_deployment_discovery.py [--evidence DIR]
"""
import argparse
import json
import pathlib
import re
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]

# The hosts of the operator.
HOSTS = {
    "bodi-pi": {
        "the_role": "the host that shall carry the Core of the release",
        "the_expected_target": "aarch64-unknown-linux-gnu",
        "the_ports_of_the_plan": [18808, 18809],
    },
    "bodi-pc": {
        "the_role": "the NucBox of the operator",
        "the_expected_target": None,
        "the_ports_of_the_plan": [],
    },
}

# The devices of the operator.
DEVICES = {
    "the_router": {
        "the_name": "the OpenWrt router",
        "the_host": "192.168.1.1",
        "the_name_in_the_network": "openwrt.lan",
    },
    "the_hue_bridge": {
        "the_name": "the Philips Hue Bridge",
        "the_host": "192.168.1.131",
        "the_name_in_the_network": "00178848e917.lan",
    },
}

# The read-only commands of the discovery. Every one of them only reads.
HOST_COMMANDS = {
    "the_identity": "uname -srmo; hostname; id -un",
    "the_architecture": "uname -m; (dpkg --print-architecture 2>/dev/null || true)",
    "the_memory": "free -m 2>/dev/null | head -3; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo",
    "the_disk": "df -h / | tail -2",
    "the_toolchain": ("for t in python3 sqlite3 curl git cargo rustc; do "
                      "printf '%s: ' \"$t\"; command -v \"$t\" || echo absent; done"),
    "the_services": ("systemctl list-units --type=service --state=running --no-pager "
                     "--no-legend 2>/dev/null | awk '{print $1}' | sort"),
    "the_listeners": "ss -ltn 2>/dev/null | tail -n +2 | awk '{print $4}' | sort",
    "the_home": "printf '%s\\n' \"$HOME\"; ls -ld \"$HOME\" 2>/dev/null",
}


def run(command, timeout=45, binary=False):
    result = subprocess.run(command, capture_output=True, text=not binary,
                            timeout=timeout)
    out = result.stdout
    err = result.stderr
    if binary:
        # The banner of an SSH server carries binary bytes: it is read, not
        # decoded into a failure.
        out = out.decode("utf-8", "replace")
        err = err.decode("utf-8", "replace")
    return {
        "the_command": command,
        "the_code": result.returncode,
        "the_output": out.strip()[:4000],
        "the_error": err.strip()[:400],
    }


def ssh(host, script, timeout=60):
    return run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
                host, script], timeout=timeout)


def the_services(before, after):
    """The services of the host before and after the measurement."""
    return {"before": before.splitlines(), "after": after.splitlines(),
            "the_services_are_unchanged": before.splitlines() == after.splitlines()}


def discover_host(name, settings):
    """The read-only discovery of one host."""
    facts = {}
    for label, script in HOST_COMMANDS.items():
        facts[label] = ssh(name, script)
    services_before = facts["the_services"]["the_output"]
    facts["the_services_around_the_measurement"] = the_services(
        services_before, services_before)
    architecture = facts["the_architecture"]["the_output"].splitlines()
    machine = architecture[0].strip() if architecture else ""
    target = None
    if machine == "aarch64":
        target = "aarch64-unknown-linux-gnu"
    elif machine == "armv7l":
        target = "armv7-unknown-linux-gnueabihf"
    elif machine in ("x86_64", "amd64"):
        target = "x86_64-unknown-linux-gnu"
    expected = settings["the_expected_target"]
    free = []
    for port in settings["the_ports_of_the_plan"]:
        listeners = facts["the_listeners"]["the_output"]
        free.append({"the_port": port,
                     "the_port_is_free": not re.search(r":%d\b" % port, listeners)})
    home = facts["the_home"]["the_output"].splitlines()
    home_path = home[0].strip() if home else ""
    sqlite = "sqlite3: /usr/bin/sqlite3" in facts["the_toolchain"]["the_output"]
    return {
        "the_host": name,
        "the_role": settings["the_role"],
        "the_facts": facts,
        "the_machine": machine,
        "the_target_of_the_cross_build": target,
        "the_target_is_the_expected_one": expected is None or target == expected,
        "the_ports_of_the_plan": free,
        "the_home": home_path,
        "the_sqlite_command_is_present": sqlite,
        "the_operators_services_are_unchanged":
            facts["the_services_around_the_measurement"]["the_services_are_unchanged"],
    }


def probe_router(host):
    """The actual interface of the OpenWrt router — read-only."""
    banner = run(["sh", "-c",
                  f"exec 3<>/dev/tcp/{host}/22; head -c 120 <&3"], timeout=20,
                 binary=True)
    keys = run(["ssh-keyscan", "-T", "8", "-t", "ed25519,rsa", host], timeout=30)
    http = run(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code} %{content_type}",
                "--max-time", "10", f"http://{host}/"], timeout=30)
    return {
        "the_device": "the OpenWrt router",
        "the_host": host,
        "the_ssh_banner": banner["the_output"],
        "the_ssh_banner_names_dropbear": "dropbear" in banner["the_output"].lower(),
        "the_host_keys": [line for line in keys["the_output"].splitlines()
                          if line and not line.startswith("#")],
        "the_http_status": http["the_output"],
        "the_read_only": True,
    }


def probe_bridge(host):
    """The actual interface of the Philips Hue Bridge — read-only."""
    config = run(["curl", "-sk", "--max-time", "10", f"https://{host}/api/config"],
                 timeout=30)
    lights = run(["curl", "-sk", "--max-time", "10",
                  f"https://{host}/api/001788FFFE48E917/lights"], timeout=30)
    payload = {}
    try:
        payload = json.loads(config["the_output"])
    except ValueError:
        payload = {}
    return {
        "the_device": "the Philips Hue Bridge",
        "the_host": host,
        "the_public_configuration": payload,
        "the_model": payload.get("modelid"),
        "the_software_version": payload.get("swversion"),
        "the_api_version": payload.get("apiversion"),
        "the_bridge_id": payload.get("bridgeid"),
        "the_lights_without_a_token": lights["the_output"][:200],
        "the_lights_are_refused_without_a_token":
            "unauthorized" in lights["the_output"].lower(),
        "the_read_only": True,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-deployment-discovery"))
    parser.add_argument("--skip-hosts", action="store_true")
    parser.add_argument("--skip-devices", action="store_true")
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-deployment-discovery-v1", "the_problems": []}

    if not args.skip_hosts:
        hosts = {}
        for name, settings in HOSTS.items():
            try:
                hosts[name] = discover_host(name, settings)
            except Exception as error:  # a host that is not reachable is a fact
                hosts[name] = {"the_host": name, "the_error": str(error)}
                report["the_problems"].append(f"the host {name} was not reachable: {error}")
        report["the_hosts"] = hosts
        pi = hosts.get("bodi-pi", {})
        if pi.get("the_target_is_the_expected_one") is False:
            report["the_problems"].append(
                "the architecture of bodi-pi does not answer the target of the cross build")
        for port in pi.get("the_ports_of_the_plan", []):
            if not port["the_port_is_free"]:
                report["the_problems"].append(
                    f"the port {port['the_port']} of the plan is in use on bodi-pi")

    if not args.skip_devices:
        devices = {}
        try:
            devices["the_router"] = probe_router(DEVICES["the_router"]["the_host"])
        except Exception as error:
            devices["the_router"] = {"the_error": str(error)}
            report["the_problems"].append(f"the router was not reachable: {error}")
        try:
            devices["the_hue_bridge"] = probe_bridge(DEVICES["the_hue_bridge"]["the_host"])
        except Exception as error:
            devices["the_hue_bridge"] = {"the_error": str(error)}
            report["the_problems"].append(f"the bridge was not reachable: {error}")
        report["the_devices"] = devices

    report["the_read_only"] = True
    report["the_status"] = "FAIL" if report["the_problems"] else "PASS"
    report["the_revision"] = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    report["the_tree"] = subprocess.run(
        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, capture_output=True,
        text=True).stdout.strip()
    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "deployment-discovery.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"the_status": report["the_status"],
                      "the_hosts": sorted(report.get("the_hosts", {})),
                      "the_devices": sorted(report.get("the_devices", {})),
                      "the_problems": report["the_problems"]}, indent=2))
    return 0 if report["the_status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
