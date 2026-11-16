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
repository. GitHub Actions needs that value as the repository secret
`OIP_OTA_SIGNING_PRIVATE_KEY`. The matching public key is embedded in
`apps/flutter/macos/Runner/Info.plist`.

The public GitHub repository is `Benriez/open-industrial-platform`. Its Actions
secret `OIP_OTA_SIGNING_PRIVATE_KEY` is configured from the local Keychain; the
secret value is never printed or committed. The repository still needs the
source push and a version tag to run the release workflow and publish the first
OTA release.

To prepare a release, push a tag such as `v0.3.2`. The workflow builds a
universal macOS bundle, signs the manifest and publishes the archive, manifest
and detached signature as assets of that GitHub Release. The app accepts only a
signed manifest whose archive digest matches; an unsigned or edited release
cannot authorize an installation.

The managed Mac release uses `http://127.0.0.1:18855`. The direct macOS app
keeps an SSH forward to the Pi Core at `127.0.0.1:18808` while the app is open.
The release workflow and app tunnel manager use the same local port.

The first updater-enabled app must be installed locally. Subsequent versions are
delivered through the GitHub release check.
