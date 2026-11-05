//! Canonical application queries and simulation control. Axum and future MCP are adapters.
use crate::{
    collector::METRICS,
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
        tracing::info!(actor=%event.actor,capability=?event.capability,target=%event.target,
            at_ms=event.at_ms,authorized=event.authorized,outcome=%event.outcome,
            correlation_id=%event.correlation_id,code="capability_execution","local development audit (not durable)");
        Ok(())
    }
}
#[derive(Clone)]
pub struct ApplicationServices {
    state: AppState,
    audit: Arc<dyn CapabilityAudit>,
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
        Self {
            state,
            audit: Arc::new(LocalLogAudit),
        }
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
        ]
        .into_iter()
        .collect::<std::collections::BTreeSet<_>>();
        if self.state.scenario_tx.is_some() {
            permissions.insert(Permission::SimulationControl);
        }
        ExecutionContext {
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
        match request {
            CapabilityRequest::SourcesRead(q)
            | CapabilityRequest::ObservationsRead(q)
            | CapabilityRequest::EventsRead(q) => q.source.clone(),
            CapabilityRequest::DevicesRead(q) => q.source.clone(),
            CapabilityRequest::OpcuaNodesRead(q) => {
                Some(q.source.clone().unwrap_or(self.state.primary.clone()))
            }
            CapabilityRequest::DeviceRead(q) => {
                self.state
                    .snapshot()
                    .ok()?
                    .devices
                    .into_iter()
                    .find(|d| d.id == q.id)?
                    .data_source_id
            }
            CapabilityRequest::SimulationScenarioSet(_) => Some(self.state.primary.clone()),
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
            actor: if safe(&context.actor) {
                context.actor.clone()
            } else {
                "invalid-context".into()
            },
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
                            && q.id
                                .split_once(':')
                                .map_or(q.id.as_str(), |(_, entity)| entity)
                                == m.entity_id.as_str()
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
        let source = q.source.unwrap_or(s.primary.clone());
        if !s.view().sources.iter().any(|v| v.id == source) {
            return Err(CapabilityError::new(
                CapabilityErrorCode::ResourceNotFound,
                "SOURCE_NOT_FOUND",
                "Source not registered",
            ));
        }
        let catalog = s
            .catalogs
            .read()
            .await
            .get(&source)
            .cloned()
            .unwrap_or_default();
        let mut found: Vec<_> = catalog
            .into_iter()
            .filter_map(|entry| {
                let name = entry.node_id.split(";s=").nth(1)?.to_owned();
                if !METRICS.contains(&name.as_str()) && !name.starts_with("bulk.") {
                    return None;
                }
                let folder = if name.starts_with("bulk.") {
                    "Bulk"
                } else {
                    "M-01"
                };
                if q.folder.as_ref().is_some_and(|f| f != "all" && f != folder)
                    || !name.to_lowercase().contains(&search)
                {
                    return None;
                }
                Some((entry.node_id, name, folder.to_owned()))
            })
            .collect();
        found.sort_by(|a, b| a.1.cmp(&b.1));
        let total = found.len();
        let selected: Vec<_> = found.into_iter().skip(offset).take(limit).collect();
        let client = s.clients.read().await.get(&source).cloned();
        let items = stream::iter(selected)
            .map(|(node_id, name, folder)| {
                let client = client.clone();
                let s = s.clone();
                let source = source.clone();
                async move {
                    let observation = if let Some(client) = client {
                        match client
                            .read(&MetricId::new(&name).expect("browsed nonempty id"))
                            .await
                        {
                            Ok(mut o) => {
                                o.data_source_id = source.clone();
                                s.ingest_for(
                                    &source,
                                    ClientEvent::Observation(Box::new(o.clone())),
                                )
                                .await
                                .map_err(storage)?;
                                Some(o)
                            }
                            Err(_) => None,
                        }
                    } else {
                        None
                    };
                    let data_type = match name.as_str() {
                        "motor_running" | "alarm_active" => "Boolean",
                        "operating_mode" => "String",
                        "units_produced" => "UInt64",
                        _ => "Double",
                    }
                    .into();
                    Ok(Node {
                        node_id,
                        name,
                        namespace: 2,
                        folder,
                        data_type,
                        access: "Read".into(),
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
        })
    }
}
impl CapabilityService for ApplicationServices {
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
            let id = request.id();
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
            let result = self.run(request).await;
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
