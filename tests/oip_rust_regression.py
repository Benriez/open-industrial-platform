#!/usr/bin/env python3
"""The regression of the Core of the current release (G11).

The acceptance of the release runs the **Flutter** tests, the widget gate, the
browser gate, the visual comparison and the eight functional phases. The
**Rust** suite of the Core — its unit tests and its integration tests — is not
part of that acceptance: the receipts of the Rust regression belong to the eras
of the milestones.

This rehearsal runs the Rust suite of the current tree and records the result
with the revision it ran on and the toolchain it used.

Nothing of the rehearsal touches the personal installation of the operator and
nothing leaves the machine.

Usage:
  python3 tests/oip_rust_regression.py [--evidence DIR] [--workspace|--crate NAME]
"""
import argparse
import json
import pathlib
import re
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]


def git(*arguments):
    return subprocess.run(["git", *arguments], cwd=ROOT, capture_output=True,
                          text=True).stdout.strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", default=str(ROOT / "target" / "oip-rust-regression"))
    parser.add_argument("--workspace", action="store_true")
    parser.add_argument("--crate")
    parser.add_argument("--timeout", type=int, default=5400)
    args = parser.parse_args()
    evidence = pathlib.Path(args.evidence)
    evidence.mkdir(parents=True, exist_ok=True)
    report = {"schema": "oip-rust-regression-v1"}

    command = ["cargo", "test"]
    if args.crate:
        command += ["-p", args.crate]
    else:
        command += ["--workspace"]
    command += ["--release", "--no-fail-fast"]
    report["the_command"] = " ".join(command)
    report["the_revision"] = git("rev-parse", "HEAD")
    report["the_tree"] = git("rev-parse", "HEAD^{tree}")
    report["the_working_tree_is_clean"] = not git("status", "--porcelain")
    report["the_toolchain"] = {
        "rustc": subprocess.run(["rustc", "--version"], capture_output=True,
                                text=True).stdout.strip(),
        "cargo": subprocess.run(["cargo", "--version"], capture_output=True,
                                text=True).stdout.strip(),
    }

    began = time.monotonic()
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                            timeout=args.timeout)
    output = result.stdout + result.stderr
    (evidence / "the-cargo-output.log").write_text(output)
    report["the_seconds"] = round(time.monotonic() - began, 1)
    report["the_exit_code"] = result.returncode

    # The numbers of the suites: "test result: ok. 12 passed; 0 failed; ..."
    passed = sum(int(m) for m in re.findall(r"(\d+) passed", output))
    failed = sum(int(m) for m in re.findall(r"(\d+) failed", output))
    ignored = sum(int(m) for m in re.findall(r"(\d+) ignored", output))
    report["the_tests"] = {"passed": passed, "failed": failed, "ignored": ignored}
    report["the_suites"] = len(re.findall(r"test result:", output))
    report["the_failures"] = [
        line for line in output.splitlines()
        if re.match(r"^(test .* FAILED|failures:)", line)
    ][:40]

    report["status"] = "PASS" if result.returncode == 0 and failed == 0 else "FAIL"
    report["finished_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    (evidence / "rust-regression.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "the_failures"}, indent=2))
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
