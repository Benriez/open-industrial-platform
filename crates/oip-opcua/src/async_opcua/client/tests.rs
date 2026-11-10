use super::*;
use crate::async_opcua::{AsyncOpcUaServerConfig, RunningAsyncOpcUaServer};
use oip_core::{CollectionError, DataQuality, Freshness, MetricValue};
use oip_simulator::{Scenario, SimulationConfig, SIMULATION_EPOCH_UNIX_MS};
use opcua::types::{AttributeId, Variant};
use std::time::Instant;

fn test_config(port: u16, scenario: Scenario, bulk_node_count: usize) -> AsyncOpcUaServerConfig {
    AsyncOpcUaServerConfig {
        port,
        simulation: SimulationConfig {
            tick_duration_ms: 50,
            bulk_node_count,
            ..SimulationConfig::default()
        },
        scenario,
        ..AsyncOpcUaServerConfig::default()
    }
}

fn free_port() -> u16 {
    std::net::TcpListener::bind(("127.0.0.1", 0))
        .expect("bind loopback port")
        .local_addr()
        .expect("local address")
        .port()
}

async fn connect(server: &RunningAsyncOpcUaServer) -> AsyncOpcUaClient {
    AsyncOpcUaClient::connect(&ClientOptions::local_simulation(server.endpoint(), 2))
        .await
        .expect("connect client")
}

async fn next_event(client: &AsyncOpcUaClient) -> Result<ClientEvent, AdapterError> {
    client.next_event(Duration::from_secs(10)).await
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn discovery_browse_read_and_scaled_namespace_work() {
    let port = free_port();
    let server = RunningAsyncOpcUaServer::start(test_config(port, Scenario::Normal, 1_000))
        .await
        .expect("start server");
    let client = connect(&server).await;
    assert!(!client.endpoints().await.expect("endpoints").is_empty());

    let started = Instant::now();
    let entries = client.browse().await.expect("browse");
    tracing::debug!(
        elapsed_ms = started.elapsed().as_millis(),
        "browse benchmark"
    );
    assert!(entries.len() >= 1_006, "only {} entries", entries.len());

    // The browse result must contain the machine metrics and be free of duplicates.
    for metric in [
        "temperature",
        "pressure",
        "motor_running",
        "operating_mode",
        "alarm_active",
        "units_produced",
    ] {
        assert!(
            entries.iter().any(|entry| entry.browse_name == metric),
            "missing {metric}"
        );
    }
    let mut node_ids = entries
        .iter()
        .map(|entry| entry.node_id.clone())
        .collect::<Vec<_>>();
    let total = node_ids.len();
    node_ids.sort();
    node_ids.dedup();
    assert_eq!(total, node_ids.len(), "browse returned duplicates");

    let temperature = client
        .read(&MetricId::new("temperature").expect("metric"))
        .await
        .expect("read temperature");
    assert!(matches!(temperature.value, Some(MetricValue::Float(_))));
    assert_eq!(temperature.quality, DataQuality::Good);
    assert!(temperature.timestamps.source.as_unix_millis() >= SIMULATION_EPOCH_UNIX_MS);
    assert_eq!(
        temperature
            .simulation_origin
            .as_ref()
            .and_then(|origin| origin.virtual_time_ms),
        Some((temperature.timestamps.source.as_unix_millis() - SIMULATION_EPOCH_UNIX_MS) as u64)
    );
    assert!(temperature.timestamps.server.is_some());
    assert!(temperature.simulation_origin.is_some());

    client.disconnect().await.expect("disconnect");
    server.stop().await.expect("stop server");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn all_simulation_variables_are_readable_and_not_writable() {
    let port = free_port();
    let server = RunningAsyncOpcUaServer::start(test_config(port, Scenario::Normal, 0))
        .await
        .expect("start server");
    let client = connect(&server).await;
    for metric in [
        "temperature",
        "pressure",
        "motor_running",
        "operating_mode",
        "alarm_active",
        "units_produced",
    ] {
        let mut access_read = ReadValueId::from(NodeId::new(2, metric));
        access_read.attribute_id = AttributeId::UserAccessLevel as u32;
        let access = client
            .session
            .read(&[access_read], TimestampsToReturn::Neither, 0.0)
            .await
            .expect("read access level")
            .pop()
            .and_then(|value| value.value)
            .expect("access level value");
        match access {
            Variant::Byte(bits) => {
                assert_eq!(bits & 2, 0, "{metric}: CURRENT_WRITE must be unset");
                assert_eq!(bits & 1, 1, "{metric}: CURRENT_READ must be set");
            }
            other => panic!("unexpected access level value for {metric}: {other:?}"),
        }
    }
    client.disconnect().await.expect("disconnect");
    server.stop().await.expect("stop server");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn browse_uses_continuation_points_beyond_one_thousand_nodes() {
    let port = free_port();
    let server = RunningAsyncOpcUaServer::start(test_config(port, Scenario::Normal, 1_100))
        .await
        .expect("start server");
    let client = connect(&server).await;
    let entries = client.browse().await.expect("browse");
    assert!(
        entries.len() >= 1_106,
        "expected continuation result, got {} entries",
        entries.len()
    );
    client.disconnect().await.expect("disconnect");
    server.stop().await.expect("stop server");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn browse_reports_the_folder_of_every_node() {
    let port = free_port();
    let server = RunningAsyncOpcUaServer::start(test_config(port, Scenario::Normal, 20))
        .await
        .expect("start server");
    let client = connect(&server).await;
    let entries = client.browse().await.expect("browse");

    // Every node names the folder it lives in: the browse name of its
    // parent. The folder is not derived from the name of the node.
    let folder_of = |name: &str| {
        entries
            .iter()
            .find(|entry| entry.browse_name == name)
            .map(|entry| entry.folder.clone())
            .unwrap_or_default()
    };
    assert_eq!(folder_of("M-01"), "OIP", "the machine folder");
    assert_eq!(folder_of("Bulk"), "OIP", "the bulk folder");
    assert_eq!(folder_of("temperature"), "M-01", "the process variable");
    assert_eq!(folder_of("bulk.0000"), "Bulk", "the bulk variable");
    // A node without a readable name keeps the folder of its parent.
    assert!(
        entries.iter().all(|entry| !entry.folder.is_empty()),
        "every entry names a folder"
    );
    client.disconnect().await.expect("disconnect");
    server.stop().await.expect("stop server");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn browse_respects_the_configured_node_limit() {
    let port = free_port();
    let server = RunningAsyncOpcUaServer::start(test_config(port, Scenario::Normal, 1_000))
        .await
        .expect("start server");
    let mut options = ClientOptions::local_simulation(server.endpoint(), 2);
    options.max_browse_nodes = 10;
    let client = AsyncOpcUaClient::connect(&options)
        .await
        .expect("connect client");
    let result = client.browse().await;
    assert!(
        matches!(result, Err(AdapterError::BrowseLimitExceeded(10))),
        "unexpected result: {result:?}"
    );
    client.disconnect().await.expect("disconnect");
    server.stop().await.expect("stop server");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn reading_an_unknown_node_reports_an_error_instead_of_a_value() {
    let port = free_port();
    let server = RunningAsyncOpcUaServer::start(test_config(port, Scenario::Normal, 0))
        .await
        .expect("start server");
    let client = connect(&server).await;
    let result = client
        .read(&MetricId::new("does-not-exist").expect("metric"))
        .await;
    assert!(result.is_err(), "unknown node must not yield a value");
    client.disconnect().await.expect("disconnect");
    server.stop().await.expect("stop server");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn data_change_subscription_contains_quality_timestamps_and_origin() {
    let port = free_port();
    let server = RunningAsyncOpcUaServer::start(test_config(port, Scenario::Normal, 0))
        .await
        .expect("start server");
    let client = connect(&server).await;
    client
        .subscribe(&[MetricId::new("temperature").expect("metric")])
        .await
        .expect("subscribe");
    let observation = loop {
        if let ClientEvent::Observation(observation) = next_event(&client).await.expect("event") {
            break observation;
        }
    };
    assert_eq!(observation.quality, DataQuality::Good);
    assert!(observation.status_code.is_some());
    assert!(observation.timestamps.server.is_some());
    assert_eq!(
        observation
            .simulation_origin
            .as_ref()
            .and_then(|origin| origin.seed),
        Some(42)
    );
    assert_eq!(
        observation
            .simulation_origin
            .as_ref()
            .and_then(|origin| origin.sequence),
        Some(
            (observation.timestamps.source.as_unix_millis() - SIMULATION_EPOCH_UNIX_MS) as u64 / 50
        )
    );
    client.disconnect().await.expect("disconnect");
    server.stop().await.expect("stop server");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn sensor_fault_preserves_bad_quality_without_zero_fallback() {
    let port = free_port();
    let server = RunningAsyncOpcUaServer::start(test_config(port, Scenario::SensorFault, 0))
        .await
        .expect("start server");
    let client = connect(&server).await;
    let temperature = client
        .read(&MetricId::new("temperature").expect("metric"))
        .await
        .expect("read");
    assert_eq!(temperature.value, None, "{temperature:?}");
    assert_eq!(temperature.quality, DataQuality::Bad, "{temperature:?}");
    assert_eq!(
        temperature.collection_error,
        Some(CollectionError::InvalidMeasurement),
        "{temperature:?}"
    );
    client.disconnect().await.expect("disconnect");
    server.stop().await.expect("stop server");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn interrupted_connection_keeps_its_reason_and_never_falls_back_to_zero() {
    let port = free_port();
    let server =
        RunningAsyncOpcUaServer::start(test_config(port, Scenario::ConnectionInterrupted, 0))
            .await
            .expect("start server");
    let client = connect(&server).await;
    let pressure = client
        .read(&MetricId::new("pressure").expect("metric"))
        .await
        .expect("read");
    assert_eq!(pressure.value, None, "{pressure:?}");
    assert_eq!(pressure.quality, DataQuality::Unknown, "{pressure:?}");
    assert_eq!(pressure.freshness, Freshness::Unknown, "{pressure:?}");
    assert_eq!(
        pressure.collection_error,
        Some(CollectionError::ConnectionInterrupted),
        "{pressure:?}"
    );
    client.disconnect().await.expect("disconnect");
    server.stop().await.expect("stop server");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn reconnect_recreates_subscription_and_reports_gap() {
    let _ = tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .with_test_writer()
        .try_init();
    let port = free_port();
    let server = RunningAsyncOpcUaServer::start(test_config(port, Scenario::Normal, 0))
        .await
        .expect("start server");
    let client = connect(&server).await;
    client
        .subscribe(&[MetricId::new("temperature").expect("metric")])
        .await
        .expect("subscribe");
    let _ = next_event(&client).await.expect("initial observation");
    server.stop().await.expect("stop server");

    let disconnected = loop {
        if let ClientEvent::ConnectionLost { at, reason } =
            next_event(&client).await.expect("event")
        {
            break (at, reason);
        }
    };
    let restarted = RunningAsyncOpcUaServer::start(test_config(port, Scenario::Reconnect, 0))
        .await
        .expect("restart server");
    let reconnected = loop {
        match next_event(&client).await.expect("event") {
            ClientEvent::Reconnected { at, gap } => break (at, gap),
            ClientEvent::SubscriptionError { reason, .. } => panic!("{reason}"),
            _ => {}
        }
    };
    assert_eq!(reconnected.1.started_at, disconnected.0);
    assert!(reconnected.1.ended_at >= reconnected.1.started_at);
    let observation = loop {
        if let ClientEvent::Observation(observation) = next_event(&client).await.expect("event") {
            break observation;
        }
    };
    assert_eq!(
        observation
            .simulation_origin
            .and_then(|origin| origin.scenario),
        Some("reconnect".to_owned())
    );
    client.disconnect().await.expect("disconnect");
    restarted.stop().await.expect("stop restarted server");
}

#[tokio::test]
async fn non_loopback_endpoint_is_rejected_before_network_access() {
    let options = ClientOptions::local_simulation("opc.tcp://192.0.2.1:4840", 2);
    let result = AsyncOpcUaClient::connect(&options).await;
    assert!(matches!(result, Err(AdapterError::NonLoopbackEndpoint(_))));
}

#[tokio::test]
async fn localhost_alias_is_rejected_to_keep_the_loopback_guarantee_literal() {
    let options = ClientOptions::local_simulation("opc.tcp://localhost:4840", 2);
    let result = AsyncOpcUaClient::connect(&options).await;
    assert!(matches!(result, Err(AdapterError::NonLoopbackEndpoint(_))));
}

#[tokio::test]
async fn production_security_profile_without_pki_fails_closed() {
    let options = ClientOptions {
        security_profile: crate::SecurityProfile::Production {
            security_policy: "http://opcfoundation.org/UA/SecurityPolicy#Basic256Sha256".to_owned(),
            security_mode: "SignAndEncrypt".to_owned(),
        },
        ..ClientOptions::local_simulation("opc.tcp://127.0.0.1:4840", 2)
    };
    let result = AsyncOpcUaClient::connect(&options).await;
    assert!(matches!(
        result,
        Err(AdapterError::InvalidSecurityConfiguration(_))
    ));
}

#[tokio::test]
async fn unbounded_session_retry_limit_is_rejected() {
    let options = ClientOptions {
        session_retry_limit: -1,
        ..ClientOptions::local_simulation("opc.tcp://127.0.0.1:4840", 2)
    };
    let result = AsyncOpcUaClient::connect(&options).await;
    assert!(matches!(result, Err(AdapterError::Protocol(_))));
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn virtual_clock_values_are_not_mistaken_for_stale_data() {
    let port = free_port();
    let server = RunningAsyncOpcUaServer::start(test_config(port, Scenario::Normal, 0))
        .await
        .expect("start server");
    let client = connect(&server).await;
    // The simulation runs on a virtual clock that differs from the client wall
    // clock by years. Its values must still be reported as fresh.
    let observation = client
        .read(&MetricId::new("temperature").expect("metric"))
        .await
        .expect("read");
    assert_eq!(
        observation.freshness,
        Freshness::Fresh,
        "virtual clock value must not be stale: {observation:?}"
    );
    assert_eq!(observation.quality, DataQuality::Good);
    client.disconnect().await.expect("disconnect");
    server.stop().await.expect("stop server");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn untrusted_origin_id_is_not_adopted_as_provenance() {
    use crate::async_opcua::mapping::{
        data_value_to_observation, quality_from_status, SimulationMetadata,
    };
    use opcua::types::StatusCode;

    let metric = MetricId::new("temperature").expect("metric");
    let metadata = SimulationMetadata {
        origin_id: Some("   ".to_owned()),
        seed: Some(1),
        scenario: Some("normal".to_owned()),
        epoch_unix_ms: Some(SIMULATION_EPOCH_UNIX_MS),
        tick_duration_ms: Some(50),
    };
    let value = opcua::types::DataValue {
        value: Some(opcua::types::Variant::from(60.0)),
        status: Some(StatusCode::Good),
        source_timestamp: Some(opcua::types::DateTime::now()),
        source_picoseconds: Some(0),
        server_timestamp: Some(opcua::types::DateTime::now()),
        server_picoseconds: Some(0),
    };
    // A whitespace-only origin is rejected instead of panicking or being
    // silently replaced by a placeholder identity.
    let result = data_value_to_observation(
        &metric,
        &value,
        &metadata,
        None,
        &FreshnessPolicy::default(),
    );
    assert!(
        matches!(result, Err(AdapterError::UntrustedProvenance)),
        "whitespace origin must be rejected"
    );

    // An empty origin must not panic either.
    let metadata = SimulationMetadata {
        origin_id: Some(String::new()),
        ..metadata
    };
    let result = data_value_to_observation(
        &metric,
        &value,
        &metadata,
        None,
        &FreshnessPolicy::default(),
    );
    assert!(matches!(result, Err(AdapterError::UntrustedProvenance)));

    // A mismatching origin must be reported instead of adopted.
    let metadata = SimulationMetadata {
        origin_id: Some("some-other-plant".to_owned()),
        ..metadata
    };
    let observation = data_value_to_observation(
        &metric,
        &value,
        &metadata,
        None,
        &FreshnessPolicy::default(),
    )
    .expect("map observation");
    assert!(observation.simulation_origin.is_none());
    assert_eq!(
        observation.collection_error,
        Some(CollectionError::InvalidProvenance)
    );

    // The status mapping restores the original failure reason.
    assert_eq!(
        quality_from_status(StatusCode::BadSensorFailure),
        (DataQuality::Bad, Some(CollectionError::InvalidMeasurement))
    );
    assert_eq!(
        quality_from_status(StatusCode::BadNotConnected),
        (
            DataQuality::Unknown,
            Some(CollectionError::DeviceUnreachable)
        )
    );
    assert_eq!(
        quality_from_status(StatusCode::BadConnectionClosed),
        (
            DataQuality::Unknown,
            Some(CollectionError::ConnectionInterrupted)
        )
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn disconnected_remote_close_does_not_leave_local_producer_running() {
    let server = RunningAsyncOpcUaServer::start(test_config(free_port(), Scenario::Normal, 0))
        .await
        .unwrap();
    let client = connect(&server).await;
    server.stop().await.unwrap();
    // Remote acknowledgement may be unavailable. That is separate from actual
    // local producer termination, which the core must verify before queue drain.
    let _remote_ack = client.shutdown().await;
    assert!(client.local_event_task_stopped());
}
