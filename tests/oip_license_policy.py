#!/usr/bin/env python3
"""Exercise the offline license trust bootstrap through its shipped entry points."""

import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from oip_license_issue import (
    ISSUER, PHP_ODP_ARTIFACT, PHP_OIP_ARTIFACT, PHP_TEST_KEYS, decode, encode, json_line, public_key,
)


ROOT = Path(__file__).resolve().parents[1]
CORE = ROOT / "target/release/oip-server"
OPERATOR = ROOT / "tools/oip_local.py"


def registry_row(kid, key, *, product="oip", state="active"):
    return {"product_id": product, "kid": kid, "public_key": key,
            "fingerprint": hashlib.sha256(decode(key)).hexdigest(), "state": state}


class LicensePolicy(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="oip-license-policy-")
        self.addCleanup(scratch.cleanup)
        self.directory = Path(scratch.name).resolve()
        self.registry = self.directory / "pruefschluessel.json"
        oip_kid = json.loads(PHP_OIP_ARTIFACT)["kid"]
        odp_kid = json.loads(PHP_ODP_ARTIFACT)["kid"]
        self.active = registry_row(oip_kid, PHP_TEST_KEYS[oip_kid])
        self.foreign = registry_row(odp_kid, PHP_TEST_KEYS[odp_kid], product="odp")
        self.policy = {
            "issuer": ISSUER, "product_id": "oip",
            "keys": {self.active["kid"]: self.active["public_key"]},
            "kinds": ["commercial"], "rights": {"installations": 20},
        }

    def write_registry(self, *keys, issuer=ISSUER):
        self.registry.write_bytes(json_line({"issuer": issuer, "keys": list(keys)}))

    def prepare(self, *flags):
        return subprocess.run(
            [sys.executable, "-B", OPERATOR, "prepare-license-policy", "--registry", self.registry,
             *flags], cwd=self.directory, capture_output=True, timeout=15,
        )

    def check_policy(self, policy):
        return subprocess.run([CORE, "--check-license-policy"], input=policy, cwd=self.directory,
                              capture_output=True, timeout=15)

    def assert_refused(self, result):
        self.assertNotEqual(result.returncode, 0, result)
        self.assertEqual(result.stdout, b"", result)

    def test_selected_rollover_keys_form_a_policy_accepted_by_core(self):
        pending, retired, compromised = [
            registry_row(*public_key(Ed25519PrivateKey.generate()), state=state)
            for state in ("pending", "retired", "compromised")
        ]
        self.write_registry(self.foreign, compromised, pending, retired, self.active)
        options = []
        for row in (self.active, pending, retired):
            options.extend(("--key-fingerprint", row["fingerprint"]))
        result = self.prepare(*options, "--kind", "commercial", "--kind", "personal",
                              "--right", "installations=20")
        self.assertEqual(result.returncode, 0, result.stderr)
        policy = json.loads(result.stdout)
        self.assertEqual(set(policy["kinds"]), {"commercial", "personal"})
        self.assertEqual(len(policy["kinds"]), 2)
        self.assertEqual({key: policy[key] for key in ("issuer", "product_id", "rights")},
                         {key: self.policy[key] for key in ("issuer", "product_id", "rights")})
        self.assertEqual(policy["keys"], {row["kid"]: row["public_key"]
                                         for row in (self.active, pending, retired)})
        check = self.check_policy(result.stdout)
        self.assertEqual(check.returncode, 0, check.stderr)
        self.assertEqual(list(self.directory.iterdir()), [self.registry])

    def test_selection_requires_an_explicit_unique_eligible_fingerprint(self):
        compromised = registry_row(*public_key(Ed25519PrivateKey.generate()), state="compromised")
        self.write_registry(self.active, self.foreign, compromised)
        for label, selection in {
            "omitted": [],
            "malformed": [self.active["kid"]],
            "absent": ["0" * 64],
            "repeated": [self.active["fingerprint"], self.active["fingerprint"]],
            "other product": [self.active["fingerprint"], self.foreign["fingerprint"]],
            "compromised": [self.active["fingerprint"], compromised["fingerprint"]],
        }.items():
            with self.subTest(label=label):
                options = [argument for value in selection for argument in ("--key-fingerprint", value)]
                self.assert_refused(self.prepare(*options, "--kind", "commercial"))

    def test_malformed_or_inconsistent_export_returns_no_policy(self):
        options = ("--key-fingerprint", self.active["fingerprint"], "--kind", "commercial")
        for label, payload in {
            "invalid JSON": b"{",
            "duplicate field": b'{"issuer":"other.example",' +
                               json_line({"issuer": ISSUER, "keys": [self.active]})[1:],
            "unknown issuer": json_line({"issuer": "other.example", "keys": [self.active]}),
            "duplicate row": json_line({"issuer": ISSUER, "keys": [self.active, self.active]}),
            "wrong key ID": json_line({"issuer": ISSUER, "keys": [{**self.active, "kid": "0" * 32}]}),
            "wrong key fingerprint": json_line({"issuer": ISSUER, "keys": [
                {**self.active, "public_key": self.foreign["public_key"]},
            ]}),
            "unknown state": json_line({"issuer": ISSUER, "keys": [{**self.active, "state": "new"}]}),
        }.items():
            with self.subTest(label=label):
                self.registry.write_bytes(payload)
                self.assert_refused(self.prepare(*options))

    def test_preparation_requires_approved_kinds_and_bounded_rights(self):
        self.write_registry(self.active)
        selection = ("--key-fingerprint", self.active["fingerprint"])
        for options in (
            (), ("--kind", "Commercial"), ("--kind", "commercial", "--kind", "commercial"),
            ("--kind", "commercial", "--right", "invalid/right=20"),
            ("--kind", "commercial", "--right", "installations=0"),
            ("--kind", "commercial", "--right", "installations=1000000"),
            ("--kind", "commercial", "--right", "installations=2", "--right", "installations=3"),
        ):
            with self.subTest(options=options):
                self.assert_refused(self.prepare(*selection, *options))
        no_explicit_rights = self.prepare(*selection, "--kind", "commercial")
        self.assertEqual(no_explicit_rights.returncode, 0, no_explicit_rights.stderr)
        self.assertEqual(json.loads(no_explicit_rights.stdout)["rights"], {})

    def test_core_rejects_invalid_policy_from_independent_input(self):
        weak = bytes(32)
        for key, values in {
            "issuer": ("other.example",),
            "product_id": ("odp",),
            "keys": ({}, {"0" * 32: self.active["public_key"]},
                     {self.active["kid"]: self.active["public_key"] + "="},
                     {hashlib.sha256(weak).hexdigest()[:32]: encode(weak)}),
            "kinds": ([], ["commercial", "commercial"], ["Commercial"]),
            "rights": ({"installations": 0}, {"installations": 1000000}, {"inva/lid": 20}),
        }.items():
            for value in values:
                with self.subTest(key=key, value=value):
                    self.assert_refused(self.check_policy(json_line({**self.policy, key: value})))
        valid = json_line(self.policy)
        repeated_id = json.dumps(self.active["kid"]).encode()
        repeated_key = json.dumps(self.active["public_key"]).encode()
        ambiguous_key = valid.replace(repeated_id + b":", repeated_id + b":" + repeated_key + b"," + repeated_id + b":")
        for malformed in (
            b'{"issuer":"other.example",' + valid[1:],
            valid.replace(b'"installations":20', b'"installations":1,"installations":20'),
            ambiguous_key,
            b"{" + b" " * (16 * 1024) + valid[1:],
        ):
            with self.subTest(payload=malformed[:120]):
                self.assertNotEqual(malformed, valid)
                self.assert_refused(self.check_policy(malformed))
        self.assertEqual(list(self.directory.iterdir()), [])

    def test_setup_refuses_invalid_policy_without_writing_configuration(self):
        policy = self.directory / "policy.json"
        policy.write_bytes(json_line({**self.policy, "keys": {"0" * 32: self.active["public_key"]}}))
        web = self.directory / "web"
        web.mkdir()
        (web / "main.dart.js").touch()
        instance, backup = self.directory / "instance", self.directory / "backup"
        result = subprocess.run([
            sys.executable, "-B", OPERATOR, "--instance", instance, "--core", CORE, "--web", web,
            "setup", "--organization", "Testbetrieb", "--infrastructure", "Testinfrastruktur",
            "--site", "Testort", "--backup-directory", backup, "--license-policy", policy,
            "--commercial-license-kind", "commercial",
        ], cwd=self.directory, capture_output=True, timeout=25)
        self.assert_refused(result)
        self.assertIn(b"Ed25519", result.stderr)
        self.assertFalse(backup.exists())
        self.assertEqual({path.name for path in instance.iterdir()}, {".local-operation.lock"})


if __name__ == "__main__":
    unittest.main()
