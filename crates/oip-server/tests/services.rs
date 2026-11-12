//! The declared service registry: the scope, the isolation and the parity of the transports.
use axum::{body::Body, http::Request};
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
use serde_json::json;
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
    (s.clone(), Arc::new(ApplicationServices::new(s)))
}
fn the_page(output: &CapabilityOutput) -> &ServicePage {
    let CapabilityOutput::ServiceRegistry(page) = output else {
        panic!("the capability did not answer a service page");
    };
    page
}

#[test]
fn the_plan_refuses_a_service_of_a_site_that_does_not_exist() {
    // The scope of a record must exist before the record exists.
    let mut broken = plan();
    broken.services[0].site_id = SiteId::new("absent").unwrap();
    assert!(HierarchyRegistry::new(broken).is_err());
    // A duplicate identity is refused.
    let mut duplicate = plan();
    duplicate.services[1].id = duplicate.services[0].id.clone();
    assert!(HierarchyRegistry::new(duplicate).is_err());
    // The plan of the example declares the services.
    assert_eq!(plan().services.len(), 3);
}

#[tokio::test]
async fn the_registry_holds_the_declared_services_of_the_authorized_scope() {
    let (s, svc) = fixture().await;
    let ctx = policy("reader-org-a").execution_context();
    let output = svc
        .execute(
            &ctx,
            CapabilityRequest::ServiceRegistryRead(ServiceQuery::default()),
        )
        .await
        .unwrap();
    let page = the_page(&output);
    // Every record carries the provenance **declared**: the Core measures no
    // service, and it says so.
    assert!(page.items.iter().all(|r| r.origin == ServiceOrigin::Declared));
    // The reader of the organization sees the services of its own sites and
    // never the service of the other organization.
    let ids: Vec<&str> = page.items.iter().map(|r| r.service.id.as_str()).collect();
    assert!(ids.contains(&"svc-a1-opcua"));
    assert!(ids.contains(&"svc-a1-https"));
    assert!(!ids.contains(&"svc-b1-ssh"));
    // The scope of a record is the site of its infrastructure.
    let declared = page
        .items
        .iter()
        .find(|r| r.service.id.as_str() == "svc-a1-opcua")
        .expect("the declared service of the site");
    assert_eq!(declared.organization_id.as_str(), "org-a");
    assert_eq!(declared.infrastructure_id.as_str(), "infra-a1");
    // The device of a record is the device of the inventory; a declaration
    // that names a device of another site leaves the relation unknown.
    assert_eq!(declared.device_id.as_ref().map(|d| d.as_str()), Some("device-a"));
    assert!(s.shutdown().await.clean);
}

#[tokio::test]
async fn a_foreign_service_is_refused_like_an_unknown_one() {
    let (s, svc) = fixture().await;
    let ctx = policy("reader-org-a").execution_context();
    // The service of the other organization is refused — and the answer does
    // not disclose whether the service exists.
    let foreign = svc
        .execute(
            &ctx,
            CapabilityRequest::ServiceRegistryRead(ServiceQuery {
                id: Some(ServiceId::new("svc-b1-ssh").unwrap()),
                ..Default::default()
            }),
        )
        .await
        .unwrap_err();
    let unknown = svc
        .execute(
            &ctx,
            CapabilityRequest::ServiceRegistryRead(ServiceQuery {
                id: Some(ServiceId::new("svc-absent").unwrap()),
                ..Default::default()
            }),
        )
        .await
        .unwrap_err();
    assert_eq!(foreign.kind, CapabilityErrorCode::ResourceNotFound);
    assert_eq!(unknown.kind, CapabilityErrorCode::ResourceNotFound);
    assert_eq!(foreign.code, unknown.code);
    assert_eq!(foreign.code, "RESOURCE_NOT_ACCESSIBLE");
    // A foreign organization is refused the same way.
    let organization = svc
        .execute(
            &ctx,
            CapabilityRequest::ServiceRegistryRead(ServiceQuery {
                organization: Some(OrganizationId::new("org-b").unwrap()),
                ..Default::default()
            }),
        )
        .await
        .unwrap_err();
    assert_eq!(organization.code, "RESOURCE_NOT_ACCESSIBLE");
    assert!(s.shutdown().await.clean);
}

#[tokio::test]
async fn the_rest_and_the_mcp_tool_deliver_the_same_registry() {
    let (s, svc) = fixture().await;
    let p = policy("reader-org-a");
    let ctx = p.execution_context();
    let output = svc
        .execute(
            &ctx,
            CapabilityRequest::ServiceRegistryRead(ServiceQuery::default()),
        )
        .await
        .unwrap();
    let expected = the_page(&output);
    let adapter = McpAdapter::new(svc.clone(), p).unwrap();
    let (a, b) = tokio::io::duplex(65536);
    let task =
        tokio::spawn(async move { adapter.serve(a).await.unwrap().waiting().await.unwrap() });
    let client = ().serve(b).await.unwrap();
    let tools = client.peer().list_all_tools().await.unwrap();
    let tool = tools.iter().find(|t| t.name == "oip_services_read").expect("the tool");
    assert_eq!(tool.description.as_deref().unwrap_or("").contains("declared"), true);
    let response = client
        .peer()
        .call_tool(CallToolRequestParams::new("oip_services_read").with_arguments(
            serde_json::Map::new(),
        ))
        .await
        .unwrap();
    assert!(!response.is_error.unwrap_or(false));
    let actual = response.structured_content.unwrap();
    let page = actual
        .get("value")
        .and_then(|v| v.get("items"))
        .and_then(|v| v.as_array())
        .expect("the tool answered a service page");
    assert_eq!(page.len(), expected.items.len());
    let ids: Vec<&str> = page
        .iter()
        .filter_map(|r| r.get("service"))
        .filter_map(|s| s.get("id"))
        .filter_map(|s| s.as_str())
        .collect();
    assert!(ids.contains(&"svc-a1-opcua"));
    assert!(!ids.contains(&"svc-b1-ssh"));
    client.cancel().await.unwrap();
    task.await.unwrap();
    // The route of the registry exists and is authorized: without a session it
    // is refused, like every other route.
    let app = api::router_with_service(s.clone(), svc, None, None);
    let r = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/api/v2/services")
                .header("host", "127.0.0.1:18808")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(r.status(), 403);
    assert!(s.shutdown().await.clean);
}
