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
    OIPPiTunnelManager.shared.startIfEnabled()

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

/// Keeps the Pi Core forward under launchd so it remains independent of the
/// Flutter application's process lifetime and scheduling. SSH keepalives and
/// launchd's KeepAlive policy recover a dead transport without interrupting
/// healthy requests whenever an HTTP health probe is slow.
private final class OIPPiTunnelManager: NSObject {
  static let shared = OIPPiTunnelManager()

  private let host = Bundle.main.object(forInfoDictionaryKey: "OIPPiTunnelHost") as? String ?? "bodi-pi"
  private let localPort = Bundle.main.object(forInfoDictionaryKey: "OIPPiTunnelLocalPort") as? Int ?? 18858
  private let remotePort = Bundle.main.object(forInfoDictionaryKey: "OIPPiTunnelRemotePort") as? Int ?? 18808
  private let tunnelLabel = "com.oip.platform-tunnel"
  private let watchdogLabel = "com.oip.platform-tunnel-watchdog"
  private var agentsConfigured = false
  private var tunnelMonitor: DispatchSourceTimer?

  func startIfEnabled() {
    guard Bundle.main.object(forInfoDictionaryKey: "OIPPiTunnelEnabled") as? Bool == true else {
      return
    }
    guard removeObsoleteAgents() else { return }
    guard let tunnelPlist = writeTunnelAgent() else { return }

    var request = URLRequest(
      url: URL(string: "http://127.0.0.1:\(localPort)/api/v2/browser/session")!,
      timeoutInterval: 2.5
    )
    request.httpMethod = "GET"
    URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
      guard let self else { return }
      let status = (response as? HTTPURLResponse)?.statusCode
      DispatchQueue.main.async {
        if status == 200 || self.localPortIsListening() {
          self.log("reusing existing local OIP tunnel on :\(self.localPort) (HTTP \(status.map { String($0) } ?? "no response"))")
        } else {
          self.startManagedTunnel(tunnelPlist)
        }
        self.monitorTunnelIfNeeded(tunnelPlist)
      }
    }.resume()
  }

  private func removeObsoleteAgents() -> Bool {
    let domain = "gui/\(getuid())"
    let home = FileManager.default.homeDirectoryForCurrentUser
    let launchAgents = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    for label in [tunnelLabel, watchdogLabel] where launchAgentIsLoaded(domain: domain, label: label) {
      guard runLaunchctl(["bootout", "\(domain)/\(label)"]) else {
        log("could not unload existing OIP LaunchAgent \(label)")
        return false
      }
    }
    // Older releases used an HTTP watchdog that killed a healthy SSH process
    // after a slow API response. It is no longer part of tunnel recovery.
    try? FileManager.default.removeItem(at: launchAgents.appendingPathComponent("\(watchdogLabel).plist"))
    return true
  }

  private func writeTunnelAgent() -> URL? {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let launchAgents = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    let logs = home.appendingPathComponent("Library/Logs/OIP", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)
      try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
      let tunnelPlist = launchAgents.appendingPathComponent("\(tunnelLabel).plist")
      let tunnelLog = logs.appendingPathComponent("platform-tunnel.log").path
      let tunnelError = logs.appendingPathComponent("platform-tunnel.err").path
      try writePropertyList([
        "Label": tunnelLabel,
        "ProgramArguments": [
          "/usr/bin/ssh", "-N", "-n",
          "-o", "BatchMode=yes",
          "-o", "ConnectTimeout=8",
          "-o", "ExitOnForwardFailure=yes",
          "-o", "ServerAliveInterval=15",
          "-o", "ServerAliveCountMax=2",
          "-o", "IPQoS=none",
          "-o", "ControlMaster=no",
          "-o", "ControlPath=none",
          "-L", "127.0.0.1:\(localPort):127.0.0.1:\(remotePort)",
          host,
        ],
        "RunAtLoad": true,
        "KeepAlive": true,
        "ProcessType": "Interactive",
        "StandardOutPath": tunnelLog,
        "StandardErrorPath": tunnelError,
      ], to: tunnelPlist)
      return tunnelPlist
    } catch {
      log("could not configure managed Pi tunnel: \(error.localizedDescription)")
      return nil
    }
  }

  private func startManagedTunnel(_ tunnelPlist: URL) {
    guard !agentsConfigured else { return }
    let domain = "gui/\(getuid())"
    let tunnelStarted = runLaunchctl(["bootstrap", domain, tunnelPlist.path])
    agentsConfigured = tunnelStarted || launchAgentIsLoaded(domain: domain, label: tunnelLabel)
    log("started managed Pi tunnel (local :\(localPort), remote :\(remotePort)); launchd=\(agentsConfigured)")
  }

  private func monitorTunnelIfNeeded(_ tunnelPlist: URL) {
    guard tunnelMonitor == nil else { return }
    let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
    timer.schedule(deadline: .now() + 10, repeating: 10, leeway: .seconds(2))
    timer.setEventHandler { [weak self] in
      guard let self, !self.localPortIsListening() else { return }
      DispatchQueue.main.async { [weak self] in
        self?.startManagedTunnel(tunnelPlist)
      }
    }
    timer.resume()
    tunnelMonitor = timer
  }

  private func localPortIsListening() -> Bool {
    let probe = Process()
    probe.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
    probe.arguments = ["-z", "-G", "1", "127.0.0.1", String(localPort)]
    probe.standardOutput = FileHandle.nullDevice
    probe.standardError = FileHandle.nullDevice
    do {
      try probe.run()
      probe.waitUntilExit()
      return probe.terminationStatus == 0
    } catch {
      return false
    }
  }

  private func writePropertyList(_ value: [String: Any], to url: URL) throws {
    let data = try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
    try data.write(to: url, options: .atomic)
  }

  private func launchAgentIsLoaded(domain: String, label: String) -> Bool {
    runLaunchctl(["print", "\(domain)/\(label)"])
  }

  @discardableResult
  private func runLaunchctl(_ arguments: [String]) -> Bool {
    let command = Process()
    command.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    command.arguments = arguments
    command.standardOutput = FileHandle.nullDevice
    command.standardError = FileHandle.nullDevice
    do {
      try command.run()
      command.waitUntilExit()
      return command.terminationStatus == 0
    } catch {
      log("launchctl \(arguments.first ?? "command") failed: \(error.localizedDescription)")
      return false
    }
  }

  private func log(_ message: String) {
    let line = "OIP-TUNNEL \(message)\n"
    FileHandle.standardError.write(line.data(using: .utf8)!)
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
      let actual = OIPGitHubOTA.sha256Hex(of: Array(SHA256.hash(data: archiveData)))
      guard OIPGitHubOTA.verifyArchiveDigest(sha256Hex: actual, manifest: manifest) == nil else {
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
      let status = deleteCredentials(context: context)
      result(status == errSecSuccess ? nil : keychainError(status))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static var baseQuery: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: service,
     kSecAttrAccount as String: account]
  }

  private static func query(dataProtection: Bool) -> [String: Any] {
    var query = baseQuery
    if #available(macOS 10.15, *) {
      query[kSecUseDataProtectionKeychain as String] = dataProtection
    }
    return query
  }

  /// Check presence without revealing the Keychain value or prompting for
  /// biometrics. A protected item can report interaction-not-allowed here and
  /// still be usable by the explicit biometric read method.
  private static func credentialExists() -> Bool {
    credentialExists(dataProtection: true) || credentialExists(dataProtection: false)
  }

  private static func credentialExists(dataProtection: Bool) -> Bool {
    var query = query(dataProtection: dataProtection)
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
        let deleteStatus = deleteCredentials(context: context)
        guard deleteStatus == errSecSuccess else {
          result(keychainError(deleteStatus))
          return
        }

        // A Team-signed build with a provisioning profile uses the data
        // protection Keychain and enforces biometryCurrentSet on the item. The
        // direct Mac build is ad-hoc signed, so it has no application-identifier
        // or keychain-access-groups entitlement; macOS rejects that store with
        // errSecMissingEntitlement (-34018). For that build, keep the credential
        // in the traditional login Keychain behind an app-executable ACL. This
        // method has already authenticated with Touch ID, and every later read
        // does the same before retrieving the credential.
        var item = query(dataProtection: true)
        item[kSecValueData as String] = secret
        item[kSecAttrAccessControl as String] = access
        item[kSecUseAuthenticationContext as String] = context
        let protectedStatus = SecItemAdd(item as CFDictionary, nil)
        let status = protectedStatus == errSecMissingEntitlement || protectedStatus == errSecParam
            ? addFileKeychainCredential(secret)
            : protectedStatus
        guard status == errSecSuccess else {
          result(keychainError(status))
          return
        }
        result(secret.map { String(format: "%02x", $0) }.joined())
      }
    }
  }

  /// File-based Keychain fallback for the ad-hoc direct build. Only this
  /// installed executable is trusted by the item's ACL.
  private static func addFileKeychainCredential(_ secret: Data) -> OSStatus {
    guard let executablePath = Bundle.main.executableURL?.path else { return errSecParam }
    var trustedApplication: SecTrustedApplication?
    let trustedStatus = executablePath.withCString {
      SecTrustedApplicationCreateFromPath($0, &trustedApplication)
    }
    guard trustedStatus == errSecSuccess, let trustedApplication else {
      return trustedStatus
    }

    var access: SecAccess?
    let accessStatus = SecAccessCreate(
      "Open Industrial Platform Touch ID" as CFString,
      [trustedApplication] as CFArray,
      &access
    )
    guard accessStatus == errSecSuccess, let access else { return accessStatus }

    var item = query(dataProtection: false)
    item[kSecValueData as String] = secret
    item[kSecAttrAccess as String] = access
    return SecItemAdd(item as CFDictionary, nil)
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
        let protected = readItem(dataProtection: true, context: context)
        let fileBased: (data: Data?, status: OSStatus) = protected.data == nil
            ? readItem(dataProtection: false, context: context)
            : (data: nil, status: errSecItemNotFound)
        guard let secret = protected.data ?? fileBased.data else {
          result(keychainError(fileBased.data == nil ? fileBased.status : protected.status))
          return
        }
        result(secret.map { String(format: "%02x", $0) }.joined())
      }
    }
  }

  private static func readItem(dataProtection: Bool, context: LAContext) -> (data: Data?, status: OSStatus) {
    var query = query(dataProtection: dataProtection)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecUseAuthenticationContext as String] = context
    if !dataProtection {
      query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
    }
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    return (item as? Data, status)
  }

  private static func deleteCredentials(context: LAContext) -> OSStatus {
    let protectedStatus = deleteItem(dataProtection: true, context: context)
    let fileStatus = deleteItem(dataProtection: false, context: context)
    for status in [protectedStatus, fileStatus] {
      if status != errSecSuccess && status != errSecItemNotFound && status != errSecMissingEntitlement {
        return status
      }
    }
    return errSecSuccess
  }

  private static func deleteItem(dataProtection: Bool, context: LAContext) -> OSStatus {
    var query = query(dataProtection: dataProtection)
    query[kSecUseAuthenticationContext as String] = context
    return SecItemDelete(query as CFDictionary)
  }

  private static func keychainError(_ status: OSStatus) -> FlutterError {
    FlutterError(code: "KEYCHAIN_ERROR", message: "Touch-ID-Schlüssel ist nicht verfügbar (\(status)).", details: nil)
  }
}
