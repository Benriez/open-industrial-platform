#!/usr/bin/env python3
"""The store assets of the Mac App Store listing, measured.

Apple accepts the screenshot of a Mac app in one of four sizes with a 16:10
aspect ratio (1280 x 800, 1440 x 900, 2560 x 1600, 2880 x 1800), forbids an
alpha channel and asks for the format `.jpeg`, `.jpg` or `.png`. The listing
of the client therefore needs **six captures** — one per workstation of the
approved shell — in one of those sizes.

This rehearsal measures the captures:

  1. the **managed Core** of the release (the release binary, a disposable
     store, a disposable IPC credential) serves the **release build of the
     client** (`apps/flutter/build/web`) with a source that is the local
     OPC-UA simulation of the release — the same source that the instance on
     the Raspberry Pi collects;
  2. the **browser** drives the six workstations of the approved shell after
     the one-time code of the operator, and every workstation is captured in
     the **viewport** — never the full page, whose height would be whatever
     the content happens to be;
  3. every capture is **measured**: the exact pixel size and the absence of
     an alpha channel are read out of the file itself;
  4. the **Core is stopped** and the simulation with it: the rehearsal leaves
     no process of its own behind.

The captures are the **store assets**. The acceptance of the visible result
stays with the operator (G12) and is never claimed by this rehearsal.

Usage:
  python3 tests/oip_store_screenshots.py [--evidence DIR] [--width N] [--height N]
"""
import argparse
import hashlib
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
SCRIPT = ROOT / "apps/flutter" / "test" / "browser_store_screenshots.mjs"
WEB = ROOT / "apps/flutter" / "build" / "web"
PLAYWRIGHT = ROOT / "apps/flutter" / "test" / "node_modules" / "playwright" / "index.mjs"
# The sizes that Apple accepts for a Mac app (App Store Connect Help,
# "Screenshot specifications", read on 2026-11-11).
ACCEPTED = [(1280, 800), (1440, 900), (2560, 1600), (2880, 1800)]
ENTITY = "press-01"


def free_port() -> int:
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


def digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def png_property(path: pathlib.Path) -> dict:
    """The size and the colour type of a PNG, read out of the file."""
    data = path.read_bytes()
    if data[:8].hex() != "89504e470d0a1a0a":
        return {"the_file": path.name, "is_a_png": False}
    colour = data[25]
    return {
        "the_file": path.name,
        "is_a_png": True,
        "the_width": int.from_bytes(data[16:20], "big"),
        "the_height": int.from_bytes(data[20:24], "big"),
        "the_colour_type": colour,
        "the_carries_an_alpha_channel": colour in (4, 6),
        "the_bytes": path.stat().st_size,
        "the_sha256": hashlib.sha256(data).hexdigest(),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-store-screenshots"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    parser.add_argument("--simulation", default=str(ROOT / "target/release/oip-simulated-server"))
    parser.add_argument("--width", type=int, default=1440)
    parser.add_argument("--height", type=int, default=900)
    args = parser.parse_args()
    # The path of the evidence is resolved: the browser runs in the directory
    # of the client, and a relative path would put the captures there.
    evidence = pathlib.Path(args.evidence).resolve()
    captures = evidence / "captures"
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-store-screenshots-v1", "steps": [], "the_problems": []}
    if (args.width, args.height) not in ACCEPTED:
        report["the_problems"].append(
            f"{args.width}x{args.height} is not a size that Apple accepts for a Mac app")
        report["the_status"] = "FAIL"
        (evidence / "store-screenshots.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report, indent=2))
        return 1

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-store-", dir="/private/tmp")).resolve()
    work.chmod(0o700)
    simulation = None
    core = None
    try:
        # 1. the managed Core of the release
        assert WEB.is_dir(), f"the release build of the client is missing: {WEB}"
        assert (WEB / "main.dart.js").is_file(), "the web release carries no bundle"
        port = free_port()
        source_port = free_port()
        source_id = "press-01-source"
        plan = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        # The plan declares the **sources of the hierarchy** and the
        # configuration declares the **collectors**: the two name the same
        # sources, one to one, and the provisioning of the Core refuses a plan
        # that names a source the configuration does not collect (and a source
        # whose entity differs).
        plan["sources"] = [{
            "source_id": source_id, "site_id": "site-a1",
            "device_id": "press-01-device", "entity_id": ENTITY}]
        plan["bindings"] = [binding for binding in plan["bindings"]
                            if binding["scope"].get("kind") != "source"]
        (work / "plan.json").write_text(json.dumps(plan, indent=2))
        (work / "core.json").write_text(json.dumps({
            "database": str(work / "core.sqlite"),
            "http_port": port,
            "sources": [{"id": source_id, "name": "Press line 1",
                         "endpoint": f"opc.tcp://127.0.0.1:{source_port}",
                         "namespace": 2, "entity_id": ENTITY}],
            "legacy_single_infrastructure": False,
            "web_dir": str(WEB),
        }, indent=2))
        credential = work / "platform.credential"
        credential.write_bytes(secrets.token_bytes(32))
        credential.chmod(0o600)
        (work / "ipc.json").write_text(json.dumps({
            "socket": str(work / "s"), "max_sessions": 16,
            "clients": [{"uid": os.getuid(), "credential_file": str(credential),
                         "policy": {"principal": "platform-reader"}}],
        }, indent=2))
        (work / "ipc.json").chmod(0o600)
        state = work / "state"

        def tool(*arguments, expect_success=True):
            result = subprocess.run(
                [sys.executable, str(TOOL), "--state-dir", str(state),
                 "--config", str(work / "core.json"), "--ipc-config", str(work / "ipc.json"),
                 "--binary", args.binary, *arguments],
                capture_output=True, text=True, timeout=900)
            if expect_success and result.returncode != 0:
                raise AssertionError(f"{arguments[0]} failed: "
                                     f"{result.stderr.strip() or result.stdout.strip()}")
            return result

        # the simulation of the release: the source that the instance on the
        # Raspberry Pi collects
        simulation_log = open(work / "simulation.log", "w")
        simulation = subprocess.Popen([args.simulation, "--port", str(source_port)],
                                      stdout=simulation_log, stderr=subprocess.STDOUT)
        time.sleep(3)
        assert simulation.poll() is None, "the simulation of the release did not start"

        tool("provision-plan", "--plan", str(work / "plan.json"))
        report["the_provisioning"] = json.loads(
            (work / "plan.json").read_text()) and "the plan is provisioned"
        tool("start")
        core = True
        base = f"http://127.0.0.1:{port}"
        deadline = time.monotonic() + 60
        answered = False
        while time.monotonic() < deadline:
            probe = subprocess.run(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
                                    "--max-time", "5", base + "/health/live"],
                                   capture_output=True, text=True)
            if probe.stdout.strip() not in ("000", ""):
                answered = True
                break
            time.sleep(0.5)
        assert answered, "the managed Core does not answer on its port"
        report["the_core"] = {
            "the_binary": args.binary,
            "the_sha256_of_the_binary": digest(pathlib.Path(args.binary)),
            "the_port": port,
            "the_source_port": source_port,
            "the_web_release": str(WEB.relative_to(ROOT)),
            "the_bundle_sha256": digest(WEB / "main.dart.js"),
        }
        report["steps"].append("the managed Core of the release serves the release build of the client")

        # 2. the browser captures the six workstations
        if captures.exists():
            shutil.rmtree(captures)
        captures.mkdir(parents=True)
        environment = dict(os.environ)
        environment["PLAYWRIGHT_MODULE"] = str(PLAYWRIGHT)
        environment["OIP_SERVER_BIN"] = str(pathlib.Path(args.binary).resolve())
        environment["OIP_IPC_SOCKET"] = str(work / "s")
        environment["OIP_BROWSER_CREDENTIAL"] = str(credential)
        environment["OIP_STORE_EVIDENCE"] = str(captures)
        result = subprocess.run(
            ["node", str(SCRIPT), base, str(captures), str(args.width), str(args.height)],
            cwd=str(ROOT / "apps/flutter"), env=environment,
            capture_output=True, text=True, timeout=1800)
        (evidence / "browser.log").write_text(result.stdout + "\n--- stderr ---\n" + result.stderr)
        browser_receipt = captures / "browser-store-screenshots.json"
        assert result.returncode == 0, (
            f"the browser did not capture the store assets: "
            f"{(result.stderr.strip() or result.stdout.strip())[-400:]}")
        assert browser_receipt.is_file(), "the browser wrote no receipt"
        report["the_browser"] = json.loads(browser_receipt.read_text())
        report["steps"].append("the six workstations are captured in the size that Apple accepts")

        # 3. every capture is measured
        measured = []
        for file in sorted(captures.glob("store-*.png")):
            property = png_property(file)
            measured.append(property)
            assert property["is_a_png"], f"{file.name} is not a PNG"
            assert (property["the_width"], property["the_height"]) == (args.width, args.height), \
                f"{file.name} has the size {property['the_width']}x{property['the_height']}"
            assert not property["the_carries_an_alpha_channel"], \
                f"{file.name} carries an alpha channel"
        report["the_captures"] = measured
        report["the_sizes_that_apple_accepts"] = [list(size) for size in ACCEPTED]
        assert len(measured) == 6, f"the rehearsal captured {len(measured)} of six workstations"
        report["steps"].append("every capture has the accepted size and no alpha channel")

        # 4. the Core stops and nothing of the rehearsal stays behind
        tool("stop")
        core = None
        # The orphans of **this** rehearsal: the processes whose command line
        # names the work directory of this run. The processes of other
        # rehearsals of the machine are not ours and are never signalled.
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
        if core is not None:
            subprocess.run([sys.executable, str(TOOL), "--state-dir", str(work / "state"),
                            "--config", str(work / "core.json"),
                            "--ipc-config", str(work / "ipc.json"),
                            "--binary", args.binary, "stop"],
                           capture_output=True, text=True, timeout=300)
        if simulation is not None and simulation.poll() is None:
            simulation.terminate()
            try:
                simulation.wait(timeout=10)
            except subprocess.TimeoutExpired:
                simulation.kill()

    report["the_revision"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    report["the_tree"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip()
    report["the_working_tree_is_clean"] = not subprocess.run(
        ["git", "status", "--porcelain"], cwd=ROOT, capture_output=True,
        text=True).stdout.strip()
    report["the_visual_acceptance_of_the_operator"] = "VISUAL_PENDING_OPERATOR_ACCEPTANCE"
    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "store-screenshots.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"the_status": report["the_status"],
                      "the_steps": len(report["steps"]),
                      "the_captures": len(report.get("the_captures", [])),
                      "the_problems": report["the_problems"]}, indent=2))
    return 0 if report["the_status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
