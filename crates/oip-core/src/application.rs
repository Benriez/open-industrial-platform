//! Protocol-, database- and executor-neutral ingestion and health policy.
use crate::*;
use std::collections::BTreeMap;

struct SourceState {
    definition: SourceDefinition,
    health: SourceHealth,
    watermarks: BTreeMap<MetricId, Timestamp>,
    gap_start: Option<i64>,
}
pub struct Application<R: CoreRepository> {
    pub repository: R,
    sources: BTreeMap<DataSourceId, SourceState>,
    latest: BTreeMap<(DataSourceId, EntityId, MetricId), ObservationEnvelope>,
    events: Vec<EventRecord>,
    health: CoreHealth,
    phase: Lifecycle,
    stale_after_ms: i64,
}
impl<R: CoreRepository> Application<R> {
    pub fn initialize(
        mut repository: R,
        definitions: Vec<SourceDefinition>,
        now: i64,
        stale_after_ms: i64,
    ) -> Result<Self, ApplicationError> {
        if stale_after_ms <= 0 || definitions.is_empty() {
            return Err(ApplicationError::RegistrationConflict);
        }
        let saved = repository
            .definitions()
            .map_err(ApplicationError::Persistence)?;
        let mut sources = BTreeMap::new();
        for d in definitions {
            if d.metrics.is_empty()
                || d.name.trim().is_empty()
                || d.binding.is_empty()
                || (d.origin_class == OriginClass::Simulation && d.simulation_origin_id.is_empty())
                || sources.contains_key(&d.id)
                || saved.iter().any(|old| old.id == d.id && old != &d)
            {
                return Err(ApplicationError::RegistrationConflict);
            }
            repository
                .register(&d)
                .map_err(ApplicationError::Persistence)?;
            let health = SourceHealth {
                id: d.id.clone(),
                name: d.name.clone(),
                entity_id: d.entity_id.clone(),
                simulated: d.origin_class == OriginClass::Simulation,
                reachability: Reachability::Unknown,
                connection: ConnectionHealth::Unknown,
                service: ServiceHealth::Unknown,
                freshness: Freshness::Unknown,
                validity: Validity::Unknown,
                last_received_ms: None,
                accepted: 0,
                duplicates: 0,
                out_of_order: 0,
                rejected: 0,
                reconnect_attempts: 0,
                dropped: 0,
                last_error: None,
            };
            sources.insert(
                d.id.clone(),
                SourceState {
                    definition: d,
                    health,
                    watermarks: BTreeMap::new(),
                    gap_start: None,
                },
            );
        }
        let mut latest = BTreeMap::new();
        for mut o in repository
            .restore_latest()
            .map_err(ApplicationError::Persistence)?
        {
            if o.simulation_origin.is_none()
                && !sources
                    .get(&o.data_source_id)
                    .is_some_and(|s| s.definition.origin_class == OriginClass::External)
            {
                return Err(ApplicationError::Provenance);
            }
            if let Some(s) = sources.get_mut(&o.data_source_id) {
                validate_observation(&s.definition, &o)?;
                if let Some(received) = o.timestamps.received.map(Timestamp::as_unix_millis) {
                    s.gap_start = Some(s.gap_start.map_or(received, |old| old.max(received)));
                }
                o.freshness = Freshness::Stale;
                latest.insert(
                    (
                        o.data_source_id.clone(),
                        o.entity_id.clone(),
                        o.metric_id.clone(),
                    ),
                    o,
                );
            }
        }
        let events = repository
            .recent_events(100)
            .map_err(ApplicationError::Persistence)?;
        let count = repository.count().map_err(ApplicationError::Persistence)?;
        let run_id = repository
            .start_run(now)
            .map_err(ApplicationError::Persistence)?;
        Ok(Self {
            repository,
            sources,
            latest,
            events,
            health: CoreHealth {
                lifecycle: Lifecycle::Initializing,
                live: true,
                ready: false,
                persistence_healthy: true,
                persistence_errors: 0,
                last_persistence_error: None,
                revision: 0,
                run_id,
                persisted_observations: count,
            },
            phase: Lifecycle::Initializing,
            stale_after_ms,
        })
    }
    pub fn started(&mut self) {
        self.phase = Lifecycle::Ready;
    }
    pub fn connecting(&mut self, id: &DataSourceId) -> Result<(), ApplicationError> {
        let s = self
            .sources
            .get_mut(id)
            .ok_or(ApplicationError::UnknownSource)?;
        s.health.reconnect_attempts += 1;
        Ok(())
    }
    /// A new collection session starts a new source-clock ordering epoch.
    pub fn connected(&mut self, id: &DataSourceId) -> Result<(), ApplicationError> {
        let s = self
            .sources
            .get_mut(id)
            .ok_or(ApplicationError::UnknownSource)?;
        s.watermarks.clear();
        s.health.connection = ConnectionHealth::Connected;
        s.health.reachability = Reachability::Reachable;
        s.health.service = ServiceHealth::Unknown;
        s.health.last_received_ms = None;
        s.health.freshness = Freshness::Unknown;
        Ok(())
    }
    pub fn recovered_gap(&self, id: &DataSourceId, now: i64) -> Option<ClientEvent> {
        self.sources.get(id)?.gap_start.map(|start| {
            if now < start {
                return ClientEvent::SubscriptionError {
                    at: Timestamp::from_unix_millis(now),
                    reason: "clock_regression: recovery gap end is unknown".into(),
                };
            }
            ClientEvent::Reconnected {
                at: Timestamp::from_unix_millis(now),
                gap: DataGap {
                    started_at: Timestamp::from_unix_millis(start),
                    ended_at: Timestamp::from_unix_millis(now),
                    reason: "collection interrupted or core restarted; no samples inferred".into(),
                },
            }
        })
    }
    pub fn ingest(
        &mut self,
        id: &DataSourceId,
        mut event: ClientEvent,
        now: i64,
    ) -> Result<IngestOutcome, ApplicationError> {
        let s = self
            .sources
            .get(id)
            .ok_or(ApplicationError::UnknownSource)?;
        if let ClientEvent::Observation(o) = &mut event {
            o.timestamps
                .received
                .get_or_insert(Timestamp::from_unix_millis(now));
        }
        let mut publish_latest = false;
        if let ClientEvent::Observation(o) = &event {
            validate_observation(&s.definition, o)?;
            publish_latest = o.collection_error != Some(CollectionError::InvalidTimestamp)
                && s.watermarks
                    .get(&o.metric_id)
                    .is_none_or(|last| o.timestamps.source > *last);
        }
        if let ClientEvent::Reconnected { gap, .. } | ClientEvent::DataLoss { gap, .. } = &event {
            if gap.ended_at < gap.started_at {
                return Err(ApplicationError::NegativeGap);
            }
        }
        let context = EventContext {
            data_source_id: id.clone(),
            origin_class: s.definition.origin_class,
        };
        let checkpoint = if publish_latest {
            if let ClientEvent::Observation(o) = &event {
                Some(o.as_ref())
            } else {
                None
            }
        } else {
            None
        };
        let (outcome, sequence) = self
            .repository
            .commit(&context, &event, checkpoint)
            .map_err(ApplicationError::Persistence)?;
        self.health.persistence_healthy = true;
        self.health.last_persistence_error = None;
        if outcome == IngestOutcome::Inserted && matches!(event, ClientEvent::Observation(_)) {
            self.health.persisted_observations += 1;
        }
        let s = self
            .sources
            .get_mut(id)
            .ok_or(ApplicationError::UnknownSource)?;
        match &event {
            ClientEvent::Observation(o) => {
                if o.collection_error == Some(CollectionError::InvalidTimestamp) {
                    s.health.validity = Validity::Invalid;
                    s.health.service = ServiceHealth::Degraded;
                }
                if outcome == IngestOutcome::Duplicate {
                    s.health.duplicates += 1;
                }
                if publish_latest {
                    s.watermarks
                        .insert(o.metric_id.clone(), o.timestamps.source);
                    s.health.accepted += 1;
                    if s.definition.required_metrics.contains(&o.metric_id) {
                        s.health.last_received_ms = Some(now);
                        s.health.validity = if o.is_usable() {
                            Validity::Valid
                        } else {
                            Validity::Invalid
                        };
                        s.health.service = if o.is_usable() {
                            ServiceHealth::Healthy
                        } else {
                            ServiceHealth::Degraded
                        };
                        s.health.freshness = o.freshness;
                        s.health.connection = ConnectionHealth::Connected;
                        s.health.reachability = Reachability::Reachable;
                        s.health.last_error = None;
                    }
                    self.latest.insert(
                        (id.clone(), o.entity_id.clone(), o.metric_id.clone()),
                        *o.clone(),
                    );
                } else if s
                    .watermarks
                    .get(&o.metric_id)
                    .is_some_and(|last| o.timestamps.source < *last)
                {
                    s.health.out_of_order += 1;
                }
            }
            ClientEvent::ConnectionLost { at, reason }
            | ClientEvent::SubscriptionError { at, reason } => {
                s.health.connection = ConnectionHealth::Disconnected;
                s.health.reachability = Reachability::Unknown;
                s.health.service = ServiceHealth::Degraded;
                s.health.last_error = Some(reason.clone());
                s.gap_start.get_or_insert(at.as_unix_millis());
            }
            ClientEvent::Reconnected { .. } => {
                s.gap_start = None;
                s.watermarks.clear();
                s.health.connection = ConnectionHealth::Connected;
                s.health.reachability = Reachability::Reachable;
                s.health.last_received_ms = None;
                s.health.freshness = Freshness::Unknown;
                s.health.service = ServiceHealth::Unknown;
            }
            ClientEvent::DataLoss { dropped, .. } => {
                s.health.dropped += dropped;
                s.health.service = ServiceHealth::Degraded;
                s.health.last_error = Some("data_loss".into());
            }
        }
        if outcome == IngestOutcome::Inserted && !matches!(event, ClientEvent::Observation(_)) {
            self.events.push(EventRecord {
                id: self.repository.event_id(&context, &event),
                sequence,
                context,
                event,
            });
            if self
                .events
                .iter()
                .filter(|e| &e.context.data_source_id == id)
                .count()
                > 100
            {
                if let Some(index) = self
                    .events
                    .iter()
                    .position(|e| &e.context.data_source_id == id)
                {
                    self.events.remove(index);
                }
            }
        }
        self.health.revision += 1;
        Ok(outcome)
    }
    pub fn rejected(&mut self, id: &DataSourceId) {
        if let Some(s) = self.sources.get_mut(id) {
            s.health.rejected += 1;
            s.health.validity = Validity::Invalid;
            s.health.service = ServiceHealth::Degraded;
            s.health.last_error = Some("validation_rejected".into());
        }
    }
    pub fn persistence_failed(&mut self) {
        self.health.persistence_healthy = false;
        self.health.persistence_errors += 1;
        self.health.last_persistence_error = Some("commit_failed_retry_pending".into());
    }
    pub fn stopping(&mut self) {
        self.phase = Lifecycle::Stopping;
    }
    pub fn finish(&mut self, now: i64, clean: bool) -> Result<(), ApplicationError> {
        if let Err(error) = self.repository.finish_run(
            self.health.run_id,
            now,
            if clean { "stopped" } else { "failed" },
        ) {
            self.phase = Lifecycle::Failed;
            self.persistence_failed();
            return Err(ApplicationError::Persistence(error));
        }
        self.phase = if clean {
            Lifecycle::Stopped
        } else {
            Lifecycle::Failed
        };
        Ok(())
    }
    pub fn view(&self, now: i64) -> CoreView {
        let mut sources: Vec<_> =
            self.sources
                .values()
                .map(|s| {
                    let mut h = s.health.clone();
                    let required: Vec<_> = s
                        .definition
                        .required_metrics
                        .iter()
                        .map(|m| {
                            self.latest
                                .get(&(
                                    s.definition.id.clone(),
                                    s.definition.entity_id.clone(),
                                    m.clone(),
                                ))
                                .filter(|_| s.watermarks.contains_key(m))
                        })
                        .collect();
                    if required.iter().any(|o| o.is_none()) {
                        h.freshness = Freshness::Unknown;
                        if h.service != ServiceHealth::Degraded {
                            h.service = ServiceHealth::Unknown;
                        }
                    } else {
                        if required.iter().flatten().any(|o| !o.is_usable()) {
                            h.service = ServiceHealth::Degraded;
                            h.validity = Validity::Invalid;
                        }
                        if required
                            .iter()
                            .flatten()
                            .any(|o| freshness(s, o, now, self.stale_after_ms) == Freshness::Stale)
                        {
                            h.freshness = Freshness::Stale;
                        } else if required.iter().flatten().any(|o| {
                            freshness(s, o, now, self.stale_after_ms) == Freshness::Unknown
                        }) {
                            h.freshness = Freshness::Unknown;
                        }
                    }

                    h.freshness = match h.last_received_ms {
                        Some(last) if now < last => Freshness::Unknown,
                        Some(last)
                            if now.saturating_sub(last) > self.stale_after_ms
                                || h.connection != ConnectionHealth::Connected =>
                        {
                            Freshness::Stale
                        }
                        Some(_) => h.freshness,
                        None => Freshness::Unknown,
                    };
                    h
                })
                .collect();
        let healthy = |s: &&SourceHealth| {
            s.connection == ConnectionHealth::Connected
                && s.service == ServiceHealth::Healthy
                && s.freshness == Freshness::Fresh
        };
        let all = sources.iter().filter(healthy).count() == sources.len();
        let any = sources.iter().any(|s| healthy(&s));
        let mut health = self.health.clone();
        health.lifecycle = match self.phase {
            Lifecycle::Ready | Lifecycle::Degraded => {
                if all && health.persistence_healthy {
                    Lifecycle::Ready
                } else {
                    Lifecycle::Degraded
                }
            }
            p => p,
        };
        health.live = !matches!(health.lifecycle, Lifecycle::Stopped | Lifecycle::Failed);
        health.ready = matches!(health.lifecycle, Lifecycle::Ready | Lifecycle::Degraded)
            && any
            && health.persistence_healthy;
        let observations = self
            .latest
            .values()
            .cloned()
            .map(|mut o| {
                o.freshness = self
                    .sources
                    .get(&o.data_source_id)
                    .map_or(Freshness::Unknown, |s| {
                        freshness(s, &o, now, self.stale_after_ms)
                    });
                o
            })
            .collect();
        if !health.live {
            for s in &mut sources {
                s.connection = ConnectionHealth::Disconnected;
                s.freshness = Freshness::Stale;
                s.reachability = Reachability::Unknown;
            }
        }
        CoreView {
            health,
            sources,
            observations,
            events: self.events.clone(),
        }
    }
}
/// Shared validation for live ingestion, recovery and explicit offline legacy adoption.
pub fn validate_observation(
    definition: &SourceDefinition,
    o: &ObservationEnvelope,
) -> Result<(), ApplicationError> {
    let provenance_matches = match definition.origin_class {
        OriginClass::Simulation => o
            .simulation_origin
            .as_ref()
            .is_some_and(|p| p.origin_id == definition.simulation_origin_id),
        OriginClass::External => o.simulation_origin.is_none(),
    };
    if o.data_source_id != definition.id
        || o.entity_id != definition.entity_id
        || !provenance_matches
    {
        return Err(ApplicationError::Provenance);
    }
    let kind = definition
        .metrics
        .get(&o.metric_id)
        .ok_or(ApplicationError::DataType)?;
    if let Some(v) = &o.value {
        if !kind.matches(v) {
            return Err(ApplicationError::DataType);
        }
        if matches!(v,MetricValue::Float(n) if !n.is_finite()) {
            return Err(ApplicationError::NonFinite);
        }
    }
    let valid_time =
        |t: Timestamp| (-11_644_473_600_000..=253_402_300_799_999).contains(&t.as_unix_millis());
    let times_valid = valid_time(o.timestamps.source)
        && o.timestamps.server.is_none_or(valid_time)
        && o.timestamps.received.is_none_or(valid_time);
    if !(times_valid
        || (o.collection_error == Some(CollectionError::InvalidTimestamp)
            && o.quality == DataQuality::Bad
            && o.freshness == Freshness::Unknown))
    {
        return Err(ApplicationError::Timestamp);
    }
    if o.value.is_none() && o.quality == DataQuality::Good {
        return Err(ApplicationError::DataType);
    }
    Ok(())
}

fn freshness(s: &SourceState, o: &ObservationEnvelope, now: i64, limit: i64) -> Freshness {
    if s.health.connection != ConnectionHealth::Connected
        || !s.watermarks.contains_key(&o.metric_id)
    {
        return Freshness::Stale;
    }
    match o.timestamps.received.map(Timestamp::as_unix_millis) {
        Some(t) if now < t => Freshness::Unknown,
        Some(t) if now.saturating_sub(t) > limit => Freshness::Stale,
        Some(_) => o.freshness,
        None => Freshness::Unknown,
    }
}
