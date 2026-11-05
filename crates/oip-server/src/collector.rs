use crate::{
    config::SourceConfig,
    runtime::{source_worker, OpcUaAdapter},
    state::AppState,
};
use oip_opcua::async_opcua::{AsyncOpcUaServerConfig, RunningAsyncOpcUaServer};
use oip_simulator::Scenario;
use std::{sync::Arc, time::Duration};
use tokio::sync::watch;
pub const METRICS: &[&str] = &[
    "temperature",
    "pressure",
    "motor_running",
    "operating_mode",
    "alarm_active",
    "units_produced",
];
pub async fn collect(state: AppState, endpoint: String) {
    let mut config = SourceConfig::primary(4840);
    config.endpoint = endpoint;
    let id = state.primary.clone();
    let adapter = Arc::new(OpcUaAdapter {
        config,
        state: state.clone(),
    });
    let _ = state.started().await;
    let _ = source_worker(
        state,
        id,
        adapter,
        tokio_util::sync::CancellationToken::new(),
    )
    .await;
}
pub async fn simulation_supervisor(port: u16, rx: watch::Receiver<String>) {
    supervised_simulator(port, rx, tokio_util::sync::CancellationToken::new()).await;
}

pub async fn supervised_simulator(
    port: u16,
    mut rx: watch::Receiver<String>,
    cancel: tokio_util::sync::CancellationToken,
) {
    let mut running: Option<RunningAsyncOpcUaServer> = None;
    loop {
        let scenario = rx.borrow_and_update().clone();
        if let Some(server) = running.take() {
            if server.stop().await.is_err() {
                tracing::error!(
                    code = "simulator_stop_failed",
                    "local simulation stop failed"
                );
            }
        }
        if cancel.is_cancelled() {
            break;
        }
        if scenario == "offline" {
            tokio::select! {_=cancel.cancelled()=>break,_=tokio::time::sleep(Duration::from_secs(6))=>{}}
        }
        match RunningAsyncOpcUaServer::start(AsyncOpcUaServerConfig {
            port,
            scenario: if scenario == "sensor" {
                Scenario::CriticalSensor
            } else {
                Scenario::Normal
            },
            ..Default::default()
        })
        .await
        {
            Ok(s) => running = Some(s),
            Err(_) => tracing::error!(
                code = "simulator_start_failed",
                "local simulator could not start"
            ),
        }
        tokio::select! {_=cancel.cancelled()=>{},r=rx.changed()=>{if r.is_err(){break;}}}
        if cancel.is_cancelled() {
            break;
        }
    }
    if let Some(server) = running {
        let _ = server.stop().await;
    }
}
