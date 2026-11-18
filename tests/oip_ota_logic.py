#!/usr/bin/env python3
"""Regression tests for the direct macOS GitHub OTA updater decision logic.

Two checks, both focused on the failure that left the installed 0.3.0+3 app
silent against the signed v0.3.1+4 release:

1. logic: the pure decision logic in apps/flutter/macos/Runner/OIPGitHubOTA.swift
   is compiled together with a self-contained Swift runner and executed. It
   proves the signed, newer release is offered and that every rejection path
   (missing/wrong asset name, unsafe URL, undecodable manifest, wrong bundle id,
   invalid signature, wrong archive name, non-newer build) is returned.

2. names: the asset names the client looks for are the exact names the packager
   and local release script publish, so the silent-failure asset-name mismatch
   cannot regress. Releases are published directly from this Mac; no GitHub
   Actions workflow is required.
"""
from __future__ import annotations

import pathlib
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
LOGIC = ROOT / "tools/oip_ota_logic_tests.swift"
UPDATER = ROOT / "apps/flutter/macos/Runner/OIPGitHubOTA.swift"
PACKAGER = ROOT / "tools/oip_github_ota_package.py"
RELEASE_SCRIPT = ROOT / "tools/oip_ota_release.sh"


class OIPGitHubOTALogic(unittest.TestCase):
    def test_decision_logic_compiles_and_passes(self):
        self.assertTrue(UPDATER.is_file(), "updater logic source missing")
        self.assertTrue(LOGIC.is_file(), "logic test runner missing")
        with tempfile.TemporaryDirectory(prefix="oip-ota-logic-") as temporary:
            binary = pathlib.Path(temporary) / "oip_ota_logic"
            compiled = subprocess.run(
                ["swiftc", "-O", str(UPDATER), str(LOGIC), "-o", str(binary)],
                capture_output=True, text=True,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
            self.assertIn("ALL OTA LOGIC TESTS PASSED", run.stdout)

    def test_client_and_packager_agree_on_asset_names(self):
        updater = UPDATER.read_text()
        # The client must look for the exact names the signer publishes.
        manifest = re.search(r'manifestAssetName\s*=\s*"([^"]+)"', updater)
        signature = re.search(r'signatureAssetName\s*=\s*"([^"]+)"', updater)
        archive = re.search(r'archiveAssetName\s*=\s*"([^"]+)"', updater)
        self.assertIsNotNone(manifest, "manifestAssetName constant missing")
        self.assertIsNotNone(signature, "signatureAssetName constant missing")
        self.assertIsNotNone(archive, "archiveAssetName constant missing")
        manifest_name, signature_name, archive_name = (m.group(1) for m in (manifest, signature, archive))

        packager = PACKAGER.read_text()
        release_script = RELEASE_SCRIPT.read_text()
        # The packager writes the manifest and derives its JSON signature path as
        # "<manifest>.sig", i.e. oip-macos-manifest.json.sig.
        self.assertIn('"oip-macos-manifest.json"', packager)
        self.assertIn('"oip-macos-universal.zip"', packager)
        signature_derived = re.search(r'"signature":\s*str\(manifest_path\) \+ "\.sig"', packager)
        self.assertIsNotNone(signature_derived, "packager does not derive the .json.sig signature name")
        # The local release script uploads the same three assets directly.
        self.assertIn('"$RELEASE_DIR/oip-macos-universal.zip"', release_script)
        self.assertIn('"$RELEASE_DIR/oip-macos-manifest.json"', release_script)
        self.assertIn('"$RELEASE_DIR/oip-macos-manifest.json.sig"', release_script)
        # The exact regression: the client's signature asset name is the JSON
        # signature the packager publishes, not the wrong bare ".sig" name.
        self.assertEqual(manifest_name, "oip-macos-manifest.json")
        self.assertEqual(signature_name, "oip-macos-manifest.json.sig")
        self.assertEqual(archive_name, "oip-macos-universal.zip")
        self.assertNotIn('"oip-macos-manifest.sig"', updater)


if __name__ == "__main__":
    unittest.main(verbosity=2)
