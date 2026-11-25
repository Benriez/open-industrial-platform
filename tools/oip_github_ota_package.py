#!/usr/bin/env python3
"""Package and sign an OIP direct-macOS GitHub OTA release."""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import plistlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUNDLE_ID = "org.openindustrial.oipDashboard"
APP_NAME = "Open Industrial Platform.app"


def run(args: list[str]) -> None:
    subprocess.run(args, check=True)


def developer_entitlements(identity: str, profile: pathlib.Path) -> dict:
    match = re.fullmatch(r"Developer ID Application: .+ \(([A-Z0-9]{10})\)", identity)
    if not match:
        raise ValueError("use the full Developer ID Application identity, including its team ID")
    team = match.group(1)
    decoded = plistlib.loads(subprocess.check_output([
        "/usr/bin/security", "cms", "-D", "-i", str(profile),
    ]))
    entitlements = decoded.get("Entitlements", {})
    app_id = f"{team}.{BUNDLE_ID}"
    if (team not in decoded.get("TeamIdentifier", [])
            or entitlements.get("com.apple.application-identifier") != app_id
            or not any(group in (app_id, f"{team}.*")
                       for group in entitlements.get("keychain-access-groups", []))):
        raise ValueError("the Developer ID provisioning profile must authorize this OIP app and Keychain group")
    return {
        "com.apple.application-identifier": app_id,
        "com.apple.developer.team-identifier": team,
        "keychain-access-groups": [app_id],
    }


def sign_developer_bundle(bundle: pathlib.Path, identity: str, entitlements: pathlib.Path) -> None:
    command = ["/usr/bin/codesign", "--force", "--timestamp", "--options", "runtime",
               "--sign", identity]
    # Sign embedded code from the inside out. The app entitlements belong to
    # Runner alone. Applying them recursively would grant access to plugins.
    nested = [path for path in (bundle / "Contents").rglob("*")
              if not path.is_symlink()
              and ((path.is_dir() and path.suffix in {".framework", ".app", ".xpc", ".appex"})
                   or (path.is_file() and path.suffix == ".dylib"))]
    for path in sorted(nested, key=lambda path: (-len(path.parts), str(path))):
        run([*command, str(path)])
    run([*command, "--entitlements", str(entitlements), str(bundle)])


def archive_bundle(bundle: pathlib.Path, path: pathlib.Path) -> None:
    path.unlink(missing_ok=True)
    run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent",
         str(bundle), str(path)])


def notarize_bundle(bundle: pathlib.Path, archive: pathlib.Path, profile: str) -> None:
    result = json.loads(subprocess.check_output([
        "/usr/bin/xcrun", "notarytool", "submit", str(archive),
        "--keychain-profile", profile, "--wait", "--output-format", "json",
    ]))
    if result.get("status") != "Accepted":
        raise ValueError(f"Apple notarization did not accept the archive (submission {result.get('id')})")
    run(["/usr/bin/xcrun", "stapler", "staple", str(bundle)])
    run(["/usr/bin/xcrun", "stapler", "validate", str(bundle)])
    run(["/usr/sbin/spctl", "--assess", "--type", "execute", str(bundle)])
    archive_bundle(bundle, archive)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=pathlib.Path, required=True)
    parser.add_argument("--out", type=pathlib.Path, required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--developer-id")
    parser.add_argument("--notary-profile")
    parser.add_argument("--provisioning-profile", type=pathlib.Path)
    args = parser.parse_args()
    signing = (args.developer_id, args.notary_profile, args.provisioning_profile)
    if any(signing) and not all(signing):
        parser.error("Developer ID, notary Keychain profile and provisioning profile are required together")

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

    entitlements = (developer_entitlements(args.developer_id, args.provisioning_profile)
                    if args.developer_id else None)
    output.mkdir(parents=True, exist_ok=True)
    staged_bundle = output / APP_NAME
    if staged_bundle.exists():
        run(["/bin/rm", "-rf", str(staged_bundle)])
    run(["/usr/bin/ditto", str(bundle), str(staged_bundle)])
    info_path = staged_bundle / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    info["OIPUpdateEnabled"] = True
    info["OIPPiTunnelEnabled"] = True
    info["OIPRequireProtectedTouchID"] = entitlements is not None
    info_path.write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_XML, sort_keys=False))
    helper = ROOT / "apps/flutter/macos/Runner/oip_ota_install_helper.sh"
    shutil.copy2(helper, staged_bundle / "Contents/Resources/oip_ota_install_helper.sh")
    shutil.copy2(ROOT / "tools/oip_tcp_relay.py", staged_bundle / "Contents/Resources/oip_tcp_relay.py")
    if entitlements is not None:
        shutil.copy2(args.provisioning_profile,
                     staged_bundle / "Contents/embedded.provisionprofile")
        entitlements_path = output / "oip-developer-id.entitlements"
        entitlements_path.write_bytes(plistlib.dumps(entitlements))
        sign_developer_bundle(staged_bundle, args.developer_id, entitlements_path)
    else:
        direct_entitlements = ROOT / "apps/flutter/macos/Runner/Direct.entitlements"
        run(["/usr/bin/codesign", "--force", "--deep", "--sign", "-",
             "--entitlements", str(direct_entitlements), str(staged_bundle)])
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(staged_bundle)])

    archive_name = "oip-macos-universal.zip"
    archive_path = output / archive_name
    archive_bundle(staged_bundle, archive_path)
    if entitlements is not None:
        notarize_bundle(staged_bundle, archive_path, args.notary_profile)
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
        "apple_notarized": entitlements is not None,
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
