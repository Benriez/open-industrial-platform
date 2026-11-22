#!/usr/bin/env python3
"""Reproducible canonical regression run over the milestone acceptance harnesses.

Every case owns its own runtime directory under /private/tmp, its own ports and its own
credentials. No personal database, no protected installation and no foreign process is
touched. A case that needs a protected historical binary is only executed when that binary
is present and its hash matches the recorded value; otherwise the case is reported as
BLOCKED with the reason instead of being run with a substitute.
Every selected case must produce fresh passing receipts to pass. A selection
with blocked but no failed cases is PARTIAL and exits with status 2.

Usage:
    python3 tests/canonical_regression.py [--only <case>] [--evidence <dir>]
"""
import argparse, hashlib, json, os, pathlib, subprocess, sys, time

ROOT = pathlib.Path(__file__).resolve().parents[1]
# Protected historical binaries from the verified milestone receipts. The hash is checked
# before a case uses one; a missing or changed binary blocks the case, it never replaces it.
BASELINES = {
    "oip0083": (
        os.environ.get(
            "OIP0083_BASELINE_BINARY",
            "/Users/benny/Documents/OIP-Handoffs/core-0084-settings-20261106T182412Z/oip0083-baseline-server",
        ),
        "3b682dfaff8479f13804d28e6fe1288bedcfea8af0b409c8f8dc22d422b9ac39",
    ),
    "oip008": (
        os.environ.get(
            "OIP008_BASELINE_BINARY",
            "/Users/benny/Documents/OIP-Handoffs/core-0082-20261105T222139Z/oip008-baseline-server",
        ),
        "889a36b2cf0d761796662e0437a18c2ed43dc8c1b1da82d70fecdd5a055865c6",
    ),
    "oip0084": (
        os.environ.get(
            "OIP0084_BASELINE_BINARY",
            "/Users/benny/Documents/OIP-Handoffs/core-0085-real-inventory-20261106T200219Z/oip0084-baseline-server",
        ),
        "73d70d8105914db20210c95268b5733ca2ec19c959c4c29fa57cb93c1935fe58",
    ),
}
CASES = [
    {
        "name": "oip008_acceptance",
        "script": "tests/oip008/acceptance.py",
        "timeout": 900,
        "reports": ["report.json"],
    },
    {
        "name": "oip0082_acceptance",
        "script": "tests/oip0082/acceptance.py",
        "timeout": 900,
        "reports": ["report.json"],
    },
    {
        "name": "oip0082_schema3_migration",
        "script": "tests/oip0082/schema3_migration.py",
        "timeout": 900,
        "reports": ["report.json"],
        "baseline": "oip008",
        "baseline_args": ("--baseline-binary", "--baseline-sha256"),
    },
    {
        "name": "oip0084_acceptance",
        "script": "tests/oip0084/acceptance.py",
        "timeout": 1200,
        "reports": ["report.json"],
        "baseline": "oip0083",
        "baseline_env": ("OIP0083_BASELINE_BINARY", "OIP0083_BASELINE_SHA256"),
    },
    {
        "name": "oip0085_acceptance",
        "script": "tests/oip0085/acceptance.py",
        "timeout": 1200,
        "reports": ["report.json"],
    },
    {
        "name": "oip0085_migration",
        "script": "tests/oip0085/migration.py",
        "timeout": 900,
        "reports": ["report.json"],
        "baseline": "oip0084",
        "baseline_env": ("OIP0084_BASELINE_BINARY", "OIP0084_BASELINE_SHA256"),
    },
    {
        "name": "oip008_ui_regression",
        "script": "tests/oip008/ui_regression.py",
        "timeout": 2400,
        "reports": ["ui-regression.json"],
    },
    {
        "name": "oip_canonical_ui_gate",
        "script": "tests/real_device/acceptance.py",
        "timeout": 2400,
        "reports": ["report.json", "browser/browser-canonical-ui-gate.json"],
        "env": {"OIP_CANONICAL_UI_GATE": "1"},
        "env_override": {"OIP_SERVER_BIN": "OIP_CANONICAL_SERVER_BIN"},
        "env_paths": {
            "OIP_SERVER_BIN": "target/debug/oip-server",
            "OIP_WEB_DIR": "apps/flutter/build/web",
            "OIP_BROWSER_SCRIPT": "apps/flutter/test/browser_canonical_ui_gate.mjs",
        },
    },
    {
        "name": "oip008_legacy_migration",
        "script": "tests/oip008/legacy_migration.py",
        "timeout": 900,
        "reports": ["report.json"],
        "baseline_env_only": ("OIP007_BASELINE_BINARY",),
        "baseline_prepared": "target/oip-007-baseline/target/debug/oip-server",
        "baseline_reason": "the harness has to create a genuine schema2 database, which only an OIP-007 schema2 writer can do; the canonical binary creates schema3 or later. Build it with python3 tests/oip007_baseline.py",
    },
]


def baseline_state(name):
    path, digest = BASELINES[name]
    file = pathlib.Path(path)
    if not file.is_file():
        return None, f"protected {name} binary not present at {path}"
    actual = hashlib.sha256(file.read_bytes()).hexdigest()
    if actual != digest:
        return None, f"protected {name} binary hash {actual} does not match the recorded {digest}"
    return (file, digest), None


def evaluate(report):
    """Read the harness report and derive its own status."""
    try:
        payload = json.loads(report.read_text())
    except (OSError, ValueError):
        return None
    if not isinstance(payload, dict):
        return None
    if isinstance(payload.get("status"), str):
        return payload["status"]
    if isinstance(payload.get("verdict"), str):
        return payload["verdict"]
    results = payload.get("results")
    if isinstance(results, list) and results:
        passed = all(isinstance(row, dict) and row.get("status") == "PASS"
                     for row in results)
        return "PASS" if passed else "FAIL"
    return None


def run_case(case, evidence):
    name = case["name"]
    command_arguments = []
    env = dict(os.environ)
    case_evidence = evidence / name
    env["OIP_EVIDENCE_DIR"] = str(case_evidence)
    case_evidence.mkdir(parents=True, exist_ok=True)
    for key, value in case.get("env", {}).items():
        env[key] = value
    for key, value in case.get("env_paths", {}).items():
        # A caller may point a case at another verified binary of the same
        # contract, for example the release build instead of the debug build.
        # The override is explicit, the default path stays the canonical one
        # and the receipt of the case names the binary that was executed.
        override = case.get("env_override", {}).get(key)
        if override and os.environ.get(override):
            env[key] = os.environ[override]
        else:
            env[key] = str(ROOT / value)
    if case.get("baseline"):
        state, reason = baseline_state(case["baseline"])
        if state is None:
            return {"name": name, "status": "BLOCKED", "reason": reason, "seconds": 0.0}
        path, digest = state
        if case.get("baseline_env"):
            variable, digest_variable = case["baseline_env"]
            env[variable] = str(path)
            env[digest_variable] = digest
        if case.get("baseline_args"):
            binary_argument, digest_argument = case["baseline_args"]
            command_arguments += [binary_argument, str(path), digest_argument, digest]
    if case.get("baseline_env_only"):
        variable = case["baseline_env_only"][0]
        if not env.get(variable):
            # A schema2 writer rebuilt from the verified OIP-007 baseline commit
            # is used when it was prepared; otherwise the case stays blocked.
            prepared = ROOT / case["baseline_prepared"]
            if prepared.is_file():
                env[variable] = str(prepared)
            else:
                return {
                    "name": name,
                    "status": "BLOCKED",
                    "reason": case["baseline_reason"],
                    "seconds": 0.0,
                }
    started = time.monotonic()
    started_wall_ns = time.time_ns()
    process = subprocess.run(
        [sys.executable, str(ROOT / case["script"]), *command_arguments,
         *case.get("args", ())],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        timeout=case["timeout"],
    )
    seconds = round(time.monotonic() - started, 1)
    log = evidence / (name + ".log")
    log.write_text(process.stdout + "\n--- stderr ---\n" + process.stderr)
    result = {
        "name": name,
        "command": "python3 " + case["script"],
        "exit_code": process.returncode,
        "seconds": seconds,
        "status": "PASS" if process.returncode == 0 else "FAIL",
        "log": str(log),
    }
    if case.get("baseline_env_only"):
        binary = pathlib.Path(env[case["baseline_env_only"][0]])
        if binary.is_file():
            result["baseline_binary_sha256"] = hashlib.sha256(binary.read_bytes()).hexdigest()
            result["baseline_source"] = "rebuilt from the verified OIP-007 baseline commit a27e7b1; the identity of the historical protected binary is not claimed"
    result["harness_status"] = "PASS"
    for candidate in case["reports"]:
        report = case_evidence / candidate
        status = None
        if report.is_file() and report.stat().st_mtime_ns >= started_wall_ns:
            status = evaluate(report)
            result.setdefault("reports", []).append(str(report))
            result.setdefault("report", str(report))
        if status != "PASS":
            result["status"] = result["harness_status"] = "FAIL"
            result.setdefault("report_errors", {})[candidate] = (
                status or "missing, stale, or invalid report")
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", action="append", default=[],
                        choices=[case["name"] for case in CASES])
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-canonical-regression"))
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence).resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    results = []
    for case in CASES:
        if args.only and case["name"] not in args.only:
            continue
        print("RUN", case["name"], flush=True)
        result = run_case(case, evidence)
        print(" ", result["status"], json.dumps({k: v for k, v in result.items() if k != "log"}), flush=True)
        results.append(result)
    summary = {
        "canonical_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "cases": results,
        "failed": [r["name"] for r in results if r["status"] == "FAIL"],
        "blocked": [r["name"] for r in results if r["status"] == "BLOCKED"],
    }
    summary["status"] = "FAIL" if summary["failed"] else "PARTIAL" if summary["blocked"] else "PASS"
    (evidence / "canonical-regression.json").write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, indent=2))
    return {"PASS": 0, "FAIL": 1, "PARTIAL": 2}[summary["status"]]


if __name__ == "__main__":
    raise SystemExit(main())
