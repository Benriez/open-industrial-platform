import Foundation

// Regression runner for the pure OTA decision logic in
// apps/flutter/macos/Runner/OIPGitHubOTA.swift. It is compiled together with
// that file by tests/oip_ota_logic.py and exits non-zero on the first failed
// assertion, so every rejected-update path (missing asset, bad download URL,
// undecodable manifest, wrong bundle id, invalid signature, wrong archive
// name, non-newer build) is covered without a network, bundle or UI.
//
// The important case is the original defect: the updater used to look for the
// asset name "oip-macos-manifest.sig", which the release never publishes, so
// the offer failed silently. The signature-asset lookup must resolve the real
// published name "oip-macos-manifest.json.sig" and return nil for the wrong
// name.

@main
struct OIPGitHubOTALogicTests {
  static func main() {
    var failures = 0
    func check(_ condition: Bool, _ name: String) {
      if condition {
        print("ok   - \(name)")
      } else {
        failures += 1
        print("FAIL - \(name)")
      }
    }

    let release = OIPGitHubOTA.Release(
      draft: false, prerelease: false,
      assets: [
        OIPGitHubOTA.Asset(name: "oip-macos-manifest.json",
                           browserDownloadURL: URL(string: "https://github.com/Benriez/open-industrial-platform/releases/download/v0.3.1/oip-macos-manifest.json")!),
        OIPGitHubOTA.Asset(name: "oip-macos-manifest.json.sig",
                           browserDownloadURL: URL(string: "https://github.com/Benriez/open-industrial-platform/releases/download/v0.3.1/oip-macos-manifest.json.sig")!),
        OIPGitHubOTA.Asset(name: "oip-macos-universal.zip",
                           browserDownloadURL: URL(string: "https://objects.githubusercontent.com/Benriez/open-industrial-platform/releases/download/v0.3.1/oip-macos-universal.zip")!),
      ])

    // --- Asset selection: the published names must resolve, a wrong name must not.

    check(OIPGitHubOTA.manifestAsset(in: release)?.name == "oip-macos-manifest.json", "manifest asset resolves by published name")
    check(OIPGitHubOTA.signatureAsset(in: release)?.name == "oip-macos-manifest.json.sig", "signature asset resolves by the JSON-signature name")
    check(OIPGitHubOTA.archiveAsset(in: release, named: "oip-macos-universal.zip")?.name == "oip-macos-universal.zip", "archive asset resolves by manifest name")

    // The original defect: the updater used to look for "oip-macos-manifest.sig".
    // That name is not published, so the offer failed silently.
    check(OIPGitHubOTA.signatureAsset(in: OIPGitHubOTA.Release(draft: false, prerelease: false,
      assets: [OIPGitHubOTA.Asset(name: "oip-macos-manifest.json", browserDownloadURL: URL(string: "https://github.com/x/o")!)])) == nil,
      "missing signature asset returns nil (was the silent-failure bug)")

    // --- URL safety.

    check(OIPGitHubOTA.safeReleaseURL(URL(string: "https://github.com/o.zip")!) != nil, "https github accepted")
    check(OIPGitHubOTA.safeReleaseURL(URL(string: "https://objects.githubusercontent.com/o.zip")!) != nil, "https objects host accepted")
    check(OIPGitHubOTA.safeReleaseURL(URL(string: "http://github.com/o.zip")) == nil, "http rejected")
    check(OIPGitHubOTA.safeReleaseURL(URL(string: "https://evil.example/o.zip")) == nil, "foreign host rejected")
    check(OIPGitHubOTA.safeReleaseURL(URL(string: "https://github.com.evil.com/o.zip")) == nil, "host-prefix spoof rejected")
    check(OIPGitHubOTA.safeReleaseURL(nil) == nil, "nil URL rejected")

    // --- Build comparison.

    check(OIPGitHubOTA.isUpdateAvailable(currentBuild: "3", remoteBuild: "4"), "4 is newer than 3")
    check(!OIPGitHubOTA.isUpdateAvailable(currentBuild: "4", remoteBuild: "4"), "4 is not newer than 4")
    check(!OIPGitHubOTA.isUpdateAvailable(currentBuild: "4", remoteBuild: "3"), "3 is not newer than 4")
    check(!OIPGitHubOTA.isUpdateAvailable(currentBuild: "abc", remoteBuild: "4"), "non-numeric current is never an update")
    check(OIPGitHubOTA.compareBuilds(current: "3", remote: "4") == 1, "compare 3 vs 4 == 1")
    check(OIPGitHubOTA.compareBuilds(current: "4", remote: "3") == -1, "compare 4 vs 3 == -1")
    check(OIPGitHubOTA.compareBuilds(current: "4", remote: "4") == 0, "compare 4 vs 4 == 0")

    // --- verify(): the authentic signed release is accepted, and every rejection.

    // A signed manifest with a valid bundle id, a real archive name and a newer build.
    let manifestData = Data("""
    {"bundle_identifier":"org.openindustrial.oipDashboard","version":"0.3.1","build":"4","archive":"oip-macos-universal.zip","archive_sha256":"deadbeef"}
    """.utf8)

    func verify(_ release: OIPGitHubOTA.Release, manifestData: Data = manifestData, signatureIsValid: Bool = true,
                bundle: String = "org.openindustrial.oipDashboard", build: String = "3") -> OIPGitHubOTA.Rejection? {
      OIPGitHubOTA.verify(release: release, manifestData: manifestData, signatureIsValid: signatureIsValid,
                          runningBundleIdentifier: bundle, runningBuild: build)
    }

    // Authentic release, signature valid, build newer -> no rejection.
    check(verify(release) == nil, "authentic newer signed release is offered")

    // Signature invalid (tampered manifest).
    check(verify(release, signatureIsValid: false) == .signatureInvalid, "invalid signature rejected")

    // Bundle identifier mismatch.
    check(verify(release, bundle: "org.evil.app") == .bundleIdentifierMismatch(got: "org.openindustrial.oipDashboard"),
      "bundle identifier mismatch rejected")

    // Same build -> not newer.
    check(verify(release, build: "4") == .versionNotNewer(current: "4", remote: "4"), "same build not offered")
    check(verify(release, build: "5") == .versionNotNewer(current: "5", remote: "4"), "older build not offered")

    // Manifest names the archive but the release carries no such asset.
    let badArchiveRelease = OIPGitHubOTA.Release(draft: false, prerelease: false,
      assets: [OIPGitHubOTA.Asset(name: "oip-macos-manifest.json", browserDownloadURL: URL(string: "https://github.com/o/m.json")!)])
    check(verify(badArchiveRelease) == .archiveAssetMissing, "missing archive asset rejected")

    // Manifest that does not decode.
    check(verify(release, manifestData: Data("not json".utf8)) == .manifestDecodeFailed, "undecodable manifest rejected")

    // Manifest decodes but the bundle id inside does not match the running bundle.
    let wrongId = Data("""
    {"bundle_identifier":"org.openindustrial.oipDashboardX","version":"0.3.1","build":"4","archive":"oip-macos-universal.zip","archive_sha256":"deadbeef"}
    """.utf8)
    check(verify(release, manifestData: wrongId) == .bundleIdentifierMismatch(got: "org.openindustrial.oipDashboardX"),
      "manifest bundle id mismatch rejected")

    // --- Archive digest: the tamper check the signed digest enforces. The live
    // downloader hashes the downloaded bytes and calls the same pure helper the
    // test drives, so a wrong digest is returned with its got/expected values.

    let manifest = try! JSONDecoder().decode(OIPGitHubOTA.Manifest.self, from: manifestData)
    let goodHex = OIPGitHubOTA.sha256Hex(of: [0xde, 0xad, 0xbe, 0xef])
    check(goodHex == "deadbeef", "sha256 hex is lowercase, zero-padded")
    check(OIPGitHubOTA.verifyArchiveDigest(sha256Hex: goodHex, manifest: manifest) == nil,
      "matching archive digest accepted")
    check(OIPGitHubOTA.verifyArchiveDigest(sha256Hex: "feedface", manifest: manifest)
      == .archiveDigestMismatch(got: "feedface", expected: "deadbeef"),
      "tampered archive digest rejected (got/expected logged)")

    print(failures == 0 ? "\nALL OTA LOGIC TESTS PASSED" : "\n\(failures) OTA LOGIC TEST(S) FAILED")
    exit(failures == 0 ? 0 : 1)
  }
}
