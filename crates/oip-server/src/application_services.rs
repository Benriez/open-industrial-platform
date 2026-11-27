//! Canonical application queries and simulation control. Axum and future MCP are adapters.
use crate::{
    demo::SCENARIOS,
    state::{now_ms, AppState},
};
use futures::{stream, StreamExt};
use oip_core::*;
use oip_opcua::ReadOnlyOpcUaAdapter;
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc,
};

// Preserve an execution outcome when a transport cancels a read future.
// No background task: the synchronous existing audit port is called on drop.
struct InterruptedExecution {
    sink: Arc<dyn CapabilityAudit>,
    event: Option<ExecutionAudit>,
}
impl Drop for InterruptedExecution {
    fn drop(&mut self) {
        if let Some(event) = &self.event {
            if self.sink.record(event).is_err() {
                tracing::error!(correlation_id=%event.correlation_id,code="interruption_audit_failed","interrupted execution audit unavailable");
            }
        }
    }
}
pub struct LocalLogAudit;
impl CapabilityAudit for LocalLogAudit {
    fn record(&self, event: &ExecutionAudit) -> Result<(), CapabilityError> {
        tracing::info!(principal=?event.principal,scope=?event.scope,hierarchy=?event.hierarchy,actor=%event.actor,capability=?event.capability,target=%event.target,
            at_ms=event.at_ms,authorized=event.authorized,outcome=%event.outcome,
            correlation_id=%event.correlation_id,code="capability_execution","local development audit (not durable)");
        Ok(())
    }
}
#[derive(Clone)]
pub struct ApplicationServices {
    pub(crate) state: AppState,
    audit: Arc<dyn CapabilityAudit>,
}
/// The namespace of a node id of the server (`ns=2;s=temperature`).
///
/// A node id of namespace 0 carries no prefix; it belongs to namespace 0.
fn namespace_of(node_id: &str) -> u16 {
    node_id
        .strip_prefix("ns=")
        .and_then(|rest| rest.split(';').next())
        .and_then(|namespace| namespace.parse().ok())
        .unwrap_or(0)
}
fn storage(_: String) -> CapabilityError {
    CapabilityError::new(
        CapabilityErrorCode::PersistenceUnavailable,
        "STORAGE_UNAVAILABLE",
        "Local evidence storage is unavailable",
    )
}
impl ApplicationServices {
    pub fn new(state: AppState) -> Self {
        let audit = state.security_audit.as_ref().map_or_else(
            || Arc::new(LocalLogAudit) as Arc<dyn CapabilityAudit>,
            |audit| audit.clone() as Arc<dyn CapabilityAudit>,
        );
        Self { state, audit }
    }
    pub fn with_audit(state: AppState, audit: Arc<dyn CapabilityAudit>) -> Self {
        Self { state, audit }
    }
    /// Restricted, explicitly local development principal. Headers/tool inputs cannot grant permissions.
    /// Remote authenticated principals and durable mutation audit are OIP-006 prerequisites.
    pub fn local_context(&self) -> ExecutionContext {
        static SEQUENCE: AtomicU64 = AtomicU64::new(1);
        let mut permissions = [
            Permission::CoreRead,
            Permission::SourcesRead,
            Permission::DevicesRead,
            Permission::TelemetryRead,
            Permission::EventsRead,
            Permission::OpcuaRead,
            Permission::InventoryManage,
        ]
        .into_iter()
        .collect::<std::collections::BTreeSet<_>>();
        if self.state.scenario_tx.is_some() {
            permissions.insert(Permission::SimulationControl);
        }
        ExecutionContext {
            principal: None,
            actor: "local-development".into(),
            correlation_id: format!(
                "run-{}-call-{}",
                self.state.view().health.run_id,
                SEQUENCE.fetch_add(1, Ordering::Relaxed)
            ),
            permissions,
            sources: SourceScope::All,
        }
    }
    fn source_for(&self, request: &CapabilityRequest) -> Option<DataSourceId> {
        if let Some(q) = crate::diagnostic_services::query(request) {
            return q.source.clone();
        }
        match request {
            CapabilityRequest::SupportPackageRead(q) => q.source.clone(),
            CapabilityRequest::SourcesRead(q)
            | CapabilityRequest::ObservationsRead(q)
            | CapabilityRequest::EventsRead(q) => q.source.clone(),
            CapabilityRequest::DevicesRead(q) => q.source.clone(),
            CapabilityRequest::OpcuaNodesRead(q) => q.source.clone().or(self.state.primary.clone()),
            CapabilityRequest::HueLightsRead(q) => Some(q.source.clone()),
            CapabilityRequest::HueLightControl(q) => Some(q.source.clone()),
            CapabilityRequest::HueSetup(q) => Some(q.source.clone()),
            CapabilityRequest::OpcuaNodeWrite(q) => Some(q.source.clone()),
            CapabilityRequest::DeviceRead(q) => {
                self.state
                    .snapshot()
                    .ok()?
                    .devices
                    .into_iter()
                    .find(|d| d.id == q.id)?
                    .data_source_id
            }
            CapabilityRequest::SimulationScenarioSet(_) => self.state.primary.clone(),
            _ => None,
        }
    }
    fn audit_event(
        &self,
        context: &ExecutionContext,
        id: CapabilityId,
        source: Option<&DataSourceId>,
        authorized: bool,
        outcome: &str,
    ) -> ExecutionAudit {
        let safe = |s: &str| {
            !s.is_empty()
                && s.len() <= 128
                && s.bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b"-_.:".contains(&b))
        };
        ExecutionAudit {
            scope: source
                .filter(|s| authorized && self.state.view().sources.iter().any(|v| &v.id == *s))
                .cloned()
                .map(AccessScope::Source),
            actor: if safe(&context.actor) {
                context.actor.clone()
            } else {
                "invalid-context".into()
            },
            principal: context.principal.clone(),
            hierarchy: source.and_then(|s| self.state.hierarchy().as_ref()?.location(s).cloned()),
            capability: id,
            // Log only enrolled resource IDs, never a caller's arbitrary target string.
            target: match source {
                None => "global".into(),
                Some(id)
                    if safe(id.as_str())
                        && self.state.view().sources.iter().any(|s| &s.id == id) =>
                {
                    id.to_string()
                }
                Some(_) => "unregistered-resource".into(),
            },
            at_ms: now_ms(),
            authorized,
            outcome: outcome.into(),
            correlation_id: if safe(&context.correlation_id) {
                context.correlation_id.clone()
            } else {
                "invalid-context".into()
            },
        }
    }
    fn check_source(&self, source: Option<&DataSourceId>) -> Result<(), CapabilityError> {
        if source.is_some_and(|id| !self.state.view().sources.iter().any(|s| &s.id == id)) {
            return Err(CapabilityError::new(
                CapabilityErrorCode::ResourceNotFound,
                "SOURCE_NOT_FOUND",
                "Source not registered",
            ));
        }
        Ok(())
    }
    async fn run(&self, request: CapabilityRequest) -> Result<CapabilityOutput, CapabilityError> {
        use CapabilityRequest::*;
        let s = &self.state;
        match request {
            HueLightsRead(_)
            | HueLightControl(_)
            | HueSetup(_)
            | OpcuaSetup(_)
            | DeviceConnectionRead(_)
            | DeviceConnectionConfigure(_)
            | InventoryRead(_)
            | ServiceRegistryRead(_)
            | InventoryPlanRead(_)
            | InventoryChange(_)
            | SettingsRead(_)
            | McpManagementRead(_)
            | SettingsChange(_)
            | LicenseStatusRead
            | LicenseProofPreview(_)
            | LicenseProofApply(_)
            | SupportPackageRead(_) => Err(CapabilityError::new(
                CapabilityErrorCode::PermissionDenied,
                "PRINCIPAL_REQUIRED",
                "Provisioned principal required",
            )),
            EventHistoryRead(_)
            | EventDetailRead(_)
            | DataGapsRead(_)
            | SourceHealthHistoryRead(_)
            | EvidenceRead(_)
            | DiagnosticFindingsRead(_)
            | ObservationHistoryRead(_) => Err(denied()),
            OrganizationsRead(_) | InfrastructuresRead(_) | SitesRead(_) | ScopedSnapshotRead => {
                Err(denied())
            }
            CoreHealthRead | CoreLivenessRead | CoreReadinessRead => {
                Ok(CapabilityOutput::CoreHealth(s.view().health))
            }
            QueueRead => Ok(CapabilityOutput::Queue(s.queue())),
            SystemStatusRead => Ok(CapabilityOutput::SystemStatus(
                s.snapshot().map_err(storage)?.system,
            )),
            SnapshotRead => Ok(CapabilityOutput::Snapshot(Box::new(
                s.snapshot().map_err(storage)?,
            ))),
            SourcesRead(q) => {
                self.check_source(q.source.as_ref())?;
                Ok(CapabilityOutput::Sources(
                    s.view()
                        .sources
                        .into_iter()
                        .filter(|v| q.source.as_ref().is_none_or(|id| &v.id == id))
                        .collect(),
                ))
            }
            DevicesRead(q) => {
                self.check_source(q.source.as_ref())?;
                if q.q.as_ref().is_some_and(|v| v.len() > 256)
                    || q.location.as_ref().is_some_and(|v| v.len() > 256)
                {
                    return Err(CapabilityError::new(
                        CapabilityErrorCode::InvalidInput,
                        "INVALID_QUERY",
                        "Device query is too long",
                    ));
                }
                let search = q.q.unwrap_or_default().trim().to_lowercase();
                let found = s
                    .snapshot()
                    .map_err(storage)?
                    .devices
                    .into_iter()
                    .filter(|d| {
                        q.source
                            .as_ref()
                            .is_none_or(|id| d.data_source_id.as_ref() == Some(id))
                            && q.location.as_ref().is_none_or(|v| &d.location == v)
                            && format!("{} {} {} {}", d.name, d.kind, d.location, d.connection)
                                .to_lowercase()
                                .contains(&search)
                    })
                    .collect();
                Ok(CapabilityOutput::Devices(found))
            }
            DeviceRead(q) => {
                let snap = s.snapshot().map_err(storage)?;
                let device = snap
                    .devices
                    .into_iter()
                    .find(|d| d.id == q.id)
                    .ok_or_else(|| {
                        CapabilityError::new(
                            CapabilityErrorCode::ResourceNotFound,
                            "DEVICE_NOT_FOUND",
                            "Device does not exist",
                        )
                    })?;
                let metrics = snap
                    .metrics
                    .into_iter()
                    .filter(|m| {
                        device.data_source_id.as_ref() == Some(&m.data_source_id)
                            && s.view()
                                .sources
                                .iter()
                                .find(|s| Some(&s.id) == device.data_source_id.as_ref())
                                .is_some_and(|s| s.entity_id == m.entity_id)
                    })
                    .collect();
                Ok(CapabilityOutput::Device(DeviceDetail {
                    device,
                    metrics,
                    history_status: "not_implemented".into(),
                }))
            }
            ObservationsRead(q) => {
                self.check_source(q.source.as_ref())?;
                Ok(CapabilityOutput::Observations(
                    s.snapshot()
                        .map_err(storage)?
                        .metrics
                        .into_iter()
                        .filter(|o| q.source.as_ref().is_none_or(|id| &o.data_source_id == id))
                        .collect(),
                ))
            }
            EventsRead(q) => {
                self.check_source(q.source.as_ref())?;
                let mut records = s.view().events;
                records.retain(|r| {
                    q.source
                        .as_ref()
                        .is_none_or(|id| &r.context.data_source_id == id)
                });
                records.reverse();
                records.truncate(100);
                let collection_events = records.iter().map(|r| r.event.clone()).collect();
                let incidents = if q.source.is_none() {
                    s.snapshot().map_err(storage)?.incidents
                } else {
                    Vec::new()
                };
                Ok(CapabilityOutput::Events(EventsResponse {
                    incidents,
                    collection_events,
                    records,
                    diagnosis_history_status: "demo_only".into(),
                    replay_supported: false,
                    resync_required: true,
                }))
            }
            OpcuaNodesRead(q) => self.nodes(q).await.map(CapabilityOutput::Nodes),
            OpcuaNodeWrite(body) => self.write_node(body).await.map(CapabilityOutput::NodeWrite),
            SimulationScenarioSet(body) => {
                if s.stopping.is_cancelled() {
                    return Err(CapabilityError::new(
                        CapabilityErrorCode::SourceUnavailable,
                        "CORE_STOPPING",
                        "Core is draining accepted work",
                    ));
                }
                if !SCENARIOS.contains(&body.scenario.as_str()) {
                    return Err(CapabilityError::new(
                        CapabilityErrorCode::InvalidInput,
                        "INVALID_SCENARIO",
                        "Unknown local demo scenario",
                    ));
                }
                let tx = s.scenario_tx.as_ref().ok_or_else(|| {
                    CapabilityError::new(
                        CapabilityErrorCode::OperationNotSupported,
                        "DEMO_DISABLED",
                        "Start with --demo to enable local simulation controls",
                    )
                })?;
                {
                    let mut d = s.data.lock().map_err(|_| storage("lock".into()))?;
                    let previous = d.scenario.clone();
                    d.scenario = body.scenario.clone();
                    if previous == "sensor"
                        || body.scenario == "sensor"
                        || body.scenario == "offline"
                    {
                        tx.send_replace(body.scenario.clone());
                    }
                }
                s.notify();
                Ok(CapabilityOutput::Scenario(ScenarioResponse {
                    accepted: true,
                    simulated: true,
                    scenario: body.scenario,
                }))
            }
        }
    }

    async fn nodes(&self, q: NodeQuery) -> Result<NodePage, CapabilityError> {
        let s = &self.state;
        if s.stopping.is_cancelled() {
            return Err(CapabilityError::new(
                CapabilityErrorCode::SourceUnavailable,
                "CORE_STOPPING",
                "Core is draining accepted work",
            ));
        }
        if q.q.as_ref().is_some_and(|v| v.len() > 256) {
            return Err(CapabilityError::new(
                CapabilityErrorCode::InvalidInput,
                "INVALID_QUERY",
                "Node query is too long",
            ));
        }
        let offset = q.offset.unwrap_or(0);
        let limit = q.limit.unwrap_or(40).clamp(1, 100);
        let search = q.q.unwrap_or_default().to_lowercase();
        // A normal browser page is address-space metadata. Reading every row
        // turns one click into dozens of OPC-UA service calls (up to eight in
        // flight) and can starve the source collector. A limit=1 query is the
        // explicit on-demand value read for the selected node.
        let read_value = limit == 1;
        let source = q.source.or(s.primary.clone()).ok_or_else(|| {
            CapabilityError::new(
                CapabilityErrorCode::SourceUnavailable,
                "NO_SOURCE",
                "No source configured",
            )
        })?;
        // The entity of the source is the entity that the **source**
        // declares: the value of a node of the source belongs to it.
        let entity = match s.view().sources.iter().find(|v| v.id == source) {
            Some(v) => v.entity_id.clone(),
            None => {
                return Err(CapabilityError::new(
                    CapabilityErrorCode::ResourceNotFound,
                    "SOURCE_NOT_FOUND",
                    "Source not registered",
                ));
            }
        };
        let catalog = s
            .catalogs
            .read()
            .await
            .get(&source)
            .cloned()
            .unwrap_or_default();
        // The address space of the source is browsed **as it is**: every node
        // of the catalogue is admitted, with the name and the folder that the
        // server delivers. A node outside the legacy catalogue is no longer
        // dropped behind a filter, and no folder is derived from the name of
        // a node.
        let folders: Vec<String> = {
            let mut names: Vec<String> = catalog
                .iter()
                .map(|entry| entry.folder.clone())
                .filter(|folder| !folder.is_empty())
                .collect();
            names.sort();
            names.dedup();
            names
        };
        let mut found: Vec<_> = catalog
            .into_iter()
            .filter_map(|entry| {
                // The browse name is the name of the node in the address
                // space of the server. The node id of a real server carries
                // no readable name — it may be numeric — so it is only the
                // fallback.
                let name = if entry.browse_name.trim().is_empty() {
                    entry.node_id.clone()
                } else {
                    entry.browse_name.clone()
                };
                let folder = entry.folder.clone();
                if q.folder
                    .as_ref()
                    .is_some_and(|f| f != "all" && *f != folder)
                    || !name.to_lowercase().contains(&search)
                {
                    return None;
                }
                Some((entry.node_id, name, folder, entry.node_class, entry.access))
            })
            .collect();
        found.sort_by(|a, b| a.1.cmp(&b.1));
        let total = found.len();
        let selected: Vec<_> = found.into_iter().skip(offset).take(limit).collect();
        let client = s.clients.read().await.get(&source).cloned();
        let collected = (read_value && s.is_selected_opcua(&source)).then(|| {
            s.view()
                .observations
                .into_iter()
                .filter(|point| point.data_source_id == source && point.entity_id == entity)
                .map(|point| (point.metric_id.clone(), point))
                .collect::<std::collections::BTreeMap<_, _>>()
        });
        let items = stream::iter(selected)
            .map(|(node_id, name, folder, _node_class, access)| {
                let client = client.clone();
                let source = source.clone();
                let entity = entity.clone();
                let collected = collected.as_ref().and_then(|points| {
                    MetricId::new(&name)
                        .ok()
                        .and_then(|metric| points.get(&metric))
                        .cloned()
                });
                async move {
                    // The browser reads the address space; it does not
                    // measure. The value of a node is read for the display
                    // and **not** ingested: a measurement belongs to the
                    // collector, which subscribes to the registered metrics
                    // of the source. The value belongs to the node with the
                    // **node id of the server** — not to a node that is
                    // reconstructed from its name — and it is bound to the
                    // entity that the source declares.
                    let observation = if collected.is_some() {
                        collected
                    } else if read_value {
                        if let Some(client) = client {
                            match MetricId::new(&name) {
                                Ok(metric) => {
                                    match client.read_node(&node_id, &metric, &entity).await {
                                        Ok(mut o) => {
                                            o.data_source_id = source.clone();
                                            Some(o)
                                        }
                                        Err(_) => None,
                                    }
                                }
                                Err(_) => None,
                            }
                        } else {
                            None
                        }
                    } else {
                        None
                    };
                    // The data type is the type of the value that the Core
                    // read for the node. A node without a value carries no
                    // data type, and the surface says so.
                    let data_type = match &observation {
                        Some(o) => match &o.value {
                            Some(MetricValue::Boolean(_)) => "Boolean",
                            Some(MetricValue::Text(_)) => "String",
                            Some(MetricValue::Float(_)) => "Double",
                            Some(MetricValue::SignedInteger(_)) => "Int64",
                            Some(MetricValue::UnsignedInteger(_)) => "UInt64",
                            None => "Nicht geliefert",
                        },
                        None => "Nicht geliefert",
                    }
                    .into();
                    // The namespace is the namespace of the node id of the
                    // server, and the access is the access of the class of
                    // the node — neither is a constant of the demo.
                    let namespace = namespace_of(&node_id);
                    Ok(Node {
                        data_source_id: source.clone(),
                        node_id,
                        name,
                        namespace,
                        folder,
                        data_type,
                        access,
                        observation,
                    })
                }
            })
            .buffered(8)
            .collect::<Vec<Result<Node, CapabilityError>>>()
            .await
            .into_iter()
            .collect::<Result<Vec<_>, _>>()?;
        Ok(NodePage {
            items,
            total,
            offset,
            limit,
            folders,
        })
    }

    async fn write_node(
        &self,
        request: NodeWriteRequest,
    ) -> Result<NodeWriteResult, CapabilityError> {
        if self.state.opcua_read_only || self.state.is_selected_opcua(&request.source) {
            return Err(CapabilityError::new(
                CapabilityErrorCode::OperationNotSupported,
                "OPCUA_READ_ONLY_PROFILE",
                "This installation permits reading OPC-UA sources",
            ));
        }
        if request.node_id.is_empty() || request.node_id.len() > 256 {
            return Err(CapabilityError::new(
                CapabilityErrorCode::InvalidInput,
                "INVALID_NODE_ID",
                "The OPC-UA node id is invalid",
            ));
        }
        let catalog = self.state.catalogs.read().await;
        let writable = catalog
            .get(&request.source)
            .and_then(|entries| {
                entries
                    .iter()
                    .find(|entry| entry.node_id == request.node_id)
            })
            .is_some_and(|entry| entry.access == "ReadWrite");
        drop(catalog);
        if !writable {
            return Err(CapabilityError::new(
                CapabilityErrorCode::OperationNotSupported,
                "NODE_NOT_WRITABLE",
                "The selected server node does not grant write access",
            ));
        }
        let client = self
            .state
            .clients
            .read()
            .await
            .get(&request.source)
            .cloned()
            .ok_or_else(|| {
                CapabilityError::new(
                    CapabilityErrorCode::SourceUnavailable,
                    "OPCUA_SOURCE_UNAVAILABLE",
                    "The selected OPC-UA source is not connected",
                )
            })?;
        client.write_node(&request.node_id, &request.value).await.map_err(|error| {
            tracing::warn!(source_id=%request.source,node_id=%request.node_id,code="opcua_write_failed",%error,"authorized OPC-UA write was rejected");
            CapabilityError::new(
                CapabilityErrorCode::OperationNotSupported,
                "OPCUA_WRITE_REJECTED",
                "The OPC-UA server rejected the requested value",
            )
        })?;
        Ok(NodeWriteResult {
            source: request.source,
            node_id: request.node_id,
            accepted: true,
        })
    }
}
impl CapabilityService for ApplicationServices {
    fn discover(&self, context: &ExecutionContext) -> Vec<CapabilityDescriptor> {
        if let Some(p) = &context.principal {
            if let Some(h) = &self.state.hierarchy() {
                return CapabilityId::ALL
                    .into_iter()
                    .filter(|id| {
                        if *id == CapabilityId::OpcuaSetup {
                            return h.plan.sites.iter().any(|site| {
                                crate::opcua_setup::authorize(h, p, &site.id)
                            });
                        }
                        if *id == CapabilityId::HueLightsRead {
                            return self.state.hue_profiles.keys().any(|source| {
                                crate::hue::visible_profile(&self.state, h, p, source).is_ok()
                            });
                        }
                        if matches!(
                            id,
                            CapabilityId::LicenseStatusRead
                                | CapabilityId::LicenseProofPreview
                                | CapabilityId::LicenseProofApply
                        ) {
                            return h.platform(p, *id);
                        }
                        !id.descriptor().mutating
                            && (h.platform(p, *id)
                                || (!matches!(
                                    id,
                                    CapabilityId::CoreHealthRead
                                        | CapabilityId::CoreLivenessRead
                                        | CapabilityId::CoreReadinessRead
                                        | CapabilityId::QueueRead
                                        | CapabilityId::SystemStatusRead
                                        | CapabilityId::SnapshotRead
                                        | CapabilityId::McpManagementRead
                                ) && h
                                    .plan
                                    .bindings
                                    .iter()
                                    .filter(|b| &b.principal_id == p)
                                    .any(|b| h.permits(p, *id, &b.scope, false))))
                    })
                    .map(CapabilityId::descriptor)
                    .collect();
            }
            return Vec::new();
        }
        if !self.state.legacy_access {
            return Vec::new();
        }
        CapabilityId::ALL
            .into_iter()
            .filter(|id| {
                !matches!(
                    id,
                    CapabilityId::HueLightsRead
                        | CapabilityId::HueLightControl
                        | CapabilityId::HueSetup
                        | CapabilityId::OpcuaSetup
                        | CapabilityId::DeviceConnectionRead
                        | CapabilityId::DeviceConnectionConfigure
                        | CapabilityId::InventoryRead
                        | CapabilityId::InventoryPlanRead
                        | CapabilityId::InventoryChange
                        | CapabilityId::SettingsRead
                        | CapabilityId::McpManagementRead
                        | CapabilityId::SupportPackageRead
                        | CapabilityId::LicenseStatusRead
                        | CapabilityId::LicenseProofPreview
                        | CapabilityId::LicenseProofApply
                        | CapabilityId::SettingsChange
                        | CapabilityId::OrganizationsRead
                        | CapabilityId::InfrastructuresRead
                        | CapabilityId::SitesRead
                        | CapabilityId::ScopedSnapshotRead
                ) && id
                    .descriptor()
                    .permission
                    .iter()
                    .all(|p| context.permissions.contains(p))
            })
            .map(CapabilityId::descriptor)
            .collect()
    }
    fn execute<'a>(
        &'a self,
        context: &'a ExecutionContext,
        request: CapabilityRequest,
    ) -> std::pin::Pin<
        Box<
            dyn std::future::Future<Output = Result<CapabilityOutput, CapabilityError>> + Send + 'a,
        >,
    > {
        Box::pin(async move {
            if self.state.hierarchy().is_none() {
                if let CapabilityRequest::InventoryRead(q) = &request {
                    let result = self.inventory_read(context, q.clone());
                    self.audit.record(&self.audit_event(
                        context,
                        request.id(),
                        None,
                        result.is_ok(),
                        if result.is_ok() {
                            "bootstrap_status"
                        } else {
                            "denied"
                        },
                    ))?;
                    return result;
                }
            }

            if self.state.hierarchy().is_some() && context.principal.is_some() {
                return self.execute_tenant(context, request).await;
            }
            if !self.state.legacy_access {
                return Err(denied());
            }
            let id = request.id();
            if matches!(&request,CapabilityRequest::SourcesRead(q)|CapabilityRequest::EventsRead(q)|CapabilityRequest::ObservationsRead(q) if q.organization.is_some()||q.infrastructure.is_some()||q.site.is_some())
            {
                self.audit.record(&self.audit_event(
                    context,
                    id,
                    None,
                    false,
                    "unsupported_hierarchy_without_principal",
                ))?;
                return Err(CapabilityError::new(
                    CapabilityErrorCode::OperationNotSupported,
                    "HIERARCHY_REQUIRES_PRINCIPAL",
                    "Hierarchy filters require a bound principal",
                ));
            }
            let source = self.source_for(&request);
            if id == CapabilityId::SimulationScenarioSet && self.state.scenario_tx.is_none() {
                let _ = self.audit.record(&self.audit_event(
                    context,
                    id,
                    source.as_ref(),
                    false,
                    "unsupported",
                ));
                return Err(CapabilityError::new(
                    CapabilityErrorCode::OperationNotSupported,
                    "DEMO_DISABLED",
                    "Start with --demo to enable local simulation controls",
                ));
            }
            if let Err(error) = context.authorize(id, source.as_ref()) {
                let _ = self.audit.record(&self.audit_event(
                    context,
                    id,
                    source.as_ref(),
                    false,
                    "denied",
                ));
                return Err(error);
            }
            // Simulation is the sole external mutation in OIP-005. Audit failure
            // before dispatch fails closed; no side effect has occurred.
            if id.descriptor().mutating {
                self.audit.record(&self.audit_event(
                    context,
                    id,
                    source.as_ref(),
                    true,
                    "started",
                ))?;
            }
            let mut interrupted = InterruptedExecution {
                sink: self.audit.clone(),
                event: Some(self.audit_event(context, id, source.as_ref(), true, "interrupted")),
            };
            let result = if let Some(q) = crate::diagnostic_services::query(&request) {
                self.diagnostic_read(context, id, q.clone()).await
            } else {
                self.run(request).await
            };
            interrupted.event = None;
            let outcome = if result.is_ok() {
                "succeeded"
            } else {
                "failed"
            };
            // Failure here may follow an effect; callers must not blindly retry.
            self.audit
                .record(&self.audit_event(context, id, source.as_ref(), true, outcome))
                .map_err(|_|CapabilityError::new(CapabilityErrorCode::AuditUnavailable,"AUDIT_COMPLETION_UNCONFIRMED","Completion audit failed; an effect may have occurred; do not retry automatically"))?;
            result
        })
    }
}

#[path = "tenant_services.rs"]
mod tenant_services;
