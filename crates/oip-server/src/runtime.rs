//! Supervised executor and protocol integration; no UI or web-server dependency.
use crate::{
    config::{CoreConfig, SourceConfig},
    state::{now_ms, AppState, ShutdownReport},
};
use futures::{future::BoxFuture, FutureExt};
use oip_core::*;
use oip_opcua::{async_opcua::AsyncOpcUaClient, ClientOptions, ReadOnlyOpcUaAdapter};
use oip_storage::SqliteStore;
use std::{collections::VecDeque, panic::AssertUnwindSafe, sync::Arc, time::Duration};
use thiserror::Error;
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;
#[derive(Debug, Error)]
pub enum RuntimeError {
    #[error("configuration: {0}")]
    Configuration(String),
    #[error("storage initialization failed")]
    Storage(#[from] oip_storage::StorageError),
    #[error("adapter operation failed")]
    Adapter(#[from] oip_opcua::AdapterError),
    #[error("core ingestion: {0}")]
    Ingestion(String),
    #[error("adapter task panicked")]
    AdapterPanic,
}
/// A new protocol implements these runtime contracts and emits domain events.
pub trait CollectionSession: Send {
    fn buffered(&self) -> BoxFuture<'_, usize>;
    fn next(&mut self) -> BoxFuture<'_, Result<ClientEvent, RuntimeError>>;
    fn close(&mut self) -> BoxFuture<'_, Result<(), RuntimeError>>;
}
pub trait CollectionAdapter: Send + Sync {
    fn connect(&self) -> BoxFuture<'_, Result<Box<dyn CollectionSession>, RuntimeError>>;
}
pub struct OpcUaAdapter {
    pub config: SourceConfig,
    pub state: AppState,
}
struct OpcUaSession {
    client: Arc<AsyncOpcUaClient>,
    initial: VecDeque<ClientEvent>,
    state: AppState,
    id: DataSourceId,
}
impl CollectionAdapter for OpcUaAdapter {
    fn connect(&self) -> BoxFuture<'_, Result<Box<dyn CollectionSession>, RuntimeError>> {
        Box::pin(async move {
            let client = Arc::new(
                AsyncOpcUaClient::connect(&ClientOptions::local_simulation_of(
                    &self.config.endpoint,
                    self.config.namespace,
                    // The measurements of the source belong to the entity that
                    // the source declares — not to the machine id of the
                    // simulation behind it.
                    oip_core::EntityId::new(
                        self.config.entity_id.as_deref().unwrap_or("M-01"),
                    )
                    .map_err(|_| RuntimeError::Configuration("entity".into()))?,
                ))
                .await?,
            );
            let catalog = client.browse().await?;
            let id = DataSourceId::new(&self.config.id)
                .map_err(|_| RuntimeError::Configuration("id".into()))?;
            let metrics = crate::collector::METRICS
                .iter()
                .map(|m| MetricId::new(*m).expect("static metric"))
                .collect::<Vec<_>>();
            let mut initial = VecDeque::new();
            for m in &metrics {
                initial.push_back(ClientEvent::Observation(Box::new(client.read(m).await?)));
            }
            client.subscribe(&metrics).await?;
            self.state
                .catalogs
                .write()
                .await
                .insert(id.clone(), catalog.clone());
            if Some(id.clone()) == self.state.primary {
                self.state
                    .data
                    .lock()
                    .map_err(|_| RuntimeError::Ingestion("catalog lock".into()))?
                    .catalog = catalog;
                *self.state.client.write().await = Some(client.clone());
            }
            self.state
                .clients
                .write()
                .await
                .insert(id.clone(), client.clone());
            Ok(Box::new(OpcUaSession {
                client,
                initial,
                state: self.state.clone(),
                id,
            }) as Box<dyn CollectionSession>)
        })
    }
}
impl CollectionSession for OpcUaSession {
    fn buffered(&self) -> BoxFuture<'_, usize> {
        Box::pin(async move { self.initial.len() + self.client.queued_events().await })
    }

    fn next(&mut self) -> BoxFuture<'_, Result<ClientEvent, RuntimeError>> {
        Box::pin(async move {
            if let Some(e) = self.initial.pop_front() {
                return Ok(e);
            }
            Ok(self.client.next_event(Duration::from_secs(3)).await?)
        })
    }
    fn close(&mut self) -> BoxFuture<'_, Result<(), RuntimeError>> {
        Box::pin(async move {
            self.state.clients.write().await.remove(&self.id);
            if Some(self.id.clone()) == self.state.primary {
                *self.state.client.write().await = None;
            }
            let remote_close = self.client.shutdown().await;
            if !self.client.local_event_task_stopped() {
                return Err(oip_opcua::AdapterError::Task(
                    "local OPC-UA producer did not stop".into(),
                )
                .into());
            }
            if remote_close.is_err() {
                // An offline server cannot acknowledge CloseSession. Local stop
                // and subsequent queue/writer drain are still verifiable. Keep
                // this distinct from an unjoined producer or ingestion failure.
                tracing::warn!(source_id=%self.id,code="opcua_remote_close_unconfirmed",local_producer_stopped=true,"remote CloseSession unconfirmed; local producer stopped, buffered observations still drain");
                return Ok(());
            }
            remote_close?;
            Ok(())
        })
    }
}
pub fn normalize(id: &DataSourceId, event: ClientEvent) -> ClientEvent {
    match event {
        ClientEvent::Observation(mut o) => {
            o.data_source_id = id.clone();
            ClientEvent::Observation(o)
        }
        other => other,
    }
}
async fn session_run(
    state: &AppState,
    id: &DataSourceId,
    adapter: &dyn CollectionAdapter,
    cancel: &CancellationToken,
) -> Result<(), RuntimeError> {
    let mut session =
        tokio::select! {_ = cancel.cancelled()=>return Ok(()),result=adapter.connect()=>result?};
    state.connected(id).await.map_err(RuntimeError::Ingestion)?;
    tracing::info!(source_id=%id,run_id=state.view().health.run_id,code="source_connected","collection session established");
    let result = AssertUnwindSafe(async {
        loop {
            let event =
                tokio::select! {_ = cancel.cancelled()=>break,result=session.next()=>result?};
            state
                .ingest_for(id, normalize(id, event))
                .await
                .map_err(RuntimeError::Ingestion)?;
        }
        Ok(())
    })
    .catch_unwind()
    .await
    .unwrap_or(Err(RuntimeError::AdapterPanic));
    // Stop the producer, then drain its bounded queue. No new ingestion after the
    // runtime closes admission. The outer supervisor bounds this entire shutdown.
    let closed = session.close().await;
    let buffered = session.buffered().await;
    for _ in 0..=buffered {
        match tokio::time::timeout(Duration::from_millis(30), session.next()).await {
            Ok(Ok(event)) => {
                state
                    .ingest_for(id, normalize(id, event))
                    .await
                    .map_err(RuntimeError::Ingestion)?;
            }
            _ => break,
        }
    }
    result.and(closed)
}
pub async fn source_worker(
    state: AppState,
    id: DataSourceId,
    adapter: Arc<dyn CollectionAdapter>,
    cancel: CancellationToken,
) -> Result<(), RuntimeError> {
    loop {
        if cancel.is_cancelled() {
            break;
        }
        state.connecting(&id).await;
        let result = AssertUnwindSafe(session_run(&state, &id, adapter.as_ref(), &cancel))
            .catch_unwind()
            .await
            .unwrap_or(Err(RuntimeError::AdapterPanic));
        if cancel.is_cancelled() {
            return result;
        }
        let code = match result {
            Err(RuntimeError::AdapterPanic) => "adapter_panic",
            Err(RuntimeError::Ingestion(_)) => "ingestion_error",
            _ => "adapter_disconnected",
        };
        // The reason of the isolation belongs in the log: without it, a
        // source that is isolated every second is indistinguishable from a
        // source that is merely unreachable.
        let detail = match &result {
            Err(RuntimeError::Ingestion(message)) => message.clone(),
            Err(RuntimeError::AdapterPanic) => "the adapter panicked".to_owned(),
            _ => "the adapter disconnected".to_owned(),
        };
        tracing::warn!(source_id=%id,code,run_id=state.view().health.run_id,detail=%detail,"source isolated; retry pending");
        let _ = state
            .ingest_for(
                &id,
                ClientEvent::ConnectionLost {
                    at: Timestamp::from_unix_millis(now_ms()),
                    reason: code.into(),
                },
            )
            .await;
        tokio::select! {_ = cancel.cancelled()=>break,_=tokio::time::sleep(Duration::from_secs(1))=>{}}
    }
    Ok(())
}
#[must_use = "call shutdown() to drain and join the core"]
pub struct CoreRuntime {
    pub state: AppState,
    // Exclusive advisory ownership on the canonical database sidecar, before SQLite opens.
    database_ownership: Option<oip_storage::DatabaseOwnership>,
    cancel: CancellationToken,
    workers: Vec<JoinHandle<Result<(), RuntimeError>>>,
    ticker: JoinHandle<()>,
    timeout: Duration,
}
impl CoreRuntime {
    pub async fn start(
        config: CoreConfig,
        scenario: Option<tokio::sync::watch::Sender<String>>,
    ) -> Result<Self, RuntimeError> {
        config.validate().map_err(RuntimeError::Configuration)?;
        let ownership = oip_storage::DatabaseOwnership::acquire(&config.database)?;
        let mut store = SqliteStore::open(&config.database)?;
        if store.hierarchy()?.is_none() && !config.sources.is_empty() {
            if !config.legacy_single_infrastructure {
                return Err(RuntimeError::Configuration("offline hierarchy provisioning required; legacy mode must be explicitly selected".into()));
            }
            let definitions = config
                .sources
                .iter()
                .map(|s| s.definition())
                .collect::<Result<Vec<_>, _>>()
                .map_err(RuntimeError::Configuration)?;
            store.provision(
                crate::provisioning::legacy_plan(&config).map_err(RuntimeError::Configuration)?,
                &definitions,
                None,
            )?;
        }
        let state =
            AppState::configured(store, &config, scenario).map_err(RuntimeError::Ingestion)?;
        let mut runtime = Self::from_state(state, config).await?;
        runtime.database_ownership = Some(ownership);
        Ok(runtime)
    }
    pub async fn from_state(state: AppState, config: CoreConfig) -> Result<Self, RuntimeError> {
        let cancel = CancellationToken::new();
        let mut workers = Vec::new();
        for source in config.sources {
            let id = DataSourceId::new(&source.id)
                .map_err(|_| RuntimeError::Configuration("source id".into()))?;
            let adapter = Arc::new(OpcUaAdapter {
                config: source,
                state: state.clone(),
            });
            workers.push(tokio::spawn(source_worker(
                state.clone(),
                id,
                adapter,
                cancel.clone(),
            )));
        }
        workers.push(tokio::spawn(crate::connection_service::supervise(
            state.clone(),
            cancel.clone(),
        )));
        if let Err(error) = state.started().await {
            cancel.cancel();
            for task in workers {
                task.abort();
                let _ = task.await;
            }
            return Err(RuntimeError::Ingestion(error));
        }
        let c = cancel.clone();
        let s = state.clone();
        let ticker = tokio::spawn(async move {
            loop {
                tokio::select! {_=c.cancelled()=>break,_=tokio::time::sleep(Duration::from_millis(250))=>s.tick(now_ms()).await}
            }
        });
        Ok(Self {
            state,
            database_ownership: None,
            cancel,
            workers,
            ticker,
            timeout: Duration::from_millis(config.shutdown_timeout_ms),
        })
    }
    pub async fn shutdown(mut self) -> ShutdownReport {
        self.state.begin_stop();
        self.state.shutdown_deadline(self.timeout);
        self.cancel.cancel();
        let start = tokio::time::Instant::now();
        let mut adapter_failures = 0;
        for task in &mut self.workers {
            match tokio::time::timeout(self.timeout.saturating_sub(start.elapsed()), &mut *task)
                .await
            {
                Ok(Ok(Ok(()))) => {}
                Ok(_) => adapter_failures += 1,
                Err(_) => {
                    task.abort();
                    let _ = task.await;
                    adapter_failures += 1;
                }
            }
        }
        if tokio::time::timeout(
            self.timeout.max(Duration::from_secs(2)),
            self.state.ssh.shutdown(),
        )
        .await
        .is_err()
        {
            adapter_failures += 1;
        }
        self.ticker.abort();
        let _ = (&mut self.ticker).await;
        let pending = self.state.queue().depth;
        match tokio::time::timeout(
            self.timeout.max(Duration::from_millis(500)),
            self.state.shutdown(),
        )
        .await
        {
            Ok(mut report) => {
                report.adapter_failures = adapter_failures;
                report.clean &= adapter_failures == 0;
                if !report.clean {
                    self.state.mark_failed();
                }
                report
            }
            Err(_) => {
                self.state.mark_failed();
                ShutdownReport {
                    clean: false,
                    uncommitted: pending + 1,
                    adapter_failures,
                    persistence_thread_joined: false,
                }
            }
        }
    }
}

impl Drop for CoreRuntime {
    fn drop(&mut self) {
        if self.workers.iter().any(|t| !t.is_finished()) || !self.ticker.is_finished() {
            tracing::error!(
                code = "runtime_dropped_without_shutdown",
                "runtime ownership abandoned; no clean shutdown claimed"
            );
            self.state.abandon();
            for task in &self.workers {
                task.abort();
            }
            self.ticker.abort();
        }
        self.cancel.cancel();
        self.state.stopping.cancel();
    }
}
