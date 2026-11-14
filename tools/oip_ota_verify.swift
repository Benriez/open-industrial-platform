import CryptoKit
import Foundation

guard CommandLine.arguments.count == 4,
      let keyBytes = Data(base64Encoded: CommandLine.arguments[3]),
      let signatureText = try? String(contentsOfFile: CommandLine.arguments[2], encoding: .utf8),
      let signature = Data(base64Encoded: signatureText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
  fputs("usage: swift tools/oip_ota_verify.swift <manifest> <signature> <public-key-base64>\n", stderr)
  exit(2)
}
do {
  let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyBytes)
  let manifest = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
  guard key.isValidSignature(signature, for: manifest) else {
    fputs("OTA manifest signature is invalid\n", stderr)
    exit(1)
  }
} catch {
  fputs("OTA manifest verification failed: \(error)\n", stderr)
  exit(1)
}
