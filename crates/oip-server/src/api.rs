use crate::{application_services::ApplicationServices, state::AppState};
use axum::extract::FromRequestParts;
use axum::{
    body::Body,
    extract::{Path, Query, Request},
    http::{header, HeaderValue, StatusCode},
    middleware::{self, Next},
    response::{
        sse::{Event, KeepAlive},
        IntoResponse, Response, Sse,
    },
    routing::{get, post},
    Json, Router,
};
use flate2::{write::GzEncoder, Compression};
use futures::{stream, StreamExt};
use oip_core::*;
use serde_json::json;
use sha2::{Digest, Sha256};
use std::{convert::Infallible, io::Write, sync::Arc, time::Duration};

#[derive(Clone)]
struct ApiContext {
    state: AppState,
    service: Arc<ApplicationServices>,
    authority: Option<ExecutionContext>,
    credentials: crate::identity::RestIdentities,
    browser_token: Option<String>,
}
struct Authorized(ApiContext);
impl FromRequestParts<ApiContext> for Authorized {
    type Rejection = CapabilityErrorResponse;
    async fn from_request_parts(
        parts: &mut axum::http::request::Parts,
        state: &ApiContext,
    ) -> Result<Self, Self::Rejection> {
        let mut s = state.clone();
        if let Some(value) = parts.headers.get(axum::http::header::AUTHORIZATION) {
            s.authority = Some(
                s.credentials
                    .authenticate(
                        value
                            .to_str()
                            .map_err(|_| CapabilityErrorResponse(denied()))?,
                    )
                    .map_err(CapabilityErrorResponse)?,
            );
        } else if let Some(token) = crate::browser_session::cookie(&parts.headers) {
            s.browser_token = Some(token.to_owned());
            let changing =
                parts.method != axum::http::Method::GET && parts.method != axum::http::Method::HEAD;
            let csrf = if changing {
                crate::browser_session::require_origin(&parts.headers)
                    .map_err(CapabilityErrorResponse)?;
                Some(
                    parts
                        .headers
                        .get("x-oip-csrf")
                        .and_then(|v| v.to_str().ok())
                        .ok_or_else(|| CapabilityErrorResponse(denied()))?,
                )
            } else {
                None
            };
            let active = !matches!(parts.uri.path(), "/api/v1/stream" | "/api/v2/stream");
            s.authority = Some(
                s.state
                    .browser_sessions
                    .check_session(token, csrf, active)
                    .map_err(CapabilityErrorResponse)?,
            );
        } else if !s.state.legacy_access {
            return Err(CapabilityErrorResponse(denied()));
        }
        Ok(Self(s))
    }
}
impl std::ops::Deref for ApiContext {
    type Target = AppState;
    fn deref(&self) -> &AppState {
        &self.state
    }
}
use tower_http::{services::ServeDir, set_header::SetResponseHeaderLayer};

pub struct ApiError(pub StatusCode, pub &'static str, pub &'static str);
impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        (
            self.0,
            Json(json!({"ok":false,"code":self.1,"message":self.2})),
        )
            .into_response()
    }
}
impl IntoResponse for CapabilityErrorResponse {
    fn into_response(self) -> Response {
        let e = self.0;
        let status = match e.kind {
            CapabilityErrorCode::ResourceNotFound => StatusCode::NOT_FOUND,
            CapabilityErrorCode::InvalidInput => StatusCode::BAD_REQUEST,
            CapabilityErrorCode::PermissionDenied => StatusCode::FORBIDDEN,
            CapabilityErrorCode::OperationNotSupported => StatusCode::CONFLICT,
            CapabilityErrorCode::SourceUnavailable | CapabilityErrorCode::DataStale => {
                StatusCode::SERVICE_UNAVAILABLE
            }
            CapabilityErrorCode::PersistenceUnavailable | CapabilityErrorCode::AuditUnavailable => {
                StatusCode::INTERNAL_SERVER_ERROR
            }
        };
        (
            status,
            Json(json!({"ok":false,"code":e.code,"message":e.message,"kind":e.kind})),
        )
            .into_response()
    }
}
struct CapabilityErrorResponse(CapabilityError);
async fn call(
    s: ApiContext,
    request: CapabilityRequest,
) -> Result<CapabilityOutput, CapabilityErrorResponse> {
    let mut s = s;
    if let Some(token) = &s.browser_token {
        s.authority = Some(
            s.state
                .browser_sessions
                .check_session(token, None, false)
                .map_err(CapabilityErrorResponse)?,
        );
    }
    let mut context = s.service.local_context();
    if let Some(authority) = s.authority {
        context.principal = authority.principal;
        context.actor = authority.actor;
        context.permissions = authority.permissions;
        context.sources = authority.sources;
    }
    s.service
        .execute(&context, request)
        .await
        .map_err(CapabilityErrorResponse)
}
fn mismatch() -> CapabilityErrorResponse {
    CapabilityErrorResponse(CapabilityError::new(
        CapabilityErrorCode::OperationNotSupported,
        "CONTRACT_MISMATCH",
        "Application output type mismatch",
    ))
}
pub fn router(state: AppState, web_dir: &str) -> Router {
    router_optional(state, Some(web_dir))
}

pub fn router_optional(state: AppState, web_dir: Option<&str>) -> Router {
    let service = Arc::new(ApplicationServices::new(state.clone()));
    router_with_service(state, service, None, web_dir)
}
/// The authority is supplied only by the local host, never HTTP inputs.
pub fn router_with_service(
    state: AppState,
    service: Arc<ApplicationServices>,
    authority: Option<ExecutionContext>,
    web_dir: Option<&str>,
) -> Router {
    router_with_identity(
        state,
        service,
        authority,
        crate::identity::RestIdentities::default(),
        web_dir,
    )
}
pub fn router_with_identity(
    state: AppState,
    service: Arc<ApplicationServices>,
    authority: Option<ExecutionContext>,
    credentials: crate::identity::RestIdentities,
    web_dir: Option<&str>,
) -> Router {
    let routes = Router::new()
        .route(
            "/api/v2/browser/session",
            get(browser_session).delete(browser_logout),
        )
        .route(
            "/api/v2/browser/login",
            post(browser_login).layer(axum::extract::DefaultBodyLimit::max(1024)),
        )
        .route(
            "/api/v2/browser/pairing",
            post(browser_pair_device).layer(axum::extract::DefaultBodyLimit::max(1024)),
        )
        .route(
            "/api/v2/browser/device-login",
            post(browser_device_login).layer(axum::extract::DefaultBodyLimit::max(1024)),
        )
        .route(
            "/api/v2/browser/device-credentials",
            get(browser_paired_devices),
        )
        .route(
            "/api/v2/browser/device-credentials/{id}",
            axum::routing::patch(browser_rename_device)
                .delete(browser_revoke_device)
                .layer(axum::extract::DefaultBodyLimit::max(1024)),
        )
        .route("/api/v2/installation/status", get(installation_status))
        .route("/api/v2/inventory/devices", get(inventory_read))
        .route(
            "/api/v2/hue/lights",
            get(hue_lights)
                .post(hue_control)
                .layer(axum::extract::DefaultBodyLimit::max(1024)),
        )
        .route(
            "/api/v2/hue/setup",
            post(hue_setup).layer(axum::extract::DefaultBodyLimit::max(1024)),
        )
        .route(
            "/api/v2/opcua/setup",
            post(opcua_setup).layer(axum::extract::DefaultBodyLimit::max(crate::opcua_setup::MAX_REQUEST)),
        )
        .route("/api/v2/services", get(services_read))
        .route("/api/v2/inventory/apply", post(inventory_apply))
        .route(
            "/api/v2/device-connections",
            get(connection_read)
                .post(connection_configure)
                .layer(axum::extract::DefaultBodyLimit::max(32 * 1024)),
        )
        .route("/api/v2/inventory/plan", post(inventory_plan))
        .route("/api/v2/settings", get(settings_read))
        .route("/api/v2/license", get(license_status))
        .route(
            "/api/v2/license/preview",
            post(license_preview).layer(axum::extract::DefaultBodyLimit::max(
                crate::licensing::MAX_PREVIEW_REQUEST,
            )),
        )
        .route(
            "/api/v2/license/apply",
            post(license_apply).layer(axum::extract::DefaultBodyLimit::max(1024)),
        )
        .route("/api/v2/management", get(management_read))
        .route("/api/v2/organizations", get(organizations))
        .route("/api/v2/infrastructures", get(infrastructures))
        .route("/api/v2/sites", get(sites))
        .route("/api/v2/sources", get(authorized_source_health))
        .route("/api/v2/support-package", get(support_package))
        .route("/api/v2/devices", get(devices))
        .route("/api/v2/devices/{id}", get(device))
        .route("/api/v2/observations", get(metrics))
        .route("/api/v2/events", get(events))
        .route("/api/v2/events/history", get(event_history))
        .route("/api/v2/events/detail", get(event_detail))
        .route("/api/v2/diagnostics/gaps", get(data_gaps))
        .route("/api/v2/diagnostics/health-history", get(health_history))
        .route("/api/v2/diagnostics/evidence", get(evidence))
        .route("/api/v2/diagnostics/findings", get(findings))
        .route("/api/v2/observations/history", get(observation_history))
        .route("/api/v2/opcua/nodes", get(nodes))
        .route("/api/v2/opcua/write", post(opcua_write))
        .route(
            "/api/v2/snapshot",
            get(scoped_snapshot).layer(middleware::from_fn(compress_live_projection)),
        )
        .route(
            "/api/v2/stream",
            get(scoped_sse).layer(middleware::from_fn(compress_live_projection)),
        )
        .route("/api/v1/system/status", get(status))
        .route("/api/v1/core/health", get(core_health))
        .route("/api/v1/sources", get(source_health))
        .route("/health/live", get(live))
        .route("/health/ready", get(ready))
        .route("/api/v1/devices", get(devices))
        .route("/api/v1/devices/{id}", get(device))
        .route("/api/v1/metrics/current", get(metrics))
        .route("/api/v1/events", get(events))
        .route("/api/v1/opcua/nodes", get(nodes))
        .route("/api/v1/stream", get(sse))
        .route("/api/v1/demo/scenario", post(scenario))
        .route(
            "/api/{*path}",
            get(|| async { ApiError(StatusCode::NOT_FOUND, "NOT_FOUND", "Unknown API route") }),
        );
    let routes = if let Some(dir) = web_dir {
        routes.fallback_service(ServeDir::new(dir))
    } else {
        routes.fallback(|| async {
            ApiError(StatusCode::NOT_FOUND, "NOT_FOUND", "No web assets enabled")
        })
    };
    routes
        .layer(SetResponseHeaderLayer::if_not_present(
            axum::http::header::CACHE_CONTROL,
            HeaderValue::from_static("no-cache"),
        ))
        .layer(middleware::from_fn(local_origin))
        .with_state(ApiContext {
            state,
            service,
            authority,
            credentials,
            browser_token: None,
        })
}

async fn compress_live_projection(request: Request, next: Next) -> Response {
    let accepts_gzip = request
        .headers()
        .get_all(header::ACCEPT_ENCODING)
        .iter()
        .filter_map(|value| value.to_str().ok())
        .flat_map(|value| value.split(','))
        .any(|encoding| {
            let (name, weight) = encoding.split_once(';').unwrap_or((encoding, "q=1"));
            name.trim().eq_ignore_ascii_case("gzip")
                && weight
                    .trim()
                    .strip_prefix("q=")
                    .and_then(|quality| quality.parse::<f32>().ok())
                    .is_some_and(|quality| quality > 0.0 && quality <= 1.0)
        });
    let mut response = next.run(request).await;
    if response.status() != StatusCode::OK {
        return response;
    }
    response
        .headers_mut()
        .append(header::VARY, HeaderValue::from_static("Accept-Encoding"));
    if !accepts_gzip {
        return response;
    }
    let (mut parts, body) = response.into_parts();
    parts.headers.remove(header::CONTENT_LENGTH);
    parts
        .headers
        .insert(header::CONTENT_ENCODING, HeaderValue::from_static("gzip"));
    let encoded = stream::try_unfold(
        (
            body.into_data_stream(),
            Some(GzEncoder::new(Vec::new(), Compression::fast())),
        ),
        |(mut body, encoder)| async move {
            let Some(mut encoder) = encoder else {
                return Ok::<_, axum::Error>(None);
            };
            if let Some(chunk) = body.next().await {
                encoder.write_all(&chunk?).map_err(axum::Error::new)?;
                // Flush every SSE frame (including keepalives) so compression
                // cannot delay the next visible update.
                encoder.flush().map_err(axum::Error::new)?;
                let bytes = std::mem::take(encoder.get_mut());
                Ok(Some((bytes, (body, Some(encoder)))))
            } else {
                let trailer = encoder.finish().map_err(axum::Error::new)?;
                Ok(Some((trailer, (body, None))))
            }
        },
    );
    Response::from_parts(parts, Body::from_stream(encoded))
}

async fn local_origin(request: Request, next: Next) -> Response {
    let valid_host = request
        .headers()
        .get("host")
        .and_then(|h| h.to_str().ok())
        .is_some_and(|h| {
            let host = h.split(':').next().unwrap_or("");
            host == "127.0.0.1" || host == "localhost"
        });
    let valid_origin = request.headers().get("origin").is_none_or(|origin| {
        let host = request
            .headers()
            .get("host")
            .and_then(|h| h.to_str().ok())
            .unwrap_or("");
        origin
            .to_str()
            .ok()
            .is_some_and(|o| o == format!("http://{host}"))
    });
    if !valid_host || !valid_origin {
        return ApiError(
            StatusCode::FORBIDDEN,
            "LOCAL_ONLY",
            "Only same-origin loopback development access is allowed",
        )
        .into_response();
    }
    let private_api = request.uri().path().starts_with("/api/");
    let mut response = next.run(request).await;
    response
        .headers_mut()
        .insert("x-frame-options", HeaderValue::from_static("DENY"));
    response.headers_mut().insert(
        "content-security-policy",
        HeaderValue::from_static("frame-ancestors 'none'"),
    );
    response
        .headers_mut()
        .insert("referrer-policy", HeaderValue::from_static("no-referrer"));
    if private_api {
        response.headers_mut().insert(
            axum::http::header::CACHE_CONTROL,
            HeaderValue::from_static("no-store"),
        );
    }
    response
}

async fn status(Authorized(s): Authorized) -> Result<Json<SystemStatus>, CapabilityErrorResponse> {
    match call(s, CapabilityRequest::SystemStatusRead).await? {
        CapabilityOutput::SystemStatus(v) => Ok(Json(v)),
        _ => Err(mismatch()),
    }
}
async fn devices(
    Authorized(s): Authorized,
    query: Result<Query<DeviceQuery>, axum::extract::rejection::QueryRejection>,
) -> Result<Json<Vec<Device>>, Response> {
    let Query(q) = query.map_err(|_| {
        ApiError(
            StatusCode::BAD_REQUEST,
            "INVALID_QUERY",
            "Invalid device query",
        )
        .into_response()
    })?;
    match call(s, CapabilityRequest::DevicesRead(q))
        .await
        .map_err(IntoResponse::into_response)?
    {
        CapabilityOutput::Devices(v) => Ok(Json(v)),
        _ => Err(mismatch().into_response()),
    }
}
async fn device(
    Authorized(s): Authorized,
    Path(id): Path<String>,
) -> Result<Json<DeviceDetail>, CapabilityErrorResponse> {
    match call(s, CapabilityRequest::DeviceRead(DeviceRequest { id })).await? {
        CapabilityOutput::Device(v) => Ok(Json(v)),
        _ => Err(mismatch()),
    }
}
async fn metrics(
    Authorized(s): Authorized,
    query: Result<Query<SourceQuery>, axum::extract::rejection::QueryRejection>,
) -> Result<Json<Vec<ObservationEnvelope>>, Response> {
    let Query(q) = query.map_err(|_| {
        ApiError(
            StatusCode::BAD_REQUEST,
            "INVALID_QUERY",
            "Invalid source query",
        )
        .into_response()
    })?;
    match call(s, CapabilityRequest::ObservationsRead(q))
        .await
        .map_err(IntoResponse::into_response)?
    {
        CapabilityOutput::Observations(v) => Ok(Json(v)),
        _ => Err(mismatch().into_response()),
    }
}
async fn events(
    Authorized(s): Authorized,
    query: Result<Query<SourceQuery>, axum::extract::rejection::QueryRejection>,
) -> Result<Json<EventsResponse>, Response> {
    let Query(q) = query.map_err(|_| {
        ApiError(
            StatusCode::BAD_REQUEST,
            "INVALID_QUERY",
            "Invalid source query",
        )
        .into_response()
    })?;
    match call(s, CapabilityRequest::EventsRead(q))
        .await
        .map_err(IntoResponse::into_response)?
    {
        CapabilityOutput::Events(v) => Ok(Json(v)),
        _ => Err(mismatch().into_response()),
    }
}
async fn nodes(
    Authorized(s): Authorized,
    query: Result<Query<NodeQuery>, axum::extract::rejection::QueryRejection>,
) -> Result<Json<NodePage>, Response> {
    let Query(q) = query.map_err(|_| {
        ApiError(
            StatusCode::BAD_REQUEST,
            "INVALID_QUERY",
            "offset/limit must be non-negative integers",
        )
        .into_response()
    })?;
    match call(s, CapabilityRequest::OpcuaNodesRead(q))
        .await
        .map_err(IntoResponse::into_response)?
    {
        CapabilityOutput::Nodes(v) => Ok(Json(v)),
        _ => Err(mismatch().into_response()),
    }
}
async fn opcua_write(
    Authorized(s): Authorized,
    body: Result<Json<NodeWriteRequest>, axum::extract::rejection::JsonRejection>,
) -> Result<Json<NodeWriteResult>, Response> {
    let Json(request) = body.map_err(|_| {
        ApiError(
            StatusCode::BAD_REQUEST,
            "INVALID_JSON",
            "Expected source, node_id, and typed value",
        )
        .into_response()
    })?;
    match call(s, CapabilityRequest::OpcuaNodeWrite(request))
        .await
        .map_err(IntoResponse::into_response)?
    {
        CapabilityOutput::NodeWrite(result) => Ok(Json(result)),
        _ => Err(mismatch().into_response()),
    }
}
async fn scenario(
    Authorized(s): Authorized,
    body: Result<Json<ScenarioRequest>, axum::extract::rejection::JsonRejection>,
) -> Result<Json<ScenarioResponse>, Response> {
    let Json(q) = body.map_err(|_| {
        ApiError(
            StatusCode::BAD_REQUEST,
            "INVALID_JSON",
            "Expected a scenario JSON object",
        )
        .into_response()
    })?;
    match call(s, CapabilityRequest::SimulationScenarioSet(q))
        .await
        .map_err(IntoResponse::into_response)?
    {
        CapabilityOutput::Scenario(v) => Ok(Json(v)),
        _ => Err(mismatch().into_response()),
    }
}
async fn core_health(
    Authorized(s): Authorized,
) -> Result<Json<CoreHealth>, CapabilityErrorResponse> {
    match call(s, CapabilityRequest::CoreHealthRead).await? {
        CapabilityOutput::CoreHealth(v) => Ok(Json(v)),
        _ => Err(mismatch()),
    }
}
async fn source_health(
    Authorized(s): Authorized,
    query: Result<Query<SourceQuery>, axum::extract::rejection::QueryRejection>,
) -> Result<Json<Vec<SourceHealth>>, Response> {
    let Query(q) = query.map_err(|_| {
        ApiError(
            StatusCode::BAD_REQUEST,
            "INVALID_QUERY",
            "Invalid source query",
        )
        .into_response()
    })?;
    match call(s, CapabilityRequest::SourcesRead(q))
        .await
        .map_err(IntoResponse::into_response)?
    {
        CapabilityOutput::Sources(v) => Ok(Json(v)),
        _ => Err(mismatch().into_response()),
    }
}
#[derive(serde::Serialize)]
struct AuthorizedSourceHealth {
    #[serde(flatten)]
    health: SourceHealth,
    opcua_browse: bool,
}
async fn authorized_source_health(
    Authorized(s): Authorized,
    query: Result<Query<SourceQuery>, axum::extract::rejection::QueryRejection>,
) -> Result<Json<Vec<AuthorizedSourceHealth>>, Response> {
    let allowed = s
        .authority
        .as_ref()
        .and_then(|authority| authority.principal.as_ref())
        .and_then(|principal| {
            s.hierarchy()
                .map(|h| h.allowed_sources(principal, CapabilityId::OpcuaNodesRead))
        })
        .unwrap_or_default();
    let bindings = s.opcua_browse_bindings.clone();
    let Json(health) = source_health(Authorized(s), query).await?;
    Ok(Json(
        health
            .into_iter()
            .map(|health| AuthorizedSourceHealth {
                opcua_browse: allowed.contains(&health.id)
                    && bindings.contains(&(health.id.clone(), health.entity_id.clone())),
                health,
            })
            .collect(),
    ))
}
async fn support_package(
    Authorized(s): Authorized,
    query: Result<Query<SupportPackageQuery>, axum::extract::rejection::QueryRejection>,
) -> Result<Json<SupportPackage>, CapabilityErrorResponse> {
    let Query(query) = query.map_err(|_| {
        CapabilityErrorResponse(CapabilityError::new(
            CapabilityErrorCode::InvalidInput,
            "SUPPORT_SCOPE_REQUIRED",
            "Select an authorized infrastructure for the support package",
        ))
    })?;
    match call(s, CapabilityRequest::SupportPackageRead(query)).await? {
        CapabilityOutput::SupportPackage(package) => Ok(Json(package)),
        _ => Err(mismatch()),
    }
}

async fn live(Authorized(s): Authorized) -> Result<impl IntoResponse, CapabilityErrorResponse> {
    match call(s, CapabilityRequest::CoreLivenessRead).await? {
        CapabilityOutput::CoreHealth(v) => Ok((
            if v.live {
                StatusCode::OK
            } else {
                StatusCode::SERVICE_UNAVAILABLE
            },
            Json(v),
        )),
        _ => Err(mismatch()),
    }
}
async fn ready(Authorized(s): Authorized) -> Result<impl IntoResponse, CapabilityErrorResponse> {
    match call(s, CapabilityRequest::CoreReadinessRead).await? {
        CapabilityOutput::CoreHealth(v) => Ok((
            if v.ready {
                StatusCode::OK
            } else {
                StatusCode::SERVICE_UNAVAILABLE
            },
            Json(v),
        )),
        _ => Err(mismatch()),
    }
}
async fn sse(Authorized(s): Authorized) -> Result<impl IntoResponse, CapabilityErrorResponse> {
    call(s.clone(), CapabilityRequest::SnapshotRead).await?;
    let rx = s.updates.subscribe();
    let output = stream::unfold(
        (s, rx, true, false),
        |(s, mut rx, first, terminal)| async move {
            if terminal || s.stopping.is_cancelled() {
                return None;
            }
            if !first {
                tokio::select! {_=s.stopping.cancelled()=>return None,changed=rx.changed()=>{if changed.is_err(){return None;}},_=tokio::time::sleep(Duration::from_secs(1))=>{}}
            }
            let result = call(s.clone(), CapabilityRequest::SnapshotRead).await;
            let terminal = result
                .as_ref()
                .is_err_and(|error| error.0.kind == CapabilityErrorCode::PermissionDenied);
            let event = match result {
                Ok(CapabilityOutput::Snapshot(snapshot)) => Event::default()
                    .event("snapshot")
                    .id(format!(
                        "{}:{}",
                        snapshot.core.run_id, snapshot.core.revision
                    ))
                    .json_data(snapshot)
                    .unwrap_or_else(|_| {
                        Event::default().event("error").data("serialization failed")
                    }),
                _ => Event::default()
                    .event("error")
                    .data("application snapshot unavailable"),
            };
            Some((Ok::<_, Infallible>(event), (s, rx, false, terminal)))
        },
    );
    Ok(Sse::new(output).keep_alive(KeepAlive::new().interval(Duration::from_secs(2))))
}

macro_rules! hierarchy_handler {
    ($name:ident,$request:ident,$output:ident,$ty:ty) => {
        async fn $name(
            Authorized(s): Authorized,
            query: Result<Query<HierarchyQuery>, axum::extract::rejection::QueryRejection>,
        ) -> Result<Json<Page<$ty>>, Response> {
            let Query(q) = query.map_err(|_| {
                ApiError(
                    StatusCode::BAD_REQUEST,
                    "INVALID_QUERY",
                    "Invalid hierarchy query",
                )
                .into_response()
            })?;
            match call(s, CapabilityRequest::$request(q))
                .await
                .map_err(IntoResponse::into_response)?
            {
                CapabilityOutput::$output(v) => Ok(Json(v)),
                _ => Err(mismatch().into_response()),
            }
        }
    };
}
hierarchy_handler!(
    organizations,
    OrganizationsRead,
    Organizations,
    Organization
);
hierarchy_handler!(
    infrastructures,
    InfrastructuresRead,
    Infrastructures,
    Infrastructure
);
hierarchy_handler!(sites, SitesRead, Sites, Site);
async fn scoped_snapshot(
    Authorized(s): Authorized,
) -> Result<Json<ScopedSnapshot>, CapabilityErrorResponse> {
    match call(s, CapabilityRequest::ScopedSnapshotRead).await? {
        CapabilityOutput::ScopedSnapshot(v) => Ok(Json(v)),
        _ => Err(mismatch()),
    }
}
async fn scoped_sse(
    Authorized(s): Authorized,
) -> Result<impl IntoResponse, CapabilityErrorResponse> {
    // Authorize before200/stream headers. Fixed cadence avoids wakeups exposing
    // unrelated organizations; full authorized resync ignores untrusted cursors.
    let first = call(s.clone(), CapabilityRequest::ScopedSnapshotRead).await?;
    let output = stream::unfold((s, Some(first), false), |(s, first, terminal)| async move {
        if terminal || s.stopping.is_cancelled() {
            return None;
        }
        let result = if let Some(first) = first {
            Ok(first)
        } else {
            tokio::select! {_=s.stopping.cancelled()=>return None,_=tokio::time::sleep(Duration::from_secs(1))=>{}}
            call(s.clone(), CapabilityRequest::ScopedSnapshotRead).await
        };
        let terminal = result
            .as_ref()
            .is_err_and(|error| error.0.kind == CapabilityErrorCode::PermissionDenied);
        let event = match result {
            Ok(CapabilityOutput::ScopedSnapshot(snapshot)) => {
                let bytes = serde_json::to_vec(&snapshot).expect("serializable snapshot");
                let digest = format!("{:x}", Sha256::digest(&bytes));
                Event::default()
                    .event("snapshot")
                    .id(digest)
                    .json_data(snapshot)
                    .expect("serializable snapshot")
            }
            _ => Event::default()
                .event("error")
                .data("Authorized snapshot unavailable"),
        };
        Some((Ok::<_, Infallible>(event), (s, None, terminal)))
    });
    Ok(Sse::new(output).keep_alive(KeepAlive::new().interval(Duration::from_secs(2))))
}

macro_rules! diagnostic_handler {
    ($name:ident,$cap:ident,$out:ident,$dto:ty) => {
        async fn $name(
            Authorized(s): Authorized,
            q: Result<Query<DiagnosticQuery>, axum::extract::rejection::QueryRejection>,
        ) -> Result<Json<$dto>, CapabilityErrorResponse> {
            let Query(q) = q.map_err(|_| CapabilityErrorResponse(diagnostic_invalid()))?;
            match call(s, CapabilityRequest::$cap(q)).await? {
                CapabilityOutput::$out(v) => Ok(Json(v)),
                _ => Err(mismatch()),
            }
        }
    };
}
diagnostic_handler!(
    event_history,
    EventHistoryRead,
    DiagnosticPage,
    DiagnosticPage
);
diagnostic_handler!(
    event_detail,
    EventDetailRead,
    DiagnosticPage,
    DiagnosticPage
);
diagnostic_handler!(data_gaps, DataGapsRead, DiagnosticPage, DiagnosticPage);
diagnostic_handler!(
    health_history,
    SourceHealthHistoryRead,
    DiagnosticPage,
    DiagnosticPage
);
diagnostic_handler!(evidence, EvidenceRead, Evidence, Box<EvidenceSet>);
diagnostic_handler!(
    findings,
    DiagnosticFindingsRead,
    DiagnosticPage,
    DiagnosticPage
);
diagnostic_handler!(
    observation_history,
    ObservationHistoryRead,
    DiagnosticPage,
    DiagnosticPage
);

async fn opcua_setup(
    Authorized(s): Authorized,
    body: Result<Json<OpcuaSetupRequest>, axum::extract::rejection::JsonRejection>,
) -> Result<Json<OpcuaSetupResult>, CapabilityErrorResponse> {
    let Json(input) = body.map_err(|_| CapabilityErrorResponse(CapabilityError::new(
        CapabilityErrorCode::InvalidInput, "OPCUA_SETUP_ARGUMENTS", "Invalid OPC-UA setup request."
    )))?;
    match call(s, CapabilityRequest::OpcuaSetup(input)).await? {
        CapabilityOutput::OpcuaSetup(value) => Ok(Json(*value)),
        _ => Err(mismatch()),
    }
}

async fn license_status(
    Authorized(s): Authorized,
) -> Result<Json<LicenseStatus>, CapabilityErrorResponse> {
    match call(s, CapabilityRequest::LicenseStatusRead).await? {
        CapabilityOutput::LicenseStatus(value) => Ok(Json(value)),
        _ => Err(mismatch()),
    }
}
async fn license_preview(
    Authorized(s): Authorized,
    Json(input): Json<LicensePreviewRequest>,
) -> Result<Json<LicensePreview>, CapabilityErrorResponse> {
    match call(s, CapabilityRequest::LicenseProofPreview(input)).await? {
        CapabilityOutput::LicensePreview(value) => Ok(Json(value)),
        _ => Err(mismatch()),
    }
}
async fn license_apply(
    Authorized(s): Authorized,
    Json(input): Json<LicenseApplyRequest>,
) -> Result<Json<LicenseStatus>, CapabilityErrorResponse> {
    match call(s, CapabilityRequest::LicenseProofApply(input)).await? {
        CapabilityOutput::LicenseStatus(value) => Ok(Json(value)),
        _ => Err(mismatch()),
    }
}

async fn settings_read(
    Authorized(s): Authorized,
    q: Result<Query<SettingsQuery>, axum::extract::rejection::QueryRejection>,
) -> Result<Json<SettingsSnapshot>, CapabilityErrorResponse> {
    let Query(q) = q.map_err(|_| CapabilityErrorResponse(diagnostic_invalid()))?;
    match call(s, CapabilityRequest::SettingsRead(q)).await? {
        CapabilityOutput::Settings(v) => Ok(Json(v)),
        _ => Err(mismatch()),
    }
}
async fn management_read(
    Authorized(s): Authorized,
    q: Result<Query<ManagementQuery>, axum::extract::rejection::QueryRejection>,
) -> Result<Json<ManagementReport>, CapabilityErrorResponse> {
    let Query(q) = q.map_err(|_| CapabilityErrorResponse(diagnostic_invalid()))?;
    match call(s, CapabilityRequest::McpManagementRead(q)).await? {
        CapabilityOutput::Management(v) => Ok(Json(v)),
        _ => Err(mismatch()),
    }
}

async fn installation_status(
    axum::extract::State(s): axum::extract::State<ApiContext>,
) -> Result<Json<InventoryPage>, CapabilityErrorResponse> {
    if s.state.hierarchy().is_some() {
        return Err(CapabilityErrorResponse(denied()));
    }
    match call(
        s,
        CapabilityRequest::InventoryRead(InventoryQuery::default()),
    )
    .await?
    {
        CapabilityOutput::Inventory(v) => Ok(Json(v)),
        _ => Err(mismatch()),
    }
}
async fn inventory_read(
    Authorized(s): Authorized,
    q: Result<Query<InventoryQuery>, axum::extract::rejection::QueryRejection>,
) -> Result<Json<InventoryPage>, CapabilityErrorResponse> {
    let Query(q) = q.map_err(|_| CapabilityErrorResponse(inventory_invalid()))?;
    match call(s, CapabilityRequest::InventoryRead(q)).await? {
        CapabilityOutput::Inventory(v) => Ok(Json(v)),
        _ => Err(mismatch()),
    }
}
async fn services_read(
    Authorized(s): Authorized,
    q: Result<Query<ServiceQuery>, axum::extract::rejection::QueryRejection>,
) -> Result<Json<ServicePage>, CapabilityErrorResponse> {
    let Query(q) = q.map_err(|_| CapabilityErrorResponse(service_invalid()))?;
    match call(s, CapabilityRequest::ServiceRegistryRead(q)).await? {
        CapabilityOutput::ServiceRegistry(v) => Ok(Json(v)),
        _ => Err(mismatch()),
    }
}
async fn inventory_plan(
    Authorized(s): Authorized,
    body: Result<Json<InventoryPlanQuery>, axum::extract::rejection::JsonRejection>,
) -> Result<Json<InventoryPlan>, CapabilityErrorResponse> {
    let Json(q) = body.map_err(|_| CapabilityErrorResponse(inventory_invalid()))?;
    match call(s, CapabilityRequest::InventoryPlanRead(q)).await? {
        CapabilityOutput::InventoryPlan(v) => Ok(Json(v)),
        _ => Err(mismatch()),
    }
}

async fn browser_session(
    axum::extract::State(s): axum::extract::State<ApiContext>,
    headers: axum::http::HeaderMap,
) -> Response {
    let mut response = Json(s.state.browser_sessions.info(
        crate::browser_session::cookie(&headers),
        s.state.legacy_access,
    ))
    .into_response();
    response.headers_mut().insert(
        axum::http::header::CACHE_CONTROL,
        HeaderValue::from_static("no-store"),
    );
    response
}
async fn browser_login(
    axum::extract::State(s): axum::extract::State<ApiContext>,
    headers: axum::http::HeaderMap,
    body: Result<Json<BrowserLogin>, axum::extract::rejection::JsonRejection>,
) -> Result<Response, CapabilityErrorResponse> {
    crate::browser_session::require_origin(&headers).map_err(CapabilityErrorResponse)?;
    let Json(body) = body.map_err(|_| CapabilityErrorResponse(denied()))?;
    let (token, info) = s
        .state
        .browser_sessions
        .login(&body.code)
        .map_err(CapabilityErrorResponse)?;
    let mut response = Json(info).into_response();
    response.headers_mut().insert(
        axum::http::header::SET_COOKIE,
        format!(
            "{}={token}; HttpOnly; SameSite=Strict; Path=/",
            crate::browser_session::COOKIE
        )
        .parse()
        .map_err(|_| CapabilityErrorResponse(denied()))?,
    );
    response.headers_mut().insert(
        axum::http::header::CACHE_CONTROL,
        HeaderValue::from_static("no-store"),
    );
    Ok(response)
}
#[derive(serde::Deserialize)]
#[serde(deny_unknown_fields)]
struct BrowserLogin {
    code: String,
}
#[derive(serde::Deserialize)]
#[serde(deny_unknown_fields)]
struct BrowserDeviceCredential {
    credential: String,
}
async fn browser_pair_device(
    axum::extract::State(s): axum::extract::State<ApiContext>,
    headers: axum::http::HeaderMap,
    body: Result<Json<BrowserDeviceCredential>, axum::extract::rejection::JsonRejection>,
) -> Result<Response, CapabilityErrorResponse> {
    let (token, csrf) = browser_mutation_identity(&headers)?;
    let Json(body) = body.map_err(|_| CapabilityErrorResponse(denied()))?;
    s.state
        .browser_sessions
        .pair_device(token, csrf, &body.credential)
        .map_err(CapabilityErrorResponse)?;
    let mut response = Json(json!({"paired":true})).into_response();
    response.headers_mut().insert(
        axum::http::header::CACHE_CONTROL,
        HeaderValue::from_static("no-store"),
    );
    Ok(response)
}
fn browser_mutation_identity(
    headers: &axum::http::HeaderMap,
) -> Result<(&str, &str), CapabilityErrorResponse> {
    crate::browser_session::require_origin(headers).map_err(CapabilityErrorResponse)?;
    let token =
        crate::browser_session::cookie(headers).ok_or_else(|| CapabilityErrorResponse(denied()))?;
    let csrf = headers
        .get("x-oip-csrf")
        .and_then(|value| value.to_str().ok())
        .ok_or_else(|| CapabilityErrorResponse(denied()))?;
    Ok((token, csrf))
}

fn browser_private_response(response: impl IntoResponse) -> Response {
    let mut response = response.into_response();
    response
        .headers_mut()
        .insert(header::CACHE_CONTROL, HeaderValue::from_static("no-store"));
    response
}

async fn browser_paired_devices(
    axum::extract::State(s): axum::extract::State<ApiContext>,
    headers: axum::http::HeaderMap,
) -> Result<Response, CapabilityErrorResponse> {
    let token = crate::browser_session::cookie(&headers)
        .ok_or_else(|| CapabilityErrorResponse(denied()))?;
    let items = s
        .state
        .browser_sessions
        .paired_devices(token)
        .map_err(CapabilityErrorResponse)?;
    Ok(browser_private_response(Json(json!({"items": items}))))
}

#[derive(serde::Deserialize)]
#[serde(deny_unknown_fields)]
struct BrowserDeviceLabel {
    label: String,
}

async fn browser_rename_device(
    axum::extract::State(s): axum::extract::State<ApiContext>,
    Path(id): Path<String>,
    headers: axum::http::HeaderMap,
    body: Result<Json<BrowserDeviceLabel>, axum::extract::rejection::JsonRejection>,
) -> Result<Response, CapabilityErrorResponse> {
    let (token, csrf) = browser_mutation_identity(&headers)?;
    let Json(body) = body.map_err(|_| CapabilityErrorResponse(denied()))?;
    s.state
        .browser_sessions
        .rename_device(token, csrf, &id, &body.label)
        .map_err(CapabilityErrorResponse)?;
    Ok(browser_private_response(Json(json!({"renamed": true}))))
}

async fn browser_revoke_device(
    axum::extract::State(s): axum::extract::State<ApiContext>,
    Path(id): Path<String>,
    headers: axum::http::HeaderMap,
) -> Result<Response, CapabilityErrorResponse> {
    let (token, csrf) = browser_mutation_identity(&headers)?;
    let result = s
        .state
        .browser_sessions
        .revoke_device(token, csrf, &id)
        .map_err(CapabilityErrorResponse)?;
    let current = result.current_session_revoked;
    let mut response = browser_private_response(Json(result));
    if current {
        response.headers_mut().insert(
            header::SET_COOKIE,
            HeaderValue::from_static("oip_session=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0"),
        );
    }
    Ok(response)
}

async fn browser_device_login(
    axum::extract::State(s): axum::extract::State<ApiContext>,
    headers: axum::http::HeaderMap,
    body: Result<Json<BrowserDeviceCredential>, axum::extract::rejection::JsonRejection>,
) -> Result<Response, CapabilityErrorResponse> {
    crate::browser_session::require_origin(&headers).map_err(CapabilityErrorResponse)?;
    let Json(body) = body.map_err(|_| CapabilityErrorResponse(denied()))?;
    let (token, info) = s
        .state
        .browser_sessions
        .device_login(&body.credential)
        .map_err(CapabilityErrorResponse)?;
    let mut response = Json(info).into_response();
    response.headers_mut().insert(
        axum::http::header::SET_COOKIE,
        format!(
            "{}={token}; HttpOnly; SameSite=Strict; Path=/",
            crate::browser_session::COOKIE
        )
        .parse()
        .map_err(|_| CapabilityErrorResponse(denied()))?,
    );
    response.headers_mut().insert(
        axum::http::header::CACHE_CONTROL,
        HeaderValue::from_static("no-store"),
    );
    Ok(response)
}
async fn browser_logout(
    Authorized(s): Authorized,
    headers: axum::http::HeaderMap,
) -> Result<Response, CapabilityErrorResponse> {
    crate::browser_session::require_origin(&headers).map_err(CapabilityErrorResponse)?;
    let token = crate::browser_session::cookie(&headers)
        .ok_or_else(|| CapabilityErrorResponse(denied()))?;
    s.state.browser_sessions.logout(token);
    let mut response = Json(serde_json::json!({"logged_out":true})).into_response();
    response.headers_mut().insert(
        axum::http::header::SET_COOKIE,
        HeaderValue::from_static("oip_session=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0"),
    );
    Ok(response)
}

async fn inventory_apply(
    Authorized(s): Authorized,
    body: Result<Json<InventoryPlanQuery>, axum::extract::rejection::JsonRejection>,
) -> Result<Json<InventoryPlan>, CapabilityErrorResponse> {
    let Json(q) = body.map_err(|_| CapabilityErrorResponse(inventory_invalid()))?;
    let principal = s
        .authority
        .as_ref()
        .and_then(|a| a.principal.clone())
        .ok_or_else(|| CapabilityErrorResponse(denied()))?;
    match call(
        s,
        CapabilityRequest::InventoryChange(InventoryAdministration {
            principal,
            changes: q.changes,
        }),
    )
    .await?
    {
        CapabilityOutput::InventoryPlan(p) => Ok(Json(p)),
        _ => Err(mismatch()),
    }
}
async fn hue_lights(
    Authorized(s): Authorized,
    Query(q): Query<HueLightsQuery>,
) -> Result<Json<HueLights>, CapabilityErrorResponse> {
    match call(s, CapabilityRequest::HueLightsRead(q)).await? {
        CapabilityOutput::HueLights(result) => Ok(Json(result)),
        _ => Err(mismatch()),
    }
}
async fn hue_control(
    Authorized(s): Authorized,
    body: Result<Json<HueLightCommand>, axum::extract::rejection::JsonRejection>,
) -> Result<Json<serde_json::Value>, CapabilityErrorResponse> {
    let Json(command) = body.map_err(|_| CapabilityErrorResponse(inventory_invalid()))?;
    match call(s, CapabilityRequest::HueLightControl(command)).await? {
        CapabilityOutput::HueCommandAccepted { light_id } => {
            Ok(Json(json!({"accepted":true,"light_id":light_id})))
        }
        _ => Err(mismatch()),
    }
}
async fn hue_setup(
    Authorized(s): Authorized,
    body: Result<Json<HueSetupRequest>, axum::extract::rejection::JsonRejection>,
) -> Result<Json<serde_json::Value>, CapabilityErrorResponse> {
    let Json(request) = body.map_err(|_| CapabilityErrorResponse(inventory_invalid()))?;
    match call(s, CapabilityRequest::HueSetup(request)).await? {
        CapabilityOutput::HueSetupAccepted { action } => {
            Ok(Json(json!({"accepted": true, "action": action})))
        }
        _ => Err(mismatch()),
    }
}

async fn connection_read(
    Authorized(s): Authorized,
    q: Result<Query<ConnectionQuery>, axum::extract::rejection::QueryRejection>,
) -> Result<Json<ConnectionResult>, CapabilityErrorResponse> {
    let Query(q) = q.map_err(|_| CapabilityErrorResponse(inventory_invalid()))?;
    match call(s, CapabilityRequest::DeviceConnectionRead(q)).await? {
        CapabilityOutput::Connection(r) => Ok(Json(*r)),
        _ => Err(mismatch()),
    }
}
async fn connection_configure(
    Authorized(s): Authorized,
    q: Result<Json<ConnectionAction>, axum::extract::rejection::JsonRejection>,
) -> Result<Json<ConnectionResult>, CapabilityErrorResponse> {
    let Json(q) = q.map_err(|_| CapabilityErrorResponse(inventory_invalid()))?;
    match call(s, CapabilityRequest::DeviceConnectionConfigure(q)).await? {
        CapabilityOutput::Connection(r) => Ok(Json(*r)),
        _ => Err(mismatch()),
    }
}
