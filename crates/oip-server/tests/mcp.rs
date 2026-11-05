use axum::{
    body::{to_bytes, Body},
    http::Request,
};
use oip_core::*;
use oip_server::{
    api,
    application_services::ApplicationServices,
    config::{CoreConfig, SourceConfig},
    mcp::{transport::BoundedTransport, McpAdapter, McpPolicy},
    state::AppState,
};
use oip_storage::SqliteStore;
use rmcp::{
    model::*,
    service::{ClientLifecycleMode, ClientServiceExt},
    ServiceExt,
};
use serde_json::{json, Value};
use std::{sync::Arc, time::Duration};
use tokio_util::sync::CancellationToken;
use tower::ServiceExt as _;
fn policy() -> McpPolicy {
    serde_json::from_str(include_str!("../../../examples/mcp-read-local.json")).unwrap()
}
fn ctx(p: &McpPolicy) -> ExecutionContext {
    ExecutionContext {
        principal: None,
        actor: p.actor.clone(),
        correlation_id: "parity-1".into(),
        permissions: p.permissions.clone(),
        sources: p.sources.clone(),
    }
}
fn state() -> AppState {
    let config = CoreConfig {
        legacy_single_infrastructure: true,
        sources: vec![
            SourceConfig {
                id: "sim-a".into(),
                name: "A".into(),
                endpoint: "opc.tcp://127.0.0.1:15841".into(),
                namespace: 2,
            },
            SourceConfig {
                id: "sim-b".into(),
                name: "B".into(),
                endpoint: "opc.tcp://127.0.0.1:15842".into(),
                namespace: 2,
            },
        ],
        ..Default::default()
    };
    AppState::configured(SqliteStore::open_in_memory().unwrap(), &config, None).unwrap()
}
async fn rest(s: AppState, svc: Arc<ApplicationServices>, p: &McpPolicy, path: &str) -> Value {
    let response = api::router_with_service(s, svc, Some(ctx(p)), None)
        .oneshot(
            Request::builder()
                .uri(path)
                .header("host", "127.0.0.1:8080")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    serde_json::from_slice(
        &to_bytes(response.into_body(), 8 * 1024 * 1024)
            .await
            .unwrap(),
    )
    .unwrap()
}
#[tokio::test]
async fn all_six_tools_have_real_sdk_direct_and_rest_parity_and_generated_schemas() {
    let s = state();
    s.started().await.unwrap();
    for id in ["sim-a", "sim-b"] {
        let source = DataSourceId::new(id).unwrap();
        s.connected(&source).await.unwrap();
        for mut o in oip_simulator::Simulation::new(
            oip_simulator::SimulationConfig::default(),
            oip_simulator::Scenario::Normal,
        )
        .frame_at(0)
        .observations
        {
            o.data_source_id = source.clone();
            s.ingest_for(&source, ClientEvent::Observation(Box::new(o)))
                .await
                .unwrap();
        }
    }
    let svc = Arc::new(ApplicationServices::new(s.clone()));
    let p = policy();
    let adapter = McpAdapter::new(svc.clone(), p.clone()).unwrap();
    let (a, b) = tokio::io::duplex(65536);
    let server =
        tokio::spawn(async move { adapter.serve(a).await.unwrap().waiting().await.unwrap() });
    let client = ()
        .serve_with_lifecycle(
            b,
            ClientLifecycleMode::Discover {
                preferred_versions: vec![ProtocolVersion::V_2026_07_28],
            },
        )
        .await
        .unwrap();
    assert_eq!(
        client.peer().peer_info().unwrap().protocol_version,
        ProtocolVersion::V_2026_07_28
    );
    let tools = client.peer().list_all_tools().await.unwrap();
    assert_eq!(tools.len(), 13);
    let cases = [
        (
            "oip_devices_read",
            json!({"source":"sim-a"}),
            "/api/v1/devices?source=sim-a",
            CapabilityRequest::DevicesRead(DeviceQuery {
                source: Some(DataSourceId::new("sim-a").unwrap()),
                ..Default::default()
            }),
        ),
        (
            "oip_device_read",
            json!({"id":"M-01"}),
            "/api/v1/devices/M-01",
            CapabilityRequest::DeviceRead(DeviceRequest { id: "M-01".into() }),
        ),
        (
            "oip_observations_read",
            json!({"source":"sim-b"}),
            "/api/v1/metrics/current?source=sim-b",
            CapabilityRequest::ObservationsRead(SourceQuery {
                source: Some(DataSourceId::new("sim-b").unwrap()),
                ..Default::default()
            }),
        ),
        (
            "oip_sources_read",
            json!({}),
            "/api/v1/sources",
            CapabilityRequest::SourcesRead(SourceQuery::default()),
        ),
        (
            "oip_events_read",
            json!({}),
            "/api/v1/events",
            CapabilityRequest::EventsRead(SourceQuery::default()),
        ),
        (
            "oip_opcua_nodes_read",
            json!({"source":"sim-a","offset":0,"limit":40}),
            "/api/v1/opcua/nodes?source=sim-a&offset=0&limit=40",
            CapabilityRequest::OpcuaNodesRead(NodeQuery {
                source: Some(DataSourceId::new("sim-a").unwrap()),
                offset: Some(0),
                limit: Some(40),
                ..Default::default()
            }),
        ),
    ];
    for (name, args, path, request) in cases {
        let direct = serde_json::to_value(svc.execute(&ctx(&p), request).await.unwrap()).unwrap();
        let wire = client
            .peer()
            .call_tool(
                CallToolRequestParams::new(name).with_arguments(args.as_object().unwrap().clone()),
            )
            .await
            .unwrap();
        let mcp = wire.structured_content.unwrap();
        assert_eq!(wire.is_error, Some(false));
        assert_eq!(direct, mcp, "{name}");
        assert_eq!(
            direct["value"],
            rest(s.clone(), svc.clone(), &p, path).await,
            "{name}"
        );
        let tool = tools.iter().find(|t| t.name == name).unwrap();
        let input = Value::Object((*tool.input_schema).clone());
        let output = Value::Object((**tool.output_schema.as_ref().unwrap()).clone());
        assert!(jsonschema::validator_for(&input).unwrap().is_valid(&args));
        assert!(jsonschema::validator_for(&output).unwrap().is_valid(&mcp));
    }
    for resource in client.peer().list_all_resources().await.unwrap() {
        let value = client
            .peer()
            .read_resource(ReadResourceRequestParams::new(resource.uri))
            .await
            .unwrap();
        assert!(!value.contents.is_empty());
    }
    client.cancel().await.unwrap();
    server.await.unwrap();
    assert!(s.shutdown().await.clean);
}
#[tokio::test]
async fn source_scope_permission_errors_and_resource_denials_match_rest() {
    let s = state();
    let svc = Arc::new(ApplicationServices::new(s.clone()));
    let mut p = policy();
    p.sources = SourceScope::Only([DataSourceId::new("sim-a").unwrap()].into());
    let adapter = McpAdapter::new(svc.clone(), p.clone()).unwrap();
    assert_eq!(
        adapter
            .resource_list(CancellationToken::new())
            .await
            .unwrap()
            .len(),
        1
    );
    for (name, args, path, request) in [
        (
            "oip_sources_read",
            json!({"source":"sim-b"}),
            "/api/v1/sources?source=sim-b",
            CapabilityRequest::SourcesRead(SourceQuery {
                source: Some(DataSourceId::new("sim-b").unwrap()),
                ..Default::default()
            }),
        ),
        (
            "oip_device_read",
            json!({"id":"sim-b:M-01"}),
            "/api/v1/devices/sim-b:M-01",
            CapabilityRequest::DeviceRead(DeviceRequest {
                id: "sim-b:M-01".into(),
            }),
        ),
    ] {
        let direct = svc.execute(&ctx(&p), request).await.unwrap_err();
        assert_eq!(direct.kind, CapabilityErrorCode::PermissionDenied);
        let wire = adapter
            .invoke(name, args, CancellationToken::new())
            .await
            .unwrap();
        assert_eq!(wire.is_error, Some(true));
        assert_eq!(
            wire.structured_content.as_ref().unwrap()["kind"],
            json!(direct.kind)
        );
        assert_eq!(
            rest(s.clone(), svc.clone(), &p, path).await["kind"],
            json!(direct.kind)
        );
    }
    for uri in [
        "oip://v1/snapshot/current",
        "oip://v1/core/health",
        "oip://v1/sources/sim-b/health",
    ] {
        let e = adapter
            .resource(uri, CancellationToken::new())
            .await
            .unwrap_err();
        assert_eq!(e.data.unwrap()["kind"], "permission_denied");
    }
    p.permissions.clear();
    let adapter = McpAdapter::new(svc, p).unwrap();
    assert!(adapter.tools().is_empty());
    assert!(adapter.resources().is_empty());
    assert_eq!(
        adapter
            .invoke(
                "oip_sources_read",
                json!({"source":"sim-a"}),
                CancellationToken::new()
            )
            .await
            .unwrap()
            .is_error,
        Some(true)
    );
    assert!(s.shutdown().await.clean);
}
#[tokio::test]
async fn malformed_mutating_unknown_and_oversized_arguments_fail_closed() {
    let s = state();
    let adapter = McpAdapter::new(Arc::new(ApplicationServices::new(s.clone())), policy()).unwrap();
    for (name, args) in [
        ("oip_devices_read", json!({"actor":"admin"})),
        (
            "oip_devices_read",
            json!({"permissions":["simulation_control"]}),
        ),
        ("oip_devices_read", json!({"q":"x".repeat(257)})),
        ("oip_devices_read", json!({"source":"bad/source"})),
        ("oip_devices_read", json!({"q":["x"]})),
        ("oip_device_read", json!({"id":null})),
        ("oip_device_read", json!({"id":""})),
        ("oip_opcua_nodes_read", json!({"limit":101})),
        ("oip_opcua_nodes_read", json!({"limit":0})),
        ("oip_opcua_nodes_read", json!({"offset":-1})),
        (
            "oip_events_read",
            json!({"timestamp":-9223372036854775808_i64}),
        ),
        ("oip_devices_read", json!({"q":"x".repeat(17000)})),
    ] {
        assert!(
            adapter
                .invoke(name, args, CancellationToken::new())
                .await
                .is_err(),
            "{name}"
        );
    }
    for name in [
        "simulation_scenario_set",
        "oip_simulation_scenario_set",
        "core_shutdown",
        "shell",
        "configuration_read",
    ] {
        assert!(adapter
            .invoke(name, json!({}), CancellationToken::new())
            .await
            .is_err());
    }
    assert!(adapter
        .resource("file:///etc/passwd", CancellationToken::new())
        .await
        .is_err());
    let missing = adapter
        .invoke(
            "oip_device_read",
            json!({"id":"missing"}),
            CancellationToken::new(),
        )
        .await
        .unwrap();
    assert_eq!(
        missing.structured_content.unwrap()["kind"],
        "resource_not_found"
    );
    for _ in 0..20 {
        assert_eq!(
            adapter
                .invoke("oip_sources_read", json!({}), CancellationToken::new())
                .await
                .unwrap()
                .is_error,
            Some(false)
        );
    }
    let mut p = policy();
    p.permissions.insert(Permission::SimulationControl);
    assert!(McpAdapter::new(Arc::new(ApplicationServices::new(s.clone())), p).is_err());
    assert!(s.shutdown().await.clean);
}
struct PendingService;
impl CapabilityService for PendingService {
    fn execute<'a>(
        &'a self,
        _: &'a ExecutionContext,
        _: CapabilityRequest,
    ) -> std::pin::Pin<
        Box<
            dyn std::future::Future<Output = Result<CapabilityOutput, CapabilityError>> + Send + 'a,
        >,
    > {
        Box::pin(std::future::pending())
    }
}
#[tokio::test]
async fn cancellation_interrupts_a_real_pending_service_future() {
    let adapter = McpAdapter::new(Arc::new(PendingService), policy()).unwrap();
    let cancel = CancellationToken::new();
    let token = cancel.clone();
    let task =
        tokio::spawn(async move { adapter.invoke("oip_sources_read", json!({}), token).await });
    tokio::task::yield_now().await;
    cancel.cancel();
    assert!(tokio::time::timeout(Duration::from_secs(1), task)
        .await
        .unwrap()
        .unwrap()
        .is_err());
}
#[tokio::test]
async fn bounded_transport_rejects_more_than_sixteen_outstanding_requests() {
    use rmcp::transport::Transport;
    use tokio::io::AsyncWriteExt;
    // JSON-RPC number 1 and string "1" are distinct correlation identities.
    {
        let (mut input, read) = tokio::io::duplex(65536);
        let (write, _output) = tokio::io::duplex(1);
        let mut transport = BoundedTransport::new(read, write);
        input.write_all(b"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}\n{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"ping\"}\n").await.unwrap();
        assert!(transport.receive().await.is_some());
        assert!(transport.receive().await.is_some());
    }
    let (mut input, read) = tokio::io::duplex(65536);
    let (write, _output) = tokio::io::duplex(1);
    let mut transport = BoundedTransport::new(read, write);
    for id in 0..17 {
        input
            .write_all(
                format!("{{\"jsonrpc\":\"2.0\",\"id\":{id},\"method\":\"ping\"}}\n").as_bytes(),
            )
            .await
            .unwrap();
        if id < 16 {
            assert!(transport.receive().await.is_some());
        } else {
            assert!(transport.receive().await.is_none());
        }
    }
}

#[tokio::test]
async fn sdk_cancellation_notification_drops_inflight_service_and_client_can_continue() {
    use std::sync::atomic::{AtomicBool, Ordering};
    struct Guard(Arc<AtomicBool>);
    impl Drop for Guard {
        fn drop(&mut self) {
            self.0.store(true, Ordering::SeqCst);
        }
    }
    struct Pending {
        started: Arc<tokio::sync::Notify>,
        dropped: Arc<AtomicBool>,
    }
    impl CapabilityService for Pending {
        fn execute<'a>(
            &'a self,
            _: &'a ExecutionContext,
            _: CapabilityRequest,
        ) -> std::pin::Pin<
            Box<
                dyn std::future::Future<Output = Result<CapabilityOutput, CapabilityError>>
                    + Send
                    + 'a,
            >,
        > {
            Box::pin(async move {
                let _guard = Guard(self.dropped.clone());
                self.started.notify_one();
                std::future::pending().await
            })
        }
    }
    let started = Arc::new(tokio::sync::Notify::new());
    let dropped = Arc::new(AtomicBool::new(false));
    let adapter = McpAdapter::new(
        Arc::new(Pending {
            started: started.clone(),
            dropped: dropped.clone(),
        }),
        policy(),
    )
    .unwrap();
    let (a, b) = tokio::io::duplex(65536);
    let server =
        tokio::spawn(async move { adapter.serve(a).await.unwrap().waiting().await.unwrap() });
    let client = ().serve(b).await.unwrap();
    let handle = client
        .peer()
        .send_cancellable_request(
            CallToolRequest::new(CallToolRequestParams::new("oip_sources_read")).into(),
            rmcp::service::PeerRequestOptions::no_options(),
        )
        .await
        .unwrap();
    tokio::time::timeout(Duration::from_secs(1), started.notified())
        .await
        .unwrap();
    client
        .peer()
        .send_notification(
            CancelledNotification::new(CancelledNotificationParam::new(
                Some(handle.id.clone()),
                None,
            ))
            .into(),
        )
        .await
        .unwrap();
    tokio::time::timeout(Duration::from_secs(1), async {
        while !dropped.load(Ordering::SeqCst) {
            tokio::task::yield_now().await;
        }
    })
    .await
    .unwrap();
    client
        .peer()
        .send_request(PingRequest::default().into())
        .await
        .unwrap();
    client.cancel().await.unwrap();
    server.await.unwrap();
}

#[tokio::test]
async fn unbounded_service_output_is_refused_before_wire_response() {
    struct Large;
    impl CapabilityService for Large {
        fn execute<'a>(
            &'a self,
            _: &'a ExecutionContext,
            _: CapabilityRequest,
        ) -> std::pin::Pin<
            Box<
                dyn std::future::Future<Output = Result<CapabilityOutput, CapabilityError>>
                    + Send
                    + 'a,
            >,
        > {
            Box::pin(async {
                Ok(CapabilityOutput::Devices(vec![Device {
                    data_source_id: None,
                    is_faulted: false,
                    id: "M-01".into(),
                    name: "x".repeat(oip_server::mcp::MAX_OUTPUT),
                    kind: "simulation".into(),
                    location: "local".into(),
                    connection: "unknown".into(),
                    simulated: true,
                    health: Health {
                        reachability: "unknown".into(),
                        vpn_transport: "unknown".into(),
                        agent_availability: "unknown".into(),
                        service_health: "unknown".into(),
                        telemetry_freshness: "unknown".into(),
                    },
                }]))
            })
        }
    }
    let adapter = McpAdapter::new(Arc::new(Large), policy()).unwrap();
    assert!(adapter
        .invoke("oip_devices_read", json!({}), CancellationToken::new())
        .await
        .is_err());
}

#[tokio::test]
async fn runtime_ownership_rejects_duplicate_and_symlink_alias_then_allows_restart() {
    use oip_server::runtime::CoreRuntime;
    let dir =
        std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../target/oip006-ownership");
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join(format!(
        "{}-{}.sqlite",
        std::process::id(),
        oip_server::state::now_ms()
    ));
    let config = CoreConfig {
        legacy_single_infrastructure: true,
        database: path.clone(),
        ..Default::default()
    };
    let first = CoreRuntime::start(config.clone(), None).await.unwrap();
    assert!(CoreRuntime::start(config.clone(), None).await.is_err());
    #[cfg(unix)]
    {
        let alias = path.with_extension("alias.sqlite");
        std::os::unix::fs::symlink(&path, &alias).unwrap();
        assert!(CoreRuntime::start(
            CoreConfig {
                legacy_single_infrastructure: true,
                database: alias,
                ..config.clone()
            },
            None
        )
        .await
        .is_err());
    }
    assert!(first.shutdown().await.clean);
    let second = CoreRuntime::start(config, None).await.unwrap();
    assert!(second.shutdown().await.clean);
}

#[tokio::test]
async fn resource_models_match_direct_service_and_rest_including_sse_projections() {
    use futures::StreamExt;
    let s = state();
    let svc = Arc::new(ApplicationServices::new(s.clone()));
    let p = policy();
    let adapter = McpAdapter::new(svc.clone(), p.clone()).unwrap();
    let response = api::router_with_service(s.clone(), svc.clone(), Some(ctx(&p)), None)
        .oneshot(
            Request::builder()
                .uri("/api/v1/stream")
                .header("host", "127.0.0.1:8080")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let mut stream = response.into_body().into_data_stream();
    let bytes = stream.next().await.unwrap().unwrap();
    let frame = std::str::from_utf8(&bytes).unwrap();
    let snapshot: Value = serde_json::from_str(
        frame
            .lines()
            .find_map(|l| l.strip_prefix("data: "))
            .unwrap(),
    )
    .unwrap();
    drop(stream);
    fn normalize(v: &mut Value) {
        if let Some(m) = v.as_object_mut() {
            m.remove("generated_at_ms");
            for x in m.values_mut() {
                normalize(x)
            }
        } else if let Some(a) = v.as_array_mut() {
            for x in a {
                normalize(x)
            }
        }
    }
    for (uri, request, path, field) in [
        (
            "oip://v1/core/health",
            CapabilityRequest::CoreHealthRead,
            Some("/api/v1/core/health"),
            "core",
        ),
        (
            "oip://v1/core/liveness",
            CapabilityRequest::CoreLivenessRead,
            Some("/health/live"),
            "core",
        ),
        (
            "oip://v1/core/readiness",
            CapabilityRequest::CoreReadinessRead,
            Some("/health/ready"),
            "core",
        ),
        (
            "oip://v1/core/queue",
            CapabilityRequest::QueueRead,
            None,
            "queue",
        ),
        (
            "oip://v1/system/status",
            CapabilityRequest::SystemStatusRead,
            Some("/api/v1/system/status"),
            "system",
        ),
        (
            "oip://v1/snapshot/current",
            CapabilityRequest::SnapshotRead,
            None,
            "",
        ),
    ] {
        let mut direct =
            serde_json::to_value(svc.execute(&ctx(&p), request).await.unwrap()).unwrap();
        let result = adapter
            .resource(uri, CancellationToken::new())
            .await
            .unwrap();
        let ResourceContents::TextResourceContents { text, .. } = &result.contents[0] else {
            panic!()
        };
        let mut mcp: Value = serde_json::from_str(text).unwrap();
        let mut http = if let Some(path) = path {
            rest(s.clone(), svc.clone(), &p, path).await
        } else if field.is_empty() {
            snapshot.clone()
        } else {
            snapshot[field].clone()
        };
        normalize(&mut direct);
        normalize(&mut mcp);
        normalize(&mut http);
        assert_eq!(direct, mcp, "{uri}");
        assert_eq!(direct["value"], http, "{uri}");
    }
    let mapping = oip_server::mcp::capability_mapping();
    assert_eq!(mapping["capabilities"].as_array().unwrap().len(), 24);
    assert_eq!(
        mapping["capabilities"]
            .as_array()
            .unwrap()
            .iter()
            .filter(|c| c["mcp_status"] == "BLOCKED")
            .count(),
        1
    );
    assert!(s.shutdown().await.clean);
}

#[tokio::test]
async fn cancelled_application_service_records_authoritative_interruption_audit() {
    use std::sync::Mutex;
    #[derive(Default)]
    struct Audit(Mutex<Vec<ExecutionAudit>>);
    impl CapabilityAudit for Audit {
        fn record(&self, e: &ExecutionAudit) -> Result<(), CapabilityError> {
            self.0.lock().unwrap().push(e.clone());
            Ok(())
        }
    }
    let s = state();
    let audit = Arc::new(Audit::default());
    let service = Arc::new(ApplicationServices::with_audit(s.clone(), audit.clone()));
    let adapter = McpAdapter::new(service, policy()).unwrap();
    let cancel = CancellationToken::new();
    let locked = s.catalogs.write().await;
    let mut call = Box::pin(adapter.invoke(
        "oip_opcua_nodes_read",
        json!({"source":"sim-a"}),
        cancel.clone(),
    ));
    assert!(futures::poll!(call.as_mut()).is_pending());
    cancel.cancel();
    assert!(call.await.is_err());
    drop(locked);
    let records = audit.0.lock().unwrap().clone();
    assert_eq!(records.len(), 1);
    assert_eq!(records[0].outcome, "interrupted");
    assert!(records[0].authorized);
    assert_eq!(records[0].target, "sim-a");
    assert_eq!(records[0].capability, CapabilityId::OpcuaNodesRead);
    assert!(s.shutdown().await.clean);
}

#[tokio::test]
async fn physically_blocked_output_leaves_ingestion_independent_and_closes_transport() {
    use rmcp::transport::Transport;
    let s = state();
    s.started().await.unwrap();
    s.connected(&s.primary).await.unwrap();
    let (_input, read) = tokio::io::duplex(1);
    let (write, _unread) = tokio::io::duplex(1);
    let mut transport = BoundedTransport::new(read, write);
    let message: ServerJsonRpcMessage =
        serde_json::from_value(json!({"jsonrpc":"2.0","id":1,"result":{}})).unwrap();
    let mut send = Box::pin(transport.send(message));
    assert!(futures::poll!(send.as_mut()).is_pending());
    let mut o = oip_simulator::Simulation::new(
        oip_simulator::SimulationConfig::default(),
        oip_simulator::Scenario::Normal,
    )
    .frame_at(0)
    .observations[0]
        .clone();
    o.data_source_id = s.primary.clone();
    s.ingest(ClientEvent::Observation(Box::new(o)))
        .await
        .unwrap();
    assert!(s.view().health.persisted_observations > 0);
    assert!(send.await.is_err());
    assert!(transport.receive().await.is_none());
    assert!(s.shutdown().await.clean);
}
