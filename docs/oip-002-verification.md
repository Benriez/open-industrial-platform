# OIP-002-Verifikation

Datum: 2026-11-04 (Baseline begonnen am 2026-11-03). Host der lokalen Ausführung: macOS, `aarch64-apple-darwin`, Rust 1.93.0. Alle Angaben beziehen sich auf tatsächlich ausgeführte lokale Befehle oder sind ausdrücklich NOT_TESTED.

## Baseline vor Implementierung

`cargo fmt --all -- --check`, `cargo check --workspace --all-targets`, Clippy in beiden Feature-Konfigurationen und alle OIP-001-Tests wurden zuerst ausgeführt. Ergebnis: 24 Workspace-Tests PASS; mit open62541 17 PASS und der damals bekannte Forward-Interop-Test ignoriert. Design-SHA-256: `bd9f9d8696ed48676055ee9a2cd0afb29e6c3d59e0945e662d925306f73c753e`.

## Ergebnisse

| Prüfung | Ergebnis | Ausgeführte Evidenz |
|---|---|---|
| Formatierung | PASS | `cargo fmt --all -- --check` |
| Default Check/Clippy | PASS | `cargo check --workspace --all-targets`; `cargo clippy --workspace --all-targets -- -D warnings` |
| open62541 Clippy | PASS | `cargo clippy -p oip-opcua --all-targets --features open62541-backend -- -D warnings` |
| Builds ohne Default-Backend | PASS | `cargo check -p oip-opcua --no-default-features --all-targets` und zusätzlich mit `open62541-backend` |
| Gesamte Default-Testsuite | PASS | `cargo test --workspace -- --test-threads=1`: 51 Tests, 0 FAIL |
| Mit open62541 | PASS | `cargo test -p oip-opcua --features open62541-backend -- --test-threads=1`: 36 Tests, 0 FAIL, 0 ignoriert |
| SignAndEncrypt Read/Subscribe | PASS | `Basic256Sha256`, tatsächliche sichere Loopback-Session; kein None-Endpunkt |
| Unbekanntes Serverzertifikat | PASS | Connect ohne expliziten Trust wird abgelehnt |
| Unbekanntes Clientzertifikat | PASS | Server ohne expliziten Client-Trust lehnt ab |
| Abgelaufenes Zertifikat | PASS | Zeitvalidierung vor Serverstart; `InvalidSecurityConfiguration` |
| Malformed Clientzertifikat | PASS | Parsefehler vor SecureChannel; kein Panic |
| Verbotene Downgrade-/fehlende PKI-Konfiguration | PASS | None oder Production ohne PKI wird vor Netzwerkzugriff abgelehnt |
| Zertifikatsrotation | PASS | alter Thumbprint schlägt fehl; neue Discovery + neuer Client + Read/Subscribe mit explizitem neuem Trust |
| Forward-Interop | PASS | open62541 → async-opcua Browse/Read/Subscription; früherer Test nicht mehr ignoriert |
| Reverse-Interop | PASS | async-opcua → open62541 Read/Subscription |
| Nonce-Root-Cause | PASS | Reproduktion: „Session cannot be activated with a nonce that is too short“; ≥32-Byte-Session-Nonce serverseitig korrigiert |
| Timestamp-Decoder Grenzwerte | PASS | `i64::MIN/MAX`, Null, Nachbarwerte, malformed Buffer; kein Panic |
| Timestamp Property-Tests | PASS | proptest über beliebige Wire-Ticks, Mapping und Domain-Encoder |
| Ungültige Source-/Server-Zeit | PASS | Originalwert erhalten; `InvalidTimestamp`, Bad/Unknown, kein Zeit-/Zero-Fallback |
| SQLite Migrationen | PASS | 9 Storage-Tests: Version, Idempotenz, Checksum, Versions-Desync |
| SQLite Restart/Wiederherstellung | PASS | Observations, Events, Gaps und Duplicate-Zähler nach erneutem Öffnen |
| SQLite Idempotenz/Rollback | PASS | erneute Ingestion erzeugt keine Rows; Fehler in Batch hinterlässt 0 Rows |
| Simulator-/Realdatentrennung | PASS | Origin-Class-Konflikt, source-spezifischer Latest-Read und getrennte identische Events |
| Beschädigte Eingaben | PASS | malformed DB/JSON und NaN werden abgelehnt; leere IDs abgelehnt, padded IDs kanonisiert |
| OIP-001-PoCs | PASS | beide PoCs erneut ausgeführt; Discovery/Browse/Read/Subscribe/Reconnect |
| Lizenz-/Quellen-/Bans-Prüfung | PASS | `cargo-deny check advisories licenses bans sources` |
| Advisory-Audit | PASS mit dokumentierten Ausnahmen | 3 initiale Befunde, unten vollständig aufgeführt |
| CI-Definition und lokale Kernschritte | PASS | `.github/workflows/ci.yml`; fmt/check/clippy/Tests/Feature-Gates/deny lokal ausgeführt |

## Nicht ausgeführte oder bewusst begrenzte Prüfungen

| Bereich | Status | Grund |
|---|---|---|
| Remote-GitHub-Actions-Lauf | NOT_TESTED | kein Commit/Push und keine Deployment-/CI-Auslösung |
| Linux x86_64/ARM64 und Windows x86_64 | NOT_TESTED lokal | Runner definiert, aber nicht ausgeführt |
| macOS ARM64 | PASS lokal | gesamte Default- und open62541-Suite auf dem Host |
| IPv6-Netzwerk-Roundtrip | NOT_TESTED | `::1`-Validierung getestet; Server bindet derzeit IPv4 127.0.0.1 |
| DNS-Hostnamen | PASS als Ablehnung | keine DNS-Auflösung; dadurch kein getesteter DNS-Rebinding-Angriffspfad |
| Secure open62541 ↔ async-opcua | NOT_TESTED | open62541-Feature nutzt im PoC weiterhin None; Production-Roundtrip nutzt async-opcua an beiden Enden |
| CA-Ketten, CRL/Revocation, Benutzerauthentifizierung | NOT_TESTED | self-signed Application-Certificates und Anonymous Token im lokalen Test |
| OPC-UA-Events | NOT_TESTED | weiterhin außerhalb des implementierten Umfangs |
| Reale Industrieanlagen / Schreibzugriffe | NOT_TESTED und nicht freigegeben | ausdrücklich verboten |

## Dependency-Audit und Restrisiken

Der erste ungefilterte Lauf meldete:

1. **RUSTSEC-2023-0071 / rsa 0.9.10:** Marvin-Timing-Seitenkanal, kein Fixed-Release. Dies ist ein produktives Blocker-Risiko, auch wenn die lokale Testsuite besteht.
2. **RUSTSEC-2023-0089 / atomic-polyfill:** unmaintained, transitiv über heapless/postcard/async-opcua.
3. **RUSTSEC-2024-0449 / unsafe-libyaml:** unmaintained, transitiv über serde_yaml/async-opcua.

`deny.toml` enthält diese drei IDs als begründete lokale Ausnahmen mit Review-by 2027-02-03. Das finale „advisories ok“ bedeutet daher **nicht**, dass keine bekannten Risiken existieren. Vor realer oder nicht-loopback Netzwerknutzung sind RSA-/Stackwahl und die unmaintained Abhängigkeiten erneut zu entscheiden.

Weitere Grenzen: Production bietet Anwendungs-Zertifikatsprüfung, aber noch keine Benutzerauthentifizierung oder Revocation. Der vendor-Patch muss bei Upgrades entfernt oder erneut validiert werden. Security-Logs können Zertifikatspfade/Thumbprints enthalten, nicht jedoch private Schlüssel.

## Reproduktion

```sh
cargo fmt --all -- --check
cargo check --workspace --all-targets
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace -- --test-threads=1
cargo clippy -p oip-opcua --all-targets --features open62541-backend -- -D warnings
cargo test -p oip-opcua --features open62541-backend -- --test-threads=1
cargo check -p oip-opcua --no-default-features --all-targets
cargo check -p oip-opcua --no-default-features --features open62541-backend --all-targets
cargo clippy -p oip-opcua --no-default-features --all-targets -- -D warnings
cargo clippy -p oip-opcua --no-default-features --features open62541-backend --all-targets -- -D warnings
cargo test -p oip-opcua --no-default-features --features open62541-backend -- --test-threads=1
cargo run -p oip-opcua --bin oip-async-opcua-poc
cargo run -p oip-opcua --bin oip-open62541-poc --features open62541-backend
# Lokale Installation wurde ausschließlich unter target/ abgelegt:
CARGO_HOME="$PWD/target/oip-002-cargo-home" \
  target/oip-002-tools/bin/cargo-deny check advisories licenses bans sources
```

Es wurden keine Commits oder Pushes erzeugt. Die HTML-Designreferenz wurde nicht verändert.
