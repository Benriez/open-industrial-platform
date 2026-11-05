use crate::{application_services::ApplicationServices, state::AppState};
use axum::{
    extract::{Path, Query, Request, State},
    http::{HeaderValue, StatusCode},
    middleware::{self, Next},
    response::{
        sse::{Event, KeepAlive},
        IntoResponse, Response, Sse,
    },
    routing::{get, post},
    Json, Router,
};
use futures::stream;
use oip_core::*;
use serde_json::json;
use std::{convert::Infallible, sync::Arc, time::Duration};

#[derive(Clone)]
struct ApiContext {
    state: AppState,
    service: Arc<ApplicationServices>,
    authority: Option<ExecutionContext>,
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
    let mut context = s.service.local_context();
    if let Some(authority) = s.authority {
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
    let routes = Router::new()
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
        })
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
    next.run(request).await
}

async fn status(
    State(s): State<ApiContext>,
) -> Result<Json<SystemStatus>, CapabilityErrorResponse> {
    match call(s, CapabilityRequest::SystemStatusRead).await? {
        CapabilityOutput::SystemStatus(v) => Ok(Json(v)),
        _ => Err(mismatch()),
    }
}
async fn devices(
    State(s): State<ApiContext>,
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
    State(s): State<ApiContext>,
    Path(id): Path<String>,
) -> Result<Json<DeviceDetail>, CapabilityErrorResponse> {
    match call(s, CapabilityRequest::DeviceRead(DeviceRequest { id })).await? {
        CapabilityOutput::Device(v) => Ok(Json(v)),
        _ => Err(mismatch()),
    }
}
async fn metrics(
    State(s): State<ApiContext>,
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
    State(s): State<ApiContext>,
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
    State(s): State<ApiContext>,
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
async fn scenario(
    State(s): State<ApiContext>,
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
    State(s): State<ApiContext>,
) -> Result<Json<CoreHealth>, CapabilityErrorResponse> {
    match call(s, CapabilityRequest::CoreHealthRead).await? {
        CapabilityOutput::CoreHealth(v) => Ok(Json(v)),
        _ => Err(mismatch()),
    }
}
async fn source_health(
    State(s): State<ApiContext>,
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
async fn live(State(s): State<ApiContext>) -> Result<impl IntoResponse, CapabilityErrorResponse> {
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
async fn ready(State(s): State<ApiContext>) -> Result<impl IntoResponse, CapabilityErrorResponse> {
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
async fn sse(State(s): State<ApiContext>) -> impl IntoResponse {
    let rx = s.updates.subscribe();
    let output = stream::unfold((s, rx, true), |(s, mut rx, first)| async move {
        if s.stopping.is_cancelled() {
            return None;
        }
        if !first {
            tokio::select! {_=s.stopping.cancelled()=>return None,changed=rx.changed()=>{if changed.is_err(){return None;}},_=tokio::time::sleep(Duration::from_secs(1))=>{}}
        }
        let event = match call(s.clone(), CapabilityRequest::SnapshotRead).await {
            Ok(CapabilityOutput::Snapshot(snapshot)) => Event::default()
                .event("snapshot")
                .id(format!(
                    "{}:{}",
                    snapshot.core.run_id, snapshot.core.revision
                ))
                .json_data(snapshot)
                .unwrap_or_else(|_| Event::default().event("error").data("serialization failed")),
            _ => Event::default()
                .event("error")
                .data("application snapshot unavailable"),
        };
        Some((Ok::<_, Infallible>(event), (s, rx, false)))
    });
    Sse::new(output).keep_alive(KeepAlive::new().interval(Duration::from_secs(2)))
}
