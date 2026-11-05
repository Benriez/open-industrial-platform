//! Isolated open62541 proof of concept used for the OIP-001 bake-off.

use crate::endpoint::validate_loopback_endpoint;
use crate::AdapterError;
use oip_core::{MetricValue, ObservationEnvelope, Timestamp};
use oip_simulator::{Scenario, Simulation, SimulationConfig};
use open62541::{
    ua, AsyncClient, ClientBuilder, DataType as _, ObjectNode, Server, ServerBuilder, ServerRunner,
    VariableNode,
};
use open62541_sys::{
    UA_NS0ID_BASEDATAVARIABLETYPE, UA_NS0ID_BOOLEAN, UA_NS0ID_DOUBLE, UA_NS0ID_FOLDERTYPE,
    UA_NS0ID_INT64, UA_NS0ID_OBJECTSFOLDER, UA_NS0ID_ORGANIZES, UA_NS0ID_STRING, UA_NS0ID_UINT64,
};
use serde::Serialize;
use std::collections::HashMap;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};
use std::thread;
use std::time::{Duration, Instant};

const NAMESPACE_URI: &str = "urn:oip:open62541-poc";

#[derive(Clone, Debug, Serialize)]
pub struct Open62541PocReport {
    pub endpoint_count: usize,
    pub browsed_machine_nodes: usize,
    pub bulk_node_count: usize,
    pub subscription_events: usize,
    pub reconnect_and_resubscribe: bool,
    pub disconnect_detected: bool,
    pub client_recreated: bool,
    pub discovery_us: u128,
    pub browse_us: u128,
    pub read_us: u128,
    pub first_subscription_us: u128,
    pub reconnect_us: u128,
}

struct NodeMap {
    metrics: HashMap<String, ua::NodeId>,
    bulk: Vec<ua::NodeId>,
}

struct RunningServer {
    endpoint: String,
    server: Server,
    running: Arc<AtomicBool>,
    runner_task: thread::JoinHandle<()>,
    update_task: thread::JoinHandle<()>,
}

impl RunningServer {
    fn start(port: u16, scenario: Scenario, bulk_node_count: usize) -> Result<Self, AdapterError> {
        let url = format!("opc.tcp://127.0.0.1:{port}");
        let (server, runner) = ServerBuilder::default().server_urls(&[&url]).build();
        let namespace = server.add_namespace(NAMESPACE_URI);
        let simulation = Simulation::new(
            SimulationConfig {
                tick_duration_ms: 50,
                bulk_node_count,
                ..SimulationConfig::default()
            },
            scenario,
        );
        let nodes = create_address_space(
            &server,
            namespace,
            bulk_node_count,
            simulation.config().seed,
            scenario,
            simulation.config().tick_duration_ms,
        )?;
        publish_frame(&server, &nodes, simulation.frame_at(0))?;
        let running = Arc::new(AtomicBool::new(true));
        let runner_task = spawn_runner(runner, running.clone());
        let endpoint = server
            .discovery_urls()
            .ok_or_else(|| AdapterError::Connection("server did not start".to_owned()))?
            .as_slice()
            .first()
            .ok_or_else(|| AdapterError::Connection("discovery URL missing".to_owned()))?
            .as_str()
            .ok_or_else(|| AdapterError::Protocol("invalid discovery URL".to_owned()))?
            .to_owned();
        let update_task = spawn_updates(server.clone(), nodes, simulation, running.clone());
        Ok(Self {
            endpoint,
            server,
            running,
            runner_task,
            update_task,
        })
    }

    fn stop(self) -> Result<(), AdapterError> {
        self.running.store(false, Ordering::Relaxed);
        self.runner_task
            .join()
            .map_err(|_| AdapterError::Task("open62541 runner panicked".to_owned()))?;
        self.update_task
            .join()
            .map_err(|_| AdapterError::Task("open62541 updater panicked".to_owned()))?;
        drop(self.server);
        Ok(())
    }
}

pub async fn run_open62541_poc(
    port: u16,
    bulk_node_count: usize,
) -> Result<Open62541PocReport, AdapterError> {
    let mut server = RunningServer::start(port, Scenario::Normal, bulk_node_count)?;
    let mut subscription_events = 0_usize;
    let endpoint = server.endpoint.clone();
    let namespace = server.server.get_namespace_by_name(
        &ua::String::new(NAMESPACE_URI)
            .map_err(|error| AdapterError::Protocol(error.to_string()))?,
    );
    let namespace =
        namespace.ok_or_else(|| AdapterError::Protocol("namespace missing".to_owned()))?;

    let discovery_started = Instant::now();
    let endpoints = ClientBuilder::default()
        .get_endpoints(&endpoint)
        .map_err(|error| AdapterError::Connection(error.to_string()))?;
    let discovery_us = discovery_started.elapsed().as_micros();

    let client = ClientBuilder::default()
        .connectivity_check_interval(Some(Duration::from_millis(50)))
        .security_mode(ua::MessageSecurityMode::NONE)
        .security_policy_uri(
            ua::String::new("http://opcfoundation.org/UA/SecurityPolicy#None")
                .map_err(|error| AdapterError::Protocol(error.to_string()))?,
        )
        .connect(&endpoint)
        .map_err(|error| AdapterError::Connection(error.to_string()))?
        .into_async();
    let machine = ua::NodeId::string(namespace, "M-01");
    let temperature = ua::NodeId::string(namespace, "temperature");

    let browse_started = Instant::now();
    let (references, _) = client
        .browse(&ua::BrowseDescription::default().with_node_id(&machine))
        .await
        .map_err(|error| AdapterError::Protocol(error.to_string()))?;
    let browse_us = browse_started.elapsed().as_micros();

    let read_started = Instant::now();
    let value = client
        .read_value(&temperature)
        .await
        .map_err(|error| AdapterError::Protocol(error.to_string()))?;
    let read_us = read_started.elapsed().as_micros();
    let value = value
        .into_value()
        .and_then(|value| value.into_scalar::<ua::Double>())
        .ok_or_else(|| AdapterError::UnsupportedValue("expected Double".to_owned()))?;
    if !value.value().is_finite() {
        return Err(AdapterError::UnsupportedValue(
            "non-finite Double".to_owned(),
        ));
    }

    let subscription_started = Instant::now();
    let subscription = client
        .create_subscription()
        .await
        .map_err(|error| AdapterError::Protocol(error.to_string()))?;
    let mut monitored = subscription
        .create_monitored_item(&temperature)
        .await
        .map_err(|error| AdapterError::Protocol(error.to_string()))?;
    tokio::time::timeout(Duration::from_secs(5), monitored.next())
        .await
        .map_err(|_| AdapterError::Protocol("initial subscription timeout".to_owned()))?
        .ok_or_else(|| AdapterError::Protocol("subscription stream closed".to_owned()))?;
    subscription_events += 1;
    let first_subscription_us = subscription_started.elapsed().as_micros();
    drop(monitored);
    drop(subscription);

    let reconnect_started = Instant::now();
    server.stop()?;
    let disconnect_detected =
        tokio::time::timeout(Duration::from_secs(2), client.read_value(&temperature))
            .await
            .is_ok_and(|result| result.is_err());
    if !disconnect_detected {
        return Err(AdapterError::Connection(
            "open62541 disconnect was not detected by read".to_owned(),
        ));
    }
    drop(client);
    server = RunningServer::start(port, Scenario::Reconnect, bulk_node_count)?;
    let client = loop {
        match connect_local_none(&server.endpoint) {
            Ok(client) => break client,
            Err(_) if reconnect_started.elapsed() < Duration::from_secs(5) => {
                tokio::time::sleep(Duration::from_millis(50)).await;
            }
            Err(error) => return Err(AdapterError::Connection(error.to_string())),
        }
    };
    let subscription = client
        .create_subscription()
        .await
        .map_err(|error| AdapterError::Protocol(error.to_string()))?;
    let mut monitored = subscription
        .create_monitored_item(&temperature)
        .await
        .map_err(|error| AdapterError::Protocol(error.to_string()))?;
    tokio::time::timeout(Duration::from_secs(5), monitored.next())
        .await
        .map_err(|_| AdapterError::Protocol("reconnect subscription timeout".to_owned()))?
        .ok_or_else(|| AdapterError::Protocol("reconnect subscription closed".to_owned()))?;
    subscription_events += 1;
    let reconnect_us = reconnect_started.elapsed().as_micros();

    drop(monitored);
    drop(subscription);
    client.disconnect().await;
    server.stop()?;
    Ok(Open62541PocReport {
        endpoint_count: endpoints.as_slice().len(),
        browsed_machine_nodes: references.len(),
        bulk_node_count,
        subscription_events,
        reconnect_and_resubscribe: true,
        disconnect_detected,
        client_recreated: true,
        discovery_us,
        browse_us,
        read_us,
        first_subscription_us,
        reconnect_us,
    })
}

fn connect_local_none(endpoint: &str) -> Result<AsyncClient, AdapterError> {
    Ok(ClientBuilder::default()
        .security_mode(ua::MessageSecurityMode::NONE)
        .security_policy_uri(
            ua::String::new("http://opcfoundation.org/UA/SecurityPolicy#None")
                .map_err(|error| AdapterError::Protocol(error.to_string()))?,
        )
        .connect(endpoint)
        .map_err(|error| AdapterError::Connection(error.to_string()))?
        .into_async())
}

pub async fn open62541_interop_check(endpoint: &str, namespace: u16) -> Result<(), AdapterError> {
    validate_loopback_endpoint(endpoint)?;
    let client = connect_local_none(endpoint)?;
    let machine = ua::NodeId::string(namespace, "M-01");
    let temperature = ua::NodeId::string(namespace, "temperature");
    let (references, _) = client
        .browse(&ua::BrowseDescription::default().with_node_id(&machine))
        .await
        .map_err(|error| AdapterError::Protocol(error.to_string()))?;
    if references.len() < 6 {
        return Err(AdapterError::Protocol(
            "incomplete M-01 browse result".to_owned(),
        ));
    }
    let value = client
        .read_value(&temperature)
        .await
        .map_err(|error| AdapterError::Protocol(error.to_string()))?;
    if value
        .into_value()
        .and_then(|value| value.into_scalar::<ua::Double>())
        .is_none()
    {
        return Err(AdapterError::UnsupportedValue("expected Double".to_owned()));
    }
    let subscription = client
        .create_subscription()
        .await
        .map_err(|error| AdapterError::Protocol(error.to_string()))?;
    let mut monitored = subscription
        .create_monitored_item(&temperature)
        .await
        .map_err(|error| AdapterError::Protocol(error.to_string()))?;
    tokio::time::timeout(Duration::from_secs(5), monitored.next())
        .await
        .map_err(|_| AdapterError::Protocol("interop subscription timeout".to_owned()))?
        .ok_or_else(|| AdapterError::Protocol("interop subscription closed".to_owned()))?;
    drop(monitored);
    drop(subscription);
    client.disconnect().await;
    Ok(())
}

fn create_address_space(
    server: &Server,
    namespace: u16,
    bulk_node_count: usize,
    seed: u64,
    scenario: Scenario,
    tick_duration_ms: u64,
) -> Result<NodeMap, AdapterError> {
    let root = add_object(
        server,
        namespace,
        "OIP",
        &ua::NodeId::ns0(UA_NS0ID_OBJECTSFOLDER),
    )?;
    let machine = add_object(server, namespace, "M-01", &root)?;
    let bulk_folder = add_object(server, namespace, "Bulk", &root)?;
    let metadata_folder = add_object(server, namespace, "Simulation", &root)?;
    for (name, data_type, value) in [
        (
            "simulation.origin_id",
            UA_NS0ID_STRING,
            ua::Variant::scalar(
                ua::String::new(oip_simulator::SIMULATION_ORIGIN_ID)
                    .map_err(|error| AdapterError::Protocol(error.to_string()))?,
            ),
        ),
        (
            "simulation.seed",
            UA_NS0ID_UINT64,
            ua::Variant::scalar(ua::UInt64::new(seed)),
        ),
        (
            "simulation.scenario",
            UA_NS0ID_STRING,
            ua::Variant::scalar(
                ua::String::new(scenario.as_str())
                    .map_err(|error| AdapterError::Protocol(error.to_string()))?,
            ),
        ),
        (
            "simulation.epoch_unix_ms",
            UA_NS0ID_INT64,
            ua::Variant::scalar(ua::Int64::new(oip_simulator::SIMULATION_EPOCH_UNIX_MS)),
        ),
        (
            "simulation.tick_duration_ms",
            UA_NS0ID_UINT64,
            ua::Variant::scalar(ua::UInt64::new(tick_duration_ms)),
        ),
    ] {
        let node = add_variable(server, namespace, name, &metadata_folder, data_type)?;
        server
            .write_value(&node, &value)
            .map_err(|error| AdapterError::Protocol(error.to_string()))?;
    }
    let mut metrics = HashMap::new();
    for (name, data_type) in [
        ("temperature", UA_NS0ID_DOUBLE),
        ("pressure", UA_NS0ID_DOUBLE),
        ("motor_running", UA_NS0ID_BOOLEAN),
        ("operating_mode", UA_NS0ID_STRING),
        ("alarm_active", UA_NS0ID_BOOLEAN),
        ("units_produced", UA_NS0ID_UINT64),
    ] {
        let node = add_variable(server, namespace, name, &machine, data_type)?;
        metrics.insert(name.to_owned(), node);
    }
    let mut bulk = Vec::with_capacity(bulk_node_count);
    for index in 0..bulk_node_count {
        let name = format!("bulk.{index:04}");
        bulk.push(add_variable(
            server,
            namespace,
            &name,
            &bulk_folder,
            UA_NS0ID_DOUBLE,
        )?);
    }
    Ok(NodeMap { metrics, bulk })
}

fn add_object(
    server: &Server,
    namespace: u16,
    name: &str,
    parent: &ua::NodeId,
) -> Result<ua::NodeId, AdapterError> {
    server
        .add_object_node(ObjectNode {
            requested_new_node_id: Some(ua::NodeId::string(namespace, name)),
            parent_node_id: parent.clone(),
            reference_type_id: ua::NodeId::ns0(UA_NS0ID_ORGANIZES),
            browse_name: ua::QualifiedName::new(namespace, name),
            type_definition: ua::NodeId::ns0(UA_NS0ID_FOLDERTYPE),
            attributes: ua::ObjectAttributes::default(),
        })
        .map_err(|error| AdapterError::Protocol(error.to_string()))
}

fn add_variable(
    server: &Server,
    namespace: u16,
    name: &str,
    parent: &ua::NodeId,
    data_type: u32,
) -> Result<ua::NodeId, AdapterError> {
    // Simulation variables are explicitly read-only: CURRENT_READ without CURRENT_WRITE.
    let access_level = ua::AccessLevelType::NONE.with_current_read(true);
    server
        .add_variable_node(VariableNode {
            requested_new_node_id: Some(ua::NodeId::string(namespace, name)),
            parent_node_id: parent.clone(),
            reference_type_id: ua::NodeId::ns0(UA_NS0ID_ORGANIZES),
            browse_name: ua::QualifiedName::new(namespace, name),
            type_definition: ua::NodeId::ns0(UA_NS0ID_BASEDATAVARIABLETYPE),
            attributes: ua::VariableAttributes::default()
                .with_data_type(&ua::NodeId::ns0(data_type))
                .with_access_level(&access_level),
        })
        .map_err(|error| AdapterError::Protocol(error.to_string()))
}

fn spawn_runner(runner: ServerRunner, running: Arc<AtomicBool>) -> thread::JoinHandle<()> {
    thread::spawn(move || {
        if let Err(error) = runner.run_until_cancelled(|| !running.load(Ordering::Relaxed)) {
            tracing::error!(%error, "open62541 server runner failed");
        }
    })
}

fn spawn_updates(
    server: Server,
    nodes: NodeMap,
    mut simulation: Simulation,
    running: Arc<AtomicBool>,
) -> thread::JoinHandle<()> {
    thread::spawn(move || {
        while running.load(Ordering::Relaxed) {
            if let Err(error) = publish_frame(&server, &nodes, simulation.next_frame()) {
                tracing::error!(%error, "open62541 simulation update failed");
                break;
            }
            thread::sleep(Duration::from_millis(50));
        }
    })
}

fn publish_frame(
    server: &Server,
    nodes: &NodeMap,
    frame: oip_simulator::SimulationFrame,
) -> Result<(), AdapterError> {
    for observation in &frame.observations {
        if let Some(node) = nodes.metrics.get(observation.metric_id.as_str()) {
            server
                .write_data_value(node, &observation_to_data_value(observation)?)
                .map_err(|error| AdapterError::Protocol(error.to_string()))?;
        }
    }
    let source = to_open62541_datetime(frame.observations[0].timestamps.source.as_unix_millis())?;
    for bulk_node in &frame.bulk_nodes {
        if let Some(node) = nodes.bulk.get(bulk_node.index) {
            let value = ua::DataValue::new(ua::Variant::scalar(ua::Double::new(bulk_node.value)))
                .with_source_timestamp(&source)
                .with_server_timestamp(&to_open62541_datetime(Timestamp::now()?.as_unix_millis())?);
            server
                .write_data_value(node, &value)
                .map_err(|error| AdapterError::Protocol(error.to_string()))?;
        }
    }
    Ok(())
}

fn observation_to_data_value(
    observation: &ObservationEnvelope,
) -> Result<ua::DataValue, AdapterError> {
    let variant = match observation.value.as_ref() {
        Some(MetricValue::Float(value)) => ua::Variant::scalar(ua::Double::new(*value)),
        Some(MetricValue::Boolean(value)) => ua::Variant::scalar(ua::Boolean::new(*value)),
        Some(MetricValue::UnsignedInteger(value)) => ua::Variant::scalar(ua::UInt64::new(*value)),
        Some(MetricValue::Text(value)) => ua::Variant::scalar(
            ua::String::new(value).map_err(|error| AdapterError::Protocol(error.to_string()))?,
        ),
        Some(other) => return Err(AdapterError::UnsupportedValue(format!("{other:?}"))),
        None => ua::Variant::init(),
    };
    // The status code encodes the concrete failure reason so that a client can
    // distinguish an invalid measurement from an unreachable source.
    let status = match observation.collection_error {
        Some(oip_core::CollectionError::InvalidMeasurement) => ua::StatusCode::BADSENSORFAILURE,
        Some(oip_core::CollectionError::DeviceUnreachable) => ua::StatusCode::BADNOTCONNECTED,
        Some(oip_core::CollectionError::ConnectionInterrupted) => {
            ua::StatusCode::BADCONNECTIONCLOSED
        }
        Some(oip_core::CollectionError::CollectorUnavailable) => ua::StatusCode::BADNODATA,
        Some(oip_core::CollectionError::StaleMeasurement) => {
            ua::StatusCode::UNCERTAINLASTUSABLEVALUE
        }
        Some(oip_core::CollectionError::InvalidTimestamp) => ua::StatusCode::BADINVALIDTIMESTAMP,
        Some(oip_core::CollectionError::SecurityValidationFailed) => {
            ua::StatusCode::BADSECURITYCHECKSFAILED
        }
        Some(oip_core::CollectionError::InvalidProvenance) => ua::StatusCode::BADINVALIDARGUMENT,
        Some(oip_core::CollectionError::Unknown) => ua::StatusCode::BADUNEXPECTEDERROR,
        None => match observation.quality {
            oip_core::DataQuality::Good => ua::StatusCode::GOOD,
            oip_core::DataQuality::Uncertain => ua::StatusCode::UNCERTAIN,
            oip_core::DataQuality::Bad => ua::StatusCode::BADSENSORFAILURE,
            oip_core::DataQuality::Unknown => ua::StatusCode::BADUNEXPECTEDERROR,
        },
    };
    Ok(ua::DataValue::new(variant)
        .with_status(&status)
        .with_source_timestamp(&to_open62541_datetime(
            observation.timestamps.source.as_unix_millis(),
        )?)
        .with_server_timestamp(&to_open62541_datetime(Timestamp::now()?.as_unix_millis())?))
}

fn to_open62541_datetime(unix_ms: i64) -> Result<ua::DateTime, AdapterError> {
    ua::DateTime::try_from_unix_timestamp_nanos(i128::from(unix_ms) * 1_000_000)
        .map_err(|error| AdapterError::Protocol(error.to_string()))
}

#[cfg(all(test, feature = "async-opcua-backend"))]
mod tests {
    use super::*;
    use crate::async_opcua::{AsyncOpcUaClient, AsyncOpcUaServerConfig, RunningAsyncOpcUaServer};
    use crate::{ClientEvent, ClientOptions, ReadOnlyOpcUaAdapter};

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn open62541_client_interoperates_with_async_opcua_server() {
        let _ = tracing_subscriber::fmt()
            .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
            .with_test_writer()
            .try_init();
        let port = std::net::TcpListener::bind(("127.0.0.1", 0))
            .expect("bind loopback")
            .local_addr()
            .expect("local address")
            .port();
        let server = RunningAsyncOpcUaServer::start(AsyncOpcUaServerConfig {
            port,
            simulation: SimulationConfig {
                tick_duration_ms: 50,
                bulk_node_count: 0,
                ..SimulationConfig::default()
            },
            scenario: Scenario::Normal,
            ..AsyncOpcUaServerConfig::default()
        })
        .await
        .expect("start independent server");
        open62541_interop_check(server.endpoint(), 2)
            .await
            .expect("cross-stack browse/read/subscription");
        server.stop().await.expect("stop server");
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn async_opcua_client_interoperates_with_open62541_server() {
        let port = std::net::TcpListener::bind(("127.0.0.1", 0))
            .expect("bind loopback")
            .local_addr()
            .expect("local address")
            .port();
        let server = RunningServer::start(port, Scenario::Normal, 0).expect("start open62541");
        let client =
            AsyncOpcUaClient::connect(&ClientOptions::local_simulation(&server.endpoint, 2))
                .await
                .expect("connect async-opcua client");
        let metric = oip_core::MetricId::new("temperature").expect("metric");
        let value = ReadOnlyOpcUaAdapter::read(&client, &metric)
            .await
            .expect("cross-stack read");
        assert!(matches!(value.value, Some(MetricValue::Float(_))));
        assert!(value.simulation_origin.is_some());
        ReadOnlyOpcUaAdapter::subscribe(&client, std::slice::from_ref(&metric))
            .await
            .expect("cross-stack subscription");
        let observation = tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                if let ClientEvent::Observation(observation) = client
                    .next_event(Duration::from_secs(5))
                    .await
                    .expect("event")
                {
                    break observation;
                }
            }
        })
        .await
        .expect("subscription timeout");
        assert_eq!(observation.quality, oip_core::DataQuality::Good);
        client.disconnect().await.expect("disconnect");
        server.stop().expect("stop open62541");
    }
}
