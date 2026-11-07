use axum::{body::Body, http::Request};
use futures::{future::BoxFuture, StreamExt};
use oip_core::*;
use oip_server::{
    api,
    config::{CoreConfig, SourceConfig},
    runtime::{source_worker, CollectionAdapter, CollectionSession, RuntimeError},
    state::{now_ms, AppState},
};
use oip_simulator::{Scenario, Simulation, SimulationConfig};
use oip_storage::SqliteStore;
use std::{
    collections::VecDeque,
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
    time::Duration,
};
use tokio_util::sync::CancellationToken;
use tower::ServiceExt;
fn source(id: &str, port: u16) -> SourceConfig {
    SourceConfig {
        id: id.into(),
        name: id.into(),
        endpoint: format!("opc.tcp://127.0.0.1:{port}"),
        namespace: 2,
    }
}
fn definitions() -> Vec<SourceDefinition> {
    [source("a", 14841), source("b", 14842)]
        .iter()
        .map(|s| {
            let mut d = s.definition().unwrap();
            d.required_metrics = [MetricId::new("temperature").unwrap()].into();
            d
        })
        .collect()
}
fn sample(id: &str, tick: u64, now: i64) -> ObservationEnvelope {
    let mut o = Simulation::new(SimulationConfig::default(), Scenario::Normal)
        .frame_at(tick)
        .observations[0]
        .clone();
    o.data_source_id = DataSourceId::new(id).unwrap();
    o.timestamps.received = Some(Timestamp::from_unix_millis(now));
    o
}
fn event(id: &str, tick: u64, now: i64) -> ClientEvent {
    ClientEvent::Observation(Box::new(sample(id, tick, now)))
}
fn app() -> Application<SqliteStore> {
    let mut a = Application::initialize(
        SqliteStore::open_in_memory().unwrap(),
        definitions(),
        1000,
        500,
    )
    .unwrap();
    a.started();
    a
}

#[test]
fn per_source_poll_cadence_applies_to_health_and_samples_without_fresh_restore() {
    let mut a = app();
    let slow = DataSourceId::new("a").unwrap();
    let fast = DataSourceId::new("b").unwrap();
    a.configure_source_cadence(&slow, 5000).unwrap();
    for id in [&slow, &fast] {
        a.connected(id).unwrap();
        a.ingest(id, event(id.as_str(), 0, 1000), 1000).unwrap();
    }
    let view = a.view(2000);
    assert_eq!(
        view.sources
            .iter()
            .find(|s| s.id == slow)
            .unwrap()
            .freshness,
        Freshness::Fresh
    );
    assert_eq!(
        view.sources
            .iter()
            .find(|s| s.id == fast)
            .unwrap()
            .freshness,
        Freshness::Stale
    );
    assert_eq!(
        view.observations
            .iter()
            .find(|o| o.data_source_id == slow)
            .unwrap()
            .freshness,
        Freshness::Fresh
    );
    assert_eq!(
        view.observations
            .iter()
            .find(|o| o.data_source_id == fast)
            .unwrap()
            .freshness,
        Freshness::Stale
    );
    assert!(a
        .view(7001)
        .observations
        .iter()
        .all(|o| o.freshness == Freshness::Stale));
    let mut restored = Application::initialize(a.repository, definitions(), 8000, 500).unwrap();
    restored.started();
    restored.configure_source_cadence(&slow, 5000).unwrap();
    assert!(restored
        .view(8000)
        .observations
        .iter()
        .all(|o| o.freshness == Freshness::Stale));
}
fn path(name: &str) -> PathBuf {
    let p = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../target/oip004-tests");
    std::fs::create_dir_all(&p).unwrap();
    p.join(format!("{name}-{}.sqlite", std::process::id()))
}
async fn until(mut f: impl FnMut() -> bool) {
    tokio::time::timeout(Duration::from_secs(8), async {
        while !f() {
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
    .unwrap();
}
async fn bootstrap(s: &AppState) {
    s.started().await.unwrap();
    s.connected(s.primary.as_ref().unwrap()).await.unwrap();
    for o in Simulation::new(SimulationConfig::default(), Scenario::Normal)
        .frame_at(0)
        .observations
    {
        s.ingest(ClientEvent::Observation(Box::new(o)))
            .await
            .unwrap();
    }
}
fn req(path: &str) -> Request<Body> {
    Request::builder()
        .uri(path)
        .header("host", "127.0.0.1:8080")
        .body(Body::empty())
        .unwrap()
}
#[test]
fn ordering_idempotence_and_clock_regression_are_independent() {
    let mut a = app();
    for id in ["a", "b"] {
        let key = DataSourceId::new(id).unwrap();
        a.connected(&key).unwrap();
        a.ingest(&key, event(id, 10, 1000), 1000).unwrap();
    }
    assert_eq!(a.view(1000).health.lifecycle, Lifecycle::Ready);
    let id = DataSourceId::new("a").unwrap();
    assert_eq!(
        a.ingest(&id, event("a", 10, 1001), 1001).unwrap(),
        IngestOutcome::Duplicate
    );
    a.ingest(&id, event("a", 9, 1002), 1002).unwrap();
    let v = a.view(1002);
    assert_eq!(v.sources[0].out_of_order, 1);
    assert_eq!(v.sources[0].duplicates, 1);
    assert_eq!(
        v.observations
            .iter()
            .find(|o| o.data_source_id == id)
            .unwrap()
            .timestamps
            .source,
        sample("a", 10, 0).timestamps.source
    );
    assert_eq!(a.view(999).sources[0].freshness, Freshness::Unknown);
    assert_eq!(a.view(1600).health.lifecycle, Lifecycle::Degraded);
    assert_eq!(
        a.view(1600).sources[0].connection,
        ConnectionHealth::Connected
    );
}
#[test]
fn invalid_inputs_remain_explicit_and_do_not_corrupt_evidence() {
    let mut a = app();
    let id = DataSourceId::new("a").unwrap();
    for value in [
        MetricValue::Float(f64::NAN),
        MetricValue::Float(f64::INFINITY),
        MetricValue::Text("wrong type".into()),
    ] {
        let mut o = sample("a", 0, 1000);
        o.value = Some(value);
        assert!(a
            .ingest(&id, ClientEvent::Observation(Box::new(o)), 1000)
            .is_err());
    }
    let mut o = sample("a", 0, 1000);
    o.value = None;
    assert!(a
        .ingest(&id, ClientEvent::Observation(Box::new(o.clone())), 1000)
        .is_err());
    o.quality = DataQuality::Bad;
    o.collection_error = Some(CollectionError::InvalidMeasurement);
    a.ingest(&id, ClientEvent::Observation(Box::new(o)), 1000)
        .unwrap();
    assert!(a.view(1000).observations[0].value.is_none());
    let mut o = sample("a", 1, 1000);
    o.timestamps.source = Timestamp::from_unix_millis(i64::MAX);
    assert!(matches!(
        a.ingest(&id, ClientEvent::Observation(Box::new(o.clone())), 1000),
        Err(ApplicationError::Timestamp)
    ));
    o.quality = DataQuality::Bad;
    o.freshness = Freshness::Unknown;
    o.collection_error = Some(CollectionError::InvalidTimestamp);
    a.ingest(&id, ClientEvent::Observation(Box::new(o)), 1000)
        .unwrap();
    assert_eq!(a.repository.observation_count().unwrap(), 2);
    let gap = DataGap {
        started_at: Timestamp::from_unix_millis(20),
        ended_at: Timestamp::from_unix_millis(10),
        reason: "bad".into(),
    };
    assert!(matches!(
        a.ingest(
            &id,
            ClientEvent::Reconnected {
                at: Timestamp::from_unix_millis(20),
                gap
            },
            1000
        ),
        Err(ApplicationError::NegativeGap)
    ));
    assert!(a.ingest(&id, event("b", 2, 1000), 1000).is_err());
    assert_eq!(a.repository.observation_count().unwrap(), 2);
}
#[test]
fn restart_recovers_identities_events_and_stale_values_then_reobserves() {
    let mut a = app();
    let id = DataSourceId::new("a").unwrap();
    a.ingest(&id, event("a", 50, 1000), 1000).unwrap();
    a.ingest(&DataSourceId::new("b").unwrap(), event("b", 50, 1000), 1000)
        .unwrap();
    a.finish(1100, true).unwrap();
    let mut a = Application::initialize(a.repository, definitions(), 1200, 500).unwrap();
    a.started();
    let v = a.view(1200);
    assert_eq!(v.sources.len(), 2);
    assert!(v
        .sources
        .iter()
        .all(|s| s.reachability == Reachability::Unknown && s.last_received_ms.is_none()));
    assert!(v
        .observations
        .iter()
        .all(|o| o.freshness == Freshness::Stale));
    a.connected(&id).unwrap();
    let gap = a.recovered_gap(&id, 1300).unwrap();
    a.ingest(&id, gap, 1300).unwrap();
    a.ingest(&id, event("a", 0, 1301), 1301).unwrap();
    assert_eq!(a.view(1301).sources[0].freshness, Freshness::Fresh);
    assert_eq!(a.repository.gaps_for_source(&id).unwrap().len(), 1);
    let before = a.repository.observation_count().unwrap();
    a.ingest(&id, event("a", 0, 1302), 1302).unwrap();
    assert_eq!(a.repository.observation_count().unwrap(), before);
}
#[tokio::test]
async fn sqlite_busy_backpressure_and_recovery_preserve_accepted_work() {
    let p = path("busy");
    let _ = std::fs::remove_file(&p);
    let c = CoreConfig {
        legacy_single_infrastructure: true,
        sources: vec![oip_server::config::SourceConfig::primary(4840)],
        database: p.clone(),
        queue_capacity: 1,
        ..Default::default()
    };
    let s = AppState::configured(SqliteStore::open(&p).unwrap(), &c, None).unwrap();
    bootstrap(&s).await;
    let db = rusqlite::Connection::open(&p).unwrap();
    db.execute_batch("BEGIN IMMEDIATE").unwrap();
    let first = {
        let s = s.clone();
        tokio::spawn(async move {
            s.ingest(event(oip_simulator::SIMULATION_ORIGIN_ID, 1, now_ms()))
                .await
        })
    };
    until(|| !s.view().health.persistence_healthy).await;
    assert_eq!(s.view().health.persisted_observations, 6);
    let queued = s
        .try_ingest(
            s.primary.as_ref().unwrap(),
            event(s.primary.as_ref().unwrap().as_str(), 2, now_ms()),
        )
        .unwrap();
    assert!(s
        .try_ingest(
            s.primary.as_ref().unwrap(),
            event(s.primary.as_ref().unwrap().as_str(), 3, now_ms())
        )
        .is_err());
    assert_eq!(s.queue().depth, 1);
    let waiting = {
        let s = s.clone();
        tokio::spawn(async move {
            s.ingest(event(s.primary.as_ref().unwrap().as_str(), 3, now_ms()))
                .await
        })
    };
    until(|| s.queue().backpressure_waits > 0).await;
    let response = tokio::time::timeout(
        Duration::from_millis(200),
        api::router(s.clone(), "missing").oneshot(req("/health/live")),
    )
    .await
    .unwrap()
    .unwrap();
    assert_eq!(response.status(), 200);
    db.execute_batch("COMMIT").unwrap();
    first.await.unwrap().unwrap();
    queued.await.unwrap().unwrap();
    waiting.await.unwrap().unwrap();
    assert_eq!(s.view().health.persisted_observations, 9);
    assert!(s.view().health.persistence_healthy);
    assert_eq!(s.queue().rejected_submissions, 1);
    s.shutdown_deadline(Duration::from_secs(2));
    assert!(s.shutdown().await.clean);
}
#[tokio::test]
async fn failed_shutdown_reports_uncommitted_instead_of_claiming_success() {
    let p = path("stop-failure");
    let _ = std::fs::remove_file(&p);
    let s = AppState::legacy(SqliteStore::open(&p).unwrap(), None).unwrap();
    bootstrap(&s).await;
    let db = rusqlite::Connection::open(&p).unwrap();
    db.execute_batch("BEGIN IMMEDIATE").unwrap();
    let work = {
        let s = s.clone();
        tokio::spawn(async move {
            s.ingest(event(s.primary.as_ref().unwrap().as_str(), 1, now_ms()))
                .await
        })
    };
    until(|| !s.view().health.persistence_healthy).await;
    s.shutdown_deadline(Duration::from_millis(150));
    let report = tokio::time::timeout(Duration::from_secs(3), s.shutdown())
        .await
        .unwrap();
    assert!(!report.clean);
    assert_eq!(report.uncommitted, 1);
    assert!(report.persistence_thread_joined);
    assert!(work.await.unwrap().is_err());
    assert_eq!(s.view().health.lifecycle, Lifecycle::Failed);
    db.execute_batch("ROLLBACK").unwrap();
    let restored = AppState::legacy(SqliteStore::open(&p).unwrap(), None).unwrap();
    assert_eq!(restored.view().health.persisted_observations, 6);
    assert!(restored
        .view()
        .observations
        .iter()
        .all(|o| o.freshness == Freshness::Stale));
    restored.shutdown().await;
}
#[tokio::test]
async fn shutdown_drains_all_admitted_events() {
    let s = AppState::legacy(SqliteStore::open_in_memory().unwrap(), None).unwrap();
    let mut receipts = Vec::new();
    for tick in 0..16 {
        receipts.push(
            s.try_ingest(
                s.primary.as_ref().unwrap(),
                event(s.primary.as_ref().unwrap().as_str(), tick, now_ms()),
            )
            .unwrap(),
        );
    }
    s.shutdown_deadline(Duration::from_secs(2));
    let report = s.shutdown().await;
    assert!(report.clean);
    assert_eq!(report.uncommitted, 0);
    for r in receipts {
        r.await.unwrap().unwrap();
    }
    assert_eq!(s.view().health.persisted_observations, 16);
    assert_eq!(s.view().health.lifecycle, Lifecycle::Stopped);
    assert!(s
        .ingest(event(s.primary.as_ref().unwrap().as_str(), 20, now_ms()))
        .await
        .is_err());
}
#[tokio::test]
async fn slow_sse_and_reconnect_use_complete_resynchronization_without_blocking() {
    let s = AppState::legacy(SqliteStore::open_in_memory().unwrap(), None).unwrap();
    bootstrap(&s).await;
    let app = api::router(s.clone(), "missing");
    let response = app.clone().oneshot(req("/api/v1/stream")).await.unwrap();
    let mut slow = response.into_body().into_data_stream();
    for tick in 1..100 {
        s.ingest(event(s.primary.as_ref().unwrap().as_str(), tick, now_ms()))
            .await
            .unwrap();
    }
    assert_eq!(s.view().health.persisted_observations, 105);
    assert!(s.view().events.len() <= 100);
    assert_eq!(s.queue().depth, 0);
    let first = String::from_utf8(slow.next().await.unwrap().unwrap().to_vec()).unwrap();
    assert!(first.contains("resync_required\":true"));
    assert!(first.contains("id:"));
    let request = Request::builder()
        .uri("/api/v1/stream")
        .header("host", "127.0.0.1:8080")
        .header("last-event-id", "old-run:1")
        .body(Body::empty())
        .unwrap();
    let response = app.oneshot(request).await.unwrap();
    let next = response
        .into_body()
        .into_data_stream()
        .next()
        .await
        .unwrap()
        .unwrap();
    assert!(String::from_utf8_lossy(&next).contains("event: snapshot"));
    s.stopping.cancel();
    assert!(tokio::time::timeout(Duration::from_secs(1), slow.next())
        .await
        .unwrap()
        .is_none());
    assert!(s.shutdown().await.clean);
}
struct FakeAdapter {
    id: String,
    panic: bool,
    closed: Arc<AtomicBool>,
}
struct FakeSession {
    id: String,
    panic: bool,
    closed: Arc<AtomicBool>,
    tick: u64,
    stopped: bool,
    items: VecDeque<ClientEvent>,
}
impl CollectionAdapter for FakeAdapter {
    fn connect(&self) -> BoxFuture<'_, Result<Box<dyn CollectionSession>, RuntimeError>> {
        Box::pin(async move {
            Ok(Box::new(FakeSession {
                id: self.id.clone(),
                panic: self.panic,
                closed: self.closed.clone(),
                tick: 0,
                stopped: false,
                items: VecDeque::new(),
            }) as Box<dyn CollectionSession>)
        })
    }
}
impl CollectionSession for FakeSession {
    fn buffered(&self) -> BoxFuture<'_, usize> {
        Box::pin(async move { self.items.len() })
    }
    fn next(&mut self) -> BoxFuture<'_, Result<ClientEvent, RuntimeError>> {
        Box::pin(async move {
            assert!(!self.panic, "injected adapter panic");
            if self.stopped && self.items.is_empty() {
                return Err(RuntimeError::Ingestion("closed".into()));
            }
            if self.items.is_empty() {
                tokio::time::sleep(Duration::from_millis(20)).await;
                self.items = Simulation::new(SimulationConfig::default(), Scenario::Normal)
                    .frame_at(self.tick)
                    .observations
                    .into_iter()
                    .map(|mut o| {
                        o.data_source_id = DataSourceId::new(&self.id).unwrap();
                        ClientEvent::Observation(Box::new(o))
                    })
                    .collect();
                self.tick += 1;
            }
            Ok(self.items.pop_front().unwrap())
        })
    }
    fn close(&mut self) -> BoxFuture<'_, Result<(), RuntimeError>> {
        Box::pin(async move {
            self.stopped = true;
            self.closed.store(true, Ordering::SeqCst);
            Ok(())
        })
    }
}
#[tokio::test]
async fn panicking_adapter_is_closed_and_isolated_from_other_source() {
    let c = CoreConfig {
        legacy_single_infrastructure: true,
        sources: vec![source("a", 14841), source("b", 14842)],
        ..Default::default()
    };
    let s = AppState::configured(SqliteStore::open_in_memory().unwrap(), &c, None).unwrap();
    s.started().await.unwrap();
    let cancel = CancellationToken::new();
    let closed = Arc::new(AtomicBool::new(false));
    let mut tasks = Vec::new();
    for id in ["a", "b"] {
        tasks.push(tokio::spawn(source_worker(
            s.clone(),
            DataSourceId::new(id).unwrap(),
            Arc::new(FakeAdapter {
                id: id.into(),
                panic: id == "a",
                closed: closed.clone(),
            }),
            cancel.clone(),
        )));
    }
    until(|| {
        s.view().sources[0].last_error.as_deref() == Some("adapter_panic")
            && s.view().sources[1].accepted >= 12
    })
    .await;
    assert_eq!(s.view().health.lifecycle, Lifecycle::Degraded);
    assert!(s.view().health.ready);
    assert!(closed.load(Ordering::SeqCst));
    s.shutdown_deadline(Duration::from_secs(2));
    cancel.cancel();
    for t in tasks {
        tokio::time::timeout(Duration::from_secs(2), t)
            .await
            .unwrap()
            .unwrap()
            .unwrap();
    }
    assert!(s.shutdown().await.clean);
}
#[tokio::test]
async fn invalid_configuration_starts_no_resources() {
    let p = path("invalid-config");
    let _ = std::fs::remove_file(&p);
    let mut c = CoreConfig {
        legacy_single_infrastructure: true,
        sources: vec![oip_server::config::SourceConfig::primary(4840)],
        database: p.clone(),
        queue_capacity: 0,
        ..Default::default()
    };
    assert!(oip_server::runtime::CoreRuntime::start(c.clone(), None)
        .await
        .is_err());
    assert!(!p.exists());
    c.queue_capacity = 1;
    c.sources = vec![source("a", 14841), source("a", 14842)];
    assert!(c.validate().is_err());
    c.sources = vec![source("a", 14841), source("b", 14841)];
    assert!(c.validate().is_err());
    c.sources = vec![source("a", 14841)];
    c.sources[0].endpoint = "opc.tcp://192.0.2.1:4840".into();
    assert!(c.validate().is_err());
    c.sources[0].endpoint = "opc.tcp://user:secret@127.0.0.1:4840".into();
    assert!(c.validate().is_err());
    assert!(serde_json::from_str::<CoreConfig>("{\"sorces\":[]}").is_err());
}
#[tokio::test]
async fn real_adapter_overflow_reports_and_persists_data_loss() {
    use oip_opcua::{
        async_opcua::{AsyncOpcUaClient, AsyncOpcUaServerConfig, RunningAsyncOpcUaServer},
        ClientOptions, ReadOnlyOpcUaAdapter,
    };
    let reservation = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let port = reservation.local_addr().unwrap().port();
    drop(reservation);
    let server = RunningAsyncOpcUaServer::start(AsyncOpcUaServerConfig {
        port,
        simulation: SimulationConfig {
            tick_duration_ms: 20,
            ..Default::default()
        },
        ..Default::default()
    })
    .await
    .unwrap();
    let client = AsyncOpcUaClient::connect(&ClientOptions::local_simulation(server.endpoint(), 2))
        .await
        .unwrap();
    let metrics = (0..1000)
        .map(|n| MetricId::new(format!("bulk.{n:04}")).unwrap())
        .collect::<Vec<_>>();
    client.subscribe(&metrics).await.unwrap();
    until(|| client.dropped_observations() > 0).await;
    let event = client.next_event(Duration::from_secs(1)).await.unwrap();
    assert!(matches!(event,ClientEvent::DataLoss{dropped,..} if dropped>0));
    let mut a = Application::initialize(
        SqliteStore::open_in_memory().unwrap(),
        vec![SourceConfig::primary(port).definition().unwrap()],
        now_ms(),
        5000,
    )
    .unwrap();
    let id = DataSourceId::new(oip_simulator::SIMULATION_ORIGIN_ID).unwrap();
    a.ingest(&id, event, now_ms()).unwrap();
    assert_eq!(a.repository.gaps_for_source(&id).unwrap().len(), 1);
    assert!(a.view(now_ms()).sources[0].dropped > 0);
    client.disconnect().await.unwrap();
    server.stop().await.unwrap();
}

#[tokio::test]
async fn abandoning_runtime_is_detected_and_does_not_detach_live_workers() {
    let reservation = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let port = reservation.local_addr().unwrap().port();
    drop(reservation);
    let p = path("abandon");
    let _ = std::fs::remove_file(&p);
    let config = CoreConfig {
        legacy_single_infrastructure: true,
        database: p,
        sources: vec![SourceConfig::primary(port)],
        ..Default::default()
    };
    let runtime = oip_server::runtime::CoreRuntime::start(config, None)
        .await
        .unwrap();
    let state = runtime.state.clone();
    drop(runtime);
    until(|| state.view().health.lifecycle == Lifecycle::Failed).await;
    let result = tokio::time::timeout(Duration::from_secs(3), state.shutdown())
        .await
        .unwrap();
    assert!(!result.clean);
    assert!(result.persistence_thread_joined);
}

#[test]
fn recovery_clock_rollback_is_reported_without_inventing_gap_times() {
    let mut a = app();
    let id = DataSourceId::new("a").unwrap();
    a.ingest(&id, event("a", 10, 2000), 2000).unwrap();
    a.finish(2100, true).unwrap();
    let a = Application::initialize(a.repository, definitions(), 1000, 500).unwrap();
    assert!(
        matches!(a.recovered_gap(&id,1000),Some(ClientEvent::SubscriptionError{reason,..}) if reason.contains("clock_regression"))
    );
}
