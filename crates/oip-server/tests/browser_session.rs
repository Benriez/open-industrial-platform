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
