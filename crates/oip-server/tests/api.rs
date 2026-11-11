use axum::{
    body::{to_bytes, Body},
    http::{Request, StatusCode},
    Router,
};
use oip_core::{ClientEvent, Freshness, Timestamp};
use oip_server::{api, collector, demo, state::AppState};
use oip_simulator::{Scenario, Simulation, SimulationConfig};
use oip_storage::SqliteStore;
use serde_json::Value;
use std::time::Duration;
use tower::ServiceExt;

async fn get(app: Router, path: &str) -> (StatusCode, Value) {
    let response = app
        .oneshot(
            Request::builder()
                .uri(path)
                .header("host", "127.0.0.1:8080")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = response.status();
    let body = to_bytes(response.into_body(), 2_000_000).await.unwrap();
    (status, serde_json::from_slice(&body).unwrap())
}
fn state() -> AppState {
    AppState::legacy(SqliteStore::open_in_memory().unwrap(), None).unwrap()
}

#[tokio::test]
async fn api_unknowns_errors_origin_and_read_only_boundaries() {
    let s = state();
    let app = api::router(s, "missing");
    let (status, body) = get(app.clone(), "/api/v1/system/status").await;
    assert_eq!(status, StatusCode::OK);
    assert!(body["cpu_percent"].is_null());
    assert!(body["gpu_percent"].is_null());
    assert_eq!(body["security_blocker"], "RUSTSEC-2023-0071");
    let (_, devices) = get(app.clone(), "/api/v1/devices").await;
    assert_eq!(devices.as_array().unwrap().len(), 1);
    let (status, body) = get(app.clone(), "/api/v1/devices/no-such-device").await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    assert_eq!(body["code"], "DEVICE_NOT_FOUND");
    let (status, body) = get(app.clone(), "/api/v1/opcua/nodes?offset=invalid").await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert_eq!(body["code"], "INVALID_QUERY");
    let response = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/api/v1/devices")
                .header("host", "attacker.example")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
    let response = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/api/v1/demo/scenario")
                .method("POST")
                .header("host", "127.0.0.1:8080")
                .header("origin", "https://attacker.example")
                .header("content-type", "application/json")
                .body(Body::from("{\"scenario\":\"sensor\"}"))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
    let response = app
        .oneshot(
            Request::builder()
                .uri("/api/v1/demo/scenario")
                .method("POST")
                .header("host", "127.0.0.1:8080")
                .header("content-type", "application/json")
                .body(Body::from("{\"scenario\":\"sensor\"}"))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::CONFLICT);
}

#[test]
fn demo_never_equates_vpn_and_agent_health() {
    let devices = demo::devices("agent", "connected");
    let remote = devices.iter().find(|d| d.id == "remote-linux").unwrap();
    assert_eq!(remote.health.reachability, "reachable");
    assert_eq!(remote.health.vpn_transport, "connected");
    assert_eq!(remote.health.agent_availability, "unavailable");
    assert_eq!(remote.health.service_health, "unknown");
    for scenario in demo::SCENARIOS {
        assert!(demo::incidents(scenario)
            .iter()
            .all(|i| i.simulated && !i.missing.is_empty()));
    }
}

#[tokio::test]
async fn persistence_failure_does_not_publish_and_restart_values_are_stale() {
    let path = std::env::temp_dir().join(format!("oip003-storage-{}.sqlite", std::process::id()));
    let _ = std::fs::remove_file(&path);
    let s = AppState::legacy(SqliteStore::open(&path).unwrap(), None).unwrap();
    let frame = Simulation::new(SimulationConfig::default(), Scenario::SensorFault).frame_at(2);
    let observation = frame.observation("temperature").unwrap().clone();
    s.ingest(ClientEvent::Observation(Box::new(observation)))
        .await
        .unwrap();
    let snap = s.snapshot().unwrap();
    assert!(snap.metrics[0].value.is_none());
    assert_eq!(snap.system.persisted_observations, 1);
    let mut invalid = frame.observations[1].clone();
    invalid.value = Some(oip_core::MetricValue::Float(f64::NAN));
    assert!(s
        .ingest(ClientEvent::Observation(Box::new(invalid)))
        .await
        .is_err());
    assert_eq!(s.snapshot().unwrap().system.persisted_observations, 1);
    assert_eq!(s.snapshot().unwrap().metrics.len(), 1);
    s.shutdown().await;
    drop(s);
    let s = AppState::legacy(SqliteStore::open(&path).unwrap(), None).unwrap();
    let snap = s.snapshot().unwrap();
    assert_eq!(snap.metrics[0].freshness, Freshness::Stale);
    assert!(snap.system.last_received_ms.is_none());
    s.shutdown().await;
    drop(s);
    std::fs::remove_file(path).unwrap();
}

#[tokio::test]
async fn real_opcua_storage_api_sse_and_reconnect() {
    use oip_opcua::async_opcua::{AsyncOpcUaServerConfig, RunningAsyncOpcUaServer};
    let reservation = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let free_port = reservation.local_addr().unwrap().port();
    drop(reservation);
    let mut server = RunningAsyncOpcUaServer::start(AsyncOpcUaServerConfig {
        port: free_port,
        ..Default::default()
    })
    .await
    .unwrap();
    let port = server.port();
    let s = state();
    let worker = tokio::spawn(collector::collect(s.clone(), server.endpoint().into()));
    let app = api::router(s.clone(), "missing");
    async fn wait(s: &AppState, alarm: bool) {
        tokio::time::timeout(Duration::from_secs(40), async {
            loop {
                let snap = s.snapshot().unwrap();
                if snap.system.opcua_status == "connected"
                    && snap.metrics.iter().any(|o| {
                        o.metric_id.as_str() == "alarm_active"
                            && o.value == Some(oip_core::MetricValue::Boolean(alarm))
                    })
                {
                    break;
                }
                tokio::time::sleep(Duration::from_millis(100)).await;
            }
        })
        .await
        .expect("collector must recover");
    }
    wait(&s, false).await;
    let (_, status) = get(app.clone(), "/api/v1/system/status").await;
    assert!(status["persisted_observations"].as_u64().unwrap() >= 6);
    let (_, nodes) = get(
        app.clone(),
        "/api/v1/opcua/nodes?folder=Bulk&offset=960&limit=40",
    )
    .await;
    assert_eq!(nodes["items"].as_array().unwrap().len(), 40);
    // The total of a folder is a number of the **server**: the test does not
    // encode the size of the simulation that it happens to run.
    let (_, all) = get(app.clone(), "/api/v1/opcua/nodes?folder=all&limit=1").await;
    let total = all["total"].as_u64().expect("the total of the address space");
    assert!(
        nodes["total"].as_u64().expect("the total of the folder") < total,
        "a folder is a part of the catalogue"
    );
    assert!(nodes["items"][0]["observation"]["value"]["float"].is_number());
    // The address space of the server is delivered as it is: every node
    // names the folder of the server, the namespace of the node id and the
    // access of the class of the node.
    let folders = nodes["folders"]
        .as_array()
        .expect("the folders of the address space")
        .clone();
    assert!(
        folders.iter().any(|folder| folder == "Bulk"),
        "the folder of the server is named"
    );
    assert!(
        folders.iter().any(|folder| folder == "M-01"),
        "the folder of the server is named"
    );
    for item in nodes["items"].as_array().unwrap() {
        let node_id = item["node_id"].as_str().expect("the node id of the server");
        let namespace = node_id
            .strip_prefix("ns=")
            .and_then(|rest| rest.split(';').next())
            .and_then(|namespace| namespace.parse::<u64>().ok())
            .unwrap_or(0);
        assert_eq!(
            item["namespace"].as_u64(),
            Some(namespace),
            "the namespace is the namespace of the node id"
        );
        assert_eq!(item["access"], "Read", "a variable of the server is read");
    }
    // Every node of the address space belongs to exactly one folder: the
    // catalogue is a set of nodes and the pages stay disjoint.
    let mut sum = 0u64;
    for folder in &folders {
        let folder = folder.as_str().expect("the name of the folder");
        let (_, page) = get(
            app.clone(),
            &format!("/api/v1/opcua/nodes?folder={folder}&limit=1"),
        )
        .await;
        sum += page["total"].as_u64().expect("the total of the folder");
    }
    assert_eq!(
        sum, total,
        "every node of the address space belongs to exactly one folder"
    );
    let (_, device) = get(app.clone(), "/api/v1/devices/M-01").await;
    assert!(device["metrics"]
        .as_array()
        .unwrap()
        .iter()
        .all(|o| o["simulation_origin"].is_object()));
    let response = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/api/v1/stream")
                .header("host", "127.0.0.1:8080")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.headers()["content-type"], "text/event-stream");
    use futures::StreamExt;
    let first = response
        .into_body()
        .into_data_stream()
        .next()
        .await
        .unwrap()
        .unwrap();
    assert!(String::from_utf8_lossy(&first).contains("event: snapshot"));
    server.stop().await.unwrap();
    tokio::time::timeout(Duration::from_secs(12), async {
        while s.snapshot().unwrap().system.opcua_status == "connected" {
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
    })
    .await
    .unwrap();
    assert!(s
        .snapshot()
        .unwrap()
        .metrics
        .iter()
        .all(|o| o.freshness == Freshness::Stale));
    server = RunningAsyncOpcUaServer::start(AsyncOpcUaServerConfig {
        port,
        scenario: Scenario::CriticalSensor,
        ..Default::default()
    })
    .await
    .unwrap();
    wait(&s, true).await;
    let (_, metrics) = get(app, "/api/v1/metrics/current").await;
    let temp = metrics
        .as_array()
        .unwrap()
        .iter()
        .find(|o| o["metric_id"] == "temperature")
        .unwrap();
    assert!(temp["value"]["float"].as_f64().unwrap() >= 90.0);
    worker.abort();
    server.stop().await.unwrap();
}

#[tokio::test]
async fn age_uses_receive_time_and_bulk_does_not_claim_collector_health() {
    let s = state();
    let frame = Simulation::new(SimulationConfig::default(), Scenario::Normal).frame_at(0);
    s.ingest(ClientEvent::Observation(Box::new(
        frame.observations[0].clone(),
    )))
    .await
    .unwrap();
    s.tick(oip_server::state::now_ms() + 6000).await;
    let snap = s.snapshot().unwrap();
    assert_eq!(snap.system.opcua_status, "stale");
    assert_eq!(snap.metrics[0].freshness, Freshness::Stale);
    s.ingest(ClientEvent::ConnectionLost {
        at: Timestamp::from_unix_millis(10),
        reason: "test".into(),
    })
    .await
    .unwrap();
    assert_eq!(s.snapshot().unwrap().system.opcua_status, "reconnecting");
}

#[tokio::test]
async fn external_evidence_cannot_be_relabelled_as_dashboard_simulation() {
    let s = state();
    let frame = Simulation::new(SimulationConfig::default(), Scenario::Normal).frame_at(0);
    let mut external = frame.observations[0].clone();
    external.simulation_origin = None;
    external.data_source_id = oip_core::DataSourceId::new("external-test-source").unwrap();
    assert!(s
        .ingest(ClientEvent::Observation(Box::new(external.clone())))
        .await
        .is_err());
    assert_eq!(s.snapshot().unwrap().system.persisted_observations, 0);
    let mut store = SqliteStore::open_in_memory().unwrap();
    store.ingest_observation(&external).unwrap();
    assert!(AppState::legacy(store, None).is_err());
}
