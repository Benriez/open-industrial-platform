use oip_core::MetricId;
use oip_opcua::async_opcua::AsyncOpcUaClient;
use oip_opcua::{ClientEvent, ClientOptions, ReadOnlyOpcUaAdapter};
use std::error::Error;
use std::time::Duration;

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    let mut endpoint = "opc.tcp://127.0.0.1:4840".to_owned();
    let mut namespace = 2_u16;
    let mut samples = 5_usize;
    let mut args = std::env::args().skip(1);
    while let Some(argument) = args.next() {
        let value = args.next().ok_or("missing argument value")?;
        match argument.as_str() {
            "--url" => endpoint = value,
            "--namespace" => namespace = value.parse()?,
            "--samples" => samples = value.parse()?,
            _ => return Err(format!("unknown argument: {argument}").into()),
        }
    }

    let client =
        AsyncOpcUaClient::connect(&ClientOptions::local_simulation(endpoint, namespace)).await?;
    println!("{}", serde_json::to_string(&client.endpoints().await?)?);
    let browse = client.browse().await?;
    println!("{{\"browsed_references\":{}}}", browse.len());
    let metrics = [
        "temperature",
        "pressure",
        "motor_running",
        "operating_mode",
        "alarm_active",
        "units_produced",
    ]
    .into_iter()
    .map(MetricId::new)
    .collect::<Result<Vec<_>, _>>()?;
    for metric in &metrics {
        println!("{}", serde_json::to_string(&client.read(metric).await?)?);
    }
    client.subscribe(&metrics).await?;

    let mut received = 0_usize;
    while samples == 0 || received < samples {
        tokio::select! {
            _ = tokio::signal::ctrl_c() => break,
            event = client.next_event(Duration::from_secs(30)) => {
                let event = event?;
                if matches!(event, ClientEvent::Observation(_)) {
                    received += 1;
                }
                println!("{}", serde_json::to_string(&event)?);
            }
        }
    }
    let dropped = client.dropped_observations();
    client.disconnect().await?;
    if dropped > 0 {
        println!("{{\"dropped_observations\":{dropped}}}");
    }
    Ok(())
}
