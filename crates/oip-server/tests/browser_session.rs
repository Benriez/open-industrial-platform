//! Browser session boundary: one-use pairing, exact Origin, CSRF on writes and
//! revocation. These are contract requirements of
//! `docs/architecture/real-device-onboarding.md` and were previously only
//! asserted by the external harness `tests/real_device/acceptance.py`.
use axum::{
    body::{to_bytes, Body},
    http::{HeaderMap, Request, StatusCode},
    Router,
};
use futures::StreamExt;
use oip_core::*;
use oip_server::{api, config::CoreConfig, state::AppState};
use oip_storage::SqliteStore;
use serde_json::{json, Value};
use std::{
    path::PathBuf,
    sync::atomic::{AtomicUsize, Ordering},
    time::Duration,
};
use tower::ServiceExt as _;

const HOST: &str = "127.0.0.1:18086";
const ORIGIN: &str = "http://127.0.0.1:18086";
const FOREIGN_ORIGIN: &str = "http://foreign.invalid";

fn dir() -> PathBuf {
    static N: AtomicUsize = AtomicUsize::new(0);
    let p = std::path::Path::new("/private/tmp").join(format!(
        "oip-browser-session-{}-{}",
        std::process::id(),
        N.fetch_add(1, Ordering::Relaxed)
    ));
    std::fs::create_dir_all(&p).unwrap();
    p
}

/// A managed multi-infrastructure state. Legacy single-infrastructure access is
/// off, so every protected read needs an authenticated browser session.
fn state() -> AppState {
    let path = dir().join("db.sqlite");
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
    AppState::configured(
        SqliteStore::open(&path).unwrap(),
        &CoreConfig::default(),
        None,
    )
    .unwrap()
}

async fn send(
    app: Router,
    method: &str,
    uri: &str,
    headers: Vec<(&str, String)>,
    body: Option<Value>,
) -> (StatusCode, Value, HeaderMap) {
    let mut builder = Request::builder()
        .uri(uri)
        .method(method)
        .header("host", HOST);
    for (name, value) in headers {
        builder = builder.header(name, value);
    }
    let request = match body {
        Some(v) => builder
            .header("content-type", "application/json")
            .body(Body::from(v.to_string()))
            .unwrap(),
        None => builder.body(Body::empty()).unwrap(),
    };
    let response = app.oneshot(request).await.unwrap();
    let status = response.status();
    let headers = response.headers().clone();
    let bytes = to_bytes(response.into_body(), 2_000_000).await.unwrap();
    let value = if bytes.is_empty() {
        Value::Null
    } else {
        serde_json::from_slice(&bytes).unwrap_or(Value::Null)
    };
    (status, value, headers)
}

async fn login(app: &Router, state: &AppState) -> (String, String) {
    let code = state
        .browser_sessions
        .issue(PrincipalId::new("platform-reader").unwrap())
        .unwrap();
    let (status, body, headers) = send(
        app.clone(),
        "POST",
        "/api/v2/browser/login",
        vec![("origin", ORIGIN.to_string())],
        Some(json!({"code": code})),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let cookie = headers
        .get("set-cookie")
        .expect("a session cookie")
        .to_str()
        .unwrap()
        .split(';')
        .next()
        .unwrap()
        .to_string();
    let csrf = body["csrf_token"].as_str().expect("csrf value").to_string();
    (cookie, csrf)
}

fn registration(id: &str) -> Value {
    json!({"changes":[{"operation":"register","device":{"id":id,"display_name":"Browser session fixture","device_type":"server","site_id":"site-a1","metadata":{}}}]})
}

/// A file-backed, multi-infrastructure state with one persisted observation.
///
/// The history reader needs a real SQLite file; an in-memory database answers
/// `HISTORY_UNAVAILABLE`. The source placements of the plan are kept, so a
/// device scoped query can resolve its source. A principal that is bound to a
/// scope but does not hold `telemetry_read` is added, because the permission
/// sets of the bindings of a principal are unioned.
fn history_state() -> (AppState, PathBuf) {
    let dir = dir();
    let path = dir.join("history.sqlite");
    let mut plan: ProvisioningPlan = serde_json::from_str(include_str!(
        "../../../examples/multi-infrastructure-plan.json"
    ))
    .unwrap();
    plan.principals.push(Principal {
        id: PrincipalId::new("no-telemetry").unwrap(),
        name: "No telemetry fixture".into(),
        enabled: true,
    });
    plan.roles.push(ReadRole {
        id: RoleId::new("no-telemetry").unwrap(),
        name: "no telemetry".into(),
        permissions: [Permission::EventsRead].into(),
    });
    plan.bindings.push(RoleBinding {
        principal_id: PrincipalId::new("no-telemetry").unwrap(),
        role_id: RoleId::new("no-telemetry").unwrap(),
        scope: AccessScope::Organization(OrganizationId::new("org-a").unwrap()),
    });
    let config: CoreConfig = serde_json::from_str(include_str!(
        "../../../examples/multi-infrastructure-core.json"
    ))
    .unwrap();
    let definitions = config
        .sources
        .iter()
        .map(|s| s.definition().unwrap())
        .collect::<Vec<_>>();
    {
        let _o = oip_storage::DatabaseOwnership::acquire(&path).unwrap();
        let mut db = SqliteStore::open(&path).unwrap();
        db.provision(plan, &definitions, None).unwrap();
        // One persisted observation of the source of device-a. It needs a
        // receive time, because a sample without one never matches the
        // history query.
        let ctx = EventContext {
            data_source_id: DataSourceId::new("source-a").unwrap(),
            origin_class: OriginClass::Simulation,
        };
        db.ingest_event(
            &ctx,
            &ClientEvent::Observation(Box::new(ObservationEnvelope {
                entity_id: EntityId::new("M-01").unwrap(),
                data_source_id: DataSourceId::new("source-a").unwrap(),
                metric_id: MetricId::new("temperature").unwrap(),
                value: Some(MetricValue::Float(61.2)),
                unit: Unit::Celsius,
                quality: DataQuality::Good,
                freshness: Freshness::Fresh,
                timestamps: Timestamps {
                    source: Timestamp::from_unix_millis(1000),
                    server: Some(Timestamp::from_unix_millis(1010)),
                    received: Some(Timestamp::from_unix_millis(1020)),
                },
                status_code: None,
                collection_error: None,
                simulation_origin: Some(SimulationOrigin {
                    origin_id: "oip-local-simulation-v1".into(),
                    seed: None,
                    scenario: None,
                    virtual_time_ms: None,
                    sequence: None,
                }),
            })),
        )
        .unwrap();
    }
    let state = AppState::configured(SqliteStore::open(&path).unwrap(), &config, None).unwrap();
    (state, dir)
}

/// A browser session for a named principal of the provisioned hierarchy.
async fn login_as(app: &Router, state: &AppState, principal: &str) -> String {
    let code = state
        .browser_sessions
        .issue(PrincipalId::new(principal).unwrap())
        .unwrap();
    let (status, body, headers) = send(
        app.clone(),
        "POST",
        "/api/v2/browser/login",
        vec![("origin", ORIGIN.to_string())],
        Some(json!({"code": code})),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    headers
        .get("set-cookie")
        .expect("a session cookie")
        .to_str()
        .unwrap()
        .split(';')
        .next()
        .unwrap()
        .to_string()
}

#[tokio::test]
async fn login_requires_the_exact_origin_and_a_single_use_code() {
    let state = state();
    let app = api::router(state.clone(), "missing");
    let code = state
        .browser_sessions
        .issue(PrincipalId::new("platform-reader").unwrap())
        .unwrap();
    let (status, _, _) = send(
        app.clone(),
        "POST",
        "/api/v2/browser/login",
        vec![("origin", FOREIGN_ORIGIN.to_string())],
        Some(json!({"code": code})),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, body, headers) = send(
        app.clone(),
        "POST",
        "/api/v2/browser/login",
        vec![("origin", ORIGIN.to_string())],
        Some(json!({"code": code})),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["authenticated"], true);
    assert_eq!(body["principal_id"], "platform-reader");
    assert_eq!(body["mode"], "local_operator_session");
    let cookie = headers.get("set-cookie").unwrap().to_str().unwrap();
    assert!(cookie.contains("HttpOnly"), "{cookie}");
    assert!(cookie.contains("SameSite=Strict"), "{cookie}");
    assert!(cookie.contains("Path=/"), "{cookie}");
    assert!(cookie.contains("Max-Age=1800"), "{cookie}");
    assert!(
        !cookie.to_lowercase().contains("domain="),
        "the cookie must stay host-only: {cookie}"
    );
    assert_eq!(headers.get("cache-control").unwrap(), "no-store");
    // The pairing code is single use.
    let (status, _, _) = send(
        app.clone(),
        "POST",
        "/api/v2/browser/login",
        vec![("origin", ORIGIN.to_string())],
        Some(json!({"code": code})),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn touch_id_pairing_requires_the_session_csrf_and_reissues_the_bound_principal() {
    let state = state();
    let app = api::router(state.clone(), "missing");
    let (session_cookie, csrf) = login(&app, &state).await;
    let credential = "a7".repeat(32);
    let headers = vec![
        ("origin", ORIGIN.to_string()),
        ("cookie", session_cookie.clone()),
        ("x-oip-csrf", csrf.clone()),
    ];
    let (status, body, _) = send(
        app.clone(),
        "POST",
        "/api/v2/browser/pairing",
        headers,
        Some(json!({"credential":credential})),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["paired"], true);

    let (status, _, _) = send(
        app.clone(),
        "POST",
        "/api/v2/browser/pairing",
        vec![
            ("origin", ORIGIN.to_string()),
            ("cookie", session_cookie.clone()),
            ("x-oip-csrf", "forged".to_string()),
        ],
        Some(json!({"credential":"b8".repeat(32)})),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    let (status, body, headers) = send(
        app.clone(),
        "POST",
        "/api/v2/browser/device-login",
        vec![("origin", ORIGIN.to_string())],
        Some(json!({"credential":credential})),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["principal_id"], "platform-reader");
    assert_eq!(body["authenticated"], true);
    let cookie = headers.get("set-cookie").unwrap().to_str().unwrap();
    assert!(cookie.contains("HttpOnly"), "{cookie}");
    assert!(cookie.contains("Max-Age=1800"), "{cookie}");
}

#[tokio::test]
async fn an_unauthenticated_session_query_never_exposes_a_csrf_value() {
    let state = state();
    let app = api::router(state.clone(), "missing");
    let (status, body, headers) =
        send(app.clone(), "GET", "/api/v2/browser/session", vec![], None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["authenticated"], false);
    assert!(body["csrf_token"].is_null(), "{body}");
    assert_eq!(headers.get("cache-control").unwrap(), "no-store");
}

#[tokio::test]
async fn cookie_authorized_writes_require_the_exact_origin_and_the_csrf_value() {
    let state = state();
    let app = api::router(state.clone(), "missing");
    let (cookie, csrf) = login(&app, &state).await;
    // The session alone authorizes a scoped read.
    let (status, body, _) = send(
        app.clone(),
        "GET",
        "/api/v2/inventory/devices",
        vec![("cookie", cookie.clone())],
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    // A cookie without the CSRF value never authorizes a write.
    for (uri, payload) in [
        (
            "/api/v2/inventory/apply",
            Some(registration("csrf-without-token")),
        ),
        (
            "/api/v2/device-connections",
            Some(json!({"operation":"cancel"})),
        ),
    ] {
        let (status, _, _) = send(
            app.clone(),
            "POST",
            uri,
            vec![("cookie", cookie.clone()), ("origin", ORIGIN.to_string())],
            payload,
        )
        .await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{uri} without csrf");
    }
    // A wrong CSRF value is rejected as well.
    let (status, _, _) = send(
        app.clone(),
        "POST",
        "/api/v2/inventory/apply",
        vec![
            ("cookie", cookie.clone()),
            ("origin", ORIGIN.to_string()),
            ("x-oip-csrf", "0".repeat(64)),
        ],
        Some(registration("csrf-wrong-value")),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    // The exact origin is part of the boundary.
    let (status, _, _) = send(
        app.clone(),
        "POST",
        "/api/v2/inventory/apply",
        vec![
            ("cookie", cookie.clone()),
            ("origin", FOREIGN_ORIGIN.to_string()),
            ("x-oip-csrf", csrf.clone()),
        ],
        Some(registration("csrf-foreign-origin")),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    // The logout route is protected the same way.
    let (status, _, _) = send(
        app.clone(),
        "DELETE",
        "/api/v2/browser/session",
        vec![("cookie", cookie.clone()), ("origin", ORIGIN.to_string())],
        None,
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    // With the exact origin and the session CSRF value the write succeeds.
    let (status, body, _) = send(
        app.clone(),
        "POST",
        "/api/v2/inventory/apply",
        vec![
            ("cookie", cookie.clone()),
            ("origin", ORIGIN.to_string()),
            ("x-oip-csrf", csrf.clone()),
        ],
        Some(registration("csrf-accepted")),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let (_, listed, _) = send(
        app.clone(),
        "GET",
        "/api/v2/inventory/devices",
        vec![("cookie", cookie)],
        None,
    )
    .await;
    assert!(
        listed["items"]
            .as_array()
            .unwrap()
            .iter()
            .any(|d| d["record"]["device"]["id"] == "csrf-accepted"),
        "{listed}"
    );
}

#[tokio::test]
async fn a_revoked_session_stops_every_cookie_authorized_request() {
    let state = state();
    let app = api::router(state.clone(), "missing");
    let (cookie, csrf) = login(&app, &state).await;
    let (status, body, headers) = send(
        app.clone(),
        "DELETE",
        "/api/v2/browser/session",
        vec![
            ("cookie", cookie.clone()),
            ("origin", ORIGIN.to_string()),
            ("x-oip-csrf", csrf),
        ],
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["logged_out"], true);
    assert!(headers
        .get("set-cookie")
        .unwrap()
        .to_str()
        .unwrap()
        .contains("Max-Age=0"));
    let (status, _, _) = send(
        app.clone(),
        "GET",
        "/api/v2/inventory/devices",
        vec![("cookie", cookie.clone())],
        None,
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, body, _) = send(
        app.clone(),
        "GET",
        "/api/v2/browser/session",
        vec![("cookie", cookie)],
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["authenticated"], false);
    assert!(body["csrf_token"].is_null(), "{body}");
}

#[tokio::test]
async fn a_revoked_session_stops_the_projection_stream() {
    let state = state();
    let app = api::router(state.clone(), "missing");
    let (cookie, csrf) = login(&app, &state).await;
    let response = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/api/v2/stream")
                .header("host", HOST)
                .header("cookie", cookie.clone())
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let mut stream = response.into_body().into_data_stream();
    let first = tokio::time::timeout(Duration::from_secs(10), stream.next())
        .await
        .expect("a first projection")
        .expect("an open stream")
        .expect("a readable chunk");
    let first = String::from_utf8_lossy(&first).to_string();
    assert!(
        first.contains("event: snapshot"),
        "the stream must deliver a projection before the revocation: {first}"
    );
    let (status, body, _) = send(
        app.clone(),
        "DELETE",
        "/api/v2/browser/session",
        vec![
            ("cookie", cookie.clone()),
            ("origin", ORIGIN.to_string()),
            ("x-oip-csrf", csrf),
        ],
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let mut reported = false;
    for _ in 0..8 {
        let chunk = tokio::time::timeout(Duration::from_secs(10), stream.next())
            .await
            .expect("a stream decision");
        let Some(chunk) = chunk else { break };
        let text = String::from_utf8_lossy(&chunk.unwrap()).to_string();
        if text.contains("event: error") {
            reported = true;
            break;
        }
        assert!(
            !text.contains("event: snapshot"),
            "a projection was delivered after the revocation: {text}"
        );
    }
    assert!(
        reported,
        "the stream must stop delivering projections after the revocation"
    );
}

/// The persisted history is authorized by the browser session cookie.
///
/// The seven history routes were proven with a bearer token only. The session
/// cookie is the transport that the operator UI uses, so its boundary is
/// proven here: a bound device is served, a foreign scope and an unknown
/// device stay invisible, a principal without the capability is refused and a
/// request without a session is refused.
#[tokio::test]
async fn the_persisted_history_is_authorized_by_the_browser_session_cookie() {
    let (state, dir) = history_state();
    let app = api::router(state.clone(), "missing");
    let bound = login_as(&app, &state, "reader-org-a").await;
    let foreign = login_as(&app, &state, "reader-org-b").await;
    let without_capability = login_as(&app, &state, "no-telemetry").await;

    // The bound device is served with the persisted sample of its source.
    let (status, body, _) = send(
        app.clone(),
        "GET",
        "/api/v2/observations/history?device=device-a",
        vec![("cookie", bound.clone())],
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let items = body["items"].as_array().expect("a list of items");
    assert_eq!(items.len(), 1, "{body}");
    assert_eq!(items[0]["category"], "observation");
    let observation = &items[0]["record"]["observation"];
    assert_eq!(observation["data_source_id"], "source-a");
    assert_eq!(observation["metric_id"], "temperature");
    // A stored sample is history; the Core never reports it as a live value.
    assert_eq!(observation["freshness"], "stale");
    assert_eq!(observation["value"]["float"], 61.2);
    // The page reports the continuation, not a total.
    assert_eq!(body["truncated"], false);
    assert!(body["next_cursor"].is_null(), "{body}");
    assert!(body.get("total").is_none(), "{body}");
    assert_eq!(body["missing_evidence"].as_array().unwrap().len(), 1);
    assert!(body["time_semantics"]
        .as_str()
        .unwrap()
        .contains("received time"));

    // A device outside the scope of the principal stays invisible. The answer
    // never names the foreign device or its source. device-a belongs to org-a
    // and device-d to org-b.
    for (cookie, device) in [(foreign.clone(), "device-a"), (bound.clone(), "device-d")] {
        let (status, body, _) = send(
            app.clone(),
            "GET",
            &format!("/api/v2/observations/history?device={device}"),
            vec![("cookie", cookie)],
            None,
        )
        .await;
        assert_eq!(status, StatusCode::NOT_FOUND, "{body}");
        assert_eq!(body["code"], "RESOURCE_NOT_ACCESSIBLE");
        assert_eq!(body["kind"], "resource_not_found");
    }
    // An unknown device is refused the same way.
    let (status, body, _) = send(
        app.clone(),
        "GET",
        "/api/v2/observations/history?device=device-absent",
        vec![("cookie", bound.clone())],
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{body}");
    assert_eq!(body["code"], "RESOURCE_NOT_ACCESSIBLE");

    // A principal that holds no telemetry_read never receives the history.
    let (status, body, _) = send(
        app.clone(),
        "GET",
        "/api/v2/observations/history?device=device-a",
        vec![("cookie", without_capability)],
        None,
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");
    assert_eq!(body["code"], "PERMISSION_DENIED");
    assert_eq!(body["kind"], "permission_denied");

    // A request without a session is refused as well.
    let (status, body, _) = send(
        app.clone(),
        "GET",
        "/api/v2/observations/history?device=device-a",
        vec![],
        None,
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN, "{body}");
    assert_eq!(body["code"], "PERMISSION_DENIED");

    // An unbounded page is refused instead of being answered.
    let (status, body, _) = send(
        app.clone(),
        "GET",
        "/api/v2/observations/history?device=device-a&limit=0",
        vec![("cookie", bound)],
        None,
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "{body}");
    assert_eq!(body["code"], "INVALID_DIAGNOSTIC_QUERY");

    state.shutdown().await;
    std::fs::remove_dir_all(dir).unwrap();
}
