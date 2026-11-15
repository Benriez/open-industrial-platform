#!/usr/bin/env python3
"""Integration check for the direct GitHub OTA package and signing path."""
from __future__ import annotations

import hashlib
import json
import pathlib
import plistlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUNDLE = ROOT / "apps/flutter/build/macos/Build/Products/Release/oip_dashboard.app"
PACKAGE = ROOT / "tools/oip_github_ota_package.py"
VERIFY = ROOT / "tools/oip_ota_verify.swift"
HELPER = ROOT / "apps/flutter/macos/Runner/oip_ota_install_helper.sh"


class GitHubOTAPackage(unittest.TestCase):
    def test_signed_direct_package_isolated_from_store_build(self):
        self.assertTrue(BUNDLE.is_dir(), "build the macOS app before this check")
        source_info_path = BUNDLE / "Contents/Info.plist"
        source_info = plistlib.loads(source_info_path.read_bytes())
        self.assertIs(source_info.get("OIPUpdateEnabled"), False)

        with tempfile.TemporaryDirectory(prefix="oip-github-ota-") as temporary:
            output = pathlib.Path(temporary)
            subprocess.run([
                sys.executable, str(PACKAGE), "--bundle", str(BUNDLE),
                "--out", str(output), "--build", str(source_info["CFBundleVersion"]),
            ], check=True, capture_output=True, text=True)
            staged = output / "Open Industrial Platform.app"
            staged_info = plistlib.loads((staged / "Contents/Info.plist").read_bytes())
            self.assertIs(staged_info["OIPUpdateEnabled"], True)
            self.assertEqual(staged_info["CFBundleIdentifier"], "org.openindustrial.oipDashboard")
            self.assertTrue((staged / "Contents/Resources/oip_ota_install_helper.sh").is_file())

            archive = output / "oip-macos-universal.zip"
            manifest_path = output / "oip-macos-manifest.json"
            signature_path = output / "oip-macos-manifest.json.sig"
            manifest_bytes = manifest_path.read_bytes()
            manifest = json.loads(manifest_bytes)
            self.assertEqual(manifest["archive_sha256"], hashlib.sha256(archive.read_bytes()).hexdigest())
            subprocess.run(["/bin/sh", "-n", str(HELPER)], check=True)
            subprocess.run([
                "/usr/bin/codesign", "--verify", "--deep", "--strict", str(staged),
            ], check=True)
            signed_entitlements = subprocess.run([
                "/usr/bin/codesign", "-d", "--entitlements", "-", "--xml", str(staged),
            ], check=True, capture_output=True, text=True)
            signed_out = signed_entitlements.stdout + signed_entitlements.stderr
            # An empty entitlements set (the direct build carries none, which is
            # the isolation this test proves) makes codesign emit only the
            # "Executable=" header with no <?xml plist. Treat that as the empty
            # dictionary instead of slicing a header, so the no-sandbox assertion
            # stays meaningful rather than crashing.
            if "<?xml" in signed_out:
                signed_xml = signed_out[signed_out.index("<?xml"):signed_out.rindex("</plist>") + 8]
                direct_entitlements = plistlib.loads(signed_xml.encode())
            else:
                direct_entitlements = {}
            self.assertIsNot(direct_entitlements.get("com.apple.security.app-sandbox"), True)
            subprocess.run([
                "swift", str(VERIFY), str(manifest_path), str(signature_path),
                staged_info["OIPUpdatePublicKey"],
            ], check=True, capture_output=True, text=True)

            tampered = output / "tampered.json"
            tampered.write_bytes(manifest_bytes + b" ")
            rejected = subprocess.run([
                "swift", str(VERIFY), str(tampered), str(signature_path),
                staged_info["OIPUpdatePublicKey"],
            ], capture_output=True, text=True)
            self.assertNotEqual(rejected.returncode, 0)
            self.assertIs(plistlib.loads(source_info_path.read_bytes())["OIPUpdateEnabled"], False)


if __name__ == "__main__":
    unittest.main(verbosity=2)
