#!/usr/bin/env python3
"""The depth of the Settings workspace of the managed surface (G7, G8).

The Settings workspace is where the operator reads what the Core can and
cannot do. The rehearsal starts a disposable Core, drives the real surface in
the browser (`apps/flutter/test/browser_settings_depth_2027.mjs`) with the
session of the operator and proves that the surface is the truth of the Core:
every category of the Core, the real MCP runtime, the schema of the Core and
a client template that carries no credential.

The minute the surface is entered the Core refuses the reads that the
principal may not perform; the settings of an instance are a **platform**
capability. The plan of the example names a read-only role without the
settings and management permissions, so the rehearsal grants them at platform
scope to the reader it authenticates — the grant is recorded in the receipt.
Without it the surface would show the refusal of the Core, not the depth of
the workspace, and the rehearsal would prove nothing.

The instance is disposable and owns its store: nothing of the installation of
the operator is touched, no private endpoint is contacted and no hardware is
invented.

Usage:
  python3 tests/oip_settings_depth_2027.py [--evidence DIR]
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


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


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
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-settings-depth"))
    parser.add_argument("--binary", default=str(ROOT / "target/release/oip-server"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-settings-depth-rehearsal-v1", "steps": []}

    work = pathlib.Path(tempfile.mkdtemp(prefix="oip-settings-depth-", dir="/private/tmp")).resolve()
    work.chmod(0o700)
    try:
        port = free_port()
        plan = json.loads((ROOT / "examples/multi-infrastructure-plan.json").read_text())
        # The subject of the rehearsal is the workspace, not a collector: the
        # instance owns no source, and the sources of the plan are removed
        # with their bindings so that the plan and the configuration agree.
        plan["sources"] = []
        plan["bindings"] = [item for item in plan["bindings"]
                            if item["scope"]["kind"] != "source"]
        # The settings of an instance are a platform capability, and the
        # management report is platform-authorized. The example plan grants
        # neither, so the rehearsal grants both to the reader it
        # authenticates and records the grant.
        plan["roles"].append({
            "id": "settings-depth-reader",
            "name": "Explicit scoped settings and management reader",
            "permissions": ["settings_read", "mcp_management_read"],
        })
        plan["bindings"].append({
            "principal_id": "reader-org-a", "role_id": "settings-depth-reader",
            "scope": {"kind": "platform"},
        })
        (work / "plan.json").write_text(json.dumps(plan, indent=2))
        (work / "core.json").write_text(json.dumps({
            "database": str(work / "core.sqlite"), "http_port": port, "sources": [],
            "legacy_single_infrastructure": False,
            "web_dir": str(ROOT / "apps/flutter/build/web"),
        }, indent=2))
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
        base = f"http://127.0.0.1:{port}"

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
        time.sleep(5)
        report["steps"].append("the instance runs with the granted platform reads")
        report["the_permissions_granted_to_the_reader"] = [
            "settings_read", "mcp_management_read"]
        report["the_reason_of_the_grant"] = (
            "the settings and the management report are platform capabilities; "
            "the example plan grants neither, and the surface would show the "
            "refusal of the Core instead of the workspace")

        result = subprocess.run(
            ["node", str(ROOT / "apps/flutter/test/browser_settings_depth_2027.mjs")],
            cwd=ROOT, capture_output=True, text=True, timeout=2400,
            env=dict(os.environ,
                     OIP_URL=base,
                     OIP_EVIDENCE_DIR=str(evidence),
                     OIP_REVISION=subprocess.check_output(
                         ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                     OIP_IPC_SOCKET=str(work / "s"),
                     OIP_BROWSER_CREDENTIAL=str(credential),
                     OIP_SERVER_BIN=args.binary,
                     PLAYWRIGHT_MODULE=playwright_module()))
        report["the_output_of_the_journey"] = result.stdout[-3000:]
        if result.returncode != 0:
            raise AssertionError(f"the browser journey failed: "
                                 f"{result.stderr.strip()[-800:] or result.stdout.strip()[-800:]}")
        receipt = json.loads((evidence / "settings-depth.json").read_text())
        assert receipt.get("status") == "PASS", receipt
        assert not receipt.get("errors"), receipt.get("errors")
        report["browser_receipt"] = receipt
        report["the_categories_of_the_core"] = receipt["the_categories_of_the_core"]
        report["the_settings_of_the_core"] = receipt["the_settings_of_the_core"]
        report["the_tools_of_the_core"] = receipt["the_tools_of_the_core"]
        report["the_tool_of_the_journey"] = receipt["the_tool_of_the_journey"]
        report["the_refusals_of_the_core"] = receipt.get("the_refusals_of_the_core", [])
        report["checks"] = len(receipt["the_checks"])
        report["steps"].append("the surface is the truth of the Core in every category")
        report["status"] = "PASS"
    except AssertionError as error:
        report["status"] = "FAIL"
        report["error"] = str(error)
    except Exception as error:  # noqa: BLE001 - the receipt names every failure
        report["status"] = "FAIL"
        report["error"] = f"{type(error).__name__}: {error}"
    finally:
        try:
            tool("stop", expect_success=False)
        except Exception:
            pass
        if report.get("status") == "PASS":
            shutil.rmtree(work, ignore_errors=True)
        else:
            report["work_directory"] = str(work)

    # The revision the receipt was measured on: a reader of the evidence must
    # be able to tell whether it is current.
    report["the_revision"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    report["the_tree"] = subprocess.check_output(
        ["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip()
    report["the_working_tree_is_clean"] = not subprocess.check_output(
        ["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()
    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "settings-depth-rehearsal.json").write_text(
        json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items()
                      if k not in ("browser_receipt", "the_output_of_the_journey",
                                   "steps")}, indent=2))
    return 0 if report.get("status") == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
