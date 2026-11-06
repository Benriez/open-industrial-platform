//! Real SQLite/application/REST/official-SDK parity and least-privilege settings contracts.
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
use std::{
    path::PathBuf,
    sync::{
        atomic::{AtomicUsize, Ordering},
        Arc,
    },
};
use tower::ServiceExt as _;
fn context(p: &str) -> ExecutionContext {
    McpPolicy {
        principal: Some(PrincipalId::new(p).unwrap()),
        actor: String::new(),
        permissions: Default::default(),
        sources: SourceScope::Only(Default::default()),
    }
    .execution_context()
}
async fn fixture() -> (AppState, Arc<ApplicationServices>, PathBuf) {
    static SEQ: AtomicUsize = AtomicUsize::new(0);
    let dir = PathBuf::from(format!(
        "/private/tmp/oip84-unit-{}-{}",
        std::process::id(),
        SEQ.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::create_dir(&dir).unwrap();
    let c: CoreConfig = serde_json::from_str(include_str!(
        "../../../examples/multi-infrastructure-core.json"
    ))
    .unwrap();
    let mut plan: ProvisioningPlan = serde_json::from_str(include_str!(
        "../../../examples/multi-infrastructure-plan.json"
    ))
    .unwrap();
    plan.roles.push(ReadRole {
        id: RoleId::new("settings").unwrap(),
        name: "Explicit settings scope grants".into(),
        permissions: [
            Permission::SettingsRead,
            Permission::SettingsWrite,
            Permission::McpManagementRead,
        ]
        .into(),
    });
    for (principal, scope) in [
        ("platform-reader", AccessScope::Platform),
        (
            "reader-org-a",
            AccessScope::Organization(OrganizationId::new("org-a").unwrap()),
        ),
    ] {
        plan.bindings.push(RoleBinding {
            principal_id: PrincipalId::new(principal).unwrap(),
            role_id: RoleId::new("settings").unwrap(),
            scope,
        })
    }
    let path = dir.join("e.sqlite");
    let defs = c
        .sources
        .iter()
        .map(|s| s.definition().unwrap())
        .collect::<Vec<_>>();
    {
        let _ownership = oip_storage::DatabaseOwnership::acquire(&path).unwrap();
        let mut db = SqliteStore::open(&path).unwrap();
        db.provision(plan, &defs, None).unwrap();
        for s in &c.sources {
            for i in 0..20 {
                db.ingest_event(
                    &EventContext {
                        data_source_id: DataSourceId::new(&s.id).unwrap(),
                        origin_class: OriginClass::Simulation,
                    },
                    &ClientEvent::ConnectionLost {
                        at: Timestamp::from_unix_millis(1000 + i),
                        reason: "test recorded event".into(),
                    },
                )
                .unwrap();
            }
        }
    }
    for (scope, value) in [
        (AccessScope::Platform, 40),
        (
            AccessScope::Organization(OrganizationId::new("org-a").unwrap()),
            30,
        ),
        (
            AccessScope::Infrastructure(InfrastructureId::new("infra-a1").unwrap()),
            20,
        ),
        (AccessScope::Site(SiteId::new("site-a1").unwrap()), 10),
        (
            AccessScope::Source(DataSourceId::new("source-a").unwrap()),
            7,
        ),
    ] {
        SqliteStore::change_settings_file(
            &path,
            SettingsChange {
                principal: PrincipalId::new("platform-reader").unwrap(),
                scope,
                key: SettingKey::HistoryPageSize,
                value: SettingValue::Integer(value),
                expected_revision: 0,
            },
            123,
        )
        .unwrap();
    }
    let state = AppState::configured(SqliteStore::open(&path).unwrap(), &c, None).unwrap();
    let service = Arc::new(ApplicationServices::new(state.clone()));
    (state, service, dir)
}
async fn clean(state: AppState, path: PathBuf) {
    assert!(state.shutdown().await.clean);
    std::fs::remove_dir_all(path).unwrap();
}
#[tokio::test]
async fn actual_history_defaults_all_ancestor_levels_and_explicit_limit() {
    let (state, s, path) = fixture().await;
    let ctx = context("reader-org-a");
    for (query, expected) in [
        (serde_json::json!({"source":"source-a"}), 7),
        (serde_json::json!({"site":"site-a1"}), 10),
        (serde_json::json!({"infrastructure":"infra-a1"}), 20),
        (serde_json::json!({"organization":"org-a"}), 30),
        (serde_json::json!({}), 40),
        (serde_json::json!({"source":"source-a","limit":2}), 2),
    ] {
        let q = serde_json::from_value(query).unwrap();
        match s
            .execute(&ctx, CapabilityRequest::EventHistoryRead(q))
            .await
            .unwrap()
        {
            CapabilityOutput::DiagnosticPage(p) => assert_eq!(p.items.len(), expected),
            _ => panic!("output"),
        }
    }
    clean(state, path).await;
}
#[tokio::test]
async fn rest_and_official_sdk_have_identical_authorized_settings() {
    let (state, s, path) = fixture().await;
    let ctx = context("reader-org-a");
    let q: SettingsQuery =
        serde_json::from_value(serde_json::json!({"scope":"source","scope_id":"source-a"}))
            .unwrap();
    let direct = s
        .execute(&ctx, CapabilityRequest::SettingsRead(q))
        .await
        .unwrap();
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o700)).unwrap();
    let cred = path.join("credential");
    std::fs::write(&cred, [13; 32]).unwrap();
    std::fs::set_permissions(&cred, std::fs::Permissions::from_mode(0o600)).unwrap();
    let ipc_file = path.join("ipc.json");
    std::fs::write(&ipc_file,serde_json::to_vec(&serde_json::json!({"socket":path.join("s"),"clients":[{"uid":oip_server::mcp::ipc::local_uid().unwrap(),"credential_file":cred,"policy":{"principal":"reader-org-a"}}]})).unwrap()).unwrap();
    std::fs::set_permissions(&ipc_file, std::fs::Permissions::from_mode(0o600)).unwrap();
    let ipc = oip_server::mcp::ipc::LocalIpc::prepare(&ipc_file)
        .await
        .unwrap();
    let identities = ipc.rest_identities();
    drop(ipc);
    let router = api::router_with_identity(state.clone(), s.clone(), None, identities, None);
    let r = router
        .oneshot(
            Request::builder()
                .uri("/api/v2/settings?scope=source&scope_id=source-a")
                .header("host", "localhost")
                .header("authorization", format!("Bearer {}", "0d".repeat(32)))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(r.status(), 200);
    let rest: serde_json::Value =
        serde_json::from_slice(&to_bytes(r.into_body(), 1_000_000).await.unwrap()).unwrap();
    let (client, server) = tokio::io::duplex(1_000_000);
    let adapter = McpAdapter::new(
        s.clone(),
        McpPolicy {
            principal: ctx.principal.clone(),
            actor: String::new(),
            permissions: Default::default(),
            sources: SourceScope::Only(Default::default()),
        },
    )
    .unwrap();
    let task = tokio::spawn(async move {
        adapter
            .serve(server)
            .await
            .unwrap()
            .waiting()
            .await
            .unwrap();
    });
    let sdk = ().serve(client).await.unwrap();
    let result = sdk
        .call_tool(
            CallToolRequestParams::new("oip_settings_read").with_arguments(
                serde_json::json!({"scope":"source","scope_id":"source-a"})
                    .as_object()
                    .unwrap()
                    .clone(),
            ),
        )
        .await
        .unwrap();
    let direct = serde_json::to_value(direct).unwrap();
    assert_eq!(direct["value"], rest);
    assert_eq!(result.structured_content.unwrap(), direct);
    assert_eq!(rest["settings"][0]["effective"]["value"], 7);
    assert!(rest["settings"][0]["persisted"]["actor"].is_null());
    sdk.cancel().await.unwrap();
    task.await.unwrap();
    clean(state, path).await;
}
#[tokio::test]
async fn foreign_scopes_platform_management_forged_actor_and_mutations_denied() {
    let (state, s, path) = fixture().await;
    let mut ctx = context("reader-org-a");
    for q in [
        serde_json::json!({}),
        serde_json::json!({"scope":"organization","scope_id":"org-b"}),
        serde_json::json!({"scope":"source","scope_id":"source-d"}),
    ] {
        assert!(s
            .execute(
                &ctx,
                CapabilityRequest::SettingsRead(serde_json::from_value(q).unwrap())
            )
            .await
            .is_err());
    }
    assert!(s
        .execute(
            &ctx,
            CapabilityRequest::McpManagementRead(ManagementQuery::default())
        )
        .await
        .is_err());
    ctx.actor = "platform-reader".into();
    assert!(s
        .execute(
            &ctx,
            CapabilityRequest::SettingsRead(SettingsQuery::default())
        )
        .await
        .is_err());
    let ctx = context("platform-reader");
    let change = SettingsChange {
        principal: ctx.principal.clone().unwrap(),
        scope: AccessScope::Platform,
        key: SettingKey::HistoryPageSize,
        value: SettingValue::Integer(5),
        expected_revision: 1,
    };
    assert!(s
        .execute(&ctx, CapabilityRequest::SettingsChange(change))
        .await
        .is_err());
    let old = context("reader-org-b");
    assert!(!s.discover(&old).iter().any(|d| matches!(
        d.id,
        CapabilityId::SettingsRead | CapabilityId::McpManagementRead
    )));
    clean(state, path).await;
}
#[tokio::test]
async fn management_catalog_schema_and_configuration_redaction() {
    let (state, s, path) = fixture().await;
    let ctx = context("platform-reader");
    let adapter = McpAdapter::new(
        s.clone(),
        McpPolicy {
            principal: ctx.principal.clone(),
            actor: String::new(),
            permissions: Default::default(),
            sources: SourceScope::Only(Default::default()),
        },
    )
    .unwrap();
    let tools = adapter.tools();
    assert_eq!(tools.len(), 19);
    for section in [
        ManagementSection::Server,
        ManagementSection::Tools,
        ManagementSection::Permissions,
        ManagementSection::ClientConfiguration,
        ManagementSection::Sessions,
        ManagementSection::Diagnostics,
        ManagementSection::Storage,
        ManagementSection::System,
        ManagementSection::Security,
        ManagementSection::DiagnosticRules,
    ] {
        let out = s
            .execute(
                &ctx,
                CapabilityRequest::McpManagementRead(ManagementQuery { section }),
            )
            .await
            .unwrap();
        let value = serde_json::to_value(&out).unwrap();
        let tool = tools
            .iter()
            .find(|t| t.name == "oip_mcp_management_read")
            .unwrap();
        let schema =
            serde_json::Value::Object(tool.output_schema.as_ref().unwrap().as_ref().clone());
        assert!(jsonschema::validator_for(&schema).unwrap().is_valid(&value));
        if let CapabilityOutput::Management(r) = out {
            if let Some(c) = r.client_configuration {
                let config: serde_json::Value =
                    serde_json::from_str(&c.configuration_json).unwrap();
                assert_eq!(config["mcpServers"]["oip-local"]["args"][0], "--mcp-bridge");
                assert!(!c.usable_without_replacement);
                assert!(!c.credential_provisioned);
                assert!(!c.configuration_json.contains(".credential"));
            }
        }
    }
    let mapping = oip_server::mcp::capability_mapping();
    let mutation = mapping["capabilities"]
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["capability"] == "settings_change")
        .unwrap();
    assert_eq!(mutation["rest"], false);
    assert_eq!(mutation["mcp_status"], "BLOCKED");
    clean(state, path).await;
}
