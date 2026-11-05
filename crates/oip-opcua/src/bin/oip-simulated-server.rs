use oip_opcua::async_opcua::{AsyncOpcUaServerConfig, RunningAsyncOpcUaServer};
use std::error::Error;

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .try_init()
        .ok();
    let mut config = AsyncOpcUaServerConfig::default();
    let mut args = std::env::args().skip(1);
    while let Some(argument) = args.next() {
        let value = args.next().ok_or("missing argument value")?;
        match argument.as_str() {
            "--port" => config.port = value.parse()?,
            "--seed" => config.simulation.seed = value.parse()?,
            "--scenario" => config.scenario = value.parse()?,
            "--bulk-nodes" => config.simulation.bulk_node_count = value.parse()?,
            "--tick-ms" => config.simulation.tick_duration_ms = value.parse()?,
            _ => return Err(format!("unknown argument: {argument}").into()),
        }
    }
    if config.port == 0 {
        return Err("port 0 is only supported by automated tests".into());
    }
    let server = RunningAsyncOpcUaServer::start(config).await?;
    println!(
        "OIP local-only simulation listening on {} (read-only, SecurityPolicy=None)",
        server.endpoint()
    );
    tokio::signal::ctrl_c().await?;
    server.stop().await?;
    Ok(())
}
