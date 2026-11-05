//! OIP-008: identical central authorization for direct, REST and real SDK reads.
use axum::{
    body::{to_bytes, Body},
    http::Request,
};
use oip_core::*;
use oip_server::{
    api,
    application_services::ApplicationServices,
    config::CoreConfig,
    mcp::{McpAdapter, McpPolicy},
    state::AppState,
};
use oip_storage::SqliteStore;
use rmcp::{model::*, ServiceExt};
use serde_json::{json, Value};
use std::sync::Arc;
use tower::ServiceExt as _;
fn plan() -> ProvisioningPlan {
    serde_json::from_str(include_str!(
        "../../../examples/multi-infrastructure-plan.json"
    ))
    .unwrap()
}
fn config() -> CoreConfig {
    serde_json::from_str(include_str!(
        "../../../examples/multi-infrastructure-core.json"
    ))
    .unwrap()
}
fn policy(id: &str) -> McpPolicy {
    serde_json::from_value(json!({"principal":id})).unwrap()
}
async fn fixture() -> (AppState, Arc<ApplicationServices>) {
    let c = config();
    let mut db = SqliteStore::open_in_memory().unwrap();
    let defs = c
        .sources
        .iter()
        .map(|s| s.definition().unwrap())
        .collect::<Vec<_>>();
    db.provision(plan(), &defs, None).unwrap();
    let s = AppState::configured(db, &c, None).unwrap();
    s.started().await.unwrap();
    for source in &c.sources {
        let id = DataSourceId::new(&source.id).unwrap();
        s.connected(&id).await.unwrap();
        for mut o in
            oip_simulator::Simulation::new(Default::default(), oip_simulator::Scenario::Normal)
                .frame_at(0)
                .observations
        {
            o.data_source_id = id.clone();
            s.ingest_for(&id, ClientEvent::Observation(Box::new(o)))
                .await
                .unwrap();
        }
    }
    (s.clone(), Arc::new(ApplicationServices::new(s)))
}
#[test]
fn identities_hierarchy_parents_and_scoped_permission_union() {
    for value in ["", " a", "a/../b", "é", "a b"] {
        assert!(OrganizationId::new(value).is_err());
    }
    assert!(DeviceId::new(format!("{}:M-01", "a".repeat(128))).is_ok());
    assert!(DeviceId::new("a".repeat(257)).is_err());
    let h = HierarchyRegistry::new(plan()).unwrap();
    let p = PrincipalId::new("reader-org-a").unwrap();
    assert_eq!(h.allowed_sources(&p, CapabilityId::SourcesRead).len(), 3);
    assert!(!h.platform(&p, CapabilityId::CoreHealthRead));
    let mut broken = plan();
    broken.sites[0].infrastructure_id = InfrastructureId::new("absent").unwrap();
    assert!(HierarchyRegistry::new(broken).is_err());
    let mut split = plan();
    split.roles = vec![
        ReadRole {
            id: RoleId::new("device").unwrap(),
            name: "Device".into(),
            permissions: [Permission::DevicesRead].into(),
        },
        ReadRole {
            id: RoleId::new("telemetry").unwrap(),
            name: "Telemetry".into(),
            permissions: [Permission::TelemetryRead].into(),
        },
    ];
    split.bindings = vec![
        RoleBinding {
            principal_id: p.clone(),
            role_id: RoleId::new("device").unwrap(),
            scope: AccessScope::Source(DataSourceId::new("source-a").unwrap()),
        },
        RoleBinding {
            principal_id: p.clone(),
            role_id: RoleId::new("telemetry").unwrap(),
            scope: AccessScope::Source(DataSourceId::new("source-d").unwrap()),
        },
    ];
    let h = HierarchyRegistry::new(split).unwrap();
    assert!(
        h.allowed_sources(&p, CapabilityId::DeviceRead).is_empty(),
        "permissions from unrelated scopes must not combine"
    );
}
#[tokio::test]
async fn hierarchy_discovery_lists_and_foreign_identifiers_are_fail_closed() {
    let (s, svc) = fixture().await;
    for (p, expected) in [
        ("reader-org-a", 3),
        ("reader-infra-a1", 3),
        ("reader-org-b", 1),
        ("reader-site-a1", 2),
        ("reader-source-b", 1),
    ] {
        let ctx = policy(p).execution_context();
        let CapabilityOutput::Sources(sources) = svc
            .execute(&ctx, CapabilityRequest::SourcesRead(Default::default()))
            .await
            .unwrap()
        else {
            panic!()
        };
        assert_eq!(sources.len(), expected);
        let ids = svc.discover(&ctx);
        assert!(!ids.iter().any(|d| matches!(
            d.id,
            CapabilityId::CoreHealthRead | CapabilityId::SnapshotRead | CapabilityId::QueueRead
        )));
        assert!(ids.iter().any(|d| d.id == CapabilityId::ScopedSnapshotRead));
        let CapabilityOutput::ScopedSnapshot(v) = svc
            .execute(&ctx, CapabilityRequest::ScopedSnapshotRead)
            .await
            .unwrap()
        else {
            panic!()
        };
        let value = serde_json::to_value(v).unwrap();
        assert!(value.get("run_id").is_none());
        assert!(value.get("queue").is_none());
    }
    let ctx = policy("reader-org-a").execution_context();
    for source in ["source-d", "does-not-exist"] {
        let error = svc
            .execute(
                &ctx,
                CapabilityRequest::SourcesRead(SourceQuery {
                    source: Some(DataSourceId::new(source).unwrap()),
                    ..Default::default()
                }),
            )
            .await
            .unwrap_err();
        assert_eq!(error.code, "RESOURCE_NOT_ACCESSIBLE");
        assert_eq!(error.message, "Resource is not accessible");
    }
    for id in ["device-d", "not-a-device"] {
        assert_eq!(
            svc.execute(
                &ctx,
                CapabilityRequest::DeviceRead(DeviceRequest { id: id.into() })
            )
            .await
            .unwrap_err()
            .code,
            "RESOURCE_NOT_ACCESSIBLE"
        );
    }
    assert!(svc
        .execute(
            &policy("unbound-reader").execution_context(),
            CapabilityRequest::SourcesRead(Default::default())
        )
        .await
        .is_err());
    let mut forged = ctx.clone();
    forged.actor = "platform-reader".into();
    assert!(svc
        .execute(&forged, CapabilityRequest::SourcesRead(Default::default()))
        .await
        .is_err());
    assert!(svc
        .execute(
            &ctx,
            CapabilityRequest::SitesRead(HierarchyQuery {
                organization: Some(OrganizationId::new("org-a").unwrap()),
                infrastructure: Some(InfrastructureId::new("infra-b1").unwrap()),
                ..Default::default()
            })
        )
        .await
        .is_err());
    assert!(s.shutdown().await.clean);
}
#[tokio::test]
async fn nine_tools_use_same_capability_output_and_no_global_resources() {
    let (s, svc) = fixture().await;
    let p = policy("reader-org-b");
    let ctx = p.execution_context();
    let adapter = McpAdapter::new(svc.clone(), p).unwrap();
    let (a, b) = tokio::io::duplex(65536);
    let task =
        tokio::spawn(async move { adapter.serve(a).await.unwrap().waiting().await.unwrap() });
    let client = ().serve(b).await.unwrap();
    let tools = client.peer().list_all_tools().await.unwrap();
    assert_eq!(tools.len(), 16);
    let resources = client.peer().list_all_resources().await.unwrap();
    assert!(!resources
        .iter()
        .any(|r| r.uri == "oip://v1/snapshot/current"));
    for (name, args, req) in [
        (
            "oip_sources_read",
            json!({}),
            CapabilityRequest::SourcesRead(Default::default()),
        ),
        (
            "oip_organizations_read",
            json!({}),
            CapabilityRequest::OrganizationsRead(Default::default()),
        ),
        (
            "oip_infrastructures_read",
            json!({}),
            CapabilityRequest::InfrastructuresRead(Default::default()),
        ),
        (
            "oip_sites_read",
            json!({}),
            CapabilityRequest::SitesRead(Default::default()),
        ),
        (
            "oip_device_read",
            json!({"id":"device-d"}),
            CapabilityRequest::DeviceRead(DeviceRequest {
                id: "device-d".into(),
            }),
        ),
    ] {
        let expected = serde_json::to_value(svc.execute(&ctx, req).await.unwrap()).unwrap();
        let response = client
            .peer()
            .call_tool(
                CallToolRequestParams::new(name).with_arguments(args.as_object().unwrap().clone()),
            )
            .await
            .unwrap();
        assert!(!response.is_error.unwrap_or(false));
        let actual = response.structured_content.unwrap();
        let tool = tools.iter().find(|t| t.name == name).unwrap();
        assert!(
            jsonschema::validator_for(&Value::Object((*tool.input_schema).clone()))
                .unwrap()
                .is_valid(&args)
        );
        assert!(jsonschema::validator_for(&Value::Object(
            (**tool.output_schema.as_ref().unwrap()).clone()
        ))
        .unwrap()
        .is_valid(&actual));
        assert_eq!(actual, expected);
    }
    for args in [
        json!({"source":"source-a"}),
        json!({"principal":"platform-reader"}),
        json!({"limit":101}),
        json!({"organization":"org-a"}),
    ] {
        let r = client
            .peer()
            .call_tool(
                CallToolRequestParams::new("oip_sources_read")
                    .with_arguments(args.as_object().unwrap().clone()),
            )
            .await;
        assert!(r.is_err() || r.unwrap().is_error.unwrap_or(false));
    }
    client.cancel().await.unwrap();
    task.await.unwrap();
    assert!(s.shutdown().await.clean);
}
#[tokio::test]
async fn unauthenticated_rest_and_global_sse_are_denied_in_multi_mode() {
    let (s, svc) = fixture().await;
    let app = api::router_with_service(s.clone(), svc, None, None);
    for path in [
        "/api/v2/sources",
        "/api/v2/stream",
        "/api/v1/stream",
        "/api/v1/core/health",
    ] {
        let r = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(path)
                    .header("host", "127.0.0.1:18808")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(r.status(), 403);
        let value: Value =
            serde_json::from_slice(&to_bytes(r.into_body(), 10000).await.unwrap()).unwrap();
        assert_eq!(value["code"], "PERMISSION_DENIED");
    }
    assert!(s.shutdown().await.clean);
}
#[tokio::test]
async fn tenant_audit_handles_implicit_non_primary_source_cancellation_and_forged_actor() {
    use std::sync::Mutex;
    #[derive(Default)]
    struct Audit(Mutex<Vec<ExecutionAudit>>);
    impl CapabilityAudit for Audit {
        fn record(&self, e: &ExecutionAudit) -> Result<(), CapabilityError> {
            self.0.lock().unwrap().push(e.clone());
            Ok(())
        }
    }
    let (s, _) = fixture().await;
    let audit = Arc::new(Audit::default());
    let svc = Arc::new(ApplicationServices::with_audit(s.clone(), audit.clone()));
    let p = policy("reader-source-b");
    let ctx = p.execution_context();
    svc.execute(&ctx, CapabilityRequest::OpcuaNodesRead(Default::default()))
        .await
        .unwrap();
    let record = audit.0.lock().unwrap().last().unwrap().clone();
    assert!(record.authorized);
    assert_eq!(record.target, "source-b");
    assert_eq!(record.hierarchy.unwrap().source_id.as_str(), "source-b");
    let mut forged = ctx.clone();
    forged.actor = "platform-reader".into();
    assert!(svc
        .execute(&forged, CapabilityRequest::SourcesRead(Default::default()))
        .await
        .is_err());
    assert_eq!(
        audit.0.lock().unwrap().last().unwrap().outcome,
        "denied_identity"
    );
    let adapter = McpAdapter::new(svc, p).unwrap();
    let locked = s.catalogs.write().await;
    let cancel = tokio_util::sync::CancellationToken::new();
    let mut call = Box::pin(adapter.invoke("oip_opcua_nodes_read", json!({}), cancel.clone()));
    assert!(futures::poll!(call.as_mut()).is_pending());
    cancel.cancel();
    assert!(call.await.is_err());
    drop(locked);
    let record = audit.0.lock().unwrap().last().unwrap().clone();
    assert_eq!(record.outcome, "interrupted_before_completion");
    assert_eq!(record.principal.unwrap().as_str(), "reader-source-b");
    assert!(s.shutdown().await.clean);
}
#[tokio::test]
async fn embedded_default_constructor_cannot_enable_legacy_all_access() {
    let s = AppState::new(SqliteStore::open_in_memory().unwrap(), None).unwrap();
    let service = ApplicationServices::new(s.clone());
    assert!(service
        .execute(
            &service.local_context(),
            CapabilityRequest::SourcesRead(Default::default())
        )
        .await
        .is_err());
    assert!(s.shutdown().await.clean);
}
