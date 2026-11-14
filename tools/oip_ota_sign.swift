import CryptoKit
import Foundation
import Security

guard CommandLine.arguments.count == 2 else {
  fputs("usage: OIP_OTA_SIGNING_PRIVATE_KEY=<base64> swift tools/oip_ota_sign.swift <manifest>\n", stderr)
  exit(2)
}
let service = "org.openindustrial.oip.ota-release"
let account = "github-ed25519-signing-key"
let keyQuery: [String: Any] = [
  kSecClass as String: kSecClassGenericPassword,
  kSecAttrService as String: service,
  kSecAttrAccount as String: account,
  kSecReturnData as String: true,
  kSecMatchLimit as String: kSecMatchLimitOne,
]
var storedItem: CFTypeRef?
let keyStatus = SecItemCopyMatching(keyQuery as CFDictionary, &storedItem)
let rawKey: Data
if let encodedKey = ProcessInfo.processInfo.environment["OIP_OTA_SIGNING_PRIVATE_KEY"] {
  guard let decoded = Data(base64Encoded: encodedKey) else {
    fputs("OIP_OTA_SIGNING_PRIVATE_KEY is malformed\n", stderr)
    exit(2)
  }
  rawKey = decoded
} else if keyStatus == errSecSuccess, let data = storedItem as? Data {
  rawKey = data
} else {
  fputs("OTA signing key missing from environment and login Keychain\n", stderr)
  exit(2)
}
do {
  let key = try Curve25519.Signing.PrivateKey(rawRepresentation: rawKey)
  let manifest = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
  let signature = try key.signature(for: manifest)
  let output = URL(fileURLWithPath: CommandLine.arguments[1] + ".sig")
  try (signature.base64EncodedString() + "\n").write(to: output, atomically: true, encoding: .utf8)
} catch {
  fputs("unable to sign OTA manifest: \(error)\n", stderr)
  exit(1)
}
