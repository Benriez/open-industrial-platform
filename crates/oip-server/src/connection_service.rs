//! Central connection lifecycle. Transports cannot supply evidence, grants or private key paths.
use crate::{
    application_services::ApplicationServices,
    ssh,
    state::{now_ms, AppState},
};
use oip_core::*;
use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};
use tokio::sync::Semaphore;
use tokio_util::sync::CancellationToken;
struct Plan {
    principal: PrincipalId,
    device: DeviceRegistration,
    expected: Option<u64>,
    status: ConnectionPlanStatus,
    key: Option<ssh::PublicHostKey>,
    expires: Instant,
    cancel: CancellationToken,
}
pub struct ConnectionHub {
    settings: ssh::SshSettings,
    work: Option<PathBuf>,
    plans: Mutex<BTreeMap<String, Plan>>,
    admission: Arc<Semaphore>,
    tasks: tokio_util::task::TaskTracker,
}
fn bad(code: &str, msg: &str) -> CapabilityError {
    connection_error(code, msg)
}
/// A verified host report is only storable while its serialised record stays
/// inside the bound of the connection table. The check happens before any write,
/// so an extreme report fails with an explicit fault instead of a rollback.
fn connection_payload_fits(c: &DeviceConnectionRecord) -> bool {
    serde_json::to_string(c)
        .map(|payload| payload.len() <= CONNECTION_PAYLOAD_MAX_BYTES)
        .unwrap_or(false)
}
fn uuid() -> Result<String, CapabilityError> {
    let x = crate::browser_session::random_token().map_err(|_| denied())?;
    let b = u8::from_str_radix(&x[16..18], 16).map_err(|_| denied())?;
    Ok(format!(
        "{}-{}-4{}-{:02x}{}-{}",
        &x[..8],
        &x[8..12],
        &x[13..16],
        (b & 0x3f) | 0x80,
        &x[18..20],
        &x[20..32]
    ))
}
impl ConnectionHub {
    pub fn new(
        settings: ssh::SshSettings,
        h: Option<&HierarchyRegistry>,
        parent: &Path,
    ) -> Result<Self, String> {
        settings.validate(h).map_err(|e| e.message)?;
        let work = if settings.profiles.is_empty() {
            None
        } else {
            let p = parent.join("ssh-work");
            ssh::private_workdir(&p).map_err(|e| e.message)?;
            Some(p)
        };
        Ok(Self {
            settings,
            work,
            plans: Mutex::new(BTreeMap::new()),
            admission: Arc::new(Semaphore::new(4)),
            tasks: tokio_util::task::TaskTracker::new(),
        })
    }
    fn prune(plans: &mut BTreeMap<String, Plan>) {
        plans.retain(|_, p| {
            if p.expires > Instant::now() {
                true
            } else {
                p.cancel.cancel();
                false
            }
        });
    }
    fn permit(
        state: &AppState,
        p: &PrincipalId,
        device: &DeviceRegistration,
        id: CapabilityId,
    ) -> Result<(), CapabilityError> {
        let h = state.hierarchy().ok_or_else(denied)?;
        if h.permits(p, id, &AccessScope::Site(device.site_id.clone()), false)
            || h.source_for_device(device.id.as_str())
                .is_some_and(|s| h.permits(p, id, &AccessScope::Source(s.clone()), false))
        {
            Ok(())
        } else {
            Err(inaccessible())
        }
    }
    fn check_plan(
        &self,
        state: &AppState,
        p: &PrincipalId,
        id: &str,
    ) -> Result<(), CapabilityError> {
        if id.len() != 64 {
            return Err(inaccessible());
        }
        let mut plans = self.plans.lock().map_err(|_| denied())?;
        Self::prune(&mut plans);
        let plan = plans
            .get(id)
            .filter(|v| &v.principal == p)
            .ok_or_else(inaccessible)?;
        Self::permit(
            state,
            p,
            &plan.device,
            CapabilityId::DeviceConnectionConfigure,
        )?;
        if let Some(rev) = plan.expected {
            if state
                .inventory()
                .iter()
                .find(|r| r.device.id == plan.device.id)
                .is_none_or(|r| {
                    r.revision != rev || r.registration != RegistrationStatus::Registered
                })
                && plan.status.stage != ConnectionStage::Committed
            {
                return Err(bad(
                    "REVISION_CONFLICT",
                    "Inventory changed; reread before confirming a connection",
                ));
            }
        }
        Ok(())
    }
    fn update(
        &self,
        id: &str,
        stage: ConnectionStage,
        key: Option<ssh::PublicHostKey>,
        identity: Option<HostInformation>,
        error: Option<ConnectionFault>,
    ) {
        if let Ok(mut plans) = self.plans.lock() {
            if let Some(p) = plans.get_mut(id) {
                if p.cancel.is_cancelled() {
                    return;
                }
                p.status.stage = stage;
                if let Some(k) = key {
                    p.status.host_key_fingerprint = Some(k.fingerprint.clone());
                    p.key = Some(k);
                }
                if let Some(i) = identity {
                    p.status.identity = Some(i);
                }
                p.status.error = error;
            }
        }
    }
    fn status(&self, id: &str) -> Result<ConnectionPlanStatus, CapabilityError> {
        self.plans
            .lock()
            .map_err(|_| denied())?
            .get(id)
            .map(|v| v.status.clone())
            .ok_or_else(inaccessible)
    }
    async fn evidence(&self, state: &AppState, id: &str, success: bool) {
        let p = self
            .plans
            .lock()
            .ok()
            .and_then(|v| v.get(id).map(|p| (p.expected.is_some(), p.status.clone())));
        if let Some((true, p)) = p {
            let attempt = ConnectionAttempt {
                device_id: p.device_id,
                endpoint: p.endpoint,
                at_ms: now_ms(),
                stage: p.stage,
                error: p.error,
                neighbors: None,
            };
            if state.connection_attempt(attempt, success).await.is_err() {
                tracing::error!(
                    code = "ssh_attempt_persistence_failed",
                    "SSH attempt evidence could not be committed"
                );
            }
        }
    }
    pub async fn shutdown(&self) {
        self.tasks.close();
        self.tasks.wait().await;
    }
    pub fn read(
        &self,
        state: &AppState,
        p: &PrincipalId,
        q: ConnectionQuery,
    ) -> Result<ConnectionResult, CapabilityError> {
        if q.device_id.is_some() && q.plan_id.is_some() {
            return Err(inventory_invalid());
        }
        let h = state.hierarchy().ok_or_else(denied)?;
        if !h
            .plan
            .bindings
            .iter()
            .filter(|b| &b.principal_id == p)
            .any(|b| h.permits(p, CapabilityId::DeviceConnectionRead, &b.scope, false))
        {
            return Err(denied());
        }
        let can_manage = h
            .plan
            .bindings
            .iter()
            .filter(|b| &b.principal_id == p)
            .any(|b| h.permits(p, CapabilityId::DeviceConnectionConfigure, &b.scope, false));
        let mut result = ConnectionResult {
            profiles: if can_manage {
                self.settings.visible(p)
            } else {
                vec![]
            },
            plan: None,
            connection: None,
            last_attempt: None,
        };
        if let Some(id) = q.plan_id {
            self.check_plan(state, p, &id)?;
            result.plan = Some(self.status(&id)?);
            return Ok(result);
        }
        if let Some(id) = q.device_id {
            let rows = state.inventory();
            let row = rows
                .iter()
                .find(|r| r.device.id == id)
                .ok_or_else(inaccessible)?;
            Self::permit(state, p, &row.device, CapabilityId::DeviceConnectionRead)?;
            let registry = state.registry();
            result.last_attempt = registry
                .attempts
                .iter()
                .find(|a| a.device_id == id)
                .cloned();
            if let Some(c) = registry.connections.iter().find(|c| c.device_id == id) {
                let view = state.view();
                let source = view.sources.iter().find(|s| s.id == c.source_id);
                let status = if c
                    .last_error
                    .as_ref()
                    .is_some_and(|e| e.code == "SSH_HOST_KEY_CHANGED")
                {
                    "host_key_changed"
                } else if c
                    .last_error
                    .as_ref()
                    .is_some_and(|e| e.code == "SSH_HOST_KEY_UNKNOWN")
                {
                    "host_key_unknown"
                } else if c.last_error.as_ref().is_some_and(|e| {
                    matches!(e.code.as_str(), "SSH_ENDPOINT_UNREACHABLE" | "SSH_TIMEOUT")
                }) {
                    "unreachable"
                } else if c.last_error.is_some() {
                    "verification_failed"
                } else if c.enabled
                    && source.is_some_and(|s| {
                        s.freshness == Freshness::Fresh && s.last_received_ms.is_some()
                    })
                {
                    "collecting"
                } else if c.enabled && source.is_some_and(|s| s.freshness == Freshness::Stale) {
                    "stale"
                } else if c.enabled {
                    "collector_configured"
                } else {
                    "ssh_verified"
                };
                result.connection = Some(ConnectionView {
                    device_id: c.device_id.clone(),
                    source_id: c.source_id.clone(),
                    endpoint: c.endpoint.clone(),
                    fingerprint: c.fingerprint.clone(),
                    verified_identity: c.identity.clone(),
                    verified_at_ms: c.verified_at_ms,
                    monitoring_enabled: c.enabled,
                    poll_seconds: c.poll_seconds,
                    revision: c.revision,
                    last_attempt_ms: c.last_attempt_ms,
                    last_success_ms: c.last_success_ms,
                    error: c.last_error.clone(),
                    status: status.into(),
                    observations: view
                        .observations
                        .into_iter()
                        .filter(|o| o.data_source_id == c.source_id)
                        .collect(),
                });
            }
        }
        Ok(result)
    }
    pub async fn configure(
        self: &Arc<Self>,
        state: AppState,
        p: PrincipalId,
        action: ConnectionAction,
    ) -> Result<ConnectionResult, CapabilityError> {
        if state.stopping.is_cancelled() {
            return Err(bad("CORE_STOPPING", "Core is stopping"));
        }
        match action {
            ConnectionAction::Start { target, endpoint } => {
                let (device, expected) = match target {
                    ConnectionTarget::Existing {
                        id,
                        expected_revision,
                    } => {
                        let rows = state.inventory();
                        let row = rows
                            .iter()
                            .find(|r| {
                                r.device.id == id
                                    && r.registration == RegistrationStatus::Registered
                            })
                            .ok_or_else(inaccessible)?;
                        Self::permit(
                            &state,
                            &p,
                            &row.device,
                            CapabilityId::DeviceConnectionConfigure,
                        )?;
                        if row.revision != expected_revision {
                            return Err(bad(
                                "REVISION_CONFLICT",
                                "Reread current inventory revision",
                            ));
                        }
                        (row.device.clone(), Some(expected_revision))
                    }
                    ConnectionTarget::New { device } => (
                        (*device)
                            .registration(DeviceId::new(uuid()?).map_err(|_| inventory_invalid())?),
                        None,
                    ),
                };
                device.validate()?;
                Self::permit(&state, &p, &device, CapabilityId::DeviceConnectionConfigure)?;
                if state.connections().iter().any(|c| c.device_id == device.id) {
                    return Err(bad("DEVICE_ALREADY_CONNECTED","A binding already exists; use its monitoring controls, not a duplicate connection"));
                }
                let (profile, endpoint) = self
                    .settings
                    .resolve(&p, &endpoint)
                    .map_err(|e| bad(&e.code, &e.message))?;
                let work = self.work.clone().ok_or_else(|| {
                    bad(
                        "SSH_PROFILE_UNAVAILABLE",
                        "Local SSH identity profile is unavailable",
                    )
                })?;
                let permit =
                    self.admission.clone().try_acquire_owned().map_err(|_| {
                        bad("SSH_BUSY", "SSH request capacity reached; retry later")
                    })?;
                let id = crate::browser_session::random_token().map_err(|_| denied())?;
                let cancel = state.stopping.child_token();
                let status = ConnectionPlanStatus {
                    plan_id: id.clone(),
                    device_id: device.id.clone(),
                    site_id: device.site_id.clone(),
                    stage: ConnectionStage::Connecting,
                    endpoint: endpoint.clone(),
                    host_key_fingerprint: None,
                    host_key_trusted: false,
                    identity: None,
                    error: None,
                    expires_at_ms: now_ms() + 600000,
                    inventory_revision: expected.unwrap_or(0),
                };
                {
                    let mut plans = self.plans.lock().map_err(|_| denied())?;
                    Self::prune(&mut plans);
                    if plans.len() >= 64
                        || plans
                            .values()
                            .filter(|v| {
                                v.principal == p
                                    && !matches!(
                                        v.status.stage,
                                        ConnectionStage::Failed
                                            | ConnectionStage::Cancelled
                                            | ConnectionStage::Committed
                                    )
                            })
                            .count()
                            >= 4
                    {
                        return Err(bad("PLAN_CAPACITY", "Connection plan capacity reached"));
                    }
                    plans.insert(
                        id.clone(),
                        Plan {
                            principal: p.clone(),
                            device,
                            expected,
                            status,
                            cancel: cancel.clone(),
                            key: None,
                            expires: Instant::now() + Duration::from_secs(600),
                        },
                    );
                }
                let hub = self.clone();
                let sid = id.clone();
                let st = state.clone();
                self.tasks.spawn(async move {
                    let _permit = permit;
                    let outcome = async {
                        let keys = ssh::scan(&endpoint, &work, &cancel).await?;
                        ssh::trusted_key(&profile, &endpoint, &keys, None, &cancel).await
                    }
                    .await;
                    match outcome {
                        Ok((key, trusted)) => {
                            hub.update(
                                &sid,
                                if trusted {
                                    ConnectionStage::ReadyForAuthentication
                                } else {
                                    ConnectionStage::AwaitingHostKey
                                },
                                Some(key),
                                None,
                                None,
                            );
                            if let Ok(mut plans) = hub.plans.lock() {
                                if let Some(plan) = plans.get_mut(&sid) {
                                    plan.status.host_key_trusted = trusted;
                                }
                            }
                        }
                        Err(e) => hub.update(&sid, ConnectionStage::Failed, None, None, Some(e)),
                    };
                    hub.evidence(&st, &sid, false).await;
                });
                self.read(
                    &state,
                    &p,
                    ConnectionQuery {
                        plan_id: Some(id.clone()),
                        device_id: None,
                    },
                )
            }
            ConnectionAction::TrustHostKey {
                plan_id,
                fingerprint,
            } => {
                self.check_plan(&state, &p, &plan_id)?;
                {
                    let mut plans = self.plans.lock().map_err(|_| denied())?;
                    let plan = plans.get_mut(&plan_id).ok_or_else(inaccessible)?;
                    if plan.status.stage != ConnectionStage::AwaitingHostKey
                        || plan
                            .key
                            .as_ref()
                            .is_none_or(|k| k.fingerprint != fingerprint)
                    {
                        return Err(bad(
                            "HOST_KEY_CONFIRMATION_MISMATCH",
                            "Confirm the exact displayed fingerprint through a trusted channel",
                        ));
                    }
                    plan.status.host_key_trusted = true;
                    plan.status.stage = ConnectionStage::ReadyForAuthentication;
                }
                self.read(
                    &state,
                    &p,
                    ConnectionQuery {
                        plan_id: Some(plan_id),
                        device_id: None,
                    },
                )
            }
            ConnectionAction::Verify { plan_id } => {
                self.check_plan(&state, &p, &plan_id)?;
                let permit = self
                    .admission
                    .clone()
                    .try_acquire_owned()
                    .map_err(|_| bad("SSH_BUSY", "SSH request capacity reached"))?;
                let (endpoint, key, cancel) = {
                    let mut plans = self.plans.lock().map_err(|_| denied())?;
                    let plan = plans.get_mut(&plan_id).ok_or_else(inaccessible)?;
                    if !plan.status.host_key_trusted
                        || plan.status.stage != ConnectionStage::ReadyForAuthentication
                    {
                        return Err(bad(
                            "HOST_KEY_CONFIRMATION_REQUIRED",
                            "An accepted host key is required before authentication",
                        ));
                    }
                    plan.status.stage = ConnectionStage::Authenticating;
                    (
                        plan.status.endpoint.clone(),
                        plan.key.clone().ok_or_else(inaccessible)?,
                        plan.cancel.clone(),
                    )
                };
                let (profile, endpoint) = self
                    .settings
                    .resolve(&p, &endpoint)
                    .map_err(|e| bad(&e.code, &e.message))?;
                let work = self.work.clone().ok_or_else(denied)?;
                let hub = self.clone();
                let sid = plan_id.clone();
                let st = state.clone();
                self.tasks.spawn(async move {
                    let _permit = permit;
                    let result = async {
                        ssh::authenticate(&endpoint, &profile, &key.key, &work, &cancel).await?;
                        hub.update(
                            &sid,
                            ConnectionStage::ReadingDeviceInformation,
                            None,
                            None,
                            None,
                        );
                        ssh::collect(&endpoint, &profile, &key.key, &work, &cancel).await
                    }
                    .await;
                    match result {
                        Ok(info) => hub.update(
                            &sid,
                            ConnectionStage::VerificationComplete,
                            None,
                            Some(info),
                            None,
                        ),
                        Err(e) => hub.update(&sid, ConnectionStage::Failed, None, None, Some(e)),
                    };
                    hub.evidence(&st, &sid, false).await;
                });
                self.read(
                    &state,
                    &p,
                    ConnectionQuery {
                        plan_id: Some(plan_id),
                        device_id: None,
                    },
                )
            }
            ConnectionAction::Confirm {
                plan_id,
                identity_confirmed,
                enable_monitoring,
                poll_seconds,
            } => {
                self.check_plan(&state, &p, &plan_id)?;
                validate_poll_seconds(poll_seconds)?;
                if !identity_confirmed {
                    return Err(bad(
                        "IDENTITY_CONFIRMATION_REQUIRED",
                        "Operator must confirm the actually observed host identity",
                    ));
                }
                let status = self.status(&plan_id)?;
                if status.stage == ConnectionStage::Committed {
                    return self.read(
                        &state,
                        &p,
                        ConnectionQuery {
                            device_id: Some(status.device_id),
                            plan_id: None,
                        },
                    );
                }
                let (device, expected, endpoint, key, identity) = {
                    let mut plans = self.plans.lock().map_err(|_| denied())?;
                    let plan = plans.get_mut(&plan_id).ok_or_else(inaccessible)?;
                    if plan.status.stage != ConnectionStage::VerificationComplete {
                        return Err(bad(
                            "SSH_VERIFICATION_REQUIRED",
                            "Successful actual SSH verification is required",
                        ));
                    }
                    plan.status.stage = ConnectionStage::Committing;
                    (
                        plan.device.clone(),
                        plan.expected,
                        plan.status.endpoint.clone(),
                        plan.key.clone().ok_or_else(inaccessible)?,
                        plan.status.identity.clone().ok_or_else(inaccessible)?,
                    )
                };
                let verified_at = identity.captured_at_ms;
                let c = DeviceConnectionRecord {
                    device_id: device.id.clone(),
                    source_id: DataSourceId::new(uuid()?).map_err(|_| inventory_invalid())?,
                    authorized_principal: p.clone(),
                    endpoint,
                    host_key: key.key,
                    fingerprint: key.fingerprint,
                    verified_at_ms: identity.captured_at_ms,
                    identity,
                    enabled: enable_monitoring,
                    poll_seconds,
                    revision: 1,
                    last_attempt_ms: Some(verified_at),
                    last_success_ms: Some(verified_at),
                    last_error: None,
                };
                let definition = ssh::definition(&c);
                if !connection_payload_fits(&c) {
                    let e = bad(
                        "SSH_REPORT_TOO_LARGE",
                        "The verified host report is larger than the stored record bound; nothing was persisted",
                    );
                    self.update(
                        &plan_id,
                        ConnectionStage::Failed,
                        None,
                        None,
                        Some(ConnectionFault {
                            code: e.code.clone(),
                            message: e.message.clone(),
                        }),
                    );
                    return Err(e);
                }
                let committed = state
                    .connection_commit(
                        VerifiedConnectionCommit {
                            principal: p.clone(),
                            device: device.clone(),
                            expected_revision: expected,
                            connection: c,
                        },
                        definition,
                    )
                    .await;
                if let Err(e) = committed {
                    self.update(
                        &plan_id,
                        ConnectionStage::Failed,
                        None,
                        None,
                        Some(ConnectionFault {
                            code: e.code.clone(),
                            message: e.message.clone(),
                        }),
                    );
                    return Err(e);
                }
                self.update(&plan_id, ConnectionStage::Committed, None, None, None);
                self.read(
                    &state,
                    &p,
                    ConnectionQuery {
                        device_id: Some(device.id),
                        plan_id: None,
                    },
                )
            }
            ConnectionAction::Monitoring {
                device_id,
                expected_revision,
                enabled,
                poll_seconds,
            } => {
                let rows = state.inventory();
                let row = rows
                    .iter()
                    .find(|r| r.device.id == device_id)
                    .ok_or_else(inaccessible)?;
                Self::permit(
                    &state,
                    &p,
                    &row.device,
                    CapabilityId::DeviceConnectionConfigure,
                )?;
                if enabled {
                    let bindings = state.connections();
                    let binding = bindings
                        .iter()
                        .find(|c| c.device_id == device_id)
                        .ok_or_else(inaccessible)?;
                    if binding.authorized_principal != p {
                        return Err(denied());
                    }
                    self.settings
                        .resolve(&p, &binding.endpoint)
                        .map_err(|_| denied())?;
                }
                state
                    .connection_control(
                        p.clone(),
                        device_id.clone(),
                        expected_revision,
                        enabled,
                        poll_seconds,
                    )
                    .await?;
                self.read(
                    &state,
                    &p,
                    ConnectionQuery {
                        device_id: Some(device_id),
                        plan_id: None,
                    },
                )
            }
            ConnectionAction::Cancel { plan_id } => {
                self.check_plan(&state, &p, &plan_id)?;
                {
                    let mut plans = self.plans.lock().map_err(|_| denied())?;
                    let plan = plans.get_mut(&plan_id).ok_or_else(inaccessible)?;
                    if matches!(
                        plan.status.stage,
                        ConnectionStage::Committing | ConnectionStage::Committed
                    ) {
                        return Err(bad(
                            "CONNECTION_ALREADY_CONFIRMED",
                            "A committed connection cannot be cancelled as a pending plan",
                        ));
                    }
                    plan.cancel.cancel();
                    plan.status.stage = ConnectionStage::Cancelled;
                }
                self.read(
                    &state,
                    &p,
                    ConnectionQuery {
                        plan_id: Some(plan_id),
                        device_id: None,
                    },
                )
            }
        }
    }
}
impl ApplicationServices {
    pub(crate) fn connection_read(
        &self,
        ctx: &ExecutionContext,
        q: ConnectionQuery,
    ) -> Result<CapabilityOutput, CapabilityError> {
        let p = ctx.principal.as_ref().ok_or_else(denied)?;
        self.state
            .ssh
            .read(&self.state, p, q)
            .map(|r| CapabilityOutput::Connection(Box::new(r)))
    }
    pub(crate) async fn connection_configure(
        &self,
        ctx: &ExecutionContext,
        q: ConnectionAction,
    ) -> Result<CapabilityOutput, CapabilityError> {
        let p = ctx.principal.as_ref().ok_or_else(denied)?;
        self.state
            .ssh
            .configure(self.state.clone(), p.clone(), q)
            .await
            .map(|r| CapabilityOutput::Connection(Box::new(r)))
    }
}
pub async fn monitor(state: AppState, c: DeviceConnectionRecord, stop: CancellationToken) {
    let mut failures = 0u32;
    loop {
        if stop.is_cancelled() {
            break;
        }
        let profile = state
            .hierarchy()
            .filter(|h| {
                h.permits(
                    &c.authorized_principal,
                    CapabilityId::DeviceConnectionConfigure,
                    &AccessScope::Source(c.source_id.clone()),
                    false,
                )
            })
            .ok_or_else(|| ssh::fault("SSH_PROFILE_UNAVAILABLE"))
            .and_then(|_| {
                state
                    .ssh
                    .settings
                    .resolve(&c.authorized_principal, &c.endpoint)
                    .map(|v| v.0)
            });
        let result = match (profile, state.ssh.work.as_ref()) {
            (Ok(profile), Some(work)) => {
                let permit = tokio::select! {
                    _ = stop.cancelled() => break,
                    result = state.ssh.admission.clone().acquire_owned() => match result { Ok(p) => p, Err(_) => break },
                };
                state.connecting(&c.source_id).await;
                let result = ssh::collect(&c.endpoint, &profile, &c.host_key, work, &stop).await;
                drop(permit);
                result
            }
            (Err(e), _) => Err(e),
            _ => Err(ssh::fault("SSH_PROFILE_UNAVAILABLE")),
        };
        let result = result.and_then(|info| {
            if c.identity.stable_host_id_sha256.as_ref().zip(info.stable_host_id_sha256.as_ref())
                .is_some_and(|(expected, actual)| expected != actual) {
                Err(ConnectionFault {code: "SSH_IDENTITY_CHANGED".into(), message: "Remote host identity differs from the operator-confirmed binding; collection blocked".into()})
            } else { Ok(info) }
        });
        match result {
            Ok(info) => {
                failures = 0;
                if state.connected(&c.source_id).await.is_err() {
                    break;
                }
                for o in ssh::observations(&c, &info) {
                    if state
                        .ingest_for(&c.source_id, ClientEvent::Observation(Box::new(o)))
                        .await
                        .is_err()
                    {
                        return;
                    }
                }
                let _ = state
                    .connection_attempt(
                        ConnectionAttempt {
                            device_id: c.device_id.clone(),
                            endpoint: c.endpoint.clone(),
                            at_ms: info.captured_at_ms,
                            stage: ConnectionStage::VerificationComplete,
                            error: None,
                            neighbors: Some(info.neighbors.clone()),
                        },
                        true,
                    )
                    .await;
            }
            Err(e) => {
                if stop.is_cancelled() {
                    break;
                }
                failures = failures.saturating_add(1);
                let at = now_ms();
                let _ = state
                    .connection_attempt(
                        ConnectionAttempt {
                            device_id: c.device_id.clone(),
                            endpoint: c.endpoint.clone(),
                            at_ms: at,
                            stage: ConnectionStage::Failed,
                            error: Some(e.clone()),
                            neighbors: None,
                        },
                        false,
                    )
                    .await;
                let _ = state
                    .ingest_for(
                        &c.source_id,
                        ClientEvent::ConnectionLost {
                            at: Timestamp::from_unix_millis(at),
                            reason: e.code,
                        },
                    )
                    .await;
            }
        }
        let seconds = c
            .poll_seconds
            .saturating_mul(1u64 << failures.min(4))
            .min(3600);
        tokio::select! {_=stop.cancelled()=>break,_=tokio::time::sleep(Duration::from_secs(seconds))=>{}}
    }
}
struct OwnedCollector {
    revision: u64,
    cancel: CancellationToken,
    task: tokio::task::JoinHandle<()>,
}
impl Drop for OwnedCollector {
    fn drop(&mut self) {
        self.cancel.cancel();
        self.task.abort();
    }
}
pub async fn supervise(
    state: AppState,
    cancel: CancellationToken,
) -> Result<(), crate::runtime::RuntimeError> {
    let mut workers: BTreeMap<DeviceId, OwnedCollector> = BTreeMap::new();
    let mut reported = std::collections::BTreeSet::new();
    loop {
        let current = state.connections();
        // A failed collector is isolated and reported once. Only an explicit
        // configuration revision restarts it; no panic/retry storm or core shutdown.
        for (id, worker) in &workers {
            let revision = worker.revision;
            if worker.task.is_finished()
                && !cancel.is_cancelled()
                && reported.insert((id.clone(), revision))
            {
                if let Some(c) = current
                    .iter()
                    .find(|c| &c.device_id == id && c.enabled && c.revision == revision)
                {
                    let at = now_ms();
                    let _ = state.connection_attempt(ConnectionAttempt {
                        device_id: id.clone(), endpoint: c.endpoint.clone(), at_ms: at,
                        stage: ConnectionStage::Failed,
                        error: Some(ConnectionFault {code: "SSH_COLLECTOR_STOPPED".into(), message: "Collector stopped unexpectedly; inspect and explicitly reapply monitoring configuration".into()}),
                        neighbors: None,
                    }, false).await;
                    let _ = state
                        .ingest_for(
                            &c.source_id,
                            ClientEvent::ConnectionLost {
                                at: Timestamp::from_unix_millis(at),
                                reason: "SSH_COLLECTOR_STOPPED".into(),
                            },
                        )
                        .await;
                }
            }
        }
        let remove = workers
            .iter()
            .filter(|(id, worker)| {
                cancel.is_cancelled()
                    || !current
                        .iter()
                        .any(|c| &c.device_id == *id && c.enabled && c.revision == worker.revision)
            })
            .map(|(id, _)| id.clone())
            .collect::<Vec<_>>();
        for id in remove {
            if let Some(mut worker) = workers.remove(&id) {
                worker.cancel.cancel();
                let _ = (&mut worker.task).await;
                reported.retain(|(device, _)| device != &id);
            }
        }
        if cancel.is_cancelled() {
            break;
        }
        for c in current.iter().filter(|c| c.enabled) {
            if !workers.contains_key(&c.device_id) {
                let token = cancel.child_token();
                let task = state
                    .ssh
                    .tasks
                    .spawn(monitor(state.clone(), c.clone(), token.clone()));
                workers.insert(
                    c.device_id.clone(),
                    OwnedCollector {
                        revision: c.revision,
                        cancel: token,
                        task,
                    },
                );
            }
        }
        tokio::select! {_=cancel.cancelled()=>{},_=tokio::time::sleep(Duration::from_millis(250))=>{}}
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn record(identity: HostInformation) -> DeviceConnectionRecord {
        DeviceConnectionRecord {
            device_id: DeviceId::new("unit-device").unwrap(),
            source_id: DataSourceId::new("unit-source").unwrap(),
            authorized_principal: PrincipalId::new("unit-principal").unwrap(),
            endpoint: SshEndpoint {
                alias: None,
                host: "127.0.0.1".into(),
                port: 22,
                user: "operator".into(),
                identity_profile: "unit".into(),
            },
            host_key: "ssh-ed25519 AAAA".into(),
            fingerprint: "SHA256:unit".into(),
            verified_at_ms: 1,
            identity,
            enabled: false,
            poll_seconds: 60,
            revision: 1,
            last_attempt_ms: None,
            last_success_ms: None,
            last_error: None,
        }
    }
    fn host(addresses: Vec<String>) -> HostInformation {
        HostInformation {
            hostname: "unit".into(),
            operating_system: "Linux".into(),
            architecture: "aarch64".into(),
            cpu_info: None,
            model: None,
            stable_host_id_sha256: None,
            memory_total_bytes: Some(1024),
            memory_used_bytes: None,
            gpu_model: None,
            gpu_utilization_percent: None,
            gpu_temperature_c: None,
            cpu_temperature_c: None,
            soc_temperature_c: None,
            memory_used_percent: None,
            uptime_seconds: None,
            disks: Vec::new(),
            interfaces: vec![NetworkInterfaceInformation {
                name: "en0".into(),
                addresses,
            }],
            neighbors: Vec::new(),
            captured_at_ms: 1,
            unavailable: Vec::new(),
            provenance: "unit".into(),
        }
    }
    #[test]
    fn a_verified_report_that_cannot_be_stored_is_refused_before_any_write() {
        let normal = record(host(vec!["192.0.2.1".into()]));
        assert!(connection_payload_fits(&normal));
        // An extreme report exceeds the stored record bound and must not be
        // handed to the writer as if it were storable.
        let long = "2001:db8::".repeat(24);
        let extreme = record(host(
            (0..32)
                .flat_map(|_| (0..32).map(|_| long.clone()))
                .collect::<Vec<String>>(),
        ));
        assert!(!connection_payload_fits(&extreme));
    }
    #[tokio::test]
    async fn abandoned_supervisor_cannot_detach_collector_tasks() {
        let tracker = tokio_util::task::TaskTracker::new();
        let token = CancellationToken::new();
        let owned = OwnedCollector {
            revision: 1,
            cancel: token.clone(),
            task: tracker.spawn(std::future::pending()),
        };
        drop(owned);
        assert!(token.is_cancelled());
        tracker.close();
        tokio::time::timeout(Duration::from_secs(1), tracker.wait())
            .await
            .expect("collector must be aborted and reaped");
    }
}
