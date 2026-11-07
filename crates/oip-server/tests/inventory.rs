use axum::{
    body::{to_bytes, Body},
    http::Request,
};
use oip_core::*;
use oip_server::{
    api, application_services::ApplicationServices, config::CoreConfig, mcp::McpPolicy,
    runtime::CoreRuntime, state::AppState,
};
use oip_storage::SqliteStore;
use std::{
    path::PathBuf,
    sync::{
        atomic::{AtomicUsize, Ordering},
        Arc, Mutex,
    },
};
use tower::ServiceExt as _;
#[derive(Default)]
struct Audit(Mutex<Vec<ExecutionAudit>>);
impl CapabilityAudit for Audit {
    fn record(&self, e: &ExecutionAudit) -> Result<(), CapabilityError> {
        self.0.lock().unwrap().push(e.clone());
        Ok(())
    }
}
fn dir() -> PathBuf {
    static N: AtomicUsize = AtomicUsize::new(0);
    let p = PathBuf::from(format!(
        "/private/tmp/oip85-unit-{}-{}",
        std::process::id(),
        N.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::create_dir(&p).unwrap();
    p
}
fn ctx(p: &str) -> ExecutionContext {
    McpPolicy {
        principal: Some(PrincipalId::new(p).unwrap()),
        actor: String::new(),
        permissions: Default::default(),
        sources: SourceScope::Only(Default::default()),
    }
    .execution_context()
}

#[tokio::test]
async fn online_inventory_uses_owned_writer_and_atomic_revision_conflicts() {
    let (state, service, _, _) = fixture().await;
    let admin = ctx("platform-reader");
    let row = state
        .inventory()
        .iter()
        .find(|r| r.device.id.as_str() == "manual-a")
        .unwrap()
        .clone();
    let mut first = row.device.clone();
    first.display_name = "First CAS update".into();
    let mut second = row.device.clone();
    second.display_name = "Concurrent CAS update".into();
    let request = |device| {
        CapabilityRequest::InventoryChange(InventoryAdministration {
            principal: PrincipalId::new("platform-reader").unwrap(),
            changes: vec![InventoryChange::Update {
                device,
                expected_revision: row.revision,
            }],
        })
    };
    let (a, b) = tokio::join!(
        service.execute(&admin, request(first)),
        service.execute(&admin, request(second))
    );
    assert_ne!(
        a.is_ok(),
        b.is_ok(),
        "exactly one transaction may advance a revision"
    );
    assert_eq!(
        state
            .inventory()
            .iter()
            .find(|r| r.device.id == row.device.id)
            .unwrap()
            .revision,
        row.revision + 1
    );
    let forged = CapabilityRequest::InventoryChange(InventoryAdministration {
        principal: PrincipalId::new("platform-reader").unwrap(),
        changes: vec![InventoryChange::Update {
            device: row.device.clone(),
            expected_revision: row.revision + 1,
        }],
    });
    assert!(service.execute(&ctx("reader-org-b"), forged).await.is_err());
    // Online archive remains unavailable: historical associations need the explicit offline operator path.
    assert!(service
        .execute(
            &admin,
            CapabilityRequest::InventoryChange(InventoryAdministration {
                principal: PrincipalId::new("platform-reader").unwrap(),
                changes: vec![InventoryChange::Archive {
                    id: row.device.id,
                    expected_revision: row.revision + 1
                }],
            })
        )
        .await
        .is_err());
    assert!(state.shutdown().await.clean);
}
#[tokio::test]
async fn default_runtime_empty_without_sources_devices_events_or_demo() {
    let dir = dir();
    let config = CoreConfig {
        database: dir.join("db.sqlite"),
        ..Default::default()
    };
    assert!(config.sources.is_empty());
    let runtime = CoreRuntime::start(config, None).await.unwrap();
    let s = runtime.state.clone();
    let snap = s.snapshot().unwrap();
    assert!(
        snap.devices.is_empty()
            && snap.sources.is_empty()
            && snap.metrics.is_empty()
            && snap.incidents.is_empty()
            && snap.topology.is_empty()
    );
    assert!(
        !snap.system.simulated
            && !snap.system.demo_controls
            && snap.system.primary_source_id.is_none()
    );
    let response = api::router_optional(s, None)
        .oneshot(
            Request::builder()
                .uri("/api/v2/installation/status")
                .header("host", "127.0.0.1:8080")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), 200);
    let v: serde_json::Value =
        serde_json::from_slice(&to_bytes(response.into_body(), 10000).await.unwrap()).unwrap();
    assert_eq!(v["status"], "No infrastructure configured");
    assert!(runtime.shutdown().await.clean);
    let db = rusqlite::Connection::open(dir.join("db.sqlite")).unwrap();
    assert_eq!(
        db.query_row("SELECT count(*) FROM collection_events", [], |r| r
            .get::<_, i64>(0))
            .unwrap(),
        0
    );
}
async fn fixture() -> (AppState, Arc<ApplicationServices>, Arc<Audit>, PathBuf) {
    let dir = dir();
    let path = dir.join("db.sqlite");
    let mut p: ProvisioningPlan = serde_json::from_str(include_str!(
        "../../../examples/multi-infrastructure-plan.json"
    ))
    .unwrap();
    p.sources.clear();
    p.bindings
        .retain(|b| !matches!(b.scope, AccessScope::Source(_)));
    p.roles.push(ReadRole {
        id: RoleId::new("inventory-admin").unwrap(),
        name: "Explicit test operator".into(),
        permissions: [Permission::InventoryManage, Permission::DevicesRead].into(),
    });
    p.bindings.push(RoleBinding {
        principal_id: PrincipalId::new("platform-reader").unwrap(),
        role_id: RoleId::new("inventory-admin").unwrap(),
        scope: AccessScope::Platform,
    });
    {
        let _o = oip_storage::DatabaseOwnership::acquire(&path).unwrap();
        let mut db = SqliteStore::open(&path).unwrap();
        db.provision(p, &[], None).unwrap();
    }
    let changes = [("manual-a", "site-a1"), ("manual-b", "site-b1")]
        .into_iter()
        .map(|(id, site)| InventoryChange::Register {
            device: DeviceRegistration {
                id: DeviceId::new(id).unwrap(),
                display_name: "A manually registered host".into(),
                site_id: SiteId::new(site).unwrap(),
                device_type: DeviceType::Server,
                metadata: DeviceMetadata {
                    ip_address: Some("192.0.2.7".into()),
                    ..Default::default()
                },
            },
        })
        .collect();
    SqliteStore::inventory_admin_file(
        &path,
        InventoryAdministration {
            principal: PrincipalId::new("platform-reader").unwrap(),
            changes,
        },
        true,
        1,
    )
    .unwrap();
    let state = AppState::configured(
        SqliteStore::open(&path).unwrap(),
        &CoreConfig::default(),
        None,
    )
    .unwrap();
    let audit = Arc::new(Audit::default());
    let service = Arc::new(ApplicationServices::with_audit(
        state.clone(),
        audit.clone(),
    ));
    (state, service, audit, dir)
}
#[tokio::test]
async fn manual_inventory_scopes_legacy_projection_and_audit_targets() {
    let (state, s, audit, _) = fixture().await;
    let c = ctx("reader-org-a");
    let q = InventoryQuery {
        id: Some(DeviceId::new("manual-a").unwrap()),
        ..Default::default()
    };
    let out = s
        .execute(&c, CapabilityRequest::InventoryRead(q))
        .await
        .unwrap();
    let CapabilityOutput::Inventory(p) = out else {
        panic!("output")
    };
    assert_eq!(p.items.len(), 1);
    let adapter = oip_server::mcp::McpAdapter::new(
        s.clone(),
        McpPolicy {
            principal: c.principal.clone(),
            actor: String::new(),
            permissions: Default::default(),
            sources: SourceScope::Only(Default::default()),
        },
    )
    .unwrap();
    let tools = adapter.tools();
    let tool = tools
        .iter()
        .find(|t| t.name == "oip_inventory_read")
        .unwrap();
    let schema = serde_json::Value::Object(tool.output_schema.as_ref().unwrap().as_ref().clone());
    assert!(jsonschema::validator_for(&schema)
        .unwrap()
        .is_valid(&serde_json::to_value(CapabilityOutput::Inventory(p.clone())).unwrap()));
    let input = serde_json::Value::Object(tool.input_schema.as_ref().clone());
    assert!(!jsonschema::validator_for(&input)
        .unwrap()
        .is_valid(&serde_json::json!({"principal":"platform-reader"})));
    let d = &p.items[0];
    assert!(d.sources.is_empty());
    assert!(matches!(d.connectivity, InventoryConnectivity::Unknown));
    assert!(matches!(d.telemetry, MonitoringAvailability::NoCollector));
    assert_eq!(d.monitoring_simulated, Some(false));
    assert!(d.record.registered_by.is_none());
    let e = audit.0.lock().unwrap().last().unwrap().clone();
    assert_eq!(e.target, "manual-a");
    assert_eq!(
        e.scope,
        Some(AccessScope::Site(SiteId::new("site-a1").unwrap()))
    );
    for id in ["manual-b", "missing"] {
        assert!(s
            .execute(
                &c,
                CapabilityRequest::InventoryRead(InventoryQuery {
                    id: Some(DeviceId::new(id).unwrap()),
                    ..Default::default()
                })
            )
            .await
            .is_err());
        assert!(s
            .execute(
                &c,
                CapabilityRequest::DeviceRead(DeviceRequest { id: id.into() })
            )
            .await
            .is_err())
    }
    let CapabilityOutput::Devices(devices) = s
        .execute(&c, CapabilityRequest::DevicesRead(DeviceQuery::default()))
        .await
        .unwrap()
    else {
        panic!("devices")
    };
    assert_eq!(devices.len(), 1);
    assert_eq!(devices[0].id, "manual-a");
    assert_eq!(devices[0].health.reachability, "unknown");
    let CapabilityOutput::ScopedSnapshot(snap) = s
        .execute(&c, CapabilityRequest::ScopedSnapshotRead)
        .await
        .unwrap()
    else {
        panic!("snapshot")
    };
    assert_eq!(snap.devices.len(), 1);
    assert!(snap.observations.is_empty() && snap.events.is_empty());
    assert!(state.shutdown().await.clean);
}
#[tokio::test]
async fn plan_read_no_mutation_and_forged_context_denied() {
    let (state, s, _, _) = fixture().await;
    let q = InventoryPlanQuery {
        changes: vec![InventoryChange::Archive {
            id: DeviceId::new("manual-a").unwrap(),
            expected_revision: 1,
        }],
    };
    assert!(s
        .execute(
            &ctx("reader-org-a"),
            CapabilityRequest::InventoryPlanRead(q.clone())
        )
        .await
        .is_err());
    let CapabilityOutput::InventoryPlan(plan) = s
        .execute(
            &ctx("platform-reader"),
            CapabilityRequest::InventoryPlanRead(q),
        )
        .await
        .unwrap()
    else {
        panic!("plan")
    };
    assert!(!plan.applied);
    assert!(state
        .inventory()
        .iter()
        .all(|r| r.registration == RegistrationStatus::Registered));
    let mut c = ctx("reader-org-a");
    c.actor = "platform-reader".into();
    assert!(s
        .execute(
            &c,
            CapabilityRequest::InventoryRead(InventoryQuery::default())
        )
        .await
        .is_err());
    assert!(
        serde_json::from_value::<InventoryQuery>(serde_json::json!({"source":" source-a "}))
            .is_err()
    );
    assert!(serde_json::from_value::<InventoryPlanQuery>(
        serde_json::json!({"principal":"platform-reader","changes":[]})
    )
    .is_err());
    assert!(serde_json::from_value::<InventoryChange>(serde_json::json!({"operation":"update","device":{"id":"manual-a","display_name":"rename","device_type":"server","site_id":"site-a1"},"expected_revision":1})).is_err());
    let mut plan = state.hierarchy().as_ref().unwrap().plan.clone();
    plan.sources.push(SourcePlacement {
        source_id: DataSourceId::new("associated-test").unwrap(),
        site_id: SiteId::new("site-a1").unwrap(),
        device_id: DeviceId::new("manual-a").unwrap(),
        entity_id: EntityId::new("M-01").unwrap(),
    });
    let h = HierarchyRegistry::new(plan).unwrap();
    let CapabilityOutput::Inventory(offline) =
        oip_server::inventory_services::inventory_projection(
            Some(&h),
            &state.inventory(),
            &[],
            &ctx("reader-org-a"),
            InventoryQuery::default(),
        )
        .unwrap()
    else {
        panic!("offline")
    };
    assert_eq!(offline.items[0].monitoring_simulated, None);
    assert!(state.shutdown().await.clean);
}
