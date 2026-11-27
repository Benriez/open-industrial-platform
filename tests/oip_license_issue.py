#!/usr/bin/env python3
"""License Center test fixtures. Test signers never enter an operator package."""

import base64
from datetime import datetime, timezone
import hashlib
import json
import unittest

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat


DOMAIN = b"code-server.de/software-license/v1\0"
ISSUER = "code-server.de"
PRODUCT = "oip"

# Public fixtures produced by License Center's PHP tests/vectors.php
# at revision 87b070545e94d409cff687e8e688ed8a31967091.
# These contain only synthetic data and signatures. Keep the trailing LF.
PHP_OIP_ARTIFACT = (
    b'{"v":1,"kid":"37f593417ec0c98c573b660d476662c3","payload":"'
    b'eyJ2ZXJzaW9uIjoxLCJwdXJwb3NlIjoic29mdHdhcmUtbGljZW5zZSIsImlzc3VlciI6ImNvZGUtc2VydmVyLmRl'
    b'IiwicHJvZHVjdF9pZCI6Im9pcCIsImtpZCI6IjM3ZjU5MzQxN2VjMGM5OGM1NzNiNjYwZDQ3NjY2MmMzIiwibGlj'
    b'ZW5zZV9pZCI6ImFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhIiwicmV2aXNpb24iOjEsImlzc3VlZF9h'
    b'dCI6IjIwMjYtMTAtMDFUMDA6MDA6MDBaIiwiaG9sZGVyIjp7ImlkIjoiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJi'
    b'YmJiYmJiYmIiLCJuYW1lIjoiTXVzdGVyZmlybWEgw4QgJiBTw7ZobmUifSwia2luZCI6InN0YW5kYXJkIiwicmln'
    b'aHRzIjp7Imluc3RhbGxhdGlvbnMiOjN9LCJ1c2FnZSI6eyJtb2RlIjoicGVycGV0dWFsIiwiZnJvbSI6IjIwMjYt'
    b'MTAtMDFUMDA6MDA6MDBaIiwidW50aWwiOm51bGx9LCJzdXBwb3J0Ijp7Im1vZGUiOiJmaXhlZCIsImZyb20iOiIy'
    b'MDI2LTEwLTAxVDAwOjAwOjAwWiIsInVudGlsIjoiMjAyNi0xMS0wMVQwMDowMDowMFoifX0'
    b'","signature":"BS7wVbQpmP4bAMnU7gbnIwucHTx5d9fIQXrLoSbWRUSK91Uh47jfK3vcBfSFD6iJMcthndho7uaC_kUhU1psDA"}\n'
)
PHP_ODP_ARTIFACT = (
    b'{"v":1,"kid":"24991ff5fe933b52513b15d095476eb9","payload":"'
    b'eyJ2ZXJzaW9uIjoxLCJwdXJwb3NlIjoic29mdHdhcmUtbGljZW5zZSIsImlzc3VlciI6ImNvZGUtc2VydmVyLmRl'
    b'IiwicHJvZHVjdF9pZCI6Im9kcCIsImtpZCI6IjI0OTkxZmY1ZmU5MzNiNTI1MTNiMTVkMDk1NDc2ZWI5IiwibGlj'
    b'ZW5zZV9pZCI6ImFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhIiwicmV2aXNpb24iOjEsImlzc3VlZF9h'
    b'dCI6IjIwMjYtMTAtMDFUMDA6MDA6MDBaIiwiaG9sZGVyIjp7ImlkIjoiYmJiYmJiYmJiYmJiYmJiYmJiYmJiYmJi'
    b'YmJiYmJiYmIiLCJuYW1lIjoiTXVzdGVyZmlybWEgw4QgJiBTw7ZobmUifSwia2luZCI6InN0YW5kYXJkIiwicmln'
    b'aHRzIjp7Imluc3RhbGxhdGlvbnMiOjN9LCJ1c2FnZSI6eyJtb2RlIjoicGVycGV0dWFsIiwiZnJvbSI6IjIwMjYt'
    b'MTAtMDFUMDA6MDA6MDBaIiwidW50aWwiOm51bGx9LCJzdXBwb3J0Ijp7Im1vZGUiOiJmaXhlZCIsImZyb20iOiIy'
    b'MDI2LTEwLTAxVDAwOjAwOjAwWiIsInVudGlsIjoiMjAyNi0xMS0wMVQwMDowMDowMFoifX0'
    b'","signature":"CV2TNDL4tcGu6fsS_zDE7o2Lk4eB_mP2QC17X-tCdbopdiwdlqkVdjoU8oB84Z7QMKL9WeLm0yQ0kdMDcSXCAw"}\n'
)
PHP_TEST_KEYS = {
    "37f593417ec0c98c573b660d476662c3": "tltBZj3RuF_GkPorA-GKt2FJ7P4ra8SQfulDEdgtmsU",
    "24991ff5fe933b52513b15d095476eb9": "UN5QDUFE4xMzJilitHUV3PE6b6W9MsC_9qIhtYpFQKs",
}
PHP_OIP_LICENSE_ID = "a" * 32
PHP_OIP_HOLDER = "Musterfirma Ä & Söhne"


def encode(data):
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def decode(data):
    return base64.urlsafe_b64decode(data + "=" * (-len(data) % 4))


def public_key(key):
    raw = key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)
    return hashlib.sha256(raw).hexdigest()[:32], encode(raw)


def write_policy(path, keys):
    path.write_bytes(json_line({
        "issuer": ISSUER,
        "product_id": PRODUCT,
        "keys": keys,
        "kinds": ["standard", "personal"],
        "rights": {"installations": 20},
    }))


def json_bytes(mapping):
    return json.dumps(mapping, separators=(",", ":"), ensure_ascii=False).encode("utf-8")


def json_line(mapping):
    return json_bytes(mapping) + b"\n"


def utc(timestamp):
    return datetime.fromtimestamp(timestamp, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def period(mode, start=None, end=None):
    return {
        "mode": mode,
        "from": utc(start) if start is not None else None,
        "until": utc(end) if end is not None else None,
    }


def sign_fixture(key, license_id, issued_at, *, usage, support=None, holder="Testbetrieb", kind="standard",
                 revision=1):
    kid, _ = public_key(key)
    payload = json_bytes({
        "version": 1,
        "purpose": "software-license",
        "issuer": ISSUER,
        "product_id": PRODUCT,
        "kid": kid,
        "license_id": license_id,
        "revision": revision,
        "issued_at": utc(issued_at),
        "holder": {"id": "b" * 32, "name": holder},
        "kind": kind,
        "rights": {},
        "usage": usage,
        "support": period("none") if support is None else support,
    })
    return json_line({
        "v": 1,
        "kid": kid,
        "payload": encode(payload),
        "signature": encode(key.sign(DOMAIN + payload)),
    })


def proof_request(artifact):
    return {"proof": {"artifact": artifact.decode("utf-8")}}


class LicenseCenterFixtures(unittest.TestCase):
    def test_php_artifacts_are_byte_exact_and_independently_signed(self):
        for raw, product, sha256 in (
            (PHP_OIP_ARTIFACT, "oip", "0f491c3a203ec8be0c278ddd60b1481df6784ea4cd8094b0915578d72d573089"),
            (PHP_ODP_ARTIFACT, "odp", "935cde2cb0cfd7c6babe0ab31c0f84cbe27e5df7a5ad3e27d0990fc85a400a15"),
        ):
            with self.subTest(product=product):
                self.assertEqual(hashlib.sha256(raw).hexdigest(), sha256)
                artifact = json.loads(raw)
                payload = decode(artifact["payload"])
                verifier = Ed25519PublicKey.from_public_bytes(decode(PHP_TEST_KEYS[artifact["kid"]]))
                verifier.verify(decode(artifact["signature"]), DOMAIN + payload)
                self.assertEqual(json.loads(payload)["product_id"], product)
                self.assertEqual(proof_request(raw)["proof"]["artifact"].encode(), raw)

    def test_synthetic_fixture_uses_exact_signed_payload(self):
        key = Ed25519PrivateKey.generate()
        raw = sign_fixture(key, "1" * 32, 1760000000, holder="Prüfunternehmen",
                           usage=period("perpetual", 1760000000),
                           support=period("fixed", 1760000100, 1760001000))
        artifact = json.loads(raw)
        kid, encoded_key = public_key(key)
        self.assertEqual(kid, artifact["kid"])
        payload = decode(artifact["payload"])
        signature = decode(artifact["signature"])
        verifier = Ed25519PublicKey.from_public_bytes(decode(encoded_key))
        verifier.verify(signature, DOMAIN + payload)
        with self.assertRaises(InvalidSignature):
            verifier.verify(signature, DOMAIN + payload + b" ")
        self.assertIn("Prüfunternehmen".encode(), payload)
        self.assertTrue(raw.endswith(b"\n"))


if __name__ == "__main__":
    unittest.main()
