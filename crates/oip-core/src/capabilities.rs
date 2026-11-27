//! Agent-first application boundary. No transport, identity provider or MCP dependency.
use crate::*;
use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
use thiserror::Error;

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum CapabilityId {
    CoreHealthRead,
    CoreLivenessRead,
    CoreReadinessRead,
    SourcesRead,
    SupportPackageRead,
    LicenseStatusRead,
    LicenseProofPreview,
    LicenseProofApply,
    QueueRead,
    SystemStatusRead,
    DevicesRead,
    DeviceRead,
    ObservationsRead,
    EventsRead,
    OpcuaNodesRead,
    OpcuaNodeWrite,
    SnapshotRead,
    SimulationScenarioSet,
    OrganizationsRead,
    InfrastructuresRead,
    SitesRead,
    ScopedSnapshotRead,
    EventHistoryRead,
    EventDetailRead,
    DataGapsRead,
    SourceHealthHistoryRead,
    EvidenceRead,
    DiagnosticFindingsRead,
    ObservationHistoryRead,
    SettingsRead,
    McpManagementRead,
    SettingsChange,
    InventoryRead,
    InventoryPlanRead,
    InventoryChange,
    DeviceConnectionRead,
    DeviceConnectionConfigure,
    ServiceRegistryRead,
    HueLightsRead,
    HueLightControl,
    HueSetup,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum Permission {
    HierarchyRead,
    CoreRead,
    SourcesRead,
    DevicesRead,
    TelemetryRead,
    EventsRead,
    OpcuaRead,
    SimulationControl,
    SettingsRead,
    SettingsWrite,
    LicenseRead,
    LicenseManage,
    InventoryManage,
    McpManagementRead,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct CapabilityDescriptor {
    pub id: CapabilityId,
    pub permission: Vec<Permission>,
    pub mutating: bool,
    pub input_type: String,
    pub output_type: String,
    pub audit: String,
}
impl CapabilityId {
    pub const ALL: [Self; 41] = [
        Self::CoreHealthRead,
        Self::CoreLivenessRead,
        Self::CoreReadinessRead,
        Self::SourcesRead,
        Self::SupportPackageRead,
        Self::LicenseStatusRead,
        Self::LicenseProofPreview,
        Self::LicenseProofApply,
        Self::QueueRead,
        Self::SystemStatusRead,
        Self::DevicesRead,
        Self::DeviceRead,
        Self::ObservationsRead,
        Self::EventsRead,
        Self::OpcuaNodesRead,
        Self::OpcuaNodeWrite,
        Self::SnapshotRead,
        Self::SimulationScenarioSet,
        Self::OrganizationsRead,
        Self::InfrastructuresRead,
        Self::SitesRead,
        Self::ScopedSnapshotRead,
        Self::EventHistoryRead,
        Self::EventDetailRead,
        Self::DataGapsRead,
        Self::SourceHealthHistoryRead,
        Self::EvidenceRead,
        Self::DiagnosticFindingsRead,
        Self::ObservationHistoryRead,
        Self::SettingsRead,
        Self::McpManagementRead,
        Self::SettingsChange,
        Self::InventoryRead,
        Self::InventoryPlanRead,
        Self::InventoryChange,
        Self::DeviceConnectionRead,
        Self::DeviceConnectionConfigure,
        Self::ServiceRegistryRead,
        Self::HueLightsRead,
        Self::HueLightControl,
        Self::HueSetup,
    ];
    pub fn descriptor(self) -> CapabilityDescriptor {
        use CapabilityId::*;
        let (permission, input, output) = match self {
            LicenseStatusRead => (vec![Permission::LicenseRead], "Empty", "LicenseStatus"),
            LicenseProofPreview => (
                vec![Permission::LicenseRead, Permission::LicenseManage],
                "LicensePreviewRequest",
                "LicensePreview",
            ),
            LicenseProofApply => (
                vec![Permission::LicenseRead, Permission::LicenseManage],
                "LicenseApplyRequest",
                "LicenseStatus",
            ),
            SupportPackageRead => (
                vec![Permission::SourcesRead],
                "SupportPackageQuery",
                "SupportPackage",
            ),
            HueLightsRead => (
                vec![Permission::DevicesRead, Permission::TelemetryRead],
                "HueLightsQuery",
                "HueLights",
            ),
            HueLightControl => (
                vec![
                    Permission::InventoryManage,
                    Permission::DevicesRead,
                    Permission::TelemetryRead,
                ],
                "HueLightCommand",
                "HueCommandAccepted",
            ),
            HueSetup => (
                vec![
                    Permission::InventoryManage,
                    Permission::DevicesRead,
                    Permission::TelemetryRead,
                ],
                "HueSetupRequest",
                "HueSetupAccepted",
            ),
            DeviceConnectionRead => (
                vec![Permission::DevicesRead, Permission::TelemetryRead],
                "ConnectionQuery",
                "ConnectionResult",
            ),
            DeviceConnectionConfigure => (
                vec![
                    Permission::InventoryManage,
                    Permission::DevicesRead,
                    Permission::TelemetryRead,
                ],
                "ConnectionAction",
                "ConnectionResult",
            ),
            InventoryRead => (
                vec![Permission::DevicesRead],
                "InventoryQuery",
                "InventoryPage",
            ),
            // The service registry is a **read** of what the operator declared: the same
            // permission that the inventory read carries, so the readers of the inventory
            // read the services of the same scope.
            ServiceRegistryRead => (vec![Permission::DevicesRead], "ServiceQuery", "ServicePage"),
            InventoryPlanRead => (
                vec![Permission::InventoryManage],
                "InventoryPlanQuery",
                "InventoryPlan",
            ),
            InventoryChange => (
                vec![Permission::InventoryManage],
                "InventoryAdministration",
                "InventoryPlan",
            ),
            SettingsRead => (
                vec![Permission::SettingsRead],
                "SettingsQuery",
                "SettingsSnapshot",
            ),
            McpManagementRead => (
                vec![Permission::McpManagementRead],
                "ManagementQuery",
                "ManagementReport",
            ),
            SettingsChange => (
                vec![Permission::SettingsWrite],
                "SettingsChange",
                "SettingsChangeResult",
            ),
            EventHistoryRead | EventDetailRead => (
                vec![Permission::EventsRead, Permission::TelemetryRead],
                "DiagnosticQuery",
                "DiagnosticPage",
            ),
            DataGapsRead | DiagnosticFindingsRead => (
                vec![Permission::EventsRead],
                "DiagnosticQuery",
                "DiagnosticPage",
            ),
            SourceHealthHistoryRead => (
                vec![Permission::EventsRead, Permission::SourcesRead],
                "DiagnosticQuery",
                "DiagnosticPage",
            ),
            ObservationHistoryRead => (
                vec![Permission::TelemetryRead],
                "DiagnosticQuery",
                "DiagnosticPage",
            ),
            EvidenceRead => (
                vec![
                    Permission::EventsRead,
                    Permission::TelemetryRead,
                    Permission::SourcesRead,
                ],
                "DiagnosticQuery",
                "EvidenceSet",
            ),
            OrganizationsRead => (
                vec![Permission::HierarchyRead],
                "HierarchyQuery",
                "Page<Organization>",
            ),
            InfrastructuresRead => (
                vec![Permission::HierarchyRead],
                "HierarchyQuery",
                "Page<Infrastructure>",
            ),
            SitesRead => (
                vec![Permission::HierarchyRead],
                "HierarchyQuery",
                "Page<Site>",
            ),
            ScopedSnapshotRead => (
                vec![
                    Permission::SourcesRead,
                    Permission::DevicesRead,
                    Permission::TelemetryRead,
                    Permission::EventsRead,
                ],
                "Empty",
                "ScopedSnapshot",
            ),
            CoreHealthRead | CoreLivenessRead | CoreReadinessRead => {
                (vec![Permission::CoreRead], "Empty", "CoreHealth")
            }
            QueueRead => (vec![Permission::CoreRead], "Empty", "QueueHealth"),
            SystemStatusRead => (vec![Permission::CoreRead], "Empty", "SystemStatus"),
            SourcesRead => (
                vec![Permission::SourcesRead],
                "SourceQuery",
                "Vec<SourceHealth>",
            ),
            DevicesRead => (vec![Permission::DevicesRead], "DeviceQuery", "Vec<Device>"),
            DeviceRead => (
                vec![Permission::DevicesRead, Permission::TelemetryRead],
                "DeviceRequest",
                "DeviceDetail",
            ),
            ObservationsRead => (
                vec![Permission::TelemetryRead],
                "SourceQuery",
                "Vec<ObservationEnvelope>",
            ),
            EventsRead => (
                vec![Permission::EventsRead],
                "SourceQuery",
                "EventsResponse",
            ),
            OpcuaNodesRead => (
                vec![Permission::OpcuaRead, Permission::TelemetryRead],
                "NodeQuery",
                "NodePage",
            ),
            OpcuaNodeWrite => (
                vec![Permission::OpcuaRead, Permission::InventoryManage],
                "NodeWriteRequest",
                "NodeWriteResult",
            ),
            SnapshotRead => (
                vec![
                    Permission::CoreRead,
                    Permission::SourcesRead,
                    Permission::DevicesRead,
                    Permission::TelemetryRead,
                    Permission::EventsRead,
                ],
                "Empty",
                "Snapshot",
            ),
            SimulationScenarioSet => (
                vec![Permission::SimulationControl],
                "ScenarioRequest",
                "ScenarioResponse",
            ),
        };
        CapabilityDescriptor {
            id: self,
            permission,
            mutating: matches!(
                self,
                SimulationScenarioSet
                    | SettingsChange
                    | LicenseProofPreview
                    | LicenseProofApply
                    | InventoryChange
                    | DeviceConnectionConfigure
                    | OpcuaNodeWrite
                    | HueLightControl
                    | HueSetup
            ),
            input_type: input.into(),
            output_type: output.into(),
            audit: if matches!(
                self,
                SimulationScenarioSet
                    | SettingsChange
                    | LicenseProofPreview
                    | LicenseProofApply
                    | InventoryChange
                    | DeviceConnectionConfigure
                    | OpcuaNodeWrite
                    | HueLightControl
                    | HueSetup
            ) {
                "decision_and_outcome_local_log"
            } else {
                "execution_local_log"
            }
            .into(),
        }
    }
}
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(default, deny_unknown_fields)]
pub struct SourceQuery {
    pub organization: Option<OrganizationId>,
    pub infrastructure: Option<InfrastructureId>,
    pub site: Option<SiteId>,
    pub offset: Option<usize>,
    pub limit: Option<usize>,
    pub source: Option<DataSourceId>,
}
/// An explicit infrastructure is required. Finer filters must belong to it.
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(deny_unknown_fields)]
pub struct SupportPackageQuery {
    pub infrastructure: InfrastructureId,
    pub site: Option<SiteId>,
    pub source: Option<DataSourceId>,
}

/// Shareable local diagnostic report. Only fixed metadata and counters may be
/// added here. Never add names, identifiers, free text, topology or raw samples.
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct SupportPackage {
    pub format_version: u8,
    pub core_version: String,
    pub build_revision: String,
    pub platform: String,
    pub architecture: String,
    pub sources: SupportSourceCounts,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct SupportSourceCounts {
    pub total: usize,
    pub simulated: usize,
    pub connected: usize,
    pub disconnected: usize,
    pub connection_unknown: usize,
    pub fresh: usize,
    pub stale: usize,
    pub freshness_unknown: usize,
    pub invalid: usize,
    pub degraded: usize,
    pub reconnect_attempts: u64,
    pub dropped: u64,
    pub rejected: u64,
}
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(default, deny_unknown_fields)]
pub struct DeviceQuery {
    pub q: Option<String>,
    pub location: Option<String>,
    pub source: Option<DataSourceId>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(deny_unknown_fields)]
pub struct DeviceRequest {
    pub id: String,
}
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(default, deny_unknown_fields)]
pub struct NodeQuery {
    pub q: Option<String>,
    pub folder: Option<String>,
    pub source: Option<DataSourceId>,
    pub offset: Option<usize>,
    pub limit: Option<usize>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(deny_unknown_fields)]
pub struct NodeWriteRequest {
    pub source: DataSourceId,
    pub node_id: String,
    pub value: MetricValue,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct NodeWriteResult {
    pub source: DataSourceId,
    pub node_id: String,
    pub accepted: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(deny_unknown_fields)]
pub struct ScenarioRequest {
    pub scenario: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(
    tag = "capability",
    content = "input",
    rename_all = "snake_case",
    deny_unknown_fields
)]
pub enum CapabilityRequest {
    SupportPackageRead(SupportPackageQuery),
    LicenseStatusRead,
    LicenseProofPreview(LicensePreviewRequest),
    LicenseProofApply(LicenseApplyRequest),
    CoreHealthRead,
    CoreLivenessRead,
    CoreReadinessRead,
    SourcesRead(SourceQuery),
    QueueRead,
    SystemStatusRead,
    DevicesRead(DeviceQuery),
    DeviceRead(DeviceRequest),
    ObservationsRead(SourceQuery),
    EventsRead(SourceQuery),
    OpcuaNodesRead(NodeQuery),
    OpcuaNodeWrite(NodeWriteRequest),
    SnapshotRead,
    SimulationScenarioSet(ScenarioRequest),
    OrganizationsRead(HierarchyQuery),
    InfrastructuresRead(HierarchyQuery),
    SitesRead(HierarchyQuery),
    ScopedSnapshotRead,
    EventHistoryRead(DiagnosticQuery),
    EventDetailRead(DiagnosticQuery),
    DataGapsRead(DiagnosticQuery),
    SourceHealthHistoryRead(DiagnosticQuery),
    EvidenceRead(DiagnosticQuery),
    DiagnosticFindingsRead(DiagnosticQuery),
    ObservationHistoryRead(DiagnosticQuery),
    SettingsRead(SettingsQuery),
    McpManagementRead(ManagementQuery),
    SettingsChange(SettingsChange),
    InventoryRead(InventoryQuery),
    InventoryPlanRead(InventoryPlanQuery),
    InventoryChange(InventoryAdministration),
    DeviceConnectionRead(ConnectionQuery),
    DeviceConnectionConfigure(ConnectionAction),
    ServiceRegistryRead(ServiceQuery),
    HueLightsRead(HueLightsQuery),
    HueLightControl(HueLightCommand),
    HueSetup(HueSetupRequest),
}
impl CapabilityRequest {
    pub fn id(&self) -> CapabilityId {
        match self {
            Self::LicenseStatusRead => CapabilityId::LicenseStatusRead,
            Self::LicenseProofPreview(_) => CapabilityId::LicenseProofPreview,
            Self::LicenseProofApply(_) => CapabilityId::LicenseProofApply,
            Self::SupportPackageRead(_) => CapabilityId::SupportPackageRead,
            Self::SettingsRead(_) => CapabilityId::SettingsRead,
            Self::McpManagementRead(_) => CapabilityId::McpManagementRead,
            Self::SettingsChange(_) => CapabilityId::SettingsChange,
            Self::InventoryRead(_) => CapabilityId::InventoryRead,
            Self::InventoryPlanRead(_) => CapabilityId::InventoryPlanRead,
            Self::InventoryChange(_) => CapabilityId::InventoryChange,
            Self::DeviceConnectionRead(_) => CapabilityId::DeviceConnectionRead,
            Self::DeviceConnectionConfigure(_) => CapabilityId::DeviceConnectionConfigure,
            Self::HueLightsRead(_) => CapabilityId::HueLightsRead,
            Self::HueLightControl(_) => CapabilityId::HueLightControl,
            Self::HueSetup(_) => CapabilityId::HueSetup,
            Self::ServiceRegistryRead(_) => CapabilityId::ServiceRegistryRead,
            Self::EventHistoryRead(_) => CapabilityId::EventHistoryRead,
            Self::EventDetailRead(_) => CapabilityId::EventDetailRead,
            Self::DataGapsRead(_) => CapabilityId::DataGapsRead,
            Self::SourceHealthHistoryRead(_) => CapabilityId::SourceHealthHistoryRead,
            Self::EvidenceRead(_) => CapabilityId::EvidenceRead,
            Self::DiagnosticFindingsRead(_) => CapabilityId::DiagnosticFindingsRead,
            Self::ObservationHistoryRead(_) => CapabilityId::ObservationHistoryRead,
            Self::CoreHealthRead => CapabilityId::CoreHealthRead,
            Self::CoreLivenessRead => CapabilityId::CoreLivenessRead,
            Self::CoreReadinessRead => CapabilityId::CoreReadinessRead,
            Self::SourcesRead(_) => CapabilityId::SourcesRead,
            Self::QueueRead => CapabilityId::QueueRead,
            Self::SystemStatusRead => CapabilityId::SystemStatusRead,
            Self::DevicesRead(_) => CapabilityId::DevicesRead,
            Self::DeviceRead(_) => CapabilityId::DeviceRead,
            Self::ObservationsRead(_) => CapabilityId::ObservationsRead,
            Self::EventsRead(_) => CapabilityId::EventsRead,
            Self::OpcuaNodesRead(_) => CapabilityId::OpcuaNodesRead,
            Self::OpcuaNodeWrite(_) => CapabilityId::OpcuaNodeWrite,
            Self::SnapshotRead => CapabilityId::SnapshotRead,
            Self::SimulationScenarioSet(_) => CapabilityId::SimulationScenarioSet,
            Self::OrganizationsRead(_) => CapabilityId::OrganizationsRead,
            Self::InfrastructuresRead(_) => CapabilityId::InfrastructuresRead,
            Self::SitesRead(_) => CapabilityId::SitesRead,
            Self::ScopedSnapshotRead => CapabilityId::ScopedSnapshotRead,
        }
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(tag = "type", content = "value", rename_all = "snake_case")]
pub enum CapabilityOutput {
    SupportPackage(SupportPackage),
    LicenseStatus(LicenseStatus),
    LicensePreview(LicensePreview),
    HueLights(HueLights),
    HueCommandAccepted { light_id: u64 },
    HueSetupAccepted { action: HueSetupAction },
    Connection(Box<ConnectionResult>),
    Inventory(InventoryPage),
    InventoryPlan(InventoryPlan),
    ServiceRegistry(ServicePage),
    Settings(SettingsSnapshot),
    Management(ManagementReport),
    SettingsChanged(SettingsChangeResult),
    DiagnosticPage(DiagnosticPage),
    Evidence(Box<EvidenceSet>),
    CoreHealth(CoreHealth),
    Sources(Vec<SourceHealth>),
    Queue(QueueHealth),
    SystemStatus(SystemStatus),
    Devices(Vec<Device>),
    Device(DeviceDetail),
    Observations(Vec<ObservationEnvelope>),
    Events(EventsResponse),
    Nodes(NodePage),
    NodeWrite(NodeWriteResult),
    Snapshot(Box<Snapshot>),
    Scenario(ScenarioResponse),
    Organizations(Page<Organization>),
    Infrastructures(Page<Infrastructure>),
    Sites(Page<Site>),
    ScopedSnapshot(ScopedSnapshot),
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum CapabilityErrorCode {
    ResourceNotFound,
    SourceUnavailable,
    InvalidInput,
    DataStale,
    PermissionDenied,
    OperationNotSupported,
    PersistenceUnavailable,
    AuditUnavailable,
}
#[derive(Clone, Debug, Error, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[error("{message}")]
pub struct CapabilityError {
    pub kind: CapabilityErrorCode,
    /// Stable legacy v1 error identifier, retained by HTTP adapters.
    pub code: String,
    pub message: String,
}
impl CapabilityError {
    pub fn new(kind: CapabilityErrorCode, code: &str, message: &str) -> Self {
        Self {
            kind,
            code: code.into(),
            message: message.into(),
        }
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(tag = "kind", content = "sources", rename_all = "snake_case")]
pub enum SourceScope {
    All,
    Only(BTreeSet<DataSourceId>),
}
/// Must be issued by the host/adapter after authentication; never deserialize this
/// from an untrusted tool body as proof of identity or authorization.
#[derive(Clone, Debug)]
pub struct ExecutionContext {
    pub principal: Option<PrincipalId>,
    pub actor: String,
    pub correlation_id: String,
    pub permissions: BTreeSet<Permission>,
    pub sources: SourceScope,
}
impl ExecutionContext {
    pub fn authorize(
        &self,
        capability: CapabilityId,
        source: Option<&DataSourceId>,
    ) -> Result<(), CapabilityError> {
        let safe_id = |s: &str| {
            !s.is_empty()
                && s.len() <= 128
                && s.bytes()
                    .all(|c| c.is_ascii_alphanumeric() || b"-_.:".contains(&c))
        };
        let scope = match &self.sources {
            SourceScope::All => true,
            SourceScope::Only(allowed) => source.is_some_and(|s| allowed.contains(s)),
        };
        if !safe_id(&self.actor)
            || !safe_id(&self.correlation_id)
            || !scope
            || !capability
                .descriptor()
                .permission
                .iter()
                .all(|p| self.permissions.contains(p))
        {
            return Err(CapabilityError::new(
                CapabilityErrorCode::PermissionDenied,
                "PERMISSION_DENIED",
                "Capability or source scope is not authorized",
            ));
        }
        Ok(())
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct ExecutionAudit {
    pub scope: Option<AccessScope>,
    pub principal: Option<PrincipalId>,
    pub hierarchy: Option<HierarchyLocation>,
    pub actor: String,
    pub capability: CapabilityId,
    pub target: String,
    pub at_ms: i64,
    pub authorized: bool,
    pub outcome: String,
    pub correlation_id: String,
}
/// OIP-005 uses structured local logs. Durable/tamper-resistant storage is an
/// explicit prerequisite for future remote mutating capabilities.
pub trait CapabilityAudit: Send + Sync {
    fn record(&self, event: &ExecutionAudit) -> Result<(), CapabilityError>;
}
/// Canonical device presentation classification, shared by all adapters.
impl Health {
    pub fn is_faulted(&self) -> bool {
        self.agent_availability == "unavailable"
            || self.vpn_transport == "degraded"
            || matches!(
                self.service_health.as_str(),
                "alarm" | "degraded" | "reconnecting" | "stale"
            )
    }
}

/// Protocol adapters call this same application boundary; no HTTP request types.
pub trait CapabilityService: Send + Sync {
    fn execute<'a>(
        &'a self,
        context: &'a ExecutionContext,
        request: CapabilityRequest,
    ) -> std::pin::Pin<
        Box<
            dyn std::future::Future<Output = Result<CapabilityOutput, CapabilityError>> + Send + 'a,
        >,
    >;
    fn discover(&self, context: &ExecutionContext) -> Vec<CapabilityDescriptor> {
        CapabilityId::ALL
            .into_iter()
            .filter(|id| {
                id.descriptor()
                    .permission
                    .iter()
                    .all(|p| context.permissions.contains(p))
            })
            .map(CapabilityId::descriptor)
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn schemas_reject_unknown_operations_fields_and_empty_source_ids() {
        for body in [
            r#"{"capability":"opcua_write","input":{}}"#,
            r#"{"capability":"devices_read","input":{"secret":"x"}}"#,
            r#"{"capability":"observations_read","input":{"source":" "}}"#,
        ] {
            assert!(
                serde_json::from_str::<CapabilityRequest>(body).is_err(),
                "{body}"
            );
        }
        let request = CapabilityRequest::OpcuaNodesRead(NodeQuery {
            source: Some(DataSourceId::new("a").unwrap()),
            limit: Some(40),
            ..Default::default()
        });
        let json = serde_json::to_string(&request).unwrap();
        let parsed: CapabilityRequest = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.id(), CapabilityId::OpcuaNodesRead);
    }
    #[test]
    fn no_implicit_wildcard_permissions_and_unsafe_contexts_are_rejected() {
        let mut ctx = ExecutionContext {
            principal: None,
            actor: "operator".into(),
            correlation_id: "call-1".into(),
            permissions: [Permission::CoreRead].into(),
            sources: SourceScope::All,
        };
        assert!(ctx.authorize(CapabilityId::CoreHealthRead, None).is_ok());
        assert!(ctx.authorize(CapabilityId::SnapshotRead, None).is_err());
        ctx.actor = "secret\nforged-log".into();
        assert!(ctx.authorize(CapabilityId::CoreHealthRead, None).is_err());
    }
}
