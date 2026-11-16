# Direct macOS OTA updates

The macOS direct-distribution build checks the latest **public GitHub Release**
every six hours. It downloads the OIP manifest and signature over HTTPS, verifies
the Ed25519 signature with the public key embedded in the app, checks the archive
SHA-256, confirms the OIP bundle identifier and a strictly newer build, then asks
the operator before installing. The updater stages the bundle beside the live
app, checks the digest again, validates the code signature and bundle identity,
replaces the app while it is closed, and restores the previous bundle if the
replacement check fails.

The implementation uses macOS SDK APIs and tools plus GitHub's REST/Release
interfaces. It carries no updater framework, access token or password. Public
release access is intentional because embedding a GitHub token in a macOS app
would expose it. The repository configured in the app is
`Benriez/open-industrial-platform`.

The Mac App Store package does not enable this updater. Its updates are delivered
by the App Store. The direct GitHub package is unsandboxed so it can replace the
operator-installed bundle under `/Applications`; the store package retains the
App Sandbox entitlement.

## Signing releases

The Ed25519 private key is stored in the maintainer's macOS login Keychain under
service `org.openindustrial.oip.ota-release` and account
`github-ed25519-signing-key`. The raw private value is never written to the
repository or uploaded to GitHub. The local signer reads it directly from that
Keychain; the matching public key is embedded in
`apps/flutter/macos/Runner/Info.plist`.

## Publishing without GitHub Actions

OTA releases are built, signed, verified, and uploaded from the maintainer's
Mac. No Actions runner is used. The old release workflow has been removed, and
push-based CI triggers are disabled so pushing a release tag does not start a
paid runner. Pull-request checks and manual `workflow_dispatch` remain
available for engineering validation.

Prerequisites are Flutter 3.22.0, GitHub CLI (`gh`) authenticated with release
write access, a clean `main` branch synced with `origin/main`, and the signing
key in the login Keychain. From the repository root, run:

```sh
tools/oip_ota_release.sh 0.3.9
```

The script downloads the latest signed manifest to determine the next numeric
build, builds the universal macOS app locally, packages and signs the manifest,
verifies the Ed25519 signature, archive digest and strict code signature, then
pushes the source tag and uploads the three assets directly with `gh release
create`. It fails before publishing if the source tree is dirty, main is not
synced, the version already exists, or any verification fails. The app accepts
only a signed manifest whose archive digest matches; GitHub serves the update
but does not authorize it.

The managed Mac release uses `http://127.0.0.1:18855`. The direct macOS app
keeps an SSH forward to the Pi Core at `127.0.0.1:18808` while the app is open.
The local release build and app tunnel manager use the same local port
`18858`.

The first updater-enabled app must be installed locally. Subsequent versions are
delivered through the public GitHub release check and installed only after the
operator accepts the in-app update prompt.
