# OIP_DEVICES_SERVICES_2027_CORE_REQUIREMENTS.md

The contract of the **authorized service inventory** of the Core.

**Status: the capability does not exist yet.** The surfaces of the client name the absence
honestly: the Devices workspace shows `Kein autorisiertes Service-Inventar verfügbar.`, the
comparison names `Unbekannt · Service Registry fehlt`, and the Network workspace states that the
Core delivers **no** VPN telemetry (`NICHT GELIEFERT`, not a connection state that the Core never
measured). This document is the contract that the next step must satisfy — it is **not** a claim
that the Core delivers it.

## The problem

The inventory of the Core is a registry of **devices**. It knows the manufacturer, the model, the
firmware, the serial number and the address of a device — and nothing about the **services** that
a device offers. The surface therefore cannot answer the question an operator asks first about a
device: *what does this thing actually run?* The answer is not in the data, and the surfaces say so
instead of deriving it from a name or from a kind.

## The rules of the contract

1. **Declared, never measured.** The Core measures no service: it runs no probe and holds no
   credential for one (`crates/oip-core/src/inventory.rs` states the rule of the inventory). The
   registry is therefore **operator-declared**, and every record carries the provenance
   `origin: declared`. A service that the Core never probed never carries a state of its own.
2. **The plan is the source of truth.** The declaration lives in the **plan** of the instance —
   offline, authorized, versioned and auditable, like the hierarchy and the inventory. The plan is
   the only place where the operator states what the infrastructure offers.
3. **Scoped like the inventory.** The read is scoped by the same rules as the inventory read: a
   reader of one organization sees no service of another, and a foreign identifier is refused
   **identically** to an identifier that does not exist (`404 RESOURCE_NOT_ACCESSIBLE` — the answer
   discloses neither).
4. **Read-only.** The capability is a **read**. The registry has no write path: a change of the
   plan is the operator's offline action, and the durable audit that a remote write would need does
   not exist yet (`docs/architecture/oip-capability-inventory.md` names that as a prerequisite).
5. **The pagination and the freshness are stated.** The read is paginated like the inventory, and
   every record names the revision of the plan it was declared in.

## What the Core must deliver

| Part | The contract |
|---|---|
| The model | `ServiceDeclaration {id, name, site_id, device_id, kind, endpoint, port, state}` and `ServicePage` — the declaration of the plan, the registry of the hierarchy, the page of the read |
| The plan | a `services` section of `ProvisioningPlan` (`crates/oip-core/src/hierarchy.rs`), defaulting to empty so that every existing plan stays valid; the validation binds every service to an existing site and to a device of that site |
| The storage | a table of the services in the store of the instance, written by the provisioning and read by the instance (`crates/oip-storage`), with its own migration |
| The capability | `CapabilityId::ServiceRegistryRead` with the request and the output of the read; the permission is the one of the inventory read (`devices_read`), so that the readers of the inventory read the services of the same scope |
| The route | `GET /api/v2/services` — scoped, paginated, and refusing a foreign identifier identically to an unknown one |
| The tool | `oip_services_read` over MCP and the local IPC, with the same scope and the same answer as the route |
| The projection | the client receives the services of the authorized scope with their provenance and their revision — never a service of another organization |

## What the client must show

* The **Services** workspace of the Devices shows the list of the authorized scope — the services
  with their kind, their endpoint, their state as **declared** and the device they belong to.
* The **comparison** of two devices names the services of each device instead of
  `Unbekannt · Service Registry fehlt`.
* The **device detail** names the services of the device instead of
  `Unbekannt · kein autorisiertes Service-Inventar`.
* A device without a service is named as such. Nothing is derived from a name, from a kind or from
  the address of a device.

## The evidence of the step

* A rehearsal of its own (`tests/oip_service_registry.py`), registered in
  `tools/oip_refresh_evidence.py`, that proves the scope, the refusal of a foreign identifier, the
  pagination and the refusal of a plan that drops a service.
* The capability mapping of the Core with the new capability and the new tool.
* The widget tests of the three places above, and the browser journey of the Services workspace.

## What stays closed until the capability exists

The surfaces keep naming the absence. They never show a service that the Core did not deliver, and
they never derive one from the name, the kind or the address of a device.
