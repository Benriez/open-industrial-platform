use crate::{
    config::{CoreConfig, SourceConfig},
    contracts::*,
    demo,
};
use oip_core::*;
use oip_opcua::{async_opcua::AsyncOpcUaClient, BrowseEntry};
use oip_storage::SqliteStore;
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    sync::{
        atomic::{AtomicBool, AtomicI64, AtomicU64, Ordering},
        Arc, Mutex,
    },
    thread::JoinHandle,
    time::Duration,
};
use tokio::sync::{mpsc, oneshot, watch, RwLock};
#[path = "writer.rs"]
mod writer;

pub fn now_ms() -> i64 {
    Timestamp::now()
        .expect("valid system wall clock required")
        .as_unix_millis()
}
pub use oip_core::QueueHealth;
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ShutdownReport {
    pub clean: bool,
    pub uncommitted: usize,
    pub adapter_failures: usize,
    pub persistence_thread_joined: bool,
}
struct EventCommand {
    source: DataSourceId,
    event: ClientEvent,
    reply: oneshot::Sender<Result<IngestOutcome, String>>,
}
enum Command {
    Event(EventCommand),
    Abandon,
    Connecting(DataSourceId),
    Connected(DataSourceId, oneshot::Sender<Result<(), String>>),
    Tick(i64, oneshot::Sender<()>),
    Started,
    Shutdown(oneshot::Sender<ShutdownReport>),
}
pub struct UiData {
    pub scenario: String,
    pub catalog: Vec<BrowseEntry>,
}
struct Inner {
    tx: mpsc::Sender<Command>,
    view: watch::Receiver<CoreView>,
    closing: AtomicBool,
    failed: AtomicBool,
    stop_requested: AtomicBool,
    shutdown_timeout_ms: u64,
    deadline: AtomicI64,
    waits: AtomicU64,
    rejected: AtomicU64,
    thread: Mutex<Option<JoinHandle<()>>>,
    capacity: usize,
}
#[derive(Clone)]
pub struct AppState {
    pub settings: Arc<Vec<SettingRecord>>,
    pub settings_loaded_ms: i64,
    pub management: Arc<Mutex<crate::settings_services::ManagementRuntime>>,
    pub history: Arc<crate::diagnostic_services::DiagnosticReads>,
    pub hierarchy: Option<Arc<HierarchyRegistry>>,
    pub legacy_access: bool,
    inner: Arc<Inner>,
    pub updates: watch::Sender<u64>,
    pub data: Arc<Mutex<UiData>>,
    pub client: Arc<RwLock<Option<Arc<AsyncOpcUaClient>>>>,
    pub clients: Arc<RwLock<BTreeMap<DataSourceId, Arc<AsyncOpcUaClient>>>>,
    pub catalogs: Arc<RwLock<BTreeMap<DataSourceId, Vec<BrowseEntry>>>>,
    pub scenario_tx: Option<watch::Sender<String>>,
    pub primary: Option<DataSourceId>,
    pub inventory: Arc<Vec<InventoryRecord>>,
    pub stopping: tokio_util::sync::CancellationToken,
}
impl AppState {
    pub fn new(
        store: SqliteStore,
        scenario_tx: Option<watch::Sender<String>>,
    ) -> Result<Self, String> {
        Self::configured(store, &CoreConfig::default(), scenario_tx)
    }
    /// Explicit compatibility host for local single-infrastructure development.
    pub fn legacy(
        store: SqliteStore,
        scenario_tx: Option<watch::Sender<String>>,
    ) -> Result<Self, String> {
        Self::configured(
            store,
            &CoreConfig {
                sources: vec![SourceConfig::primary(4840)],
                legacy_single_infrastructure: true,
                ..Default::default()
            },
            scenario_tx,
        )
    }
    pub fn configured(
        store: SqliteStore,
        config: &CoreConfig,
        scenario_tx: Option<watch::Sender<String>>,
    ) -> Result<Self, String> {
        config.validate()?;
        let hierarchy = store
            .hierarchy()
            .map_err(|_| "hierarchy unavailable")?
            .map(Arc::new);
        if let Some(h) = &hierarchy {
            let ids: std::collections::BTreeSet<_> =
                config.sources.iter().map(|s| s.id.as_str()).collect();
            if ids
                != h.plan
                    .sources
                    .iter()
                    .map(|s| s.source_id.as_str())
                    .collect()
            {
                return Err("runtime sources must exactly match provisioned registry".into());
            }
            if scenario_tx.is_some() && !h.plan.legacy_single_infrastructure {
                return Err("demo is only available in explicit single-infrastructure mode".into());
            }
        }
        let legacy_access = config.legacy_single_infrastructure
            && hierarchy
                .as_ref()
                .is_none_or(|h| h.plan.legacy_single_infrastructure);
        let definitions = config
            .sources
            .iter()
            .map(SourceConfig::definition)
            .collect::<Result<Vec<_>, _>>()?;
        let inventory = Arc::new(store.inventory_records().map_err(|_| "invalid inventory")?);
        if let Some(h) = &hierarchy {
            for row in inventory.iter() {
                oip_core::device_site_scope(h, &row.device.site_id)
                    .map_err(|_| "invalid inventory placement")?;
            }
            for source in &h.plan.sources {
                if !inventory
                    .iter()
                    .any(|r| r.device.id == source.device_id && r.device.site_id == source.site_id)
                {
                    return Err("source/inventory placement mismatch".into());
                }
            }
        } else if !inventory.is_empty() {
            return Err("unassigned inventory without hierarchy".into());
        }
        let settings = Arc::new(
            store
                .settings_records()
                .map_err(|_| "invalid stored settings")?,
        );
        let settings_loaded_ms = now_ms();
        let management = Arc::new(Mutex::new(
            crate::settings_services::ManagementRuntime::new(
                store.schema_version().map_err(|_| "schema")?,
            ),
        ));
        let history = Arc::new(crate::diagnostic_services::DiagnosticReads::new(
            store.history_reader().map_err(|_| "history_reader")?,
        ));
        let app = Application::initialize(store, definitions, now_ms(), config.stale_after_ms)
            .map_err(|e| e.to_string())?;
        let initial = app.view(now_ms());
        let (view_tx, view) = watch::channel(initial);
        let (updates, _) = watch::channel(0u64);
        let (tx, rx) = mpsc::channel(config.queue_capacity);
        let inner = Arc::new(Inner {
            tx,
            view,
            closing: AtomicBool::new(false),
            failed: AtomicBool::new(false),
            stop_requested: AtomicBool::new(false),
            shutdown_timeout_ms: config.shutdown_timeout_ms,
            deadline: AtomicI64::new(i64::MAX),
            waits: AtomicU64::new(0),
            rejected: AtomicU64::new(0),
            thread: Mutex::new(None),
            capacity: config.queue_capacity,
        });
        let weak = Arc::downgrade(&inner);
        let notifications = updates.clone();
        let worker = writer::spawn(app, rx, view_tx, notifications, weak)
            .map_err(|_| "writer_thread_start")?;
        *inner.thread.lock().map_err(|_| "thread lock")? = Some(worker);
        Ok(Self {
            settings,
            settings_loaded_ms,
            management,
            history,
            inventory,
            hierarchy,
            legacy_access,
            inner,
            updates,
            data: Arc::new(Mutex::new(UiData {
                scenario: if scenario_tx.is_some() {
                    "normal"
                } else {
                    "not_applicable"
                }
                .into(),
                catalog: Vec::new(),
            })),
            client: Arc::new(RwLock::new(None)),
            clients: Arc::new(RwLock::new(BTreeMap::new())),
            catalogs: Arc::new(RwLock::new(BTreeMap::new())),
            scenario_tx,
            stopping: tokio_util::sync::CancellationToken::new(),
            primary: config
                .sources
                .first()
                .map(|s| DataSourceId::new(&s.id).map_err(|_| "id"))
                .transpose()?,
        })
    }
    pub fn view(&self) -> CoreView {
        let mut v = self.inner.view.borrow().clone();
        if self.inner.stop_requested.load(Ordering::SeqCst)
            && !matches!(v.health.lifecycle, Lifecycle::Stopped | Lifecycle::Failed)
        {
            v.health.lifecycle = Lifecycle::Stopping;
            v.health.ready = false;
        }
        let writer_ended = self
            .inner
            .thread
            .lock()
            .ok()
            .is_some_and(|h| h.as_ref().is_some_and(|h| h.is_finished()));
        if writer_ended && !matches!(v.health.lifecycle, Lifecycle::Stopped | Lifecycle::Failed) {
            self.inner.failed.store(true, Ordering::SeqCst);
        }
        if self.inner.failed.load(Ordering::SeqCst) {
            v.health.lifecycle = Lifecycle::Failed;
            v.health.ready = false;
            v.health.live = false;
            for s in &mut v.sources {
                s.freshness = Freshness::Stale;
                s.reachability = Reachability::Unknown;
            }
            for o in &mut v.observations {
                o.freshness = Freshness::Stale;
            }
        }
        v
    }
    pub fn begin_stop(&self) {
        self.inner.stop_requested.store(true, Ordering::SeqCst);
        self.stopping.cancel();
        self.notify();
    }
    pub fn abandon(&self) {
        self.begin_stop();
        self.shutdown_deadline(Duration::from_millis(self.inner.shutdown_timeout_ms));
        self.inner.closing.store(true, Ordering::SeqCst);
        self.mark_failed();
        let _ = self.inner.tx.try_send(Command::Abandon);
    }
    pub fn mark_failed(&self) {
        self.inner.failed.store(true, Ordering::SeqCst);
        self.notify();
    }
    pub fn queue(&self) -> QueueHealth {
        QueueHealth {
            capacity: self.inner.capacity,
            depth: self.inner.capacity - self.inner.tx.capacity(),
            backpressure_waits: self.inner.waits.load(Ordering::Relaxed),
            rejected_submissions: self.inner.rejected.load(Ordering::Relaxed),
        }
    }
    pub fn notify(&self) {
        self.updates.send_modify(|n| *n = n.wrapping_add(1));
    }
    pub async fn started(&self) -> Result<(), String> {
        self.inner
            .tx
            .send(Command::Started)
            .await
            .map_err(|_| "core_stopped".into())
    }
    pub async fn connecting(&self, id: &DataSourceId) {
        let _ = self.inner.tx.send(Command::Connecting(id.clone())).await;
    }
    pub async fn connected(&self, id: &DataSourceId) -> Result<(), String> {
        let (tx, rx) = oneshot::channel();
        self.inner
            .tx
            .send(Command::Connected(id.clone(), tx))
            .await
            .map_err(|_| "core_stopped")?;
        rx.await.map_err(|_| "core_stopped")?
    }
    pub async fn tick(&self, now: i64) {
        let (tx, rx) = oneshot::channel();
        let _ = self.inner.tx.send(Command::Tick(now, tx)).await;
        let _ = rx.await;
    }
    pub async fn ingest(&self, event: ClientEvent) -> Result<IngestOutcome, String> {
        let id = match &event {
            ClientEvent::Observation(o) => o.data_source_id.clone(),
            _ => self.primary.clone().ok_or("No primary source configured")?,
        };
        self.ingest_for(&id, event).await
    }
    pub async fn ingest_for(
        &self,
        id: &DataSourceId,
        event: ClientEvent,
    ) -> Result<IngestOutcome, String> {
        if self.inner.closing.load(Ordering::SeqCst) {
            return Err("core_stopping".into());
        }
        if self.inner.tx.capacity() == 0 {
            self.inner.waits.fetch_add(1, Ordering::Relaxed);
        }
        let (tx, rx) = oneshot::channel();
        self.inner
            .tx
            .send(Command::Event(EventCommand {
                source: id.clone(),
                event,
                reply: tx,
            }))
            .await
            .map_err(|_| "core_stopped")?;
        rx.await.map_err(|_| "core_stopped")?
    }
    pub fn try_ingest(
        &self,
        id: &DataSourceId,
        event: ClientEvent,
    ) -> Result<oneshot::Receiver<Result<IngestOutcome, String>>, String> {
        if self.inner.closing.load(Ordering::SeqCst) {
            return Err("core_stopping".into());
        }
        let (tx, rx) = oneshot::channel();
        self.inner
            .tx
            .try_send(Command::Event(EventCommand {
                source: id.clone(),
                event,
                reply: tx,
            }))
            .map_err(|_| {
                self.inner.rejected.fetch_add(1, Ordering::Relaxed);
                "queue_full_or_closed"
            })?;
        Ok(rx)
    }
    pub fn shutdown_deadline(&self, timeout: Duration) {
        self.inner
            .deadline
            .store(now_ms() + timeout.as_millis() as i64, Ordering::SeqCst);
    }
    pub async fn shutdown(&self) -> ShutdownReport {
        self.begin_stop();
        if self.inner.deadline.load(Ordering::SeqCst) == i64::MAX {
            self.shutdown_deadline(Duration::from_millis(self.inner.shutdown_timeout_ms));
        }
        self.inner.closing.store(true, Ordering::SeqCst);
        let (tx, rx) = oneshot::channel();
        let _ = self.inner.tx.send(Command::Shutdown(tx)).await;
        let mut report = rx.await.unwrap_or(ShutdownReport {
            clean: false,
            uncommitted: 1,
            adapter_failures: 0,
            persistence_thread_joined: false,
        });
        let handle = self.inner.thread.lock().ok().and_then(|mut h| h.take());
        if let Some(handle) = handle {
            report.persistence_thread_joined =
                tokio::task::spawn_blocking(move || handle.join().is_ok())
                    .await
                    .unwrap_or(false);
        }
        report.clean &= report.persistence_thread_joined;
        report
    }
    pub fn snapshot(&self) -> Result<Snapshot, String> {
        let v = self.view();
        let primary = v
            .sources
            .iter()
            .find(|s| Some(&s.id) == self.primary.as_ref());
        let status = if let Some(primary) = primary {
            if primary.connection == ConnectionHealth::Connected {
                if primary.freshness == Freshness::Fresh {
                    "connected"
                } else {
                    "stale"
                }
            } else if primary.connection == ConnectionHealth::Unknown
                && primary.reconnect_attempts == 0
            {
                "connecting"
            } else {
                "reconnecting"
            }
        } else {
            "unavailable"
        };
        let scenario = self
            .data
            .lock()
            .map_err(|_| "ui metadata lock")?
            .scenario
            .clone();
        let metrics = v
            .observations
            .iter()
            .filter(|o| !o.metric_id.as_str().starts_with("bulk."))
            .cloned()
            .collect();
        let mut devices = if self.scenario_tx.is_some() {
            demo::devices(&scenario, status)
        } else {
            v.sources
                .iter()
                .map(|s| Device {
                    data_source_id: Some(s.id.clone()),
                    is_faulted: false,
                    id: if let Some(p) = self.hierarchy.as_ref().and_then(|h| h.placement(&s.id)) {
                        p.device_id.to_string()
                    } else if Some(&s.id) == self.primary.as_ref() {
                        s.entity_id.to_string()
                    } else {
                        format!("{}:{}", s.id, s.entity_id)
                    },
                    name: s.name.clone(),
                    kind: "Industrial".into(),
                    location: "Local simulation".into(),
                    connection: "OPC UA".into(),
                    simulated: s.simulated,
                    health: Health {
                        reachability: match s.reachability {
                            Reachability::Reachable => "reachable",
                            Reachability::Unreachable => "unreachable",
                            _ => "unknown",
                        }
                        .into(),
                        vpn_transport: "not_applicable".into(),
                        agent_availability: "unknown".into(),
                        service_health: match s.service {
                            ServiceHealth::Healthy => "connected",
                            ServiceHealth::Degraded => "degraded",
                            _ => "unknown",
                        }
                        .into(),
                        telemetry_freshness: match s.freshness {
                            Freshness::Fresh => "fresh",
                            Freshness::Stale => "stale",
                            _ => "unknown",
                        }
                        .into(),
                    },
                })
                .collect()
        };
        if self.scenario_tx.is_none() {
            devices.retain(|d| {
                self.inventory
                    .iter()
                    .find(|r| r.device.id.as_str() == d.id)
                    .is_none_or(|r| r.registration == RegistrationStatus::Registered)
            });
            for record in self
                .inventory
                .iter()
                .filter(|r| r.registration == RegistrationStatus::Registered)
            {
                if let Some(d) = devices
                    .iter_mut()
                    .find(|d| d.id == record.device.id.as_str())
                {
                    d.name = record.device.display_name.clone();
                    d.kind = format!("{:?}", record.device.device_type);
                    d.location = record
                        .device
                        .metadata
                        .physical_location
                        .clone()
                        .unwrap_or_else(|| record.device.site_id.to_string());
                } else {
                    devices.push(Device {
                        data_source_id: None,
                        is_faulted: false,
                        id: record.device.id.to_string(),
                        name: record.device.display_name.clone(),
                        kind: format!("{:?}", record.device.device_type),
                        location: record
                            .device
                            .metadata
                            .physical_location
                            .clone()
                            .unwrap_or_else(|| record.device.site_id.to_string()),
                        connection: "No collector".into(),
                        simulated: record.origin == InventoryOrigin::ExistingSimulationSource,
                        health: Health {
                            reachability: "unknown".into(),
                            vpn_transport: "unknown".into(),
                            agent_availability: "unknown".into(),
                            service_health: "not_evaluated".into(),
                            telemetry_freshness: "no_collector".into(),
                        },
                    });
                }
            }
        }
        for device in &mut devices {
            if self.legacy_access && device.id == "M-01" {
                device.data_source_id = self.primary.clone();
            }
            if v.observations.iter().any(|o| {
                device.data_source_id.as_ref() == Some(&o.data_source_id)
                    && o.metric_id.as_str() == "alarm_active"
                    && o.is_usable()
                    && o.value == Some(MetricValue::Boolean(true))
            }) {
                device.health.service_health = "alarm".into();
            }
            device.is_faulted = device.health.is_faulted();
        }
        Ok(Snapshot {
            system: SystemStatus {
                primary_source_id: self.primary.clone(),
                api_version: "v1".into(),
                simulated: v.sources.iter().any(|s| s.simulated),
                demo_controls: self.scenario_tx.is_some(),
                scenario: scenario.clone(),
                opcua_status: status.into(),
                subscription_status: if status == "connected" {
                    "active"
                } else {
                    "waiting"
                }
                .into(),
                last_received_ms: primary.and_then(|p| p.last_received_ms),
                generated_at_ms: now_ms(),
                persisted_observations: v.health.persisted_observations,
                cpu_percent: None,
                gpu_percent: None,
                ram_percent: None,
                network_status: "unknown".into(),
                security_blocker: "RUSTSEC-2023-0071".into(),
            },
            devices,
            metrics,
            incidents: if self.scenario_tx.is_some() {
                demo::incidents(&scenario)
            } else {
                Vec::new()
            },
            topology: if self.scenario_tx.is_some() {
                demo::topology(&scenario)
            } else {
                Vec::new()
            },
            core: v.health,
            sources: v.sources,
            queue: self.queue(),
            resync_required: true,
        })
    }
}
