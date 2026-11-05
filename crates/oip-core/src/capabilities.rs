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
    QueueRead,
    SystemStatusRead,
    DevicesRead,
    DeviceRead,
    ObservationsRead,
    EventsRead,
    OpcuaNodesRead,
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
    pub const ALL: [Self; 24] = [
        Self::CoreHealthRead,
        Self::CoreLivenessRead,
        Self::CoreReadinessRead,
        Self::SourcesRead,
        Self::QueueRead,
        Self::SystemStatusRead,
        Self::DevicesRead,
        Self::DeviceRead,
        Self::ObservationsRead,
        Self::EventsRead,
        Self::OpcuaNodesRead,
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
    ];
    pub fn descriptor(self) -> CapabilityDescriptor {
        use CapabilityId::*;
        let (permission, input, output) = match self {
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
            mutating: self == SimulationScenarioSet,
            input_type: input.into(),
            output_type: output.into(),
            audit: if self == SimulationScenarioSet {
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
}
impl CapabilityRequest {
    pub fn id(&self) -> CapabilityId {
        match self {
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
