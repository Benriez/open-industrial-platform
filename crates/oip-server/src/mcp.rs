//! Local read-only MCP adapter. No SQL, protocol client or domain policy lives here.
use oip_core::*;
use rmcp::{model::*, service::RequestContext, ErrorData, RoleServer, ServerHandler};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{
    collections::BTreeSet,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc,
    },
    time::Duration,
};
use tokio_util::sync::CancellationToken;

#[cfg(unix)]
pub mod ipc;
pub mod transport;
pub const MAX_INPUT: usize = 16 * 1024;
pub const MAX_OUTPUT: usize = 4 * 1024 * 1024;
pub const MAX_REQUESTS: usize = 16;
pub const READ_TIMEOUT: Duration = Duration::from_secs(15);

/// Trusted local startup file, never accepted as a tool argument. No implicit grants.
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct McpPolicy {
    #[serde(default)]
    pub principal: Option<PrincipalId>,
    #[serde(default)]
    pub actor: String,
    #[serde(default)]
    pub permissions: BTreeSet<Permission>,
    #[serde(default = "empty_scope")]
    pub sources: SourceScope,
}
fn empty_scope() -> SourceScope {
    SourceScope::Only(BTreeSet::new())
}
impl McpPolicy {
    pub fn validate(&self) -> Result<(), &'static str> {
        if self.principal.is_some() {
            if !self.actor.is_empty()
                || !self.permissions.is_empty()
                || !matches!(&self.sources,SourceScope::Only(ids) if ids.is_empty())
            {
                return Err("principal policies cannot carry legacy actor/grants/scopes");
            }
            return Ok(());
        }
        let safe = |v: &str| {
            !v.is_empty()
                && v.len() <= 128
                && v.bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b"-_.:".contains(&b))
        };
        if !safe(&self.actor) || self.permissions.contains(&Permission::SimulationControl) {
            return Err("MCP policy requires a safe local actor and read-only permissions");
        }
        if let SourceScope::Only(ids) = &self.sources {
            if ids.len() > 32 || ids.iter().any(|id| !safe(id.as_str())) {
                return Err("Invalid local MCP source scope");
            }
        }
        Ok(())
    }
    pub fn execution_context(&self) -> ExecutionContext {
        static NEXT: AtomicU64 = AtomicU64::new(1);
        ExecutionContext {
            principal: self.principal.clone(),
            actor: self
                .principal
                .as_ref()
                .map_or_else(|| self.actor.clone(), ToString::to_string),
            correlation_id: format!(
                "mcp-{}-{}",
                std::process::id(),
                NEXT.fetch_add(1, Ordering::Relaxed)
            ),
            permissions: self.permissions.clone(),
            sources: self.sources.clone(),
        }
    }
}
#[derive(Clone)]
pub struct McpAdapter {
    service: Arc<dyn CapabilityService>,
    policy: McpPolicy,
}
#[derive(Clone, Copy)]
struct ToolSpec {
    name: &'static str,
    id: CapabilityId,
    description: &'static str,
}
const TOOLS: [ToolSpec; 20] = [
    ToolSpec{name:"oip_inventory_read",id:CapabilityId::InventoryRead,description:"Read authorized persistent device inventory, metadata and collector availability. No collector does not mean offline; bounded pagination."},
    ToolSpec{name:"oip_inventory_plan_read",id:CapabilityId::InventoryPlanRead,description:"Validate a bounded inventory change plan against current permissions and revisions. Read-only; never applies changes or grants permissions."},
    ToolSpec{name:"oip_settings_read",id:CapabilityId::SettingsRead,description:"Read authorized typed setting definitions or effective startup values at an explicit scope; no mutation or credential access."},
    ToolSpec{name:"oip_mcp_management_read",id:CapabilityId::McpManagementRead,description:"Platform-authorized MCP/system management information. Read-only; missing session telemetry and unsupported controls are explicit."},
    ToolSpec {name:"oip_event_history_read",id:CapabilityId::EventHistoryRead,description:"Authorized bounded historical event history; stable persisted evidence, no inferred root cause. Time range uses Unix milliseconds; continuation cursor is principal/query bound and expires after five minutes."},
    ToolSpec {name:"oip_event_detail_read",id:CapabilityId::EventDetailRead,description:"Authorized bounded historical event detail; stable persisted evidence, no inferred root cause. Time range uses Unix milliseconds; continuation cursor is principal/query bound and expires after five minutes."},
    ToolSpec {name:"oip_data_gaps_read",id:CapabilityId::DataGapsRead,description:"Authorized bounded historical data gaps; stable persisted evidence, no inferred root cause. Time range uses Unix milliseconds; continuation cursor is principal/query bound and expires after five minutes."},
    ToolSpec {name:"oip_source_health_history_read",id:CapabilityId::SourceHealthHistoryRead,description:"Authorized bounded historical source health history; stable persisted evidence, no inferred root cause. Time range uses Unix milliseconds; continuation cursor is principal/query bound and expires after five minutes."},
    ToolSpec {name:"oip_evidence_read",id:CapabilityId::EvidenceRead,description:"Authorized bounded historical evidence; stable persisted evidence, no inferred root cause. Time range uses Unix milliseconds; continuation cursor is principal/query bound and expires after five minutes."},
    ToolSpec {name:"oip_diagnostic_findings_read",id:CapabilityId::DiagnosticFindingsRead,description:"Authorized bounded historical diagnostic findings; stable persisted evidence, no inferred root cause. Time range uses Unix milliseconds; continuation cursor is principal/query bound and expires after five minutes."},
    ToolSpec {name:"oip_observation_history_read",id:CapabilityId::ObservationHistoryRead,description:"Authorized bounded historical observation history; stable persisted evidence, no inferred root cause. Time range uses Unix milliseconds; continuation cursor is principal/query bound and expires after five minutes."},
    ToolSpec {name:"oip_organizations_read",id:CapabilityId::OrganizationsRead,description:"Discover only authorized organizations and ancestor labels, bounded pagination."},
    ToolSpec {name:"oip_infrastructures_read",id:CapabilityId::InfrastructuresRead,description:"List authorized infrastructures; parent IDs never grant access."},
    ToolSpec {name:"oip_sites_read",id:CapabilityId::SitesRead,description:"List authorized sites with validated parent filters, bounded pagination."},
    ToolSpec { name: "oip_devices_read", id: CapabilityId::DevicesRead, description: "List/search registered devices; source scope and authoritative health are preserved. Bounded current registry, not discovery of remote endpoints." },
    ToolSpec { name: "oip_device_read", id: CapabilityId::DeviceRead, description: "Read a device by its exact registry ID, with current source-specific observations." },
    ToolSpec { name: "oip_observations_read", id: CapabilityId::ObservationsRead, description: "Read current observations with source/entity, quality, freshness, timestamps and simulation provenance; not historical replay." },
    ToolSpec { name: "oip_sources_read", id: CapabilityId::SourcesRead, description: "Read registered source health, preserving connection, reachability, service, validity and freshness as separate fields." },
    ToolSpec { name: "oip_events_read", id: CapabilityId::EventsRead, description: "Read the last 100 persisted control events, source context, sequences and data gaps; no complete history/replay. Diagnostics fixtures are labeled." },
    ToolSpec { name: "oip_opcua_nodes_read", id: CapabilityId::OpcuaNodesRead, description: "Browse/read existing registered simulation nodes. Offset pagination, max 100 nodes, no arbitrary endpoint or device writes. Read samples use normal core ingestion." },
];
const RESOURCES: [(&str, CapabilityId); 7] = [
    (
        "oip://v2/snapshot/current",
        CapabilityId::ScopedSnapshotRead,
    ),
    ("oip://v1/core/health", CapabilityId::CoreHealthRead),
    ("oip://v1/core/liveness", CapabilityId::CoreLivenessRead),
    ("oip://v1/core/readiness", CapabilityId::CoreReadinessRead),
    ("oip://v1/core/queue", CapabilityId::QueueRead),
    ("oip://v1/system/status", CapabilityId::SystemStatusRead),
    ("oip://v1/snapshot/current", CapabilityId::SnapshotRead),
];
fn input_schema(id: CapabilityId) -> Value {
    let mut v = match id {
        CapabilityId::InventoryRead => serde_json::to_value(schemars::schema_for!(InventoryQuery)),
        CapabilityId::InventoryPlanRead => {
            serde_json::to_value(schemars::schema_for!(InventoryPlanQuery))
        }
        CapabilityId::SettingsRead => serde_json::to_value(schemars::schema_for!(SettingsQuery)),
        CapabilityId::McpManagementRead => {
            serde_json::to_value(schemars::schema_for!(ManagementQuery))
        }
        CapabilityId::EventHistoryRead
        | CapabilityId::EventDetailRead
        | CapabilityId::DataGapsRead
        | CapabilityId::SourceHealthHistoryRead
        | CapabilityId::EvidenceRead
        | CapabilityId::DiagnosticFindingsRead
        | CapabilityId::ObservationHistoryRead => {
            serde_json::to_value(schemars::schema_for!(DiagnosticQuery))
        }
        CapabilityId::OrganizationsRead
        | CapabilityId::InfrastructuresRead
        | CapabilityId::SitesRead => serde_json::to_value(schemars::schema_for!(HierarchyQuery)),
        CapabilityId::DevicesRead => serde_json::to_value(schemars::schema_for!(DeviceQuery)),
        CapabilityId::DeviceRead => serde_json::to_value(schemars::schema_for!(DeviceRequest)),
        CapabilityId::OpcuaNodesRead => serde_json::to_value(schemars::schema_for!(NodeQuery)),
        _ => serde_json::to_value(schemars::schema_for!(SourceQuery)),
    }
    .expect("static serializable schema");
    if let Some(props) = v.get_mut("properties").and_then(Value::as_object_mut) {
        for (name, p) in props {
            match name.as_str() {
                "start_ms" | "end_ms" => {
                    p["minimum"] = json!(-11644473600000_i64);
                    p["maximum"] = json!(253402300799999_i64);
                }
                "metric" => {
                    *p = json!({"type":["string","null"],"minLength":1,"maxLength":128});
                }
                "event_id" | "cursor" => {
                    *p = json!({"type":["string","null"],"minLength":64,"maxLength":64,"pattern":"^[a-f0-9]{64}$"});
                }
                "source" => {
                    *p = json!({"type":["string","null"],"minLength":1,"maxLength":128,"pattern":"^[A-Za-z0-9_.-]+$"});
                }
                "q" | "location" | "folder" | "id" => {
                    p["maxLength"] = json!(256);
                    if name == "id" {
                        p["minLength"] = json!(1);
                    }
                }
                "offset" => {
                    p["maximum"] = json!(1_000_000);
                }
                "limit" => {
                    p["minimum"] = json!(1);
                    p["maximum"] = json!(100);
                }
                _ => {}
            }
        }
    }
    use CapabilityId::*;
    if matches!(
        id,
        EventHistoryRead
            | EventDetailRead
            | DataGapsRead
            | SourceHealthHistoryRead
            | EvidenceRead
            | DiagnosticFindingsRead
            | ObservationHistoryRead
    ) {
        let props = v["properties"].as_object_mut().expect("query object");
        if id != ObservationHistoryRead {
            props.remove("metric");
        }
        if !matches!(id, EventHistoryRead | EventDetailRead | EvidenceRead) {
            props.remove("event_id");
            props.remove("event_type");
        }
        if matches!(id, EventDetailRead | EvidenceRead) {
            props.remove("cursor");
        }
        if id == EventDetailRead {
            props.get_mut("event_id").unwrap()["type"] = json!("string");
            v["required"] = json!(["event_id"]);
        } else if id == EvidenceRead {
            props.remove("event_type");
            props.get_mut("limit").unwrap()["minimum"] = json!(4);
            for name in ["start_ms", "end_ms"] {
                props.get_mut(name).unwrap()["type"] = json!("integer");
            }
            v["required"] = json!(["start_ms", "end_ms"]);
            v["anyOf"] = json!([{"required":["source"],"properties":{"source":{"type":"string"}}},{"required":["event_id"],"properties":{"event_id":{"type":"string"}}}]);
        }
    }

    v
}
fn invalid() -> ErrorData {
    ErrorData::invalid_params("Invalid bounded tool arguments; see inputSchema", None)
}
fn parse_request(spec: ToolSpec, args: Value) -> Result<CapabilityRequest, ErrorData> {
    if serde_json::to_vec(&args).map_err(|_| invalid())?.len() > MAX_INPUT {
        return Err(invalid());
    }
    let obj = args.as_object().ok_or_else(invalid)?;
    for (key, value) in obj {
        if let Some(s) = value.as_str() {
            let max = if key == "source" { 128 } else { 256 };
            if s.len() > max
                || (key == "id" && s.is_empty())
                || (key == "source"
                    && (s.is_empty()
                        || !s
                            .bytes()
                            .all(|b| b.is_ascii_alphanumeric() || b"-_.".contains(&b))))
            {
                return Err(invalid());
            }
        }
    }
    for (key, min, max) in [("offset", 0, 1_000_000), ("limit", 1, 100)] {
        if let Some(v) = obj.get(key).filter(|v| !v.is_null()) {
            if !v.as_u64().is_some_and(|n| (min..=max).contains(&n)) {
                return Err(invalid());
            }
        }
    }
    let body = json!({"capability":spec.id,"input":args});
    serde_json::from_value(body).map_err(|_| invalid())
}
fn unit_request(id: CapabilityId) -> CapabilityRequest {
    serde_json::from_value(json!({"capability":id})).expect("unit read capability")
}
fn output_schema(id: CapabilityId) -> Value {
    let tag = match id {
        CapabilityId::InventoryRead => "inventory",
        CapabilityId::InventoryPlanRead | CapabilityId::InventoryChange => "inventory_plan",
        CapabilityId::SettingsRead => "settings",
        CapabilityId::McpManagementRead => "management",
        CapabilityId::SettingsChange => "settings_changed",
        CapabilityId::EvidenceRead => "evidence",
        CapabilityId::EventHistoryRead
        | CapabilityId::EventDetailRead
        | CapabilityId::DataGapsRead
        | CapabilityId::SourceHealthHistoryRead
        | CapabilityId::DiagnosticFindingsRead
        | CapabilityId::ObservationHistoryRead => "diagnostic_page",
        CapabilityId::OrganizationsRead => "organizations",
        CapabilityId::InfrastructuresRead => "infrastructures",
        CapabilityId::SitesRead => "sites",
        CapabilityId::ScopedSnapshotRead => "scoped_snapshot",
        CapabilityId::DevicesRead => "devices",
        CapabilityId::DeviceRead => "device",
        CapabilityId::ObservationsRead => "observations",
        CapabilityId::SourcesRead => "sources",
        CapabilityId::EventsRead => "events",
        CapabilityId::OpcuaNodesRead => "nodes",
        CapabilityId::QueueRead => "queue",
        CapabilityId::SystemStatusRead => "system_status",
        CapabilityId::SnapshotRead => "snapshot",
        CapabilityId::SimulationScenarioSet => "scenario",
        _ => "core_health",
    };
    let generated = serde_json::to_value(schemars::schema_for!(CapabilityOutput)).expect("schema");
    let mut root = generated["oneOf"]
        .as_array()
        .expect("tagged schema")
        .iter()
        .find(|v| v["properties"]["type"]["const"] == tag)
        .expect("output variant")
        .clone();
    root["$schema"] = generated["$schema"].clone();
    fn refs(v: &Value, used: &mut BTreeSet<String>) {
        match v {
            Value::Object(m) => {
                if let Some(name) = m
                    .get("$ref")
                    .and_then(Value::as_str)
                    .and_then(|r| r.strip_prefix("#/$defs/"))
                {
                    used.insert(name.into());
                }
                for x in m.values() {
                    refs(x, used);
                }
            }
            Value::Array(a) => {
                for x in a {
                    refs(x, used);
                }
            }
            _ => {}
        }
    }
    let mut used = BTreeSet::new();
    refs(&root, &mut used);
    loop {
        let old = used.len();
        for key in used.clone() {
            refs(&generated["$defs"][key], &mut used);
        }
        if used.len() == old {
            break;
        }
    }
    let defs = used
        .into_iter()
        .map(|key| {
            let value = generated["$defs"][&key].clone();
            (key, value)
        })
        .collect::<serde_json::Map<_, _>>();
    root["$defs"] = Value::Object(defs);
    root
}
/// Operator/test catalog, derived from the same allowlist as runtime discovery.
/// It is not an MCP tool and never grants permissions.
pub fn capability_mapping() -> Value {
    static CACHE: std::sync::OnceLock<Value> = std::sync::OnceLock::new();
    CACHE.get_or_init(|| json!({"protocol":"2026-07-28","legacy_protocol":"2025-11-25","sdk":"rmcp 3.8.0","capabilities":CapabilityId::ALL.into_iter().map(|id| {
        let tool=TOOLS.iter().find(|t|t.id==id);
        let resource=RESOURCES.iter().find(|(_,c)|*c==id).map(|(uri,_)|*uri);
        json!({"capability":id,"core_status":if matches!(id,CapabilityId::SettingsChange|CapabilityId::InventoryChange) {"OFFLINE_OPERATOR_ONLY"}else{"IMPLEMENTED"},"rest":!matches!(id,CapabilityId::SettingsChange|CapabilityId::InventoryChange),"mcp_status":if id.descriptor().mutating {"BLOCKED"}else{"IMPLEMENTED"},"tool":tool.map(|t|t.name),"resource":resource,"source_resource":if id==CapabilityId::SourcesRead {Some("oip://v1/sources/{id}/health")}else{None},"permissions":id.descriptor().permission,"input_schema":tool.map(|_|input_schema(id)),"output_schema":if id.descriptor().mutating {None}else{Some(output_schema(id))},"test":"crates/oip-server/tests/mcp.rs"})
    }).collect::<Vec<_>>()})).clone()
}
fn bounded(output: CapabilityOutput) -> Result<Value, ErrorData> {
    let bytes = serde_json::to_vec(&output)
        .map_err(|_| ErrorData::internal_error("Output encoding failed", None))?;
    if bytes.len() > MAX_OUTPUT {
        return Err(ErrorData::internal_error(
            "Output limit exceeded; narrow the source or query",
            None,
        ));
    }
    serde_json::from_slice(&bytes)
        .map_err(|_| ErrorData::internal_error("Output encoding failed", None))
}
impl McpAdapter {
    pub fn new(
        service: Arc<dyn CapabilityService>,
        policy: McpPolicy,
    ) -> Result<Self, &'static str> {
        policy.validate()?;
        Ok(Self { service, policy })
    }
    fn visible(&self, id: CapabilityId, source: Option<&DataSourceId>) -> bool {
        if self.policy.principal.is_some() {
            self.service
                .discover(&self.policy.execution_context())
                .iter()
                .any(|d| d.id == id)
        } else {
            self.service
                .discover(&self.policy.execution_context())
                .iter()
                .any(|d| d.id == id)
                && self
                    .policy
                    .execution_context()
                    .authorize(id, source)
                    .is_ok()
        }
    }
    pub fn tools(&self) -> Vec<Tool> {
        TOOLS
            .iter()
            .filter(|s| {
                self.service
                    .discover(&self.policy.execution_context())
                    .iter()
                    .any(|d| d.id == s.id)
            })
            .map(|s| {
                let mut tool = Tool::new(
                    s.name,
                    s.description,
                    input_schema(s.id).as_object().unwrap().clone(),
                );
                tool.output_schema =
                    Some(Arc::new(output_schema(s.id).as_object().unwrap().clone()));
                tool.annotations = Some(ToolAnnotations::from_raw(
                    None,
                    Some(true),
                    Some(false),
                    Some(true),
                    Some(false),
                ));
                tool
            })
            .collect()
    }
    pub fn resources(&self) -> Vec<Resource> {
        RESOURCES
            .iter()
            .filter(|(_, id)| self.visible(*id, None))
            .map(|(uri, id)| {
                Resource::new(*uri, serde_json::to_value(id).unwrap().as_str().unwrap())
                    .with_mime_type("application/json")
            })
            .collect()
    }
    pub async fn resource_list(
        &self,
        cancel: CancellationToken,
    ) -> Result<Vec<Resource>, ErrorData> {
        let mut resources = self.resources();
        if self
            .service
            .discover(&self.policy.execution_context())
            .iter()
            .any(|d| d.id == CapabilityId::SourcesRead)
        {
            let sources = if self.policy.principal.is_some() {
                vec![None]
            } else {
                match &self.policy.sources {
                    SourceScope::All => vec![None],
                    SourceScope::Only(ids) => ids.iter().cloned().map(Some).collect(),
                }
            };
            for source in sources {
                if let Ok(value) = self
                    .execute(
                        CapabilityRequest::SourcesRead(SourceQuery {
                            source,
                            ..Default::default()
                        }),
                        cancel.clone(),
                    )
                    .await?
                {
                    // Typed service result; no independent source registry.
                    if let CapabilityOutput::Sources(sources) = serde_json::from_value(value)
                        .map_err(|_| ErrorData::internal_error("Source contract mismatch", None))?
                    {
                        resources.extend(sources.into_iter().map(|s| {
                            Resource::new(
                                format!("oip://v1/sources/{}/health", s.id),
                                "source_health",
                            )
                            .with_mime_type("application/json")
                        }));
                    }
                }
            }
        }
        Ok(resources)
    }
    async fn execute(
        &self,
        request: CapabilityRequest,
        cancel: CancellationToken,
    ) -> Result<Result<Value, CapabilityError>, ErrorData> {
        let ctx = self.policy.execution_context();
        // Scope is trusted policy data, not tool payload. Existing audit records the decision/result.
        tracing::info!(actor=%ctx.actor,correlation_id=%ctx.correlation_id,source_scope=?ctx.sources,capability=?request.id(),code="mcp_dispatch","local read request");
        tokio::select! {
            biased;
            _=cancel.cancelled()=> {tracing::info!(correlation_id=%ctx.correlation_id,code="mcp_cancelled","read cancelled");Err(ErrorData::internal_error("Request cancelled",None))},
            result=tokio::time::timeout(READ_TIMEOUT,self.service.execute(&ctx,request))=> match result {
                Ok(Ok(value))=>bounded(value).map(Ok),
                Ok(Err(error))=>Ok(Err(error)),
                Err(_)=> {tracing::warn!(correlation_id=%ctx.correlation_id,code="mcp_timeout","read deadline exceeded");Err(ErrorData::internal_error("Read deadline exceeded",None))},
            }
        }
    }
    pub async fn invoke(
        &self,
        name: &str,
        args: Value,
        cancel: CancellationToken,
    ) -> Result<CallToolResult, ErrorData> {
        let rejected = |capability: &str, outcome: &str| {
            let context = self.policy.execution_context();
            tracing::warn!(actor=%context.actor,correlation_id=%context.correlation_id,source_scope=?context.sources,capability,target="untrusted_input_redacted",authorized=false,outcome,code="mcp_rejected","MCP boundary rejected request");
        };
        let Some(spec) = TOOLS.iter().find(|s| s.name == name) else {
            rejected("not_supported", "unsupported_tool");
            return Err(ErrorData::method_not_found::<CallToolRequestMethod>());
        };
        let request = parse_request(*spec, args).inspect_err(|_| {
            rejected(spec.name, "invalid_input");
        })?;
        match self.execute(request, cancel).await? {
            Ok(value) => Ok(CallToolResult::structured(value)),
            Err(error) => Ok(CallToolResult::structured_error(
                serde_json::to_value(error).unwrap(),
            )),
        }
    }
    pub async fn resource(
        &self,
        uri: &str,
        cancel: CancellationToken,
    ) -> Result<ReadResourceResult, ErrorData> {
        let request = if let Some((_, id)) = RESOURCES.iter().find(|(u, _)| *u == uri) {
            unit_request(*id)
        } else if let Some(id) = uri
            .strip_prefix("oip://v1/sources/")
            .and_then(|v| v.strip_suffix("/health"))
        {
            if id.is_empty()
                || id.len() > 128
                || !id
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b"-_.".contains(&b))
            {
                return Err(invalid());
            }
            CapabilityRequest::SourcesRead(SourceQuery {
                source: Some(DataSourceId::new(id).map_err(|_| invalid())?),
                ..Default::default()
            })
        } else {
            return Err(ErrorData::resource_not_found("Unknown OIP resource", None));
        };
        match self.execute(request, cancel).await? {
            Ok(value) => Ok(ReadResourceResult::new(vec![ResourceContents::text(
                value.to_string(),
                uri,
            )])
            .with_ttl_ms(0)
            .with_cache_scope(CacheScope::Private)),
            Err(error) => Err(ErrorData::new(
                ErrorCode(-32001),
                "OIP capability failed",
                Some(serde_json::to_value(error).unwrap()),
            )),
        }
    }
}
impl ServerHandler for McpAdapter {
    fn get_info(&self) -> ServerConfig {
        ServerConfig::new(
            ServerCapabilities::builder()
                .enable_tools()
                .enable_resources()
                .build(),
        )
        .with_server_info(Implementation::new(
            "oip-local-read",
            env!("CARGO_PKG_VERSION"),
        ))
    }
    async fn list_tools(
        &self,
        _: Option<PaginatedRequestParams>,
        _: RequestContext<RoleServer>,
    ) -> Result<ListToolsResult, ErrorData> {
        Ok(ListToolsResult::with_all_items(self.tools()))
    }
    async fn call_tool(
        &self,
        request: CallToolRequestParams,
        context: RequestContext<RoleServer>,
    ) -> Result<CallToolResponse, ErrorData> {
        self.invoke(
            &request.name,
            Value::Object(request.arguments.unwrap_or_default()),
            context.ct,
        )
        .await
        .map(Into::into)
    }
    async fn list_resources(
        &self,
        _: Option<PaginatedRequestParams>,
        ctx: RequestContext<RoleServer>,
    ) -> Result<ListResourcesResult, ErrorData> {
        Ok(ListResourcesResult::with_all_items(
            self.resource_list(ctx.ct).await?,
        ))
    }
    async fn read_resource(
        &self,
        request: ReadResourceRequestParams,
        context: RequestContext<RoleServer>,
    ) -> Result<ReadResourceResponse, ErrorData> {
        self.resource(&request.uri, context.ct)
            .await
            .map(Into::into)
    }
}

pub fn tool_description(id: CapabilityId) -> &'static str {
    TOOLS
        .iter()
        .find(|t| t.id == id)
        .map_or("", |t| t.description)
}
