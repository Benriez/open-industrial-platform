import Foundation
import Security

let query: [String: Any] = [
  kSecClass as String: kSecClassGenericPassword,
  kSecAttrService as String: "org.openindustrial.oip.ota-release",
  kSecAttrAccount as String: "github-ed25519-signing-key",
  kSecReturnData as String: true,
  kSecMatchLimit as String: kSecMatchLimitOne,
]
var item: CFTypeRef?
guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let raw = item as? Data else {
  fputs("OTA signing key missing from login Keychain\n", stderr)
  exit(1)
}
print(raw.base64EncodedString())
