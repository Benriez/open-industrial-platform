# OIP-008 — Identity und Authorization

## Vertrauenswürdige Bindung

Principal, Role und Scope sind separate persistierte Typen. Ein Principal kann mehrere RoleBindings besitzen. ReadRoles enthalten explizite vorhandene Read-Permissions; SimulationControl ist verboten. AccessScope: Platform, Organization, Infrastructure, Site oder Source. **Deny by default.** Keine automatisch vergebenen Platform-Grants.

Der OIP-007-IPC-Handshake bleibt bestehen: OS-Peer-UID plus privates 32-Byte-Credential. Die geschützte Daemon-Konfiguration bindet ein Credential an `{ "principal": "reader-org-a" }`. Legacy actor/permissions/sources dürfen nicht zusätzlich gesetzt werden. Nur vorhandene, aktivierte Principals sind zulässig. Eine zweite Bridge mit demselben Credential erhält dieselbe Identität und dieselben Scopes; Connection-IDs vergeben keine Rechte.

Loopback-REST verwendet dieselben Credentials als `Authorization: Bearer <64 hex characters>`. Header werden begrenzt und ASCII-validiert, bevor Bytes dekodiert werden; unbekannte Tokens scheitern geschlossen. Header, Tokens und vollständige MCP-Payloads werden nicht geloggt. Keine Identität in URL/Query, keine Rollen aus Toolparametern. Ohne Credential sind Multi-Infrastructure-Reads verboten. `ExecutionContext` ist ein vertrauenswürdiger In-Process-Vertrag für Composition/Transportadapter, keine vom Client serialisierte Authentisierungsbehauptung.

Die lokale Credential-/UID-Grenze isoliert **keine feindlichen Prozesse desselben OS-Users**. Dieser User kann lokale Credentials lesen und den Prozess kontrollieren. Das ist keine produktive Mandanten-Authentisierung. macOS wurde tatsächlich getestet; keine neue Windows-IPC-Unterstützung wird behauptet.

## Zentrale Auswertung

`HierarchyRegistry::permits` löst den Ziel-Scope auf und vereinigt erst danach Permissions passender Bindings. DevicesRead auf Source A plus TelemetryRead auf Source B ergeben ausdrücklich **kein** DeviceRead auf A oder B. Parent-IDs aus einem Request müssen existieren, autorisiert und untereinander konsistent sein. Sie sind Filter und keine Grants.

Ein Reader darf notwendige eigene Ancestor-Labels entdecken; daraus entsteht kein Zugriff auf Geschwister. Beispiel: Source-Reader darf seinen Organization-/Infrastructure-/Site-Pfad sehen, aber keine anderen Sources dieser Organization. Listen/Pagination beziehen sich ausschließlich auf sichtbare Objekte. Ein Infrastructure-Reader sieht keine andere Infrastructure derselben Organization.

CoreHealth, Liveness, Readiness, Queue, SystemStatus und der bisherige globale Snapshot erfordern Platform-Scope. Der neue ScopedSnapshot enthält nur erlaubte Sources, Devices, Observations, Events und ihre Locations. Globale Counts, Run-/Revision-IDs und globale Diagnose-Fixtures fehlen. Permission-Sets für den Snapshot müssen für dieselbe Source gelten.

## Fehler und Audit

Nicht berechtigte und nicht existierende einzelne Zielressourcen liefern denselben generischen `ResourceNotFound / RESOURCE_NOT_ACCESSIBLE` (HTTP404), ohne Namen. Fehlende Identität bzw. Capability-Grants liefern generisches PermissionDenied (HTTP403). Ungültige Queries sind InvalidInput. MCP verwendet dieselben Capability-Kategorien, bei syntaktisch ungültigen Parametern SDK InvalidParams. Keine Exactly-once- oder Replay-Garantie.

ExecutionAudit enthält Principal, Actor, Capability, autorisierten Scope/Hierarchiepfad, Target, Entscheidung, Outcome, Correlation-ID und Zeitpunkt. Fremde Request-IDs gelangen nicht in Target-Felder. Implizite Node-Source wird aus dem tatsächlich erlaubten Source-Set aufgelöst. Cancellation wird auch ohne Completion aufgezeichnet.

Grenzen: das lokale Execution-Audit ist weder dauerhaft noch manipulationssicher. Bei InvalidInput kann die Ausführung als `denied_or_failed` mit nicht bestätigter Autorisierung klassifiziert werden; bei Cancellation vor Completion bleibt der Ziel-Scope unbestätigt. Das ist keine Compliance-Audit-Garantie. Offline-Provisioning besitzt zusätzlich ein transaktionales, aber ebenfalls nicht manipulationssicheres SQLite-Provisioning-Journal mit Plan-Digest.

## Legacy-Modus

Nur `--legacy-single-infrastructure`, ein entsprechendes explizites Config-Flag oder `--demo` erlaubt den bisherigen lokalen GUI-/Operator-Zugang ohne Bearer. Eine provisionierte Multi-Infrastructure-DB kann dadurch nicht global freigeschaltet werden. `AppState::new` ist geschlossen; eingebettete Alt-Fixtures verwenden ausdrücklich `AppState::legacy`. Hierarchie-Filter ohne gebundenen Principal werden auch im Legacy-Modus verweigert. Legacy-IPC-Policies sind nur dort zulässig; Mischkonfigurationen mit Principal-Policies werden abgewiesen.
