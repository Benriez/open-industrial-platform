//! OIP-008.2: real SQLite, common capability services and official MCP SDK (no mocked decisions).
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
fn context(id: &str) -> ExecutionContext {
    McpPolicy {
        principal: Some(PrincipalId::new(id).unwrap()),
        actor: String::new(),
        permissions: Default::default(),
        sources: SourceScope::Only(Default::default()),
    }
    .execution_context()
}
async fn fixture() -> (AppState, Arc<ApplicationServices>, Arc<Audit>, PathBuf) {
    static N: AtomicUsize = AtomicUsize::new(0);
    let dir = PathBuf::from(format!(
        "/private/tmp/oip0082-unit-{}-{}",
        std::process::id(),
        N.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::create_dir(&dir).unwrap();
    let mut plan: ProvisioningPlan = serde_json::from_str(include_str!(
        "../../../examples/multi-infrastructure-plan.json"
    ))
    .unwrap();
    plan.principals.push(Principal {
        id: PrincipalId::new("events-only").unwrap(),
        name: "Events only fixture".into(),
        enabled: true,
    });
    plan.roles.push(ReadRole {
        id: RoleId::new("events-only").unwrap(),
        name: "events only".into(),
        permissions: [Permission::EventsRead].into(),
    });
    plan.bindings.push(RoleBinding {
        principal_id: PrincipalId::new("events-only").unwrap(),
        role_id: RoleId::new("events-only").unwrap(),
        scope: AccessScope::Organization(OrganizationId::new("org-a").unwrap()),
    });
    let c: CoreConfig = serde_json::from_str(include_str!(
        "../../../examples/multi-infrastructure-core.json"
    ))
    .unwrap();
    let mut db = SqliteStore::open(dir.join("e.sqlite")).unwrap();
    let defs = c
        .sources
        .iter()
        .map(|s| s.definition().unwrap())
        .collect::<Vec<_>>();
    let result = db.provision(plan, &defs, None).unwrap();
    assert_eq!(result.schema_version, 5);
    for s in &c.sources {
        let ctx = EventContext {
            data_source_id: DataSourceId::new(&s.id).unwrap(),
            origin_class: OriginClass::Simulation,
        };
        for i in 0..85 {
            db.ingest_event(
                &ctx,
                &ClientEvent::ConnectionLost {
                    at: Timestamp::from_unix_millis(1000 + i),
                    reason: format!("fixture-{i}"),
                },
            )
            .unwrap();
        }
        db.ingest_event(
            &ctx,
            &ClientEvent::Reconnected {
                at: Timestamp::from_unix_millis(1100),
                gap: DataGap {
                    started_at: Timestamp::from_unix_millis(1084),
                    ended_at: Timestamp::from_unix_millis(1100),
                    reason: "documented fixture".into(),
                },
            },
        )
        .unwrap();
    }
    let state = AppState::configured(db, &c, None).unwrap();
    state.started().await.unwrap();
    let audit = Arc::new(Audit::default());
    let svc = Arc::new(ApplicationServices::with_audit(
        state.clone(),
        audit.clone(),
    ));
    (state, svc, audit, dir)
}
async fn router(
    state: AppState,
    svc: Arc<ApplicationServices>,
    dir: &std::path::Path,
    p: &str,
) -> axum::Router {
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(dir, std::fs::Permissions::from_mode(0o700)).unwrap();
    let secret = dir.join("read.credential");
    std::fs::write(&secret, [7u8; 32]).unwrap();
    std::fs::set_permissions(&secret, std::fs::Permissions::from_mode(0o600)).unwrap();
    let cfg = dir.join("ipc.json");
    std::fs::write(&cfg,json!({"socket":dir.join("s"),"clients":[{"uid":oip_server::mcp::ipc::local_uid().unwrap(),"credential_file":secret,"policy":{"principal":p}}]}).to_string()).unwrap();
    std::fs::set_permissions(&cfg, std::fs::Permissions::from_mode(0o600)).unwrap();
    let ipc = oip_server::mcp::ipc::LocalIpc::prepare(&cfg).await.unwrap();
    ipc.validate_principals(&state).unwrap();
    api::router_with_identity(state, svc, None, ipc.rest_identities(), None)
}
async fn clean(s: AppState, dir: PathBuf) {
    assert!(s.shutdown().await.clean);
    drop(s);
    std::fs::remove_dir_all(dir).unwrap();
}
fn page(out: CapabilityOutput) -> DiagnosticPage {
    let CapabilityOutput::DiagnosticPage(p) = out else {
        panic!()
    };
    p
}
#[tokio::test]
async fn bounded_cursor_scope_filters_retry_and_long_traversal() {
    let (s, svc, _, dir) = fixture().await;
    let a = context("reader-org-a");
    let b = context("reader-org-b");
    let base = DiagnosticQuery {
        source: Some(DataSourceId::new("source-a").unwrap()),
        limit: Some(1),
        ..Default::default()
    };
    let mut q = base.clone();
    let mut keys = std::collections::BTreeSet::new();
    let first = page(
        svc.execute(&a, CapabilityRequest::EventHistoryRead(q.clone()))
            .await
            .unwrap(),
    );
    let token = first.next_cursor.clone().unwrap();
    for mut attack in [
        base.clone(),
        DiagnosticQuery {
            limit: Some(2),
            ..base.clone()
        },
        DiagnosticQuery {
            end_ms: Some(1040),
            ..base.clone()
        },
    ] {
        attack.cursor = Some(token.clone());
        let ctx = if attack.limit == base.limit && attack.end_ms.is_none() {
            &b
        } else {
            &a
        };
        assert!(svc
            .execute(ctx, CapabilityRequest::EventHistoryRead(attack))
            .await
            .is_err());
    }
    let mut same_visible = base.clone();
    same_visible.cursor = Some(token.clone());
    let foreign_same_sources = context("reader-infra-a1");
    assert_eq!(
        svc.execute(
            &foreign_same_sources,
            CapabilityRequest::EventHistoryRead(same_visible)
        )
        .await
        .unwrap_err()
        .code,
        "INVALID_DIAGNOSTIC_QUERY"
    );
    for _ in 0..100 {
        let p = page(
            svc.execute(&a, CapabilityRequest::EventHistoryRead(q.clone()))
                .await
                .unwrap(),
        );
        for item in p.items {
            let DiagnosticItem::Event(e) = item else {
                panic!()
            };
            assert!(keys.insert(e.id));
            assert_eq!(e.source.as_str(), "source-a");
        }
        if let Some(cursor) = p.next_cursor {
            q.cursor = Some(cursor);
        } else {
            break;
        }
    }
    assert_eq!(keys.len(), 86); // more than the old 64-token limit, without leaking memory
    clean(s, dir).await;
}
#[tokio::test]
async fn direct_rest_mcp_parity_for_all_seven_reads() {
    let (s, svc, _, dir) = fixture().await;
    let ctx = context("reader-org-a");
    let first = page(
        svc.execute(
            &ctx,
            CapabilityRequest::EventHistoryRead(DiagnosticQuery {
                source: Some(DataSourceId::new("source-a").unwrap()),
                limit: Some(1),
                ..Default::default()
            }),
        )
        .await
        .unwrap(),
    );
    let DiagnosticItem::Event(e) = &first.items[0] else {
        panic!()
    };
    let id = e.id.clone();
    let policy: McpPolicy = serde_json::from_value(json!({"principal":"reader-org-a"})).unwrap();
    let adapter = McpAdapter::new(svc.clone(), policy.clone()).unwrap();
    let (a, b) = tokio::io::duplex(1024 * 1024);
    let server =
        tokio::spawn(async move { adapter.serve(a).await.unwrap().waiting().await.unwrap() });
    let client = ().serve(b).await.unwrap();
    let tools = client.list_all_tools().await.unwrap();
    let detail = tools
        .iter()
        .find(|t| t.name == "oip_event_detail_read")
        .unwrap();
    let schema = serde_json::to_value(&detail.input_schema).unwrap();
    let validator = jsonschema::validator_for(&schema).unwrap();
    assert!(!validator.is_valid(&json!({})));
    assert!(validator.is_valid(&json!({"event_id":id})));
    let evidence = tools
        .iter()
        .find(|t| t.name == "oip_evidence_read")
        .unwrap();
    let schema = serde_json::to_value(&evidence.input_schema).unwrap();
    let validator = jsonschema::validator_for(&schema).unwrap();
    for bad in [
        json!({}),
        json!({"source":"source-a"}),
        json!({"start_ms":0,"end_ms":2000}),
        json!({"source":"source-a","start_ms":0,"end_ms":2000,"limit":1}),
    ] {
        assert!(!validator.is_valid(&bad));
    }
    let router = router(s.clone(), svc.clone(), &dir, "reader-org-a").await;
    for (cap, tool, path) in [
        ("event_history_read", "event_history_read", "events/history"),
        ("event_detail_read", "event_detail_read", "events/detail"),
        ("data_gaps_read", "data_gaps_read", "diagnostics/gaps"),
        (
            "source_health_history_read",
            "source_health_history_read",
            "diagnostics/health-history",
        ),
        ("evidence_read", "evidence_read", "diagnostics/evidence"),
        (
            "diagnostic_findings_read",
            "diagnostic_findings_read",
            "diagnostics/findings",
        ),
        (
            "observation_history_read",
            "observation_history_read",
            "observations/history",
        ),
    ] {
        let mut args = json!({"source":"source-a","start_ms":0,"end_ms":2000,"limit":100});
        if cap == "event_detail_read" || cap == "evidence_read" {
            args["event_id"] = json!(id);
        }
        let request: CapabilityRequest =
            serde_json::from_value(json!({"capability":cap,"input":args})).unwrap();
        let direct = serde_json::to_value(svc.execute(&ctx, request).await.unwrap()).unwrap();
        let mcp = client
            .call_tool(
                CallToolRequestParams::new(format!("oip_{tool}"))
                    .with_arguments(args.as_object().unwrap().clone()),
            )
            .await
            .unwrap();
        assert!(!mcp.is_error.unwrap_or(false), "{mcp:?}");
        assert_eq!(direct, mcp.structured_content.unwrap());
        let suffix = if cap == "event_detail_read" || cap == "evidence_read" {
            format!("&event_id={id}")
        } else {
            String::new()
        };
        let response = router
            .clone()
            .oneshot(
                Request::builder()
                    .header("host", "127.0.0.1:18808")
                    .header("authorization", format!("Bearer {}", "07".repeat(32)))
                    .uri(format!(
                        "/api/v2/{path}?source=source-a&start_ms=0&end_ms=2000&limit=100{suffix}"
                    ))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), 200);
        let rest: Value = serde_json::from_slice(
            &to_bytes(response.into_body(), 4 * 1024 * 1024)
                .await
                .unwrap(),
        )
        .unwrap();
        assert_eq!(direct["value"], rest, "{cap}");
    }
    client.cancel().await.unwrap();
    server.await.unwrap();
    clean(s, dir).await;
}
#[tokio::test]
async fn permission_content_default_deny_foreign_evidence_and_audit() {
    let (s, svc, audit, dir) = fixture().await;
    let q = DiagnosticQuery {
        organization: Some(OrganizationId::new("org-a").unwrap()),
        limit: Some(100),
        ..Default::default()
    };
    let only = context("events-only");
    for req in [
        CapabilityRequest::EventHistoryRead(q.clone()),
        CapabilityRequest::SourceHealthHistoryRead(q.clone()),
        CapabilityRequest::EvidenceRead(DiagnosticQuery {
            start_ms: Some(0),
            end_ms: Some(2000),
            source: Some(DataSourceId::new("source-a").unwrap()),
            ..Default::default()
        }),
    ] {
        assert!(svc.execute(&only, req).await.is_err());
    }
    assert!(svc
        .execute(&only, CapabilityRequest::DataGapsRead(q.clone()))
        .await
        .is_ok());
    let a = context("reader-org-a");
    svc.execute(&a, CapabilityRequest::EventHistoryRead(q))
        .await
        .unwrap();
    {
        let audits = audit.0.lock().unwrap();
        let last = audits.last().unwrap();
        assert!(matches!(last.scope, Some(AccessScope::Organization(_))));
    }
    let foreign = page(
        svc.execute(
            &context("reader-org-b"),
            CapabilityRequest::EventHistoryRead(DiagnosticQuery {
                limit: Some(1),
                ..Default::default()
            }),
        )
        .await
        .unwrap(),
    );
    let DiagnosticItem::Event(e) = &foreign.items[0] else {
        panic!()
    };
    for key in [e.id.clone(), "a".repeat(64)] {
        let error = svc
            .execute(
                &a,
                CapabilityRequest::EventDetailRead(DiagnosticQuery {
                    event_id: Some(key),
                    ..Default::default()
                }),
            )
            .await
            .unwrap_err();
        assert_eq!(error.code, "RESOURCE_NOT_ACCESSIBLE");
    }
    let health = svc
        .execute(
            &a,
            CapabilityRequest::SourceHealthHistoryRead(DiagnosticQuery::default()),
        )
        .await
        .unwrap();
    assert!(!serde_json::to_string(&health).unwrap().contains("run_id"));
    clean(s, dir).await;
}
#[tokio::test]
async fn invalid_inputs_and_oversized_persisted_payload_fail_bounded() {
    let (s, svc, _, dir) = fixture().await;
    let ctx = context("reader-org-a");
    for q in [
        DiagnosticQuery {
            start_ms: Some(-11644473600001),
            ..Default::default()
        },
        DiagnosticQuery {
            start_ms: Some(20),
            end_ms: Some(10),
            ..Default::default()
        },
        DiagnosticQuery {
            limit: Some(101),
            ..Default::default()
        },
        DiagnosticQuery {
            cursor: Some("x".into()),
            ..Default::default()
        },
        DiagnosticQuery {
            metric: Some(MetricId::new("t").unwrap()),
            ..Default::default()
        },
    ] {
        assert!(svc
            .execute(&ctx, CapabilityRequest::EventHistoryRead(q))
            .await
            .is_err());
    }
    s.ingest_for(
        &DataSourceId::new("source-a").unwrap(),
        ClientEvent::ConnectionLost {
            at: Timestamp::from_unix_millis(2000),
            reason: "x".repeat(70000),
        },
    )
    .await
    .unwrap();
    let q = DiagnosticQuery {
        source: Some(DataSourceId::new("source-a").unwrap()),
        start_ms: Some(2000),
        ..Default::default()
    };
    let e = svc
        .execute(&ctx, CapabilityRequest::EventHistoryRead(q))
        .await
        .unwrap_err();
    assert_eq!(e.code, "HISTORY_BYTE_LIMIT");
    assert!(s.view().health.live);
    let router = router(s.clone(), svc.clone(), &dir, "reader-org-a").await;
    let response = router
        .oneshot(
            Request::builder()
                .header("host", "127.0.0.1:18808")
                .header("authorization", format!("Bearer {}", "07".repeat(32)))
                .uri("/api/v2/events/history?source=source-a&start_ms=2000")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), 400);
    clean(s, dir).await;
}
#[tokio::test]
async fn failed_final_health_persistence_cannot_claim_clean_shutdown() {
    let (s, _, _, dir) = fixture().await;
    let db = rusqlite::Connection::open(dir.join("e.sqlite")).unwrap();
    db.execute_batch("CREATE TRIGGER reject_health BEFORE INSERT ON source_health_history BEGIN SELECT RAISE(ABORT,'injected'); END;").unwrap();
    s.connected(&DataSourceId::new("source-a").unwrap())
        .await
        .unwrap();
    let report = s.shutdown().await;
    assert!(!report.clean);
    assert!(report.uncommitted > 0);
    let result: String = db
        .query_row(
            "select result from core_runs order by id desc limit 1",
            [],
            |r| r.get(0),
        )
        .unwrap();
    assert_ne!(result, "stopped");
    drop(s);
    drop(db);
    std::fs::remove_dir_all(dir).unwrap();
}
