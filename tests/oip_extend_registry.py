#!/usr/bin/env python3
"""The extension of the registry of an instance (G12).

The registry of an instance is written by a plan. The operator adds
infrastructure by **extending** the plan and provisioning it again — the Core
refuses a plan that drops an organization, an infrastructure, a site, a source
or a principal: the identities of an instance stay stable.

This rehearsal proves that path against the **release** binary:

  1. the instance is provisioned with four sources and serves them;
  2. the plan is extended by a fifth source and the configuration with it;
  3. the instance is provisioned again with the extended plan — the four
     sources survive and the fifth is registered;
  4. the fifth source collects;
  5. a plan that **drops** a source is refused.

Nothing of the rehearsal touches the personal installation of the operator and
nothing leaves the machine.

Usage:
  python3 tests/oip_extend_registry.py [--evidence DIR]
"""
import argparse
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

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "oip_ops.py"
SIMULATOR = ROOT / "target/debug/oip-simulated-server"


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-extend-registry"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-extend-registry-v1", "steps": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-extend-", dir="/private/tmp")).resolve()
    work.chmod(0o700)
    simulators = []
    try:
        source_ports = [free_port() for _ in range(5)]
        http_port = free_port()
        plan = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        (work / "plan.json").write_text(json.dumps(plan, indent=2))

        def configuration(count):
            return {
                "database": str(work / "core.sqlite"), "http_port": http_port,
                "sources": [{"id": f"source-{letter}", "name": f"Local simulation {letter}",
                             "endpoint": f"opc.tcp://127.0.0.1:{source_ports[index]}",
                             "namespace": 2}
                            for index, letter in enumerate("abcde"[:count])],
                "legacy_single_infrastructure": False,
                "web_dir": str(ROOT / "apps/flutter/build/web"),
            }

        (work / "core.json").write_text(json.dumps(configuration(4), indent=2))
        credential = work / "platform.credential"
        credential.write_bytes(secrets.token_bytes(32))
        credential.chmod(0o600)
        (work / "ipc.json").write_text(json.dumps({
            "socket": str(work / "s"), "max_sessions": 8,
            "clients": [{"uid": os.getuid(), "credential_file": str(credential),
                         "policy": {"principal": "reader-org-a"}}],
        }, indent=2))
        (work / "ipc.json").chmod(0o600)
        state = work / "state"

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

        def start_collectors(count):
            for index in range(count):
                simulators.append(subprocess.Popen(
                    [str(SIMULATOR), "--port", str(source_ports[index]),
                     "--seed", str(42 + index * 7), "--tick-ms", "250"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
            time.sleep(2)

        def the_sources():
            result = subprocess.run(["/usr/bin/sqlite3", "-batch", "-noheader",
                                     str(work / "core.sqlite"),
                                     "select source_id from source_placements order by source_id;"],
                                    capture_output=True, text=True, timeout=60)
            return [line for line in result.stdout.splitlines() if line]

        # 1. the instance with four sources
        start_collectors(4)
        step = tool("provision-plan", "--plan", str(work / "plan.json"))
        report["the_first_provisioning"] = json.loads(step.stdout).get("result", "{}")
        tool("start")
        time.sleep(4)
        report["the_sources_at_the_start"] = the_sources()
        assert len(report["the_sources_at_the_start"]) == 4, report["the_sources_at_the_start"]
        report["steps"].append("the instance serves four sources")

        # 2. the plan is extended by a fifth source
        tool("stop")
        extended = json.loads(json.dumps(plan))
        extended["sources"].append({"source_id": "source-e", "site_id": "site-a2",
                                     "device_id": "device-e", "entity_id": "M-01"})
        (work / "plan.json").write_text(json.dumps(extended, indent=2))
        (work / "core.json").write_text(json.dumps(configuration(5), indent=2))
        start_collectors(5)

        # 3. the instance is provisioned again with the extended plan
        step = tool("provision-plan", "--plan", str(work / "plan.json"))
        report["the_second_provisioning"] = json.loads(step.stdout).get("result", "{}")
        report["the_sources_after_the_extension"] = the_sources()
        assert len(report["the_sources_after_the_extension"]) == 5, \
            report["the_sources_after_the_extension"]
        report["the_four_sources_survived"] = all(
            source in report["the_sources_after_the_extension"]
            for source in report["the_sources_at_the_start"])
        assert report["the_four_sources_survived"], "the extension lost a source"
        report["steps"].append("the registry is extended and the sources survive")

        # 4. the fifth source collects
        tool("start")
        time.sleep(6)
        result = subprocess.run(["/usr/bin/sqlite3", "-batch", "-noheader",
                                 str(work / "core.sqlite"),
                                 "select count(*) from observations where data_source_id='source-e';"],
                                capture_output=True, text=True, timeout=60)
        report["the_observations_of_the_new_source"] = result.stdout.strip()
        assert report["the_observations_of_the_new_source"] not in ("", "0"), \
            "the new source collected nothing"
        report["the_new_source_collects"] = True
        report["steps"].append("the new source collects")
        tool("stop")

        # 5. a plan that drops a source is refused
        reduced = json.loads(json.dumps(extended))
        reduced["sources"] = [item for item in reduced["sources"]
                              if item["source_id"] != "source-e"]
        (work / "plan-reduced.json").write_text(json.dumps(reduced, indent=2))
        (work / "core.json").write_text(json.dumps(configuration(4), indent=2))
        result = subprocess.run([sys.executable, str(TOOL), "--state-dir", str(state),
                                 "--config", str(work / "core.json"),
                                 "--ipc-config", str(work / "ipc.json"),
                                 "--binary", args.binary, "provision-plan",
                                 "--plan", str(work / "plan-reduced.json")],
                                capture_output=True, text=True, timeout=300)
        report["the_reduced_plan"] = {"exit_code": result.returncode,
                                      "output": (result.stderr.strip()
                                                 or result.stdout.strip())[:300]}
        assert result.returncode != 0, "the plan that drops a source was accepted"
        report["the_sources_after_the_refusal"] = the_sources()
        assert len(report["the_sources_after_the_refusal"]) == 5, \
            "the refused plan changed the registry"
        report["steps"].append("a plan that drops a source is refused")

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

    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "extend-registry.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "steps"}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
