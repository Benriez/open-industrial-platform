use axum::{
    body::{to_bytes, Body},
    http::Request,
};
use oip_core::*;
use oip_server::{
    api,
    application_services::ApplicationServices,
    config::{CoreConfig, SourceConfig},
    state::AppState,
};
use oip_storage::SqliteStore;
use std::sync::{Arc, Mutex};
use tower::ServiceExt;
#[derive(Default)]
struct Audit {
    events: Mutex<Vec<ExecutionAudit>>,
    fail_on: Option<&'static str>,
}
impl CapabilityAudit for Audit {
    fn record(&self, e: &ExecutionAudit) -> Result<(), CapabilityError> {
        self.events.lock().unwrap().push(e.clone());
        if self.fail_on == Some(e.outcome.as_str()) {
            return Err(CapabilityError::new(
                CapabilityErrorCode::AuditUnavailable,
                "AUDIT_UNAVAILABLE",
                "Audit unavailable",
            ));
        }
        Ok(())
    }
}
fn context() -> ExecutionContext {
    ExecutionContext {
        principal: None,
        actor: "operator-test".into(),
        correlation_id: "call-1".into(),
        permissions: [
            Permission::CoreRead,
            Permission::SourcesRead,
            Permission::DevicesRead,
            Permission::TelemetryRead,
            Permission::EventsRead,
            Permission::OpcuaRead,
            Permission::SimulationControl,
        ]
        .into(),
        sources: SourceScope::All,
    }
}
fn state(demo: bool) -> AppState {
    let tx = if demo {
        Some(tokio::sync::watch::channel("normal".into()).0)
    } else {
        None
    };
    AppState::legacy(SqliteStore::open_in_memory().unwrap(), tx).unwrap()
}
fn request(name: &str) -> CapabilityRequest {
    CapabilityRequest::SimulationScenarioSet(ScenarioRequest {
        scenario: name.into(),
    })
}
#[tokio::test]
async fn direct_capabilities_and_rest_use_the_same_query_contracts() {
    let state = state(true);
    let service = ApplicationServices::new(state.clone());
    let ctx = context();
    let CapabilityOutput::Devices(direct) = service
        .execute(
            &ctx,
            CapabilityRequest::DevicesRead(DeviceQuery {
                q: Some(" AMD ".into()),
                ..Default::default()
            }),
        )
        .await
        .unwrap()
    else {
        panic!()
    };
    let response = api::router_optional(state.clone(), None)
        .oneshot(
            Request::builder()
                .uri("/api/v1/devices?q=%20AMD%20")
                .header("host", "127.0.0.1:8080")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), 200);
    let rest: Vec<Device> =
        serde_json::from_slice(&to_bytes(response.into_body(), 100000).await.unwrap()).unwrap();
    assert_eq!(direct.len(), 1);
    assert_eq!(
        serde_json::to_value(direct).unwrap(),
        serde_json::to_value(rest).unwrap()
    );
    let error = service
        .execute(
            &ctx,
            CapabilityRequest::DeviceRead(DeviceRequest {
                id: "missing".into(),
            }),
        )
        .await
        .unwrap_err();
    assert_eq!(error.kind, CapabilityErrorCode::ResourceNotFound);
    assert_eq!(error.code, "DEVICE_NOT_FOUND");
    let catalog = service.discover(&ctx);
    assert_eq!(catalog.len(), 21);
    assert_eq!(catalog.iter().filter(|c| c.mutating).count(), 1);
    assert!(state.shutdown().await.clean);
}
#[tokio::test]
async fn authorization_and_audit_are_enforced_before_any_simulation_effect() {
    let state = state(true);
    let audit = Arc::new(Audit::default());
    let service = ApplicationServices::with_audit(state.clone(), audit.clone());
    let mut ctx = context();
    ctx.permissions.remove(&Permission::SimulationControl);
    assert_eq!(
        service
            .execute(&ctx, request("sensor"))
            .await
            .unwrap_err()
            .kind,
        CapabilityErrorCode::PermissionDenied
    );
    assert_eq!(state.snapshot().unwrap().system.scenario, "normal");
    assert!(!audit.events.lock().unwrap()[0].authorized);
    ctx.permissions.insert(Permission::SimulationControl);
    service.execute(&ctx, request("gpu")).await.unwrap();
    let events = audit.events.lock().unwrap().clone();
    assert_eq!(events.len(), 3);
    assert_eq!(events[1].outcome, "started");
    assert_eq!(events[2].outcome, "succeeded");
    assert_eq!(events[2].actor, "operator-test");
    assert_eq!(events[2].correlation_id, "call-1");
    assert_eq!(events[2].target, state.primary.as_ref().unwrap().as_str());
    let encoded = serde_json::to_string(&events).unwrap();
    assert!(!encoded.contains("sensor"));
    assert!(!encoded.contains("gpu"));
    let untrusted = "sentinel-untrusted-value";
    assert_eq!(
        service
            .execute(
                &ctx,
                CapabilityRequest::SourcesRead(SourceQuery {
                    source: Some(DataSourceId::new(untrusted).unwrap()),
                    ..Default::default()
                })
            )
            .await
            .unwrap_err()
            .kind,
        CapabilityErrorCode::ResourceNotFound
    );
    {
        let records = audit.events.lock().unwrap();
        assert_eq!(records.last().unwrap().target, "unregistered-resource");
        assert!(!serde_json::to_string(&*records)
            .unwrap()
            .contains(untrusted));
    }
    assert!(state.shutdown().await.clean);
}
#[tokio::test]
async fn audit_failure_fails_closed_and_completion_failure_is_explicit() {
    let state = state(true);
    let fail_start = Arc::new(Audit {
        fail_on: Some("started"),
        ..Default::default()
    });
    let service = ApplicationServices::with_audit(state.clone(), fail_start);
    assert_eq!(
        service
            .execute(&context(), request("sensor"))
            .await
            .unwrap_err()
            .kind,
        CapabilityErrorCode::AuditUnavailable
    );
    assert_eq!(state.snapshot().unwrap().system.scenario, "normal");
    let fail_end = Arc::new(Audit {
        fail_on: Some("succeeded"),
        ..Default::default()
    });
    let service = ApplicationServices::with_audit(state.clone(), fail_end);
    assert_eq!(
        service
            .execute(&context(), request("gpu"))
            .await
            .unwrap_err()
            .code,
        "AUDIT_COMPLETION_UNCONFIRMED"
    );
    assert_eq!(state.snapshot().unwrap().system.scenario, "gpu");
    assert!(state.shutdown().await.clean);
}
#[tokio::test]
async fn source_scopes_cannot_leak_other_sources_or_global_snapshots() {
    let config = CoreConfig {
        legacy_single_infrastructure: true,
        sources: vec![
            SourceConfig {
                id: "a".into(),
                name: "A".into(),
                endpoint: "opc.tcp://127.0.0.1:14841".into(),
                namespace: 2,
                entity_id: None,
                opcua: None,
            },
            SourceConfig {
                id: "b".into(),
                name: "B".into(),
                endpoint: "opc.tcp://127.0.0.1:14842".into(),
                namespace: 2,
                entity_id: None,
                opcua: None,
            },
        ],
        ..Default::default()
    };
    let state =
        AppState::configured(SqliteStore::open_in_memory().unwrap(), &config, None).unwrap();
    let service = ApplicationServices::new(state.clone());
    let mut ctx = context();
    let id = DataSourceId::new("a").unwrap();
    ctx.sources = SourceScope::Only([id.clone()].into());
    let CapabilityOutput::Sources(sources) = service
        .execute(
            &ctx,
            CapabilityRequest::SourcesRead(SourceQuery {
                source: Some(id.clone()),
                ..Default::default()
            }),
        )
        .await
        .unwrap()
    else {
        panic!()
    };
    assert_eq!(sources.len(), 1);
    assert_eq!(sources[0].id, id);
    let CapabilityOutput::Devices(devices) = service
        .execute(
            &ctx,
            CapabilityRequest::DevicesRead(DeviceQuery {
                source: Some(id),
                ..Default::default()
            }),
        )
        .await
        .unwrap()
    else {
        panic!()
    };
    assert_eq!(devices.len(), 1);
    assert_eq!(devices[0].id, "M-01");
    for request in [
        CapabilityRequest::SnapshotRead,
        CapabilityRequest::SourcesRead(SourceQuery::default()),
        CapabilityRequest::OpcuaNodesRead(NodeQuery {
            source: Some(DataSourceId::new("b").unwrap()),
            ..Default::default()
        }),
        CapabilityRequest::DeviceRead(DeviceRequest {
            id: "b:M-01".into(),
        }),
    ] {
        assert_eq!(
            service.execute(&ctx, request).await.unwrap_err().kind,
            CapabilityErrorCode::PermissionDenied
        );
    }
    assert!(state.shutdown().await.clean);
}
#[tokio::test]
async fn unsupported_and_invalid_input_remain_typed_without_http() {
    let state = state(false);
    let service = ApplicationServices::new(state.clone());
    let error = service
        .execute(&context(), request("sensor"))
        .await
        .unwrap_err();
    assert_eq!(error.kind, CapabilityErrorCode::OperationNotSupported);
    assert_eq!(error.code, "DEMO_DISABLED");
    let error = service
        .execute(
            &context(),
            CapabilityRequest::DevicesRead(DeviceQuery {
                q: Some("x".repeat(257)),
                ..Default::default()
            }),
        )
        .await
        .unwrap_err();
    assert_eq!(error.kind, CapabilityErrorCode::InvalidInput);
    let mut ctx = context();
    ctx.permissions.remove(&Permission::TelemetryRead);
    assert!(service
        .discover(&ctx)
        .iter()
        .all(|c| !c.permission.contains(&Permission::TelemetryRead)));
    assert_eq!(
        service
            .execute(
                &ctx,
                CapabilityRequest::DeviceRead(DeviceRequest { id: "M-01".into() })
            )
            .await
            .unwrap_err()
            .kind,
        CapabilityErrorCode::PermissionDenied
    );
    assert!(state.shutdown().await.clean);
}
