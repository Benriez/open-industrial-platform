# Narrowly scoped upstream patches

## async-opcua-server 0.19.0

Source: crates.io package `async-opcua-server =0.19.0`, upstream
`FreeOpcUa/async-opcua`, license MPL-2.0.

OIP change: `src/session/manager.rs`, function `activate_session`, now creates
the ActivateSession server nonce with the configured session nonce length and
a minimum of 32 bytes for **every** security policy. Upstream 0.19.0 used
`SecurityPolicy::random_nonce()`, which returns an empty value for Policy None.
open62541 1.5.10 rejects that response with `BadSecurityChecksFailed` because
OPC UA session nonces must contain at least 32 bytes independently of the
SecureChannel nonce length.

This is not a security bypass: certificate validation, trust stores, security
policies and open62541's nonce-length check remain enabled. The patch is wired
with `[patch.crates-io]` in the workspace root and must be re-evaluated before
any async-opcua upgrade.
