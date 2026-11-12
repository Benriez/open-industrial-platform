//! The authorized service inventory: what the operator declares, never what the Core measured.
//!
//! The Core runs no probe for a service and holds no credential for one (`inventory.rs` states
//! the rule of the inventory). A service of the registry is therefore **declared** by the
//! operator in the plan of the instance, and every record of the registry carries that
//! provenance. The Core never derives a service from the name, the kind or the address of a
//! device, and a device without a declared service has no service — not an empty one that is
//! invented.
use crate::*;
use serde::{Deserialize, Serialize};

/// The state that the operator declares for a service.
///
/// The state is the **claim** of the operator, not a measurement of the Core: a service that the
/// Core never probed carries no state of its own.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum ServiceState {
    Running,
    Stopped,
}

/// The declaration of a service in the plan of the instance.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(deny_unknown_fields)]
pub struct ServiceDeclaration {
    pub id: ServiceId,
    pub name: String,
    /// The site that offers the service. The site is the scope of the record.
    pub site_id: SiteId,
    /// The device that offers the service, when the operator names one. The relation is
    /// resolved against the inventory of the Core when the registry is read: a device that the
    /// inventory does not hold leaves the relation **unknown**, and the service stays declared.
    #[serde(default)]
    pub device_id: Option<DeviceId>,
    /// The kind of the service (`opcua`, `ssh`, `https`, …). A free word of the operator: the
    /// Core does not have a vocabulary of service kinds and does not invent one.
    pub kind: String,
    /// The endpoint of the service, when the operator names one.
    #[serde(default)]
    pub endpoint: Option<String>,
    /// The port of the service, when the operator names one.
    #[serde(default)]
    pub port: Option<u16>,
    /// The declared state of the service.
    pub state: ServiceState,
}

/// The provenance of a record of the registry.
///
/// The only provenance today is `declared`: the Core measures no service.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum ServiceOrigin {
    Declared,
}

/// A service of the registry, with the scope it belongs to.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct ServiceRecord {
    pub service: ServiceDeclaration,
    pub organization_id: OrganizationId,
    pub infrastructure_id: InfrastructureId,
    /// The device of the inventory that offers the service, when the Core can resolve it.
    pub device_id: Option<DeviceId>,
    pub origin: ServiceOrigin,
}

/// The query of the registry.
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(default, deny_unknown_fields)]
pub struct ServiceQuery {
    pub organization: Option<OrganizationId>,
    pub infrastructure: Option<InfrastructureId>,
    pub site: Option<SiteId>,
    pub id: Option<ServiceId>,
    pub device: Option<DeviceId>,
    pub q: Option<String>,
    pub offset: Option<usize>,
    pub limit: Option<usize>,
}

/// A page of the registry.
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct ServicePage {
    pub items: Vec<ServiceRecord>,
    pub offset: usize,
    pub limit: usize,
    pub has_more: bool,
    pub status: String,
    pub management_channel: String,
}

/// The refusal of a query that the registry cannot answer.
pub fn service_invalid() -> CapabilityError {
    CapabilityError::new(
        CapabilityErrorCode::InvalidInput,
        "SERVICE_QUERY_INPUT",
        "Invalid bounded service request",
    )
}

/// The validation of a declaration of the plan.
///
/// A declaration that names a site that the plan does not hold is refused: the scope of a
/// record must exist before the record exists. The device of a declaration is **not** validated
/// here — the inventory of an instance is empty while it is provisioned, and a device that is
/// registered later is a legitimate relation.
pub fn validate_service_declaration(
    declaration: &ServiceDeclaration,
    sites: &[Site],
) -> Result<(), &'static str> {
    if declaration.name.trim().is_empty()
        || declaration.name.len() > 256
        || declaration.name.chars().any(char::is_control)
    {
        return Err("invalid display name");
    }
    if declaration.kind.trim().is_empty()
        || declaration.kind.len() > 128
        || declaration.kind.chars().any(char::is_control)
    {
        return Err("invalid service kind");
    }
    if let Some(endpoint) = &declaration.endpoint {
        if endpoint.trim().is_empty()
            || endpoint.len() > 256
            || endpoint.chars().any(char::is_control)
        {
            return Err("invalid service endpoint");
        }
    }
    if !sites.iter().any(|site| site.id == declaration.site_id) {
        return Err("service site missing");
    }
    Ok(())
}
