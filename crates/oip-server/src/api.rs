use crate::{application_services::ApplicationServices, state::AppState};
use axum::extract::FromRequestParts;
use axum::{
    extract::{Path, Query, Request},
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
use sha2::{Digest, Sha256};
use std::{convert::Infallible, sync::Arc, time::Duration};

#[derive(Clone)]
struct ApiContext {
    state: AppState,
    service: Arc<ApplicationServices>,
    authority: Option<ExecutionContext>,
    credentials: crate::identity::RestIdentities,
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
        .route("/api/v2/installation/status", get(installation_status))
        .route("/api/v2/inventory/devices", get(inventory_read))
        .route("/api/v2/inventory/plan", post(inventory_plan))
        .route("/api/v2/settings", get(settings_read))
        .route("/api/v2/management", get(management_read))
        .route("/api/v2/organizations", get(organizations))
        .route("/api/v2/infrastructures", get(infrastructures))
        .route("/api/v2/sites", get(sites))
        .route("/api/v2/sources", get(source_health))
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
        .route("/api/v2/snapshot", get(scoped_snapshot))
        .route("/api/v2/stream", get(scoped_sse))
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
    let output = stream::unfold((s, Some(first)), |(s, first)| async move {
        if s.stopping.is_cancelled() {
            return None;
        }
        let result = if let Some(first) = first {
            Ok(first)
        } else {
            tokio::select! {_=s.stopping.cancelled()=>return None,_=tokio::time::sleep(Duration::from_secs(1))=>{}}
            call(s.clone(), CapabilityRequest::ScopedSnapshotRead).await
        };
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
        Some((Ok::<_, Infallible>(event), (s, None)))
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
    if s.state.hierarchy.is_some() {
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
