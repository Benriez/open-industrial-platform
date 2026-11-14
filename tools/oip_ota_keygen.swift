import CryptoKit
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
let status = SecItemCopyMatching(query as CFDictionary, &item)
let key: Curve25519.Signing.PrivateKey
if status == errSecSuccess, let data = item as? Data {
  do {
    key = try Curve25519.Signing.PrivateKey(rawRepresentation: data)
  } catch {
    fputs("stored OTA key is malformed\n", stderr)
    exit(1)
  }
} else if status == errSecItemNotFound {
  key = Curve25519.Signing.PrivateKey()
  var add = query
  add.removeValue(forKey: kSecReturnData as String)
  add.removeValue(forKey: kSecMatchLimit as String)
  add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
  add[kSecValueData as String] = key.rawRepresentation
  let addStatus = SecItemAdd(add as CFDictionary, nil)
  guard addStatus == errSecSuccess else {
    fputs("cannot store OTA key in login Keychain: \(addStatus)\n", stderr)
    exit(1)
  }
} else {
  fputs("cannot read OTA key from login Keychain: \(status)\n", stderr)
  exit(1)
}
print(key.publicKey.rawRepresentation.base64EncodedString())
