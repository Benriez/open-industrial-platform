#!/usr/bin/env python3
"""The deployment hosts of the operator, measured read-only.

The **discovery** of the deployed hosts and of the two real devices of the
operator is one rehearsal (`tests/oip_deployment_discovery.py`): it measures
`bodi-pi` and `bodi-pc` over SSH and it probes the OpenWrt router and the
Philips Hue Bridge of the operator. The devices live on `192.168.1.x` — the
network of the operator — and the machine of the loop is on
`192.168.178.0/24`, so the probe of the devices fails there while the hosts
answer over SSH from anywhere.

The two halves are therefore measured in **two** rehearsals: the hosts here
and the devices in the discovery. The receipt of the hosts stays fresh at
every revision of the release, while the discovery of the devices keeps the
receipt of the measurement that could reach them — the operator's action (the
machine on the network of the devices) is named in the record.

Nothing is written on any host: every command is a read, and the services of
the operator are listed before and after the measurement.

Usage:
  python3 tests/oip_deployment_hosts.py [--evidence DIR]
"""
import argparse
import json
import pathlib
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))

from oip_deployment_discovery import HOSTS, discover_host  # noqa: E402


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-deployment-hosts"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {
        "schema": "oip-deployment-hosts-v1",
        "the_problems": [],
        "the_scope": "the two deployment hosts of the operator — the hosts are "
                     "reached over SSH from any network",
        "the_devices_are_not_part_of_this_receipt": {
            "the_receipt": "docs/evidence/oip-deployment-discovery/deployment-discovery.json",
            "the_reason": "the router and the bridge of the operator live on the "
                          "network of the operator (192.168.1.x); the machine of the "
                          "loop is on another network, so the probe of the devices "
                          "fails there. Their discovery is the receipt of the "
                          "measurement that could reach them.",
        },
    }

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

    report["the_read_only"] = True
    report["the_status"] = "FAIL" if report["the_problems"] else "PASS"
    report["the_revision"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    report["the_tree"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip()
    report["the_working_tree_is_clean"] = not subprocess.check_output(
        ["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()
    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "deployment-hosts.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"the_status": report["the_status"],
                      "the_hosts": sorted(hosts),
                      "the_problems": report["the_problems"]}, indent=2))
    return 0 if report["the_status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
