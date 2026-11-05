use crate::async_opcua::mapping::{observation_to_data_value, timestamp_to_datetime};
use crate::{AdapterError, ProductionSecurityConfig, SecurityProfile};
use oip_simulator::{Scenario, Simulation, SimulationConfig};
use opcua::crypto::SecurityPolicy;
use opcua::server::address_space::Variable;
use opcua::server::diagnostics::NamespaceMetadata;
use opcua::server::node_manager::memory::{
    simple_node_manager, InMemoryNodeManager, SimpleNodeManager, SimpleNodeManagerImpl,
};
use opcua::server::{
    ServerBuilder, ServerEndpoint, ServerHandle, SubscriptionCache, ANONYMOUS_USER_TOKEN_ID,
};
use opcua::types::{DataValue, DateTime, MessageSecurityMode, NodeId, UAString};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

pub const NAMESPACE_URI: &str = "urn:oip:local-simulation";

pub struct AsyncOpcUaServerConfig {
    pub port: u16,
    pub simulation: SimulationConfig,
    pub scenario: Scenario,
    pub security_profile: SecurityProfile,
    pub production_security: Option<ProductionSecurityConfig>,
}

impl Default for AsyncOpcUaServerConfig {
    fn default() -> Self {
        Self {
            port: 4840,
            simulation: SimulationConfig::default(),
            scenario: Scenario::Normal,
            security_profile: SecurityProfile::LocalSimulation,
            production_security: None,
        }
    }
}

struct NodeMap {
    metrics: HashMap<String, NodeId>,
    bulk: Vec<NodeId>,
}

pub struct RunningAsyncOpcUaServer {
    endpoint: String,
    port: u16,
    handle: ServerHandle,
    cancellation: CancellationToken,
    server_task: JoinHandle<()>,
    update_task: JoinHandle<()>,
}

impl RunningAsyncOpcUaServer {
    pub async fn start(config: AsyncOpcUaServerConfig) -> Result<Self, AdapterError> {
        let endpoint = format!("opc.tcp://127.0.0.1:{}", config.port);
        let cancellation = CancellationToken::new();
        let mut builder = ServerBuilder::new()
            .application_name("OIP Read-only Simulation")
            .application_uri("urn:oip:local-simulation-server")
            .product_uri("urn:oip:local-simulation")
            .host("127.0.0.1")
            .port(config.port)
            .discovery_urls(vec!["/".to_owned()]);
        match &config.security_profile {
            SecurityProfile::LocalSimulation => {
                if config.production_security.is_some() {
                    return Err(AdapterError::InvalidSecurityConfiguration(
                        "local simulation must not carry production PKI settings".to_owned(),
                    ));
                }
                builder = builder.add_endpoint(
                    "none",
                    ServerEndpoint::new_none("/", &[ANONYMOUS_USER_TOKEN_ID.to_string()]),
                );
            }
            SecurityProfile::Production {
                security_policy,
                security_mode,
            } => {
                if security_policy != SecurityPolicy::Basic256Sha256.to_str()
                    || security_mode != "SignAndEncrypt"
                {
                    return Err(AdapterError::InvalidSecurityConfiguration(
                        "production requires Basic256Sha256 and SignAndEncrypt".to_owned(),
                    ));
                }
                let pki = config.production_security.as_ref().ok_or_else(|| {
                    AdapterError::InvalidSecurityConfiguration(
                        "production requires explicit certificate, key and trust store paths"
                            .to_owned(),
                    )
                })?;
                super::security::validate_production_pki(pki)?;
                builder = builder
                    .pki_dir(&pki.pki_dir)
                    .certificate_path(&pki.certificate_path)
                    .private_key_path(&pki.private_key_path)
                    .add_endpoint(
                        "basic256sha256_sign_encrypt",
                        ServerEndpoint::new(
                            "/",
                            SecurityPolicy::Basic256Sha256,
                            MessageSecurityMode::SignAndEncrypt,
                            &[ANONYMOUS_USER_TOKEN_ID.to_string()],
                        ),
                    );
            }
        }
        let (server, handle) = builder
            .with_node_manager(simple_node_manager(
                NamespaceMetadata {
                    namespace_uri: NAMESPACE_URI.to_owned(),
                    ..Default::default()
                },
                "oip-simulation",
            ))
            .trust_client_certs(false)
            .check_cert_time(true)
            .create_sample_keypair(false)
            .diagnostics_enabled(false)
            .subscription_poll_interval_ms(20)
            .token(cancellation.clone())
            .build()
            .map_err(AdapterError::Connection)?;

        let node_manager = handle
            .node_managers()
            .get_of_type::<SimpleNodeManager>()
            .ok_or_else(|| AdapterError::Protocol("simulation node manager missing".to_owned()))?;
        let namespace = handle
            .get_namespace_index(NAMESPACE_URI)
            .ok_or_else(|| AdapterError::Protocol("simulation namespace missing".to_owned()))?;
        let nodes = create_address_space(
            node_manager.clone(),
            namespace,
            &config.simulation,
            config.scenario,
        )?;
        let simulation = Simulation::new(config.simulation.clone(), config.scenario);
        publish_frame(
            node_manager.clone(),
            handle.subscriptions().clone(),
            &nodes,
            simulation.frame_at(0),
        )?;

        let server_task = tokio::spawn(async move {
            if let Err(error) = server.run().await {
                tracing::error!(%error, "local OPC UA simulation server failed");
            }
        });
        wait_for_listener(config.port).await?;

        let update_task = spawn_updates(
            node_manager,
            handle.subscriptions().clone(),
            nodes,
            simulation,
            cancellation.clone(),
        );

        Ok(Self {
            endpoint,
            port: config.port,
            handle,
            cancellation,
            server_task,
            update_task,
        })
    }

    pub fn endpoint(&self) -> &str {
        &self.endpoint
    }

    pub fn port(&self) -> u16 {
        self.port
    }

    pub async fn stop(self) -> Result<(), AdapterError> {
        self.cancellation.cancel();
        self.handle.cancel();
        self.update_task
            .await
            .map_err(|error| AdapterError::Task(error.to_string()))?;
        self.server_task
            .await
            .map_err(|error| AdapterError::Task(error.to_string()))?;
        Ok(())
    }
}

fn create_address_space(
    manager: Arc<InMemoryNodeManager<SimpleNodeManagerImpl>>,
    namespace: u16,
    config: &SimulationConfig,
    scenario: Scenario,
) -> Result<NodeMap, AdapterError> {
    let mut metrics = HashMap::new();
    let mut bulk = Vec::with_capacity(config.bulk_node_count);
    let mut address_space = manager.address_space().write();
    let root = NodeId::new(namespace, "OIP");
    let machine = NodeId::new(namespace, "M-01");
    let bulk_folder = NodeId::new(namespace, "Bulk");
    let metadata_folder = NodeId::new(namespace, "Simulation");
    for (node_id, browse_name, display_name, parent) in [
        (&root, "OIP", "OIP", &NodeId::objects_folder_id()),
        (&machine, "M-01", "Machine M-01", &root),
        (&bulk_folder, "Bulk", "Scalable test nodes", &root),
        (&metadata_folder, "Simulation", "Simulation origin", &root),
    ] {
        if !address_space.add_folder(node_id, browse_name, display_name, parent) {
            return Err(AdapterError::Protocol(format!(
                "failed to create folder {browse_name}"
            )));
        }
    }

    let initial_values: Vec<(&str, Variable)> = vec![
        (
            "temperature",
            Variable::new(
                &NodeId::new(namespace, "temperature"),
                "temperature",
                "Temperature",
                0.0,
            ),
        ),
        (
            "pressure",
            Variable::new(
                &NodeId::new(namespace, "pressure"),
                "pressure",
                "Pressure",
                0.0,
            ),
        ),
        (
            "motor_running",
            Variable::new(
                &NodeId::new(namespace, "motor_running"),
                "motor_running",
                "Motor running",
                false,
            ),
        ),
        (
            "operating_mode",
            Variable::new(
                &NodeId::new(namespace, "operating_mode"),
                "operating_mode",
                "Operating mode",
                UAString::from(""),
            ),
        ),
        (
            "alarm_active",
            Variable::new(
                &NodeId::new(namespace, "alarm_active"),
                "alarm_active",
                "Alarm active",
                false,
            ),
        ),
        (
            "units_produced",
            Variable::new(
                &NodeId::new(namespace, "units_produced"),
                "units_produced",
                "Produced units",
                0_u64,
            ),
        ),
        (
            "temperature.unit",
            Variable::new(
                &NodeId::new(namespace, "temperature.unit"),
                "temperature.unit",
                "Temperature unit",
                UAString::from("°C"),
            ),
        ),
        (
            "pressure.unit",
            Variable::new(
                &NodeId::new(namespace, "pressure.unit"),
                "pressure.unit",
                "Pressure unit",
                UAString::from("kPa"),
            ),
        ),
    ];
    for (name, variable) in initial_values {
        let node_id = NodeId::new(namespace, name);
        metrics.insert(name.to_owned(), node_id);
        if !address_space.add_variables(vec![variable], &machine)[0] {
            return Err(AdapterError::Protocol(format!(
                "failed to create variable {name}"
            )));
        }
    }

    for index in 0..config.bulk_node_count {
        let name = format!("bulk.{index:04}");
        let node_id = NodeId::new(namespace, name.clone());
        if !address_space.add_variables(
            vec![Variable::new(&node_id, name.clone(), name, 0.0)],
            &bulk_folder,
        )[0]
        {
            return Err(AdapterError::Protocol(
                "failed to create bulk node".to_owned(),
            ));
        }
        bulk.push(node_id);
    }

    let metadata = vec![
        Variable::new(
            &NodeId::new(namespace, "simulation.origin_id"),
            "simulation.origin_id",
            "Simulation origin ID",
            UAString::from(oip_simulator::SIMULATION_ORIGIN_ID),
        ),
        Variable::new(
            &NodeId::new(namespace, "simulation.seed"),
            "simulation.seed",
            "Simulation seed",
            config.seed,
        ),
        Variable::new(
            &NodeId::new(namespace, "simulation.scenario"),
            "simulation.scenario",
            "Simulation scenario",
            UAString::from(scenario.as_str()),
        ),
        Variable::new(
            &NodeId::new(namespace, "simulation.epoch_unix_ms"),
            "simulation.epoch_unix_ms",
            "Simulation epoch in Unix milliseconds",
            oip_simulator::SIMULATION_EPOCH_UNIX_MS,
        ),
        Variable::new(
            &NodeId::new(namespace, "simulation.tick_duration_ms"),
            "simulation.tick_duration_ms",
            "Simulation tick duration in milliseconds",
            config.tick_duration_ms,
        ),
    ];
    let metadata_inserted = address_space.add_variables(metadata, &metadata_folder);
    if metadata_inserted.iter().any(|inserted| !inserted) {
        return Err(AdapterError::Protocol(
            "failed to create simulation metadata nodes".to_owned(),
        ));
    }

    Ok(NodeMap { metrics, bulk })
}

fn spawn_updates(
    manager: Arc<InMemoryNodeManager<SimpleNodeManagerImpl>>,
    subscriptions: Arc<SubscriptionCache>,
    nodes: NodeMap,
    mut simulation: Simulation,
    cancellation: CancellationToken,
) -> JoinHandle<()> {
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_millis(
            simulation.config().tick_duration_ms.max(10),
        ));
        interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        loop {
            tokio::select! {
                _ = cancellation.cancelled() => break,
                _ = interval.tick() => {
                    let frame = simulation.next_frame();
                    if let Err(error) = publish_frame(manager.clone(), subscriptions.clone(), &nodes, frame) {
                        tracing::error!(%error, "failed to publish simulated frame");
                        break;
                    }
                }
            }
        }
    })
}

fn publish_frame(
    manager: Arc<InMemoryNodeManager<SimpleNodeManagerImpl>>,
    subscriptions: Arc<SubscriptionCache>,
    nodes: &NodeMap,
    frame: oip_simulator::SimulationFrame,
) -> Result<(), AdapterError> {
    let mut updates = Vec::with_capacity(frame.observations.len() + frame.bulk_nodes.len());
    for observation in &frame.observations {
        if let Some(node_id) = nodes.metrics.get(observation.metric_id.as_str()) {
            updates.push((node_id, None, observation_to_data_value(observation)?));
        }
    }
    let source = timestamp_to_datetime(frame.observations[0].timestamps.source)?;
    for bulk_node in &frame.bulk_nodes {
        if let Some(node_id) = nodes.bulk.get(bulk_node.index) {
            updates.push((
                node_id,
                None,
                DataValue {
                    value: Some(bulk_node.value.into()),
                    status: Some(opcua::types::StatusCode::Good),
                    source_timestamp: Some(source),
                    source_picoseconds: Some(0),
                    server_timestamp: Some(DateTime::now()),
                    server_picoseconds: Some(0),
                },
            ));
        }
    }
    manager
        .set_values(&subscriptions, updates.into_iter())
        .map_err(|error| AdapterError::Protocol(error.to_string()))
}

async fn wait_for_listener(port: u16) -> Result<(), AdapterError> {
    tokio::time::timeout(Duration::from_secs(5), async {
        loop {
            if tokio::net::TcpStream::connect(("127.0.0.1", port))
                .await
                .is_ok()
            {
                return;
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await
    .map_err(|_| AdapterError::Connection(format!("server on port {port} did not start")))
}
