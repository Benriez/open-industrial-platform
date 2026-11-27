//! Supervised executor and protocol integration; no UI or web-server dependency.
use crate::{
    config::{CoreConfig, OpcUaBrowseSource, OpcUaReadProfile, SourceConfig},
    state::{now_ms, AppState, ShutdownReport},
};
use futures::{future::BoxFuture, FutureExt};
use oip_core::*;
use oip_opcua::{
    async_opcua::AsyncOpcUaClient, AdapterError, BrowseEntry, ClientOptions,
    ProductionSecurityConfig, ReadOnlyOpcUaAdapter, SecurityProfile,
};
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
struct SelectedOpcUaSession {
    client: AsyncOpcUaClient,
    points: Vec<(String, MetricId)>,
    kinds: Vec<ValueKind>,
    pending: VecDeque<ClientEvent>,
    period: Duration,
    next_poll: tokio::time::Instant,
    closed: bool,
}

impl OpcUaAdapter {
    async fn connect_selected(
        &self,
        profile: &OpcUaReadProfile,
    ) -> Result<Box<dyn CollectionSession>, RuntimeError> {
        let definition = self
            .config
            .definition()
            .map_err(RuntimeError::Configuration)?;
        let mut options =
            ClientOptions::local_host_service(&self.config.endpoint, 0, definition.entity_id);
        options.security_profile = SecurityProfile::Production {
            security_policy: "Basic256Sha256".into(),
            security_mode: "SignAndEncrypt".into(),
        };
        options.production_security = Some(ProductionSecurityConfig::new(
            &profile.pki_dir,
            &profile.certificate_path,
            &profile.private_key_path,
        ));
        options.expected_server_uri = Some(profile.server_application_uri.clone());
        if definition.id == crate::opcua_setup::source_id()
            && self.state.opcua_setup.configured.borrow().is_some()
        {
            options.client_application_uri = Some(
                crate::opcua_setup::client_application_uri(&profile.pki_dir).map_err(|_| {
                    AdapterError::InvalidSecurityConfiguration("managed OPC-UA client identity unavailable".into())
                })?
            );
            options.expected_server_certificate = Some(
                crate::opcua_setup::server_certificate(&profile.pki_dir).map_err(|_| {
                    AdapterError::InvalidSecurityConfiguration("managed OPC-UA server certificate unavailable".into())
                })?
            );
        }
        // The value can legitimately stay unchanged for hours. The Core uses
        // local receipt cadence and connection status to evaluate freshness.
        options.freshness.max_source_age = None;
        let client = AsyncOpcUaClient::connect(&options).await?;
        let identifiers: Vec<_> = profile.points.iter().map(|p| p.node_id.clone()).collect();
        let node_ids = match client
            .resolve_selected_nodes(&profile.namespace_uri, &identifiers)
            .await
        {
            Ok(ids) => ids,
            Err(error) => {
                let _ = client.shutdown().await;
                return Err(error.into());
            }
        };
        let points: Vec<_> = node_ids
            .into_iter()
            .zip(profile.points.iter().map(|p| p.metric.clone()))
            .collect();
        let catalog = points
            .iter()
            .map(|(node_id, metric)| BrowseEntry {
                node_id: node_id.clone(),
                browse_name: metric.as_str().to_owned(),
                display_name: metric.as_str().to_owned(),
                node_class: "Variable".into(),
                access: "Read".into(),
                folder: "Ausgewählte Datenpunkte".into(),
            })
            .collect();
        self.state
            .catalogs
            .write()
            .await
            .insert(definition.id, catalog);
        // Keep the transport private to the collector. Browser/API/MCP use the
        // source's collected view, so their requests cannot increase plant load.
        Ok(Box::new(SelectedOpcUaSession {
            client,
            points,
            kinds: profile.points.iter().map(|p| p.value_kind).collect(),
            pending: VecDeque::new(),
            period: Duration::from_millis(profile.poll_ms),
            next_poll: tokio::time::Instant::now(),
            closed: false,
        }))
    }
}

impl CollectionAdapter for OpcUaAdapter {
    fn connect(&self) -> BoxFuture<'_, Result<Box<dyn CollectionSession>, RuntimeError>> {
        Box::pin(async move {
            if let Some(profile) = &self.config.opcua {
                return self.connect_selected(profile).await;
            }
            let mut options = ClientOptions::local_simulation_of(
                &self.config.endpoint,
                self.config.namespace,
                // The measurements of the source belong to the entity that
                // the source declares — not to the machine id of the
                // simulation behind it.
                oip_core::EntityId::new(self.config.entity_id.as_deref().unwrap_or("M-01"))
                    .map_err(|_| RuntimeError::Configuration("entity".into()))?,
            );
            options.read_only = self.state.opcua_read_only;
            let client = Arc::new(AsyncOpcUaClient::connect(&options).await?);
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

impl CollectionSession for SelectedOpcUaSession {
    fn buffered(&self) -> BoxFuture<'_, usize> {
        Box::pin(async move { self.pending.len() })
    }

    fn next(&mut self) -> BoxFuture<'_, Result<ClientEvent, RuntimeError>> {
        Box::pin(async move {
            if let Some(event) = self.pending.pop_front() {
                return Ok(event);
            }
            if self.closed {
                return Err(AdapterError::Task("selected polling session is closed".into()).into());
            }
            tokio::time::sleep_until(self.next_poll).await;
            let observations = self.client.read_selected(&self.points).await?;
            self.next_poll = tokio::time::Instant::now() + self.period;
            let mut point_error = None;
            for (observation, kind) in observations.into_iter().zip(&self.kinds) {
                match observation {
                    Ok(mut observation) => {
                        if observation
                            .value
                            .as_ref()
                            .is_some_and(|value| !kind.matches(value))
                        {
                            observation.value = None;
                            observation.quality = DataQuality::Bad;
                            observation.collection_error =
                                Some(CollectionError::InvalidMeasurement);
                            observation.freshness = Freshness::Unknown;
                        }
                        self.pending
                            .push_back(ClientEvent::Observation(Box::new(observation)));
                    }
                    Err(AdapterError::MissingSourceTimestamp) => {
                        point_error = Some("opcua_missing_source_timestamp")
                    }
                    Err(_) => point_error = Some("opcua_unsupported_measurement"),
                }
            }
            if let Some(reason) = point_error {
                self.pending.push_back(ClientEvent::SubscriptionError {
                    at: Timestamp::from_unix_millis(now_ms()),
                    reason: reason.into(),
                });
            }
            self.pending.pop_front().ok_or_else(|| {
                AdapterError::Protocol("no selected observations returned".into()).into()
            })
        })
    }

    fn close(&mut self) -> BoxFuture<'_, Result<(), RuntimeError>> {
        Box::pin(async move {
            self.closed = true;
            let closed = self.client.shutdown().await;
            if !self.client.local_event_task_stopped() {
                return Err(
                    AdapterError::Task("local OPC-UA event loop still active".into()).into(),
                );
            }
            if closed.is_err() {
                tracing::warn!(
                    code = "opcua_remote_close_unconfirmed",
                    "remote CloseSession unconfirmed; local event loop stopped"
                );
            }
            Ok(())
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
    let selected = state.is_selected_opcua(&id);
    let mut consecutive_failures = 0u32;
    loop {
        if cancel.is_cancelled() {
            break;
        }
        state.connecting(&id).await;
        let started = tokio::time::Instant::now();
        let result = AssertUnwindSafe(session_run(&state, &id, adapter.as_ref(), &cancel))
            .catch_unwind()
            .await
            .unwrap_or(Err(RuntimeError::AdapterPanic));
        if cancel.is_cancelled() {
            return result;
        }
        let code = match &result {
            Err(RuntimeError::AdapterPanic) => "adapter_panic",
            Err(RuntimeError::Ingestion(_)) => "ingestion_error",
            Err(RuntimeError::Adapter(error)) if selected => selected_opcua_error_code(error),
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
        let delay = if selected {
            if started.elapsed() >= Duration::from_secs(125) {
                consecutive_failures = 0;
            }
            let base = (3000u64 << consecutive_failures.min(4)).min(48_000);
            consecutive_failures = consecutive_failures.saturating_add(1);
            let jitter = now_ms().unsigned_abs() % (base / 4);
            Duration::from_millis(base + jitter)
        } else {
            Duration::from_secs(1)
        };
        tokio::select! {_ = cancel.cancelled()=>break,_=tokio::time::sleep(delay)=>{}}
    }
    Ok(())
}

async fn managed_opcua_worker(state: AppState, cancel: CancellationToken) -> Result<(), RuntimeError> {
    let setup = state.opcua_setup.clone();
    let mut updates = setup.configured.subscribe();
    loop {
        let saved = updates.borrow_and_update().clone();
        if let Some(source) = saved {
            let child = cancel.child_token();
            let adapter = Arc::new(OpcUaAdapter { config: source.config(&setup.root), state: state.clone() });
            let worker = source_worker(state.clone(), crate::opcua_setup::source_id(), adapter, child.clone());
            tokio::pin!(worker);
            tokio::select! {
                result = &mut worker => return result,
                changed = updates.changed() => {
                    child.cancel();
                    let stopped = worker.await;
                    if changed.is_err() || cancel.is_cancelled() {
                        return stopped;
                    }
                    if stopped.is_err() {
                        tracing::warn!(code="opcua_rotation_shutdown", "previous OPC-UA session stopped with an error");
                    }
                }
            }
        } else {
            tokio::select! {
                _ = cancel.cancelled() => return Ok(()),
                result = updates.changed() => {
                    if result.is_err() {
                        return Ok(());
                    }
                }
            }
        }
    }
}

fn selected_opcua_error_code(error: &AdapterError) -> &'static str {
    match error {
        AdapterError::InvalidSecurityConfiguration(reason) if reason.contains("server certificate changed") => "opcua_certificate_changed",
        AdapterError::InvalidSecurityConfiguration(_) => "opcua_security_configuration_invalid",
        AdapterError::Connection(reason) | AdapterError::Protocol(reason) => {
            if reason.contains("BadCertificateUntrusted") {
                "opcua_certificate_untrusted"
            } else if reason.contains("BadCertificateTimeInvalid")
                || reason.contains("BadCertificateIssuerTimeInvalid")
            {
                "opcua_certificate_time_invalid"
            } else if reason.contains("BadCertificateHostNameInvalid")
                || reason.contains("BadCertificateUriInvalid")
            {
                "opcua_certificate_identity_mismatch"
            } else if reason.contains("BadSecurityChecksFailed")
                || reason.contains("BadCertificate")
            {
                "opcua_certificate_validation_failed"
            } else if reason.contains("timed out") {
                "opcua_request_timeout"
            } else if reason.contains("BadIdentityToken") || reason.contains("BadUserAccessDenied")
            {
                "opcua_login_rejected"
            } else if reason.contains("namespace") || reason.contains("NamespaceArray") {
                "opcua_namespace_unavailable"
            } else {
                "opcua_disconnected"
            }
        }
        _ => "opcua_disconnected",
    }
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
        mut config: CoreConfig,
        scenario: Option<tokio::sync::watch::Sender<String>>,
    ) -> Result<Self, RuntimeError> {
        config.validate().map_err(RuntimeError::Configuration)?;
        if config.browser_credentials_file.is_none() {
            let mut sidecar = config.database.as_os_str().to_os_string();
            sidecar.push(".browser-credentials.json");
            config.browser_credentials_file = Some(sidecar.into());
        }
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
        // SSH source schemas evolve with the fixed, read-only host collector.
        // Add the newer metric declarations to verified connection sources so
        // the normal collector can persist those measurements after restart.
        for connection in store.connection_records()? {
            let definition = crate::ssh::definition(&connection);
            store.merge_connection_source_definition(&definition)?;
        }
        // A verified read-only collector is placed on the device it reads: the
        // identity of a Hue bridge is pinned to its own certificate, exactly
        // like the host key of an SSH host.
        if let Some(hue) = &config.hue {
            let hierarchy = store
                .hierarchy()?
                .ok_or_else(|| RuntimeError::Configuration("HUE_DEVICE_UNREGISTERED".into()))?;
            hue.validate(Some(&hierarchy))
                .map_err(|error| RuntimeError::Configuration(error.code))?;
            let inventory = store.inventory_records()?;
            for profile in &hue.profiles {
                let device = inventory
                    .iter()
                    .find(|row| row.device.id == profile.device_id)
                    .ok_or_else(|| RuntimeError::Configuration("HUE_DEVICE_UNREGISTERED".into()))?;
                if !profile.principals.iter().all(|p| {
                    hierarchy.permits(
                        p,
                        CapabilityId::DeviceRead,
                        &AccessScope::Site(device.device.site_id.clone()),
                        false,
                    )
                }) {
                    return Err(RuntimeError::Configuration(
                        "HUE_PROFILE_UNAVAILABLE".into(),
                    ));
                }
            }
            for profile in &hue.profiles {
                store
                    .register_device_source(
                        &profile.device_id,
                        &crate::hue::definition(profile),
                    )
                    .map_err(|error| {
                        RuntimeError::Configuration(format!(
                            "the Hue profile {} is not a valid placement of a registered device: {error}",
                            profile.id
                        ))
                    })?;
            }
        }
        let audit = crate::security_audit::DurableAudit::open(&config.database)
            .map_err(|error| RuntimeError::Configuration(format!("security audit: {error}")))?;
        let state =
            AppState::configured_with_audit(store, &config, scenario, Some(Arc::new(audit)))
                .map_err(RuntimeError::Ingestion)?;
        let mut runtime = Self::from_state(state, config).await?;
        runtime.database_ownership = Some(ownership);
        Ok(runtime)
    }
    pub async fn from_state(state: AppState, config: CoreConfig) -> Result<Self, RuntimeError> {
        let hue_tls = if config.hue.is_some() {
            Some(
                state
                    .hue_tls
                    .get_or_try_init(crate::hue::openssl)
                    .await
                    .cloned()
                    .map_err(|error| RuntimeError::Configuration(error.code))?,
            )
        } else {
            None
        };
        let cancel = CancellationToken::new();
        let mut workers = Vec::new();
        if state.opcua_setup.enabled && state.hierarchy().is_some() {
            workers.push(tokio::spawn(managed_opcua_worker(state.clone(), cancel.clone())));
        }
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
        for source in config.opcua_browse_sources {
            workers.push(tokio::spawn(opcua_browser_source_worker(
                state.clone(),
                source,
                cancel.clone(),
            )));
        }
        workers.push(tokio::spawn(crate::connection_service::supervise(
            state.clone(),
            cancel.clone(),
        )));
        if let (Some(hue), Some(binary)) = (&config.hue, hue_tls) {
            workers.push(tokio::spawn(crate::hue::supervise(
                binary,
                state.clone(),
                hue.profiles.clone(),
                cancel.clone(),
            )));
        }
        if config.tailscale_peer_status {
            workers.push(tokio::spawn(crate::network_services::supervise(
                state.clone(),
                cancel.clone(),
            )));
        }
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

async fn opcua_browser_source_worker(
    state: AppState,
    source: OpcUaBrowseSource,
    cancel: CancellationToken,
) -> Result<(), RuntimeError> {
    let id = DataSourceId::new(&source.id)
        .map_err(|_| RuntimeError::Configuration("OPC-UA browser source id".into()))?;
    let entity = oip_core::EntityId::new(&source.entity_id)
        .map_err(|_| RuntimeError::Configuration("OPC-UA browser entity id".into()))?;
    loop {
        if cancel.is_cancelled() {
            break;
        }
        let registered = state
            .view()
            .sources
            .iter()
            .any(|candidate| candidate.id == id && candidate.entity_id == entity);
        if !registered {
            tracing::error!(source_id=%id,code="opcua_browser_source_unregistered","OPC-UA browser binding must reference a registered source");
            tokio::select! { _ = cancel.cancelled() => break, _ = tokio::time::sleep(Duration::from_secs(30)) => continue }
        }
        let mut options =
            ClientOptions::local_host_service(&source.endpoint, source.namespace, entity.clone());
        options.read_only = state.opcua_read_only;
        let client = match AsyncOpcUaClient::connect(&options).await {
            Ok(client) => Arc::new(client),
            Err(error) => {
                tracing::warn!(source_id=%id,code="opcua_browser_connect_failed",%error,"OPC-UA browser source unavailable");
                tokio::select! { _ = cancel.cancelled() => break, _ = tokio::time::sleep(Duration::from_secs(5)) => continue }
            }
        };
        let mut catalog = match client.browse().await {
            Ok(catalog) => catalog,
            Err(error) => {
                tracing::warn!(source_id=%id,code="opcua_browser_browse_failed",%error,"OPC-UA browse failed");
                let _ = client.shutdown().await;
                tokio::select! { _ = cancel.cancelled() => break, _ = tokio::time::sleep(Duration::from_secs(5)) => continue }
            }
        };
        state
            .clients
            .write()
            .await
            .insert(id.clone(), client.clone());
        state
            .catalogs
            .write()
            .await
            .insert(id.clone(), catalog.clone());
        tracing::info!(source_id=%id,node_count=catalog.len(),code="opcua_browser_connected","registered OPC-UA address space loaded");
        loop {
            tokio::select! {
                _ = cancel.cancelled() => break,
                _ = tokio::time::sleep(Duration::from_secs(10)) => match client.browse().await {
                    Ok(next) => { catalog = next; state.catalogs.write().await.insert(id.clone(), catalog.clone()); }
                    Err(error) => { tracing::warn!(source_id=%id,code="opcua_browser_connection_lost",%error,"OPC-UA browser connection lost"); break; }
                }
            }
        }
        state.clients.write().await.remove(&id);
        state.catalogs.write().await.remove(&id);
        let _ = client.shutdown().await;
        if cancel.is_cancelled() {
            break;
        }
        tokio::select! { _ = cancel.cancelled() => break, _ = tokio::time::sleep(Duration::from_secs(5)) => {} }
    }
    Ok(())
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
