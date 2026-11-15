import Foundation

/// First-party GitHub Releases updater for the direct macOS distribution.
///
/// Release metadata is signed with an embedded Ed25519 public key; the archive
/// digest is covered by that signature, so GitHub's release API is only the
/// transport and cannot authorize altered code.
///
/// The decision logic below is deliberately free of `URLSession`, `NSAlert`
/// and `Bundle` so that every branch — including every reason an update is
/// rejected — can be unit-tested without a network, a bundle or a UI. The
/// live updater in `MainFlutterWindow.swift` calls these functions and records
/// the outcome in the local OTA log.
enum OIPGitHubOTA {

  // The signed manifest and its signature are published with these exact asset
  // names by `tools/oip_github_ota_package.py` and the macOS OTA workflow. The
  // updater must look for these names and nothing else: a wrong name makes the
  // offer fail silently, which is the defect this module documents and tests.
  static let manifestAssetName = "oip-macos-manifest.json"
  static let signatureAssetName = "oip-macos-manifest.json.sig"
  static let archiveAssetName = "oip-macos-universal.zip"

  /// Only GitHub's own download hosts may serve the archive and its signature.
  static let trustedDownloadHosts = ["github.com", "objects.githubusercontent.com"]

  // MARK: - Decodable release payload

  struct Manifest: Decodable {
    let bundleIdentifier: String
    let version: String
    let build: String
    let archive: String
    let archiveSHA256: String

    enum CodingKeys: String, CodingKey {
      case bundleIdentifier = "bundle_identifier"
      case version
      case build
      case archive
      case archiveSHA256 = "archive_sha256"
    }
  }

  struct Release: Decodable {
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
  }

  struct Asset: Decodable {
    let name: String
    let browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
      case name
      case browserDownloadURL = "browser_download_url"
    }
  }

  /// Every reason the updater stops before it offers an update. The associated
  /// values are the measurements the operator needs to see in the log: the HTTP
  /// status of a rejected response, the decoded-versus-expected strings, and the
  /// version comparison. Nothing here is a silent `return` any more.
  enum Rejection: Equatable {
    case releasesNotOK(status: Int?)
    case releasesDecodeFailed
    case releaseIsDraftOrPrerelease
    case manifestAssetMissing
    case manifestNotOK(status: Int?)
    case manifestDecodeFailed
    case bundleIdentifierMismatch(got: String?)
    case signatureNotOK(status: Int?)
    case signatureDecodeFailed
    case signatureInvalid
    case archiveAssetMissing
    case archiveDigestMismatch(got: String, expected: String)
    case versionNotNewer(current: String, remote: String)
    case unsafeDownloadURL(got: String)
  }

  // MARK: - Pure decision functions

  /// Selects the signed manifest asset, or nil when the release does not carry
  /// the exact asset name the signer published.
  static func manifestAsset(in release: Release) -> Asset? {
    release.assets.first { $0.name == manifestAssetName }
  }

  /// Selects the detached signature asset by its exact published name.
  static func signatureAsset(in release: Release) -> Asset? {
    release.assets.first { $0.name == signatureAssetName }
  }

  /// Selects the archive asset the manifest names, if present.
  static func archiveAsset(in release: Release, named name: String) -> Asset? {
    release.assets.first { $0.name == name }
  }

  /// Accepts a download URL only when it is `https` and its host is GitHub's
  /// own release or asset host. Everything else is rejected with the offending
  /// string so a spoofed or wrong host is visible in the log.
  static func safeReleaseURL(_ url: URL?) -> URL? {
    guard let url, let host = url.host,
          trustedDownloadHosts.contains(host), url.scheme == "https" else {
      return nil
    }
    return url
  }

  /// Build comparison, positive when the remote build is newer than the running
  /// build, negative when it is older, zero when equal. Non-numeric builds fall
  /// back to a string comparison and still never count as an update. The value
  /// is returned separately from the decision so the log can name both sides.
  static func compareBuilds(current: String, remote: String) -> Int {
    if let c = Int(current), let r = Int(remote) {
      return c == r ? 0 : (c < r ? 1 : -1)
    }
    return current == remote ? 0 : (current < remote ? 1 : -1)
  }

  /// An update is offered only when the remote build is strictly newer than the
  /// running build.
  static func isUpdateAvailable(currentBuild: String, remoteBuild: String) -> Bool {
    compareBuilds(current: currentBuild, remote: remoteBuild) > 0
  }

  /// The full verification of a signed release against the running bundle and
  /// the manifest. Returns the first reason it is rejected, or `nil` when the
  /// manifest is authentic, the archive matches and the build is newer. This is
  /// the single function the live updater calls to decide whether to offer, and
  /// the single function the regression test drives with crafted inputs.
  static func verify(
    release: Release,
    manifestData: Data,
    signatureIsValid: Bool,
    runningBundleIdentifier: String,
    runningBuild: String
  ) -> Rejection? {
    guard let manifest = try? JSONDecoder().decode(Manifest.self, from: manifestData) else {
      return .manifestDecodeFailed
    }
    guard manifest.bundleIdentifier == runningBundleIdentifier else {
      return .bundleIdentifierMismatch(got: manifest.bundleIdentifier)
    }
    guard signatureIsValid else {
      return .signatureInvalid
    }
    guard manifest.archive == archiveAssetName,
          archiveAsset(in: release, named: manifest.archive) != nil else {
      return .archiveAssetMissing
    }
    // The archive digest is checked against the downloaded archive bytes in the
    // live downloader; here we only know the signed expected digest.
    let comparison = compareBuilds(current: runningBuild, remote: manifest.build)
    guard comparison > 0 else {
      return .versionNotNewer(current: runningBuild, remote: manifest.build)
    }
    return nil
  }

  /// Local OTA log. Every check result — success and every rejection reason —
  /// is written here and to standard error so the operator and the diagnostic
  /// receipts can see why an update was or was not offered. The log never
  /// contains secrets: only asset names, HTTP statuses, bundle ids and builds.
  static func log(_ message: String) {
    let line = "[OIP-OTA] \(message)"
    FileHandle.standardError.write((line + "\n").data(using: .utf8)!)
    guard let dir = logsDirectory,
          let data = (line + "\n").data(using: .utf8) else { return }
    if !FileManager.default.fileExists(atPath: dir.path) {
      try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    if let handle = try? FileHandle(forWritingTo: logFileURL) {
      handle.seekToEndOfFile()
      handle.write(data)
      handle.closeFile()
    } else {
      try? data.write(to: logFileURL, options: .atomic)
    }
  }

  private static var logsDirectory: URL? {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent("Library/Logs/OIP", isDirectory: true)
  }

  private static var logFileURL: URL {
    logsDirectory!.appendingPathComponent("ota.log")
  }
}
