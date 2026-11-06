//! Inventory identity and placement are independent of collectors. No network probes or credentials.
use crate::*;
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum DeviceType {
    Server,
    Desktop,
    Laptop,
    SingleBoardComputer,
    NetworkDevice,
    IndustrialDevice,
    Sensor,
    Other,
}
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(default, deny_unknown_fields)]
pub struct DeviceMetadata {
    pub manufacturer: Option<String>,
    pub model: Option<String>,
    pub operating_system: Option<String>,
    pub hostname: Option<String>,
    pub ip_address: Option<String>,
    pub mac_address: Option<String>,
    pub serial_number: Option<String>,
    pub description: Option<String>,
    pub tags: Vec<String>,
    pub physical_location: Option<String>,
    pub notes: Option<String>,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(deny_unknown_fields)]
pub struct DeviceRegistration {
    pub id: DeviceId,
    pub display_name: String,
    pub device_type: DeviceType,
    pub site_id: SiteId,
    #[serde(default)]
    pub metadata: DeviceMetadata,
}
impl DeviceRegistration {
    pub fn validate(&self) -> Result<(), CapabilityError> {
        self.validate_name(128, false)
    }
    pub fn validate_existing_source(&self) -> Result<(), CapabilityError> {
        self.validate_name(16384, true)
    }
    fn validate_name(&self, max: usize, legacy: bool) -> Result<(), CapabilityError> {
        let text = |s: &str, max: usize| s.len() <= max && !s.chars().any(char::is_control);
        let m = &self.metadata;
        if self.display_name.trim().is_empty()
            || self.display_name.len() > max
            || (!legacy && self.display_name.chars().any(char::is_control))
            || [
                &m.manufacturer,
                &m.model,
                &m.operating_system,
                &m.hostname,
                &m.serial_number,
                &m.physical_location,
            ]
            .into_iter()
            .flatten()
            .any(|s| !text(s, 256))
            || [&m.description, &m.notes]
                .into_iter()
                .flatten()
                .any(|s| !text(s, 1024))
            || m.tags.len() > 16
            || m.tags.iter().any(|s| s.trim().is_empty() || !text(s, 32))
            || m.tags.iter().collect::<BTreeSet<_>>().len() != m.tags.len()
            || m.ip_address
                .as_ref()
                .is_some_and(|s| s.parse::<std::net::IpAddr>().is_err())
            || m.mac_address.as_ref().is_some_and(|s| {
                s.len() != 17
                    || s.bytes().enumerate().any(|(i, b)| {
                        if i % 3 == 2 {
                            b != b':'
                        } else {
                            !b.is_ascii_hexdigit()
                        }
                    })
            })
        {
            return Err(inventory_invalid());
        }
        Ok(())
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum RegistrationStatus {
    Registered,
    Archived,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum InventoryOrigin {
    ManualOperator,
    ExistingSimulationSource,
    ExistingExternalSource,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct InventoryRecord {
    pub device: DeviceRegistration,
    pub registration: RegistrationStatus,
    pub origin: InventoryOrigin,
    pub created_ms: Option<i64>,
    pub updated_ms: Option<i64>,
    pub registered_by: Option<PrincipalId>,
    pub revision: u64,
}
#[derive(Clone, Copy, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum InventoryConnectivity {
    Unknown,
    ObservedReachable,
    ObservedUnreachable,
}
#[derive(Clone, Copy, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum MonitoringAvailability {
    NoCollector,
    CollectorConfigured,
    Receiving,
    Stale,
    Unknown,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum InventoryHealth {
    NotEvaluated,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct InventoryDevice {
    pub record: InventoryRecord,
    pub organization_id: OrganizationId,
    pub infrastructure_id: InfrastructureId,
    pub sources: Vec<DataSourceId>,
    pub connectivity: InventoryConnectivity,
    pub telemetry: MonitoringAvailability,
    pub health: InventoryHealth,
    pub monitoring_simulated: Option<bool>,
}
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(default, deny_unknown_fields)]
pub struct InventoryQuery {
    pub organization: Option<OrganizationId>,
    pub infrastructure: Option<InfrastructureId>,
    pub site: Option<SiteId>,
    #[serde(default, deserialize_with = "inventory_source")]
    pub source: Option<DataSourceId>,
    pub id: Option<DeviceId>,
    pub q: Option<String>,
    pub offset: Option<usize>,
    pub limit: Option<usize>,
    pub include_archived: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct InventoryPage {
    pub items: Vec<InventoryDevice>,
    pub offset: usize,
    pub limit: usize,
    pub has_more: bool,
    pub status: String,
    pub management_channel: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(tag = "operation", rename_all = "snake_case", deny_unknown_fields)]
pub enum InventoryChange {
    Register {
        device: DeviceRegistration,
    },
    Update {
        #[serde(deserialize_with = "replacement_device")]
        #[cfg_attr(feature = "schemas", schemars(with = "DeviceReplacement"))]
        device: DeviceRegistration,
        expected_revision: u64,
    },
    Archive {
        id: DeviceId,
        expected_revision: u64,
    },
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(deny_unknown_fields)]
pub struct InventoryPlanQuery {
    pub changes: Vec<InventoryChange>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(deny_unknown_fields)]
pub struct InventoryAdministration {
    pub principal: PrincipalId,
    pub changes: Vec<InventoryChange>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct InventoryAction {
    pub id: DeviceId,
    pub outcome: String,
    pub expected_revision: u64,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct InventoryPlan {
    pub actions: Vec<InventoryAction>,
    pub applied: bool,
    pub apply_mode: String,
    pub audit: String,
}
pub fn inventory_invalid() -> CapabilityError {
    CapabilityError::new(
        CapabilityErrorCode::InvalidInput,
        "INVENTORY_INPUT",
        "Invalid bounded inventory request",
    )
}
pub fn device_site_scope(
    h: &HierarchyRegistry,
    site: &SiteId,
) -> Result<(OrganizationId, InfrastructureId), CapabilityError> {
    let s = h
        .plan
        .sites
        .iter()
        .find(|s| &s.id == site)
        .ok_or_else(inaccessible)?;
    let i = h
        .plan
        .infrastructures
        .iter()
        .find(|i| i.id == s.infrastructure_id)
        .ok_or_else(inaccessible)?;
    Ok((i.organization_id.clone(), i.id.clone()))
}
/// One rule set for offline apply and remote read-only validation. A plan is never authority.
pub fn validate_inventory_plan(
    h: &HierarchyRegistry,
    p: &PrincipalId,
    rows: &[InventoryRecord],
    changes: &[InventoryChange],
) -> Result<InventoryPlan, CapabilityError> {
    if changes.is_empty() || changes.len() > 100 {
        return Err(inventory_invalid());
    }
    let mut seen = BTreeSet::new();
    let mut actions = Vec::new();
    for c in changes {
        let (id, site, expected) = match c {
            InventoryChange::Register { device } => (device.id.clone(), device.site_id.clone(), 0),
            InventoryChange::Update {
                device,
                expected_revision,
            } => (
                device.id.clone(),
                device.site_id.clone(),
                *expected_revision,
            ),
            InventoryChange::Archive {
                id,
                expected_revision,
            } => {
                let old = rows
                    .iter()
                    .find(|r| &r.device.id == id)
                    .ok_or_else(inaccessible)?;
                (id.clone(), old.device.site_id.clone(), *expected_revision)
            }
        };
        if !seen.insert(id.clone()) {
            return Err(inventory_invalid());
        }
        if !h.permits(
            p,
            CapabilityId::InventoryChange,
            &AccessScope::Site(site.clone()),
            false,
        ) {
            return Err(inaccessible());
        }
        let old = rows.iter().find(|r| r.device.id == id);
        if let Some(old) = old {
            if !h.permits(
                p,
                CapabilityId::InventoryChange,
                &AccessScope::Site(old.device.site_id.clone()),
                false,
            ) {
                return Err(inaccessible());
            }
        }
        let outcome = match c {
            InventoryChange::Register { device } => {
                device.validate()?;
                match old {
                    None => "create",
                    Some(old)
                        if old.device == *device
                            && old.registration == RegistrationStatus::Registered =>
                    {
                        "idempotent"
                    }
                    _ => {
                        return Err(CapabilityError::new(
                            CapabilityErrorCode::InvalidInput,
                            "INVENTORY_CONFLICT",
                            "Identifier or revision conflict",
                        ))
                    }
                }
            }
            InventoryChange::Update {
                device,
                expected_revision,
            } => {
                device.validate()?;
                let old = old.ok_or_else(inaccessible)?;
                if old.device.site_id != device.site_id {
                    return Err(CapabilityError::new(
                        CapabilityErrorCode::OperationNotSupported,
                        "INVENTORY_MOVE_UNSUPPORTED",
                        "Ownership/site moves require separate provisioning",
                    ));
                }
                if old.revision != *expected_revision {
                    return Err(CapabilityError::new(
                        CapabilityErrorCode::InvalidInput,
                        "INVENTORY_CONFLICT",
                        "Identifier or revision conflict",
                    ));
                }
                if old.device == *device {
                    "idempotent"
                } else {
                    "update"
                }
            }
            InventoryChange::Archive {
                expected_revision, ..
            } => {
                let old = old.ok_or_else(inaccessible)?;
                if old.revision != *expected_revision {
                    return Err(CapabilityError::new(
                        CapabilityErrorCode::InvalidInput,
                        "INVENTORY_CONFLICT",
                        "Identifier or revision conflict",
                    ));
                }
                if old.registration == RegistrationStatus::Archived {
                    "idempotent"
                } else {
                    "archive"
                }
            }
        };
        actions.push(InventoryAction {
            id,
            outcome: outcome.into(),
            expected_revision: expected,
        });
    }
    if rows.len() + actions.iter().filter(|a| a.outcome == "create").count() > 2048 {
        return Err(inventory_invalid());
    }
    Ok(InventoryPlan {
        actions,
        applied: false,
        apply_mode: "offline_requires_restart".into(),
        audit:
            "local OS operator authority separate from selected policy principal; no values logged"
                .into(),
    })
}

fn inventory_source<'de, D: serde::Deserializer<'de>>(
    d: D,
) -> Result<Option<DataSourceId>, D::Error> {
    let value = Option::<String>::deserialize(d)?;
    value
        .map(|s| {
            if s.is_empty()
                || s.len() > 128
                || !s
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b"-_.".contains(&b))
            {
                return Err(serde::de::Error::custom("Invalid canonical source ID"));
            }
            DataSourceId::new(s).map_err(|_| serde::de::Error::custom("Invalid source ID"))
        })
        .transpose()
}

// Update is an explicit full replacement. Unlike registration, metadata may not be omitted.
// Local onboarding clients merge requested metadata fields with the current record under CAS.
#[derive(Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(deny_unknown_fields)]
struct DeviceReplacement {
    id: DeviceId,
    display_name: String,
    device_type: DeviceType,
    site_id: SiteId,
    metadata: DeviceMetadata,
}
fn replacement_device<'de, D: serde::Deserializer<'de>>(
    d: D,
) -> Result<DeviceRegistration, D::Error> {
    let r = DeviceReplacement::deserialize(d)?;
    Ok(DeviceRegistration {
        id: r.id,
        display_name: r.display_name,
        device_type: r.device_type,
        site_id: r.site_id,
        metadata: r.metadata,
    })
}
