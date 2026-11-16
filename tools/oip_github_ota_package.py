#!/usr/bin/env python3
"""Package and sign an OIP direct-macOS GitHub OTA release."""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import plistlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUNDLE_ID = "org.openindustrial.oipDashboard"
APP_NAME = "Open Industrial Platform.app"


def run(args: list[str]) -> None:
    subprocess.run(args, check=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=pathlib.Path, required=True)
    parser.add_argument("--out", type=pathlib.Path, required=True)
    parser.add_argument("--build", required=True)
    args = parser.parse_args()

    bundle = args.bundle.resolve()
    output = args.out.resolve()
    if not bundle.is_dir() or bundle.suffix != ".app":
        parser.error(f"not a macOS app bundle: {bundle}")
    info_path = bundle / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    if info.get("CFBundleIdentifier") != BUNDLE_ID:
        parser.error("bundle identifier does not match OIP")
    if str(info.get("CFBundleVersion")) != args.build:
        parser.error("bundle build does not match --build")

    output.mkdir(parents=True, exist_ok=True)
    staged_bundle = output / APP_NAME
    if staged_bundle.exists():
        run(["/bin/rm", "-rf", str(staged_bundle)])
    run(["/usr/bin/ditto", str(bundle), str(staged_bundle)])
    info_path = staged_bundle / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    info["OIPUpdateEnabled"] = True
    info["OIPPiTunnelEnabled"] = True
    info_path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_XML, sort_keys=False))
    helper = ROOT / "apps/flutter/macos/Runner/oip_ota_install_helper.sh"
    shutil.copy2(helper, staged_bundle / "Contents/Resources/oip_ota_install_helper.sh")
    direct_entitlements = ROOT / "apps/flutter/macos/Runner/Direct.entitlements"
    run(["/usr/bin/codesign", "--force", "--deep", "--sign", "-",
         "--entitlements", str(direct_entitlements), str(staged_bundle)])
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(staged_bundle)])

    archive_name = "oip-macos-universal.zip"
    archive_path = output / archive_name
    archive_path.unlink(missing_ok=True)
    run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent",
         str(staged_bundle), str(archive_path)])
    digest = hashlib.sha256(archive_path.read_bytes()).hexdigest()
    manifest = {
        "bundle_identifier": BUNDLE_ID,
        "version": str(info["CFBundleShortVersionString"]),
        "build": args.build,
        "archive": archive_name,
        "archive_sha256": digest,
    }
    manifest_path = output / "oip-macos-manifest.json"
    manifest_path.write_text(json.dumps(manifest, sort_keys=True, separators=(",", ":")) + "\n")
    signer = ROOT / "tools/oip_ota_sign.swift"
    run(["/usr/bin/swift", str(signer), str(manifest_path)])
    print(json.dumps({
        "bundle": str(staged_bundle),
        "version": manifest["version"],
        "build": manifest["build"],
        "archive": str(archive_path),
        "archive_sha256": digest,
        "manifest": str(manifest_path),
        "signature": str(manifest_path) + ".sig",
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
