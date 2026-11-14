import Cocoa
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

private enum TouchIdKeychain {
  private static let service = "org.openindustrial.oip.touch-id"
  private static let account = "operator-device-credential"

  static func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "available":
      let context = LAContext()
      var error: NSError?
      result(context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error))
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
