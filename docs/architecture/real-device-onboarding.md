# Real device connection and monitoring

Baseline: `49a86bb0aa9f737fe9392eb2b5421e1ffe2f8c68`. Core branch `feature/real-device-connection-core`; Flutter branch `feature/real-device-connection-ui`. One integration authority; canonical main and the independent OIP-009/UI workstreams are not changed. This is local development, not a production identity or OT certification.

## Registration is separate from connection

Inventory-only registration creates a persistent Device/Site placement. It does not contact a host, install an agent, create observations, or imply connectivity/health. The offline `tests/oip0085/onboard.py` now explicitly reports this distinction. Existing inventory UUIDs and metadata are retained when a connection is confirmed; an expected inventory revision prevents overwriting concurrent changes.

For a new connection the operator selects an authorized Organization/Infrastructure/Site, enters one explicit SSH endpoint and a server-authorized identity profile, tests it, verifies its host key and confirms the actual observed host identity. A new device is persisted only at confirmation. An existing device uses its exact ID and revision; names never establish identity. Failed/cancelled proposals leave inventory unchanged. An unconfirmed failed endpoint is not proof that the inventory device itself is unreachable.

## Central contracts

| Capability | Permission | Scope | REST v2 | MCP |
|---|---|---|---|---|
| DeviceConnectionRead | DevicesRead + TelemetryRead | authorized Site/Source; plan also owned by Principal | GET `/device-connections?device_id=…` or `?plan_id=…`; no selectors returns only own permitted profiles | `oip_device_connection_read` |
| DeviceConnectionConfigure | InventoryManage + DevicesRead + TelemetryRead | target Site; bound Source for monitoring control | POST `/device-connections` | blocked |
| InventoryChange, register/update | InventoryManage | centrally validated old/new placement | POST `/inventory/apply` | blocked |

The existing CapabilityService is authoritative. There are 32 capability contracts, 28 reads and four mutations; a fully permitted Principal can discover up to 21 registered MCP read tools. Discovery remains policy-filtered. No mutating MCP tool is registered. REST handlers cannot accept Principal, grants, private-key paths, facts or fabricated verification evidence.

`ConnectionAction` is a closed tagged enum: `start`, `trust_host_key`, `verify`, `confirm`, `monitoring`, `cancel`. `start.target` is either an existing DeviceId/expected_revision or a typed new DeviceDraft. Host, port, non-root user and profile are validated. The other actions reference an opaque Principal-owned expiring plan. `confirm` requires `identity_confirmed=true`, `enable_monitoring`, and a 10–3600 second interval. Enabling a persisted collector also requires the originally verifying Principal and a currently valid authorized SSH profile; another scoped inventory manager may disable it but cannot reuse a foreign credential grant to enable it. A committed plan cannot be cancelled; confirmation retries return the committed binding. Conflicting revisions fail rather than overwrite.

Stages are real execution states: connecting, awaiting_host_key, ready_for_authentication, authenticating, reading_device_information, verification_complete, committing, committed, failed, cancelled. Responses expose facts, fingerprint, error code, timestamps and expiry, never private SSH keys or agent paths.

## Browser session boundary

Start the daemon with its existing protected IPC profile, then explicitly issue a one-use browser code:

```sh
oip-server --browser-login --ipc-socket /absolute/private/socket --ipc-credential /absolute/private/operator.credential
```

The command authenticates through the existing Unix peer-UID/credential boundary. It does not open SQLite or create grants. Only the selected server-bound Principal is associated with the code. The operator enters that code into Flutter; no durable IPC credential is transmitted to JavaScript.

- Code: 256-bit random, 120 seconds, single use; at most32 pending grants.
- Session: 256-bit random, server-side hashed index, 30-minute absolute expiry; at most64 sessions. Invalid-code admission is bounded. Rejected codes never block a valid one-time grant, and a full session table does not consume an issued grant.
- POST `/api/v2/browser/login` requires exact same Origin and creates a host-only HttpOnly SameSite=Strict cookie. GET `/api/v2/browser/session` returns only that session's bound Principal and an ephemeral CSRF value, with `Cache-Control: no-store`.
- Cookie-authorized writes and DELETE `/api/v2/browser/session` require exact Origin and `x-oip-csrf`. Cookie value and CSRF state are never put in URLs, web assets or LocalStorage. The CSRF value exists only in Flutter memory.
- Existing Host/Origin loopback restrictions remain. No public listener, CORS grant or anonymous tenant fallback is introduced. SSE checks session validity again for every projection, including after logout/expiry. API responses are no-store; framing is denied with X-Frame-Options and CSP frame-ancestors, and referrers are suppressed.
- Restart invalidates browser sessions; device/collector configuration persists. The old explicitly enabled demo contract remains available only in isolated demo mode.

HTTP loopback cookies are not a production browser-identity solution: cookies are host-scoped, not port-isolated. Hostile same-user processes/local services, browser extensions, OS compromise, remote identity and HTTPS remain separate security work. No claim of isolation against hostile same-UID processes is made. Real authenticated Flutter web is supported here; native authenticated session-cookie transport is not claimed. The pre-existing native explicit-demo regression remains supported.

## SSH security and observations

System OpenSSH is used through Tokio child processes, with the installed CLI checked directly. No extra Rust crate or dependency-version upgrade is introduced. Core domain types have no OpenSSH/HTTP/MCP dependency. Modern public-key authentication uses only administrator-configured local key/agent references. Endpoint host/port and allowed Principals are allowlisted per profile. Optional aliases are explicit server-side host/user/port tuples; arbitrary local SSH config, ProxyCommand and Match exec directives are never evaluated.

`ssh-keyscan` obtains candidate public keys; it does not authenticate them. Existing trusted bindings must match. Unknown keys require an explicit exact-fingerprint acceptance through an independent trusted channel before authentication. Changed keys are blocked. Verification and every monitoring connection use a private temporary pinned known_hosts file with StrictHostKeyChecking=yes. RSA keys require at least2048 bits. The server reads the size of every offered host key itself and rejects a key below the accepted minimum before it is shown for acceptance or pinned; the attempt fails with `SSH_HOST_KEY_TOO_WEAK` and no binding is created. A changed key (`SSH_HOST_KEY_CHANGED`) and an unknown key that is not the pinned one (`SSH_HOST_KEY_UNKNOWN`) are separate outcomes and are reported separately. A fixed `/usr/bin/id -u` guard rejects UID 0 or an unverifiable UID before authentication verification and before every fact query; a non-root-looking username is insufficient. No passwords, root login, agent forwarding, port forwarding, remote install, user-provided command, privileged command or scan is available.

The fixed Linux/macOS script reads hostname, OS, architecture, CPU/model, memory, uptime, local disk usage and interface-reported addresses. `df -Pkl` excludes network mounts. Filesystem URI userinfo is redacted defensively. Output is bounded; absent values remain None/omitted. The collected report text has its own budget, so a verified report always fits into the stored connection record. A report beyond that budget is refused with the explicit fault `SSH_OUTPUT_LIMIT`, and a record that would exceed the stored bound is refused with `SSH_REPORT_TOO_LARGE` before any write; no partial binding is ever created. GPU, temperature and CPU utilization are explicitly unavailable. Linux memory-used derives from MemTotal–MemAvailable; macOS derives from measured vm_stat page counts, not an independent pressure metric. The host report is evidence, not hardware attestation or proof of cause.

Core capture time is authoritative for SSH polling. The existing mandatory Observation source timestamp is collector-assigned capture time, not a claimed remote source clock; server timestamp is absent and receive time uses Core capture. Multi-command measurements are not an atomic remote snapshot. Clock/sensor uncertainty is stated in HostInformation provenance. Historical restored samples are stale until an actual new collection completes.

## Storage and writer ownership

Schema7 adds `device_connections`, latest-only `device_connection_attempts`, and `device_connection_audit`; migrations1–6 and their checksums remain unchanged. The stored connection record and the stored latest attempt are size bounded, and the server uses the same bound before it hands a verified report to the writer. Public pinned host keys and a non-secret profile reference are persisted, never a private key/passphrase. Existing inventory, settings, source placements, observations, events, gaps and health IDs are preserved.

Online inventory/configuration/control/attempt writes run through the existing bounded Core writer channel and owned SqliteStore. No second writer is opened by Flutter, REST or a bridge. The complete prospective hierarchy is validated before SQL, including the existing shared **32-source total limit** across OPC UA and SSH. Source definition, identity, placement, inventory CAS, connection record and audit commit atomically. Live registry watches are refreshed only from committed storage.

If an unexpected post-commit in-memory apply fails, the response is `APPLY_PENDING_RESTART` and persistence is marked unhealthy; no active collector is falsely asserted. The durable binding is recovered on controlled reopen. Online archive remains unavailable; history-preserving archival stays in the explicit offline operator path. Configuration-file preparation is also offline and takes the existing DB sidecar lock; it never writes SQLite.

## Collector lifecycle and limits

One runtime supervisor owns at most one collector per Device. All collectors and proposals share four SSH execution permits. At most64 plans, four active plans per Principal, ten-minute plan expiry, 32KiB connection request body, 128KiB subprocess stdout and16KiB stderr are admitted. Each subprocess has a ten-second deadline, kill-on-drop and explicit kill/wait on cancellation/error. Poll intervals are10–3600 seconds, with bounded exponential failure backoff up to3600 seconds. A configuration revision cancels and joins the previous collector before replacement. Supervisor Drop guards abort its children; TaskTracker drains them on controlled shutdown.

Client disconnect never owns the Core lifecycle. SSH failure is isolated to that Source. A failed collector task is reported once and requires explicit configuration reapply; it cannot spin-restart or stop unrelated sources. Freshness uses twice the configured polling interval plus15 seconds. A known stable host-ID change blocks new collection even if the SSH key remains the same. Host-key rotation is not silently accepted; a future reviewed rotation workflow is required.

Device registration, endpoint reachability, SSH verification, collector state, freshness and host health remain separate. Disabled/unverified devices are not shown online. SSH adapter service health is not host health; host health stays NotEvaluated. After confirmed binding, only actual network failure evidence supports Unreachable; authentication/configuration failures remain distinct.

The existing OPC-UA1000-node overflow regression exposed CloseSession cleanup exceeding two seconds. Queue admission now closes before protocol shutdown, retaining queued records; callbacks stop mapping after queue admission closes. A connected-session close has an eight-second cap; an already offline session retains its two-second cap, determined through the SDK connection-state watch. The outer Core shutdown deadline can cancel earlier and must then report an unclean shutdown. This is bounded cleanup, not an SLA or a claim that every buffered sample was persisted.

## Operator profile preparation

The Core must be stopped cleanly. The operator explicitly supplies a target and a private local identity reference:

```sh
python3 tools/configure_ssh_profile.py --config /absolute/private/core.json \
  --principal <existing-principal-id> --profile operator-ssh \
  --host <explicitly-confirmed-host> --port 22 \
  --identity-file /absolute/private/ssh-identity
# Inspect dry run, then repeat with --apply. No connection occurs here.
```

The helper does not overwrite a profile, creates a private configuration backup, checks configuration drift, uses the canonical SQLite sidecar lock and atomically replaces only the config. Core startup validates the profile again. No role/grant is created. For encrypted keys, an explicitly configured already-unlocked local agent profile can be used; passphrase entry/export through the browser is not supported.

Then start the existing daemon with that config and IPC profile, issue a browser login code, select the existing inventory device, and complete both host-key and identity confirmations in Flutter. Do not run offline inventory CLI writes alongside the daemon. Manual registration is available in Flutter as **Nur Inventar, keine Verbindung**.

## OIP-009 integration seam and remaining boundaries

`OnboardingScope` accepts Organization/Infrastructure/Site from the existing/future global context. The wizard validates only authorized descendants and locks placement for an existing device. No competing global switcher is introduced. `setInfrastructureContext` clears display caches, advances a context revision and closes stale inspectors/dialogs. The final OIP-009 payload must still be reconciled three ways; this work does not overwrite it.

SNMP, Windows/Android agents, VPN telemetry, broad discovery, remote client installation and productive OPC-UA endpoint onboarding are not added. The existing OPC-UA simulation adapter remains isolated for regression. Productive remote/browser identity, hostile same-UID isolation, durable tamper-proof audit and OT/endurance certification remain open, along with RUSTSEC-2023-0071, RUSTSEC-2023-0089 and RUSTSEC-2024-0449.

Automated SSH/Flutter acceptance uses an owned loopback SSH server and actual local host facts. It cannot substitute for the physical Raspberry-Pi acceptance. No private endpoint is contacted without explicit operator input, and no hardware SSH/monitoring verdict is inferred from an inventory entry or loopback fixture.

## Reviewed security references

The installed OpenSSH flags were checked against its local manuals and the [official OpenSSH configuration manual](https://man.openbsd.org/ssh_config). Browser writes combine explicit authorization, same-origin checks and a memory-held CSRF header; SameSite alone is not the boundary, consistent with [OWASP CSRF guidance](https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html). These references do not certify this local development implementation.
