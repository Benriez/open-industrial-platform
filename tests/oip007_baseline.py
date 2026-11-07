#!/usr/bin/env python3
"""Build the OIP-007 baseline binary that can create a genuine schema2 database.

The legacy adoption case of the OIP-008 milestone needs a writer that still
creates the schema2 layout. The historical protected binary of that milestone
is not part of the workspace any more, so the writer is rebuilt from the
verified OIP-007 baseline commit.

A rebuild is not byte identical to the historical binary, therefore the result
records the source commit and the hash of the rebuild and never claims the
identity of the original. The rebuild only writes into the given destination
directory; the canonical checkout, its database and its runtime stay untouched.

Usage:
    python3 tests/oip007_baseline.py [--destination target/oip-007-baseline]
"""
import argparse, hashlib, json, os, pathlib, subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
# The verified OIP-007 project baseline of the repository history.
COMMIT = "a27e7b1e01dc1cb6f4d97c34319b0aa6d7321871"
# The hash of the historical protected binary, recorded by the OIP-008 receipt.
HISTORICAL_BINARY_SHA256 = "8a726547e9c7ac3c4483a24220425889bdba92c52fd8240aa6b3e9eff632feaf"


def build(destination):
    source = destination / "source"
    source.mkdir(parents=True, exist_ok=True)
    archive = subprocess.check_output(["git", "archive", COMMIT], cwd=ROOT)
    subprocess.run(["tar", "-x", "-C", str(source)], input=archive, check=True)
    environment = dict(
        os.environ,
        CARGO_TARGET_DIR=str(destination / "target"),
        CARGO_PROFILE_DEV_DEBUG="0",
    )
    subprocess.run(
        ["cargo", "build", "--locked", "-p", "oip-server", "--bin", "oip-server"],
        cwd=source,
        env=environment,
        check=True,
    )
    binary = destination / "target" / "debug" / "oip-server"
    digest = hashlib.sha256(binary.read_bytes()).hexdigest()
    return {
        "source_commit": COMMIT,
        "binary": str(binary),
        "sha256": digest,
        "historical_binary_sha256": HISTORICAL_BINARY_SHA256,
        "byte_identical_to_historical": digest == HISTORICAL_BINARY_SHA256,
        "note": "the rebuild comes from the verified OIP-007 baseline commit; it is a genuine schema2 writer, but the identity of the historical protected binary is not claimed",
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--destination", default=str(ROOT / "target" / "oip-007-baseline"))
    args = parser.parse_args()
    destination = pathlib.Path(args.destination)
    result = build(destination)
    (destination / "baseline.json").write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
