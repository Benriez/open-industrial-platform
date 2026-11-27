#!/usr/bin/env python3
"""Stage a reviewed OIP ZIP for HTTPS or export its first-install verifier."""

import argparse
import hashlib
from io import BytesIO
import json
import os
from pathlib import Path
import re
import sys
import tempfile
from zipfile import BadZipFile
import zlib

from oip_update import (
    LICENSE_MATERIALS,
    LICENSE_SETUP,
    MAX_ASSET_BYTES,
    MAX_ZIP_DIRECTORY,
    NOTICE,
    Refused,
    digest_of,
    flush_directory,
    open_asset,
    open_package,
    open_package_asset,
    public_key,
    verify_assets,
    verify_manifest,
    write_release_file,
)


TARGET = "aarch64-apple-darwin"
ZIP_NAME = "oip-local-darwin-arm64.zip"
MAX_ZIP = MAX_ASSET_BYTES + 2 * MAX_ZIP_DIRECTORY
BOOTSTRAP_MANIFEST = "SHA256SUMS"
BOOTSTRAP_PUBLIC_KEY = "update-public.pem"
BOOTSTRAP_ASSETS = ("tools/oip_update.py", "tools/oip_ops.py", "LICENSE", NOTICE)
APACHE = rb"""Options -Indexes -ExecCGI -Includes
<Files "oip-local-darwin-arm64.zip">
    Require expr "%{HTTPS} == 'on'"
    AcceptPathInfo Off
    SetHandler default-handler
    ForceType application/zip
    Header set Cache-Control "public, max-age=31536000, immutable"
    Header always set X-Content-Type-Options "nosniff"
</Files>
<FilesMatch "^(?!oip-local-darwin-arm64\.zip$)">
    Require all denied
</FilesMatch>
"""


def export_bootstrap(package, assets, key, zip_digest, directory):
    from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

    directory.mkdir(mode=0o700)
    digests = {ZIP_NAME: zip_digest}
    for asset in BOOTSTRAP_ASSETS:
        name = Path(asset).name
        with open_package_asset(package, asset) as source:
            write_release_file(directory / name, source)
        digests[name] = assets[asset]
    pem = key.public_bytes(Encoding.PEM, PublicFormat.SubjectPublicKeyInfo)
    write_release_file(directory / BOOTSTRAP_PUBLIC_KEY, BytesIO(pem))
    digests[BOOTSTRAP_PUBLIC_KEY] = hashlib.sha256(pem).hexdigest()
    checksums = "".join(f"{digest}  {name}\n" for name, digest in sorted(digests.items())).encode("ascii")
    write_release_file(directory / BOOTSTRAP_MANIFEST, BytesIO(checksums))
    flush_directory(directory)
    return hashlib.sha256(checksums).hexdigest()


def stage(bundle, key_path, approved_digest, output, *, bootstrap=False):
    if bundle.suffix != ".zip" or not re.fullmatch(r"[0-9a-f]{64}", approved_digest):
        raise Refused("provide a release ZIP and its approved SHA-256")
    if os.path.lexists(output):
        raise Refused("the publication staging directory already exists")
    key = public_key(key_path.absolute())
    with tempfile.TemporaryDirectory(prefix=".oip-publication-", dir=output.parent) as temporary:
        staging = Path(temporary) / "download"
        staging.mkdir(mode=0o700)
        archive = staging / ZIP_NAME
        with open_asset(bundle.parent, bundle.name) as source:
            write_release_file(archive, source, limit=MAX_ZIP)
        with archive.open("rb") as source:
            archive_digest = digest_of(source, MAX_ZIP)
        if archive_digest != approved_digest:
            raise Refused("the release ZIP does not match the approved SHA-256")
        with open_package(archive) as package:
            manifest, manifest_bytes, _ = verify_manifest(package, key, TARGET)
            assets = manifest["the_artefacts"]
            verify_assets(package, assets)
            if manifest.get(LICENSE_MATERIALS) != 1:
                raise Refused("the signed release must include the third-party license materials")
            license_setup = manifest.get(LICENSE_SETUP)
            if not license_setup or not license_setup["commercial_license_kinds"]:
                raise Refused("the signed release must include the commercial OIP license policy")
            tree = Path(temporary) / "tree"
            if bootstrap:
                checksum_digest = export_bootstrap(package, assets, key, archive_digest, tree)
        version = manifest["the_version"]
        if bootstrap:
            outcome = {"the_status": "BOOTSTRAP_READY", "the_bootstrap_manifest_sha256": checksum_digest}
        else:
            relative = Path("oip") / "macos-arm64" / version
            tree.mkdir(mode=0o700)
            (tree / relative).parent.mkdir(mode=0o700, parents=True)
            write_release_file(staging / ".htaccess", BytesIO(APACHE))
            flush_directory(staging)
            staging.rename(tree / relative)
            for directory in (tree / relative.parent, tree / "oip", tree):
                flush_directory(directory)
            outcome = {"the_status": "STAGED", "the_public_path": "/" + (relative / ZIP_NAME).as_posix()}
        if os.path.lexists(output):
            raise Refused("the publication staging directory already exists")
        tree.rename(output)
        flush_directory(output.parent)
    return {
        **outcome,
        "the_target": TARGET,
        "the_version": version,
        "the_revision": manifest["the_revision"],
        "the_zip_sha256": archive_digest,
        "the_manifest_sha256": hashlib.sha256(manifest_bytes).hexdigest(),
        "the_license_sha256": assets["LICENSE"],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle", type=Path, required=True, help="reviewed signed release ZIP")
    parser.add_argument("--public-key", type=Path, required=True, help="trusted package public key")
    parser.add_argument("--sha256", required=True, help="approved SHA-256 of the entire release ZIP")
    output = parser.add_mutually_exclusive_group(required=True)
    output.add_argument("--output", type=Path, help="new local static HTTPS staging directory")
    output.add_argument("--bootstrap", type=Path, help="new local first-install verifier directory")
    args = parser.parse_args()
    try:
        result = stage(args.bundle, args.public_key, args.sha256, args.bootstrap or args.output,
                       bootstrap=args.bootstrap is not None)
    except (BadZipFile, EOFError, NotImplementedError, OSError, Refused, ValueError, zlib.error) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    except ImportError:
        print("error: publication staging requires Python cryptography with Ed25519 support", file=sys.stderr)
        return 2
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
