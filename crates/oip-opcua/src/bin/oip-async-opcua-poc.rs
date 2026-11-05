use oip_core::MetricId;
use oip_opcua::async_opcua::{AsyncOpcUaClient, AsyncOpcUaServerConfig, RunningAsyncOpcUaServer};
use oip_opcua::{ClientEvent, ClientOptions, ReadOnlyOpcUaAdapter};
use oip_simulator::{Scenario, SimulationConfig};
use std::error::Error;
use std::time::{Duration, Instant};

#[tokio::main(flavor = "multi_thread", worker_threads = 2)]
async fn main() -> Result<(), Box<dyn Error>> {
    let port = std::net::TcpListener::bind(("127.0.0.1", 0))?
        .local_addr()?
        .port();
    let simulation = SimulationConfig {
        tick_duration_ms: 50,
        ..SimulationConfig::default()
    };
    let bulk_node_count = simulation.bulk_node_count;
    let config = || AsyncOpcUaServerConfig {
        port,
        scenario: Scenario::Normal,
        simulation: simulation.clone(),
        ..AsyncOpcUaServerConfig::default()
    };
    let connect_started = Instant::now();
    let server = RunningAsyncOpcUaServer::start(config()).await?;
    let client =
        AsyncOpcUaClient::connect(&ClientOptions::local_simulation(server.endpoint(), 2)).await?;
    let connect_discovery_us = connect_started.elapsed().as_micros();
    let endpoint_count = client.endpoints().await?.len();

    let browse_started = Instant::now();
    let browsed_references = client.browse().await?.len();
    let browse_us = browse_started.elapsed().as_micros();

    let metric = MetricId::new("temperature")?;
    let read_started = Instant::now();
    let observation = client.read(&metric).await?;
    let read_us = read_started.elapsed().as_micros();
    if observation.value.is_none() {
        return Err("temperature value missing".into());
    }

    let subscription_started = Instant::now();
    client.subscribe(std::slice::from_ref(&metric)).await?;
    wait_for_observation(&client).await?;
    let first_subscription_us = subscription_started.elapsed().as_micros();

    let reconnect_started = Instant::now();
    server.stop().await?;
    let lost = loop {
        if let ClientEvent::ConnectionLost { at, .. } = next_event(&client).await? {
            break at;
        }
    };
    let restarted = RunningAsyncOpcUaServer::start(AsyncOpcUaServerConfig {
        scenario: Scenario::Reconnect,
        ..config()
    })
    .await?;
    let gap = loop {
        match next_event(&client).await? {
            ClientEvent::Reconnected { gap, .. } => break gap,
            ClientEvent::SubscriptionError { reason, .. } => return Err(reason.into()),
            _ => {}
        }
    };
    wait_for_observation(&client).await?;
    let reconnect_us = reconnect_started.elapsed().as_micros();

    let dropped = client.dropped_observations();
    client.disconnect().await?;
    restarted.stop().await?;
    let report = serde_json::json!({
        "stack": "async-opcua 0.19.0",
        "endpoint_count": endpoint_count,
        "browsed_references": browsed_references,
        "bulk_node_count": bulk_node_count,
        "subscription_events": 2,
        "disconnect_detected": true,
        "client_recreated": false,
        "reconnect_and_resubscribe": true,
        "dropped_observations": dropped,
        "gap_ms": gap.ended_at.as_unix_millis() - gap.started_at.as_unix_millis(),
        "connect_discovery_us": connect_discovery_us,
        "browse_us": browse_us,
        "read_us": read_us,
        "first_subscription_us": first_subscription_us,
        "reconnect_us": reconnect_us,
        "connection_lost_at_unix_ms": lost.as_unix_millis()
    });
    println!("{}", serde_json::to_string_pretty(&report)?);
    Ok(())
}

async fn next_event(client: &AsyncOpcUaClient) -> Result<ClientEvent, Box<dyn Error>> {
    Ok(client.next_event(Duration::from_secs(10)).await?)
}

async fn wait_for_observation(client: &AsyncOpcUaClient) -> Result<(), Box<dyn Error>> {
    loop {
        if let ClientEvent::Observation(_) = next_event(client).await? {
            return Ok(());
        }
    }
}
