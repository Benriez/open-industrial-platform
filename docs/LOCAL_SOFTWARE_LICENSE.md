# Local software license

The Core verifies the License Center v1 artifact offline. Configure two absolute file paths in the protected startup environment of the Core.

- `OIP_LICENSE_POLICY_PATH` points to the product-owned JSON policy. Use issuer `code-server.de`, product `oip`, the independently distributed Ed25519 public keys indexed by `kid`, and the agreed license kinds and rights. Protect this file and its parent directories from changes by customers and other untrusted users. Public keys are established independently of the license.
- `OIP_LICENSE_FILE_PATH` points to the signed license imported by the local operator. Copy the issued artifact there unchanged. Replace it atomically on renewal. The Core reads the current files for each authorized status request.

Authorized platform readers see license facts in Settings → Runtime via `GET /api/v2/management?section=system`. The same management report is available through the `oip_mcp_management_read` tool with section `system`.

A verified result distinguishes usage from support. The public status includes neither the licensee nor paths or trust material. Licensing is observational. Existing rules govern OPC UA, device commands, writes, roles and operating modes.

The dependency at `vendor/code-server-license-verifier` mirrors the License Center repository's `verifier` library v0.1.0. Synchronize `Cargo.toml`, `src/lib.rs` and `src/local.rs` together when updating the protocol. The product build needs no checkout of the issuer application.
