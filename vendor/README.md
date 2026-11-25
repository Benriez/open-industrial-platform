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

The server uses Postcard only to encode and decode owned opaque NodeIds.
The manifest selects `use-std` without Postcard's default embedded heapless
feature, removing the unused unmaintained `atomic-polyfill` dependency.

## async-opcua-client and async-opcua-crypto 0.19.0

Source: crates.io packages from [FreeOpcUa/async-opcua at 9ad28fc](https://github.com/FreeOpcUa/async-opcua/tree/9ad28fc011002398f2e8a95696a50408a14531d9), license MPL-2.0.

The OIP patch backports the RSA 0.10 API changes from upstream
[d6a336d](https://github.com/FreeOpcUa/async-opcua/commit/d6a336d)
to close RUSTSEC-2023-0071. It retains the 0.19 transport, security policies
and OPC UA certificate extensions. Private RSA operations and certificate signing
use randomized blinding. X.509 certificate and key loading still accept the
existing PEM and DER formats.

## Chrono compatibility adapter

The local `chrono` package only forwards the API and the features used in the
lockfile to [sad-chrono 0.5.2](https://crates.io/crates/sad-chrono).
The maintained implementation replaces the original registry package throughout
the lockfile, including the OPC UA stack, RMCP and Schemars (RUSTSEC-2026-0543).
The adapter keeps their date/time types identical and adds no serialization or
date/time logic of its own.
