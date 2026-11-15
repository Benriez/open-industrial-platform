import Cocoa
import CryptoKit
import FlutterMacOS
import LocalAuthentication
import Security

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let touchId = FlutterMethodChannel(
      name: "org.openindustrial.oip/touch_id",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    touchId.setMethodCallHandler { call, result in
      TouchIdKeychain.handle(call: call, result: result)
    }

    super.awakeFromNib()

    placeOnVisibleScreen()

    // The direct build checks GitHub Releases after its window is ready. The
    // Store package leaves OIPUpdateEnabled false and uses App Store updates.
    DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
      if #available(macOS 10.15, *) {
        GitHubOTAUpdater.shared.checkForUpdate()
      }
    }
  }

  /// The window of the bundle has to be visible on a screen of the machine.
  ///
  /// The frame of the storyboard is a fixed rectangle of the screen the
  /// bundle was generated for. On a smaller display the window opens above
  /// the visible area and the operator sees nothing at all. When the frame
  /// touches no visible screen, the window is placed in the centre of the
  /// visible frame of the main screen and fitted into it.
  private func placeOnVisibleScreen() {
    let visibleFrames = NSScreen.screens.map { $0.visibleFrame }
    let visible = visibleFrames.contains(where: { $0.intersects(frame) })
    report("frames=\(visibleFrames) window=\(frame) visible=\(visible)")
    if visible {
      return
    }
    guard let screen = NSScreen.main ?? NSScreen.screens.first else {
      report("no screen of the machine")
      return
    }
    let visibleFrame = screen.visibleFrame
    var target = frame
    target.size.width = min(target.size.width, visibleFrame.width)
    target.size.height = min(target.size.height, visibleFrame.height)
    target.origin.x = visibleFrame.midX - target.width / 2
    target.origin.y = visibleFrame.midY - target.height / 2
    setFrame(target, display: true)
    report("placed=\(frame)")
  }

  /// One line of the placement of the window on the standard error of the
  /// bundle. The operator sees the window; the log says where it came.
  private func report(_ message: String) {
    FileHandle.standardError.write(("OIP-WINDOW " + message + "\n").data(using: .utf8)!)
  }
}

/// First-party GitHub Releases updater for the direct macOS distribution.
/// Release metadata is signed with an embedded Ed25519 public key; the archive
/// digest is covered by that signature, so GitHub's release API is only the
/// transport and cannot authorize altered code.
@available(macOS 10.15, *)
private final class GitHubOTAUpdater {
  static let shared = GitHubOTAUpdater()

  // All release/manifest/asset shapes come from the shared, unit-tested
  // `OIPGitHubOTA` module so the live updater and the decision logic can never
  // drift into two different types.
  private let session = URLSession(configuration: .ephemeral)
  private let repository = Bundle.main.object(forInfoDictionaryKey: "OIPGitHubRepository") as? String ?? ""
  private let publicKey = Bundle.main.object(forInfoDictionaryKey: "OIPUpdatePublicKey") as? String ?? ""
  private let runningBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""

  func checkForUpdate() {
    OIPGitHubOTA.log("check requested (build \(runningBuild))")
    guard Bundle.main.object(forInfoDictionaryKey: "OIPUpdateEnabled") as? Bool == true else {
      OIPGitHubOTA.log("skipped: OIPUpdateEnabled is not true")
      return
    }
    guard !repository.isEmpty else {
      OIPGitHubOTA.log("skipped: OIPGitHubRepository is empty")
      return
    }
    guard !publicKey.hasPrefix("__") else {
      OIPGitHubOTA.log("skipped: OIPUpdatePublicKey is a placeholder")
      return
    }
    guard ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] == nil else {
      OIPGitHubOTA.log("skipped: running in the App Store sandbox")
      return
    }
    guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest"),
          url.host == "api.github.com" else {
      OIPGitHubOTA.log("skipped: repository URL is invalid")
      return
    }

    let defaults = UserDefaults.standard
    let now = Date().timeIntervalSince1970
    guard now - defaults.double(forKey: "oip.github-ota.last-check") > 21_600 else {
      OIPGitHubOTA.log("skipped: last check \(Int(now)) within 6h")
      return
    }
    defaults.set(now, forKey: "oip.github-ota.last-check")

    var request = URLRequest(url: url)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("OpenIndustrialPlatform-macOS", forHTTPHeaderField: "User-Agent")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
    session.dataTask(with: request) { [weak self] data, response, error in
      guard let self else { return }
      let status = (response as? HTTPURLResponse)?.statusCode
      if let error {
        OIPGitHubOTA.log("release list request failed: \(error.localizedDescription)")
        return
      }
      guard status == 200, let data else {
        OIPGitHubOTA.log("release list request rejected: status \(status ?? -1)")
        return
      }
      guard let release = try? JSONDecoder().decode(OIPGitHubOTA.Release.self, from: data) else {
        OIPGitHubOTA.log("release list response did not decode as a GitHub release")
        return
      }
      if release.draft || release.prerelease {
        OIPGitHubOTA.log("release is draft or prerelease: \(release.draft) / \(release.prerelease)")
        return
      }
      self.verifyRelease(release)
    }.resume()
  }

  private func verifyRelease(_ release: OIPGitHubOTA.Release) {
    guard let manifestAsset = OIPGitHubOTA.manifestAsset(in: release),
          let signatureAsset = OIPGitHubOTA.signatureAsset(in: release) else {
      let names = release.assets.map(\.name).sorted()
      OIPGitHubOTA.log("manifest/signature asset missing; release assets: \(names)")
      return
    }
    getAsset(manifestAsset.browserDownloadURL) { [weak self] manifestData in
      guard let self, let manifestData else {
        OIPGitHubOTA.log("manifest download failed for \(OIPGitHubOTA.manifestAssetName)")
        return
      }
      let manifest = try? JSONDecoder().decode(OIPGitHubOTA.Manifest.self, from: manifestData)
      if manifest == nil {
        OIPGitHubOTA.log("manifest did not decode")
        return
      }
      if manifest?.bundleIdentifier != Bundle.main.bundleIdentifier {
        OIPGitHubOTA.log("bundle identifier mismatch: manifest \(manifest?.bundleIdentifier ?? "nil"), running \(Bundle.main.bundleIdentifier)")
        return
      }
      self.verifySignature(manifestData: manifestData, manifest: manifest!, release: release, signatureURL: signatureAsset.browserDownloadURL)
    }
  }

  private func verifySignature(manifestData: Data, manifest: OIPGitHubOTA.Manifest, release: OIPGitHubOTA.Release, signatureURL: URL) {
    getAsset(signatureURL) { [weak self] signatureData in
      guard let self, let signatureData else {
        OIPGitHubOTA.log("signature download failed for \(OIPGitHubOTA.signatureAssetName)")
        return
      }
      guard let signatureText = String(data: signatureData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            let signature = Data(base64Encoded: signatureText) else {
        OIPGitHubOTA.log("signature response is not valid base64 text")
        return
      }
      guard let rawKey = Data(base64Encoded: self.publicKey),
            let key = try? Curve25519.Signing.PublicKey(rawRepresentation: rawKey) else {
        OIPGitHubOTA.log("embedded update public key is missing or invalid")
        return
      }
      let valid = key.isValidSignature(signature, for: manifestData)
      OIPGitHubOTA.log("manifest signature \(valid ? "verified" : "invalid"); build \(manifest.build)")
      guard valid else { return }
      guard let archiveAsset = OIPGitHubOTA.archiveAsset(in: release, named: manifest.archive) else {
        OIPGitHubOTA.log("manifest archive \(manifest.archive) is not a release asset")
        return
      }
      guard OIPGitHubOTA.isUpdateAvailable(currentBuild: self.runningBuild, remoteBuild: manifest.build) else {
        let comparison = OIPGitHubOTA.compareBuilds(current: self.runningBuild, remote: manifest.build)
        OIPGitHubOTA.log("version not newer: running \(self.runningBuild) vs remote \(manifest.build) (compare \(comparison))")
        return
      }
      self.offer(manifest, archiveAsset: archiveAsset)
    }
  }

  private func getAsset(_ url: URL, completion: @escaping (Data?) -> Void) {
    guard let safe = OIPGitHubOTA.safeReleaseURL(url) else {
      OIPGitHubOTA.log("unsafe download URL rejected: \(url.absoluteString)")
      completion(nil)
      return
    }
    var request = URLRequest(url: safe)
    request.setValue("OpenIndustrialPlatform-macOS", forHTTPHeaderField: "User-Agent")
    session.dataTask(with: request) { data, response, error in
      let status = (response as? HTTPURLResponse)?.statusCode
      if error != nil || status != 200 {
        OIPGitHubOTA.log("asset download rejected: status \(status ?? -1)")
        completion(nil)
        return
      }
      completion(data)
    }.resume()
  }

  private func offer(_ manifest: OIPGitHubOTA.Manifest, archiveAsset: OIPGitHubOTA.Asset) {
    DispatchQueue.main.async {
      let alert = NSAlert()
      alert.messageText = "OIP-Update verfügbar"
      alert.informativeText = "Version \(manifest.version) ist verfügbar. Die signierte Aktualisierung wird heruntergeladen und nach dem Neustart installiert."
      alert.addButton(withTitle: "Jetzt aktualisieren")
      alert.addButton(withTitle: "Später")
      guard alert.runModal() == .alertFirstButtonReturn else { return }
      self.downloadAndInstall(manifest, archiveAsset: archiveAsset)
    }
  }

  private func downloadAndInstall(_ manifest: OIPGitHubOTA.Manifest, archiveAsset: OIPGitHubOTA.Asset) {
    guard let url = OIPGitHubOTA.safeReleaseURL(archiveAsset.browserDownloadURL) else {
      showFailure("Der Download-Link des signierten Updates ist ungültig.")
      return
    }
    let appURL = Bundle.main.bundleURL
    guard FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path) else {
      showFailure("Der App-Ordner ist nicht beschreibbar. Installiere OIP unter /Applications mit Schreibrechten.")
      return
    }
    var request = URLRequest(url: url)
    request.setValue("OpenIndustrialPlatform-macOS", forHTTPHeaderField: "User-Agent")
    session.downloadTask(with: request) { [weak self] temporaryURL, response, error in
      guard let self else { return }
      let status = (response as? HTTPURLResponse)?.statusCode
      if error != nil || status != 200 {
        OIPGitHubOTA.log("archive download rejected: status \(status ?? -1)")
        self.showFailure("Das Update ließ sich nicht vollständig prüfen und wurde verworfen.")
        return
      }
      guard let temporaryURL, let archiveData = try? Data(contentsOf: temporaryURL) else {
        OIPGitHubOTA.log("archive download could not be read from disk")
        self.showFailure("Das Update ließ sich nicht vollständig prüfen und wurde verworfen.")
        return
      }
      let actual = SHA256.hash(data: archiveData).map({ String(format: "%02x", $0) }).joined()
      guard actual == manifest.archiveSHA256 else {
        OIPGitHubOTA.log("archive digest mismatch: got \(actual) expected \(manifest.archiveSHA256)")
        self.showFailure("Das Update ließ sich nicht vollständig prüfen und wurde verworfen.")
        return
      }
      OIPGitHubOTA.log("archive verified (sha256 \(actual)); starting installer")
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OIP-OTA-\(UUID().uuidString)", isDirectory: true)
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let archive = directory.appendingPathComponent(manifest.archive)
        try FileManager.default.moveItem(at: temporaryURL, to: archive)
        self.launchInstaller(archive: archive, appURL: appURL, manifest: manifest)
      } catch {
        self.showFailure("Das geprüfte Update konnte nicht vorbereitet werden.")
      }
    }.resume()
  }

  private func launchInstaller(archive: URL, appURL: URL, manifest: OIPGitHubOTA.Manifest) {
    guard let helper = Bundle.main.url(forResource: "oip_ota_install_helper", withExtension: "sh") else {
      showFailure("Der Update-Installer fehlt im App-Bundle.")
      return
    }
    DispatchQueue.main.async {
      let process = Process()
      process.executableURL = URL(fileURLWithPath: "/bin/sh")
      process.arguments = [helper.path, String(ProcessInfo.processInfo.processIdentifier), archive.path,
                          appURL.path, manifest.archiveSHA256, manifest.bundleIdentifier, manifest.build]
      do {
        try process.run()
        NSApp.terminate(nil)
      } catch {
        self.showFailure("Der Update-Installer konnte nicht gestartet werden.")
      }
    }
  }

  private func showFailure(_ message: String) {
    DispatchQueue.main.async {
      let alert = NSAlert()
      alert.messageText = "OIP konnte nicht aktualisiert werden"
      alert.informativeText = message
      alert.addButton(withTitle: "OK")
      alert.runModal()
    }
  }
}

private enum TouchIdKeychain {
  private static let service = "org.openindustrial.oip.touch-id"
  private static let account = "operator-device-credential"

  static func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "available":
      let context = LAContext()
      var error: NSError?
      result(context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error))
    case "credentialExists":
      result(credentialExists())
    case "createCredential":
      createCredential(result: result)
    case "readCredential":
      readCredential(result: result)
    case "deleteCredential":
      let context = LAContext()
      var query = baseQuery
      query[kSecUseAuthenticationContext as String] = context
      let status = SecItemDelete(query as CFDictionary)
      result(status == errSecSuccess || status == errSecItemNotFound ? nil : keychainError(status))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static var baseQuery: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: service,
     kSecAttrAccount as String: account]
  }

  /// Check presence without revealing the Keychain value or prompting for
  /// biometrics. A protected item can report interaction-not-allowed here and
  /// still be usable by the explicit biometric read method.
  private static func credentialExists() -> Bool {
    var query = baseQuery
    query[kSecReturnAttributes as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    return status == errSecSuccess || status == errSecInteractionNotAllowed || status == errSecAuthFailed
  }

  private static func createCredential(result: @escaping FlutterResult) {
    let context = LAContext()
    var authError: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
      result(FlutterError(code: "TOUCH_ID_UNAVAILABLE", message: "Touch ID ist nicht verfügbar.", details: nil))
      return
    }
    context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Touch ID für OIP aktivieren") { success, error in
      DispatchQueue.main.async {
        guard success else {
          result(FlutterError(code: "TOUCH_ID_CANCELLED", message: error?.localizedDescription ?? "Touch ID wurde abgebrochen.", details: nil))
          return
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
          result(FlutterError(code: "CREDENTIAL_GENERATION_FAILED", message: "Schlüssel konnte nicht erzeugt werden.", details: nil))
          return
        }
        let secret = Data(bytes)
        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
          nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, &accessError
        ) else {
          result(FlutterError(code: "KEYCHAIN_POLICY_FAILED", message: "Touch-ID-Keychain konnte nicht vorbereitet werden.", details: nil))
          return
        }
        var oldItem = baseQuery
        oldItem[kSecUseAuthenticationContext as String] = context
        let oldStatus = SecItemDelete(oldItem as CFDictionary)
        guard oldStatus == errSecSuccess || oldStatus == errSecItemNotFound else {
          result(keychainError(oldStatus))
          return
        }
        var item = baseQuery
        item[kSecValueData as String] = secret
        item[kSecAttrAccessControl as String] = access
        item[kSecUseAuthenticationContext as String] = context
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
          result(keychainError(status))
          return
        }
        result(secret.map { String(format: "%02x", $0) }.joined())
      }
    }
  }

  private static func readCredential(result: @escaping FlutterResult) {
    let context = LAContext()
    var authError: NSError?
    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
      result(FlutterError(code: "TOUCH_ID_UNAVAILABLE", message: "Touch ID ist nicht verfügbar.", details: nil))
      return
    }
    context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Bei OIP anmelden") { success, error in
      DispatchQueue.main.async {
        guard success else {
          result(FlutterError(code: "TOUCH_ID_CANCELLED", message: error?.localizedDescription ?? "Touch ID wurde abgebrochen.", details: nil))
          return
        }
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let secret = item as? Data else {
          result(keychainError(status))
          return
        }
        result(secret.map { String(format: "%02x", $0) }.joined())
      }
    }
  }

  private static func keychainError(_ status: OSStatus) -> FlutterError {
    FlutterError(code: "KEYCHAIN_ERROR", message: "Touch-ID-Schlüssel ist nicht verfügbar (\(status)).", details: nil)
  }
}
