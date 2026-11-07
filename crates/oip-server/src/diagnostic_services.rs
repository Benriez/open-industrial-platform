//! One application read service shared by REST/MCP. Authorization precedes SQL and cursor lookup.
use crate::application_services::ApplicationServices;
use oip_core::*;
use oip_storage::{HistoryKind, HistoryPosition, HistoryReader, HistorySnapshot};
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    time::{Duration, Instant},
};
use tokio::sync::Semaphore;
#[derive(Clone)]
struct Cursor {
    binding: String,
    owner: String,
    snapshot: HistorySnapshot,
    position: HistoryPosition,
    created: Instant,
    issued: Instant,
    chain: String,
}
pub struct DiagnosticReads {
    reader: Option<HistoryReader>,
    slots: Arc<Semaphore>,
    cursors: Mutex<BTreeMap<String, Cursor>>,
}
impl DiagnosticReads {
    pub fn new(reader: Option<HistoryReader>) -> Self {
        Self {
            reader,
            slots: Arc::new(Semaphore::new(4)),
            cursors: Mutex::new(BTreeMap::new()),
        }
    }
}
struct Cancel(Arc<AtomicBool>);
impl Drop for Cancel {
    fn drop(&mut self) {
        self.0.store(true, Ordering::Relaxed);
    }
}
fn unavailable() -> CapabilityError {
    CapabilityError::new(
        CapabilityErrorCode::PersistenceUnavailable,
        "HISTORY_UNAVAILABLE",
        "Historical evidence storage is unavailable",
    )
}
fn history_error(e: oip_storage::StorageError) -> CapabilityError {
    match e {
        oip_storage::StorageError::HistoryLimit => CapabilityError::new(
            CapabilityErrorCode::InvalidInput,
            "HISTORY_BYTE_LIMIT",
            "Historical evidence byte limit exceeded; narrow the query",
        ),
        oip_storage::StorageError::Sqlite(rusqlite::Error::SqliteFailure(e, _))
            if e.code == rusqlite::ErrorCode::OperationInterrupted =>
        {
            CapabilityError::new(
                CapabilityErrorCode::SourceUnavailable,
                "HISTORY_TIMEOUT",
                "Historical query deadline or cancellation reached",
            )
        }
        _ => unavailable(),
    }
}
fn inaccessible() -> CapabilityError {
    CapabilityError::new(
        CapabilityErrorCode::ResourceNotFound,
        "RESOURCE_NOT_ACCESSIBLE",
        "Resource is not accessible",
    )
}
fn kind(id: CapabilityId) -> HistoryKind {
    match id {
        CapabilityId::ObservationHistoryRead => HistoryKind::Observations,
        CapabilityId::DataGapsRead | CapabilityId::DiagnosticFindingsRead => HistoryKind::Gaps,
        CapabilityId::SourceHealthHistoryRead => HistoryKind::Health,
        _ => HistoryKind::Events,
    }
}
pub fn query(request: &CapabilityRequest) -> Option<&DiagnosticQuery> {
    match request {
        CapabilityRequest::EventHistoryRead(q)
        | CapabilityRequest::EventDetailRead(q)
        | CapabilityRequest::DataGapsRead(q)
        | CapabilityRequest::SourceHealthHistoryRead(q)
        | CapabilityRequest::EvidenceRead(q)
        | CapabilityRequest::DiagnosticFindingsRead(q)
        | CapabilityRequest::ObservationHistoryRead(q) => Some(q),
        _ => None,
    }
}
fn page(
    rows: oip_storage::HistoryRows,
    id: CapabilityId,
) -> (DiagnosticPage, Option<HistoryPosition>) {
    let position = rows.rows.last().map(|r| r.0.clone());
    let items = rows
        .rows
        .into_iter()
        .map(|(_, item)| {
            if id == CapabilityId::DiagnosticFindingsRead {
                match item {
                    DiagnosticItem::Gap(g) => {
                        DiagnosticItem::Finding(oip_diagnostics::documented_gap(&g))
                    }
                    v => v,
                }
            } else {
                item
            }
        })
        .collect();
    (DiagnosticPage{items,next_cursor:None,truncated:rows.more,missing_evidence:vec![],time_semantics:"Events: recorded event time (observation events use source time). Observations: received time, stale historical values; missing receive timestamps excluded. Health: runtime wall-clock observation. Gap: documented start marker. No clock synchronization or causal ordering guarantee.".into()},position)
}
impl ApplicationServices {
    pub(super) async fn diagnostic_read(
        &self,
        context: &ExecutionContext,
        id: CapabilityId,
        mut q: DiagnosticQuery,
    ) -> Result<CapabilityOutput, CapabilityError> {
        if q.limit.is_none() {
            q.limit = Some(self.history_default(&q));
        }
        let limit = q.validate()?;
        let is_event = matches!(
            id,
            CapabilityId::EventHistoryRead
                | CapabilityId::EventDetailRead
                | CapabilityId::EvidenceRead
        );
        if (!is_event && (q.event_id.is_some() || q.event_type.is_some()))
            || (id != CapabilityId::ObservationHistoryRead && q.metric.is_some())
            || (matches!(id, CapabilityId::EventDetailRead)
                && (q.event_id.is_none() || q.cursor.is_some()))
            || (id == CapabilityId::EvidenceRead
                && (q.cursor.is_some()
                    || q.start_ms.is_none()
                    || q.end_ms.is_none()
                    || q.end_ms.unwrap() - q.start_ms.unwrap() > 7 * 86400000
                    || limit < 4
                    || q.event_type.is_some()))
        {
            return Err(diagnostic_invalid());
        }
        let mut sources = if let Some(p) = &context.principal {
            let h = self.state.hierarchy().ok_or_else(inaccessible)?;
            self.tenant_sources(
                &h,
                p,
                id,
                &SourceQuery {
                    organization: q.organization.clone(),
                    infrastructure: q.infrastructure.clone(),
                    site: q.site.clone(),
                    source: q.source.clone(),
                    ..Default::default()
                },
            )?
        } else {
            if q.organization.is_some() || q.infrastructure.is_some() || q.site.is_some() {
                return Err(diagnostic_invalid());
            }
            let allowed: BTreeSet<_> = self
                .state
                .view()
                .sources
                .into_iter()
                .map(|s| s.id)
                .filter(|s| match &context.sources {
                    SourceScope::All => true,
                    SourceScope::Only(ids) => ids.contains(s),
                })
                .collect();
            if q.source.as_ref().is_some_and(|s| !allowed.contains(s)) {
                return Err(inaccessible());
            }
            allowed
                .into_iter()
                .filter(|s| q.source.as_ref().is_none_or(|v| v == s))
                .collect()
        };
        if let Some(device) = &q.device {
            let source = if let Some(h) = &self.state.hierarchy() {
                h.source_for_device(device.as_str()).cloned()
            } else {
                self.state.snapshot().ok().and_then(|v| {
                    v.devices
                        .into_iter()
                        .find(|d| d.id == device.as_str())
                        .and_then(|d| d.data_source_id)
                })
            }
            .ok_or_else(inaccessible)?;
            if !sources.contains(&source) {
                return Err(inaccessible());
            }
            sources.retain(|s| s == &source);
        }
        // Fingerprint includes every filter, sort (fixed ascending), capability and effective authority.
        let cursor_token = q.cursor.take();
        let binding = format!(
            "{:x}",
            Sha256::digest(
                serde_json::to_vec(&(
                    id,
                    &q,
                    &sources,
                    &context.principal,
                    &context.actor,
                    &context.permissions,
                    &context.sources
                ))
                .map_err(|_| diagnostic_invalid())?
            )
        );
        let owner = context
            .principal
            .as_ref()
            .map_or_else(|| context.actor.clone(), ToString::to_string);
        let reads = self.state.history.clone();
        let prior = {
            let mut cache = reads.cursors.lock().map_err(|_| unavailable())?;
            cache.retain(|_, c| c.created.elapsed() < Duration::from_secs(300));
            match cursor_token {
                Some(token) => {
                    let c = cache
                        .get(&token)
                        .filter(|c| c.binding == binding && c.owner == owner)
                        .ok_or_else(diagnostic_invalid)?;
                    Some(c.clone())
                }
                None => None,
            }
        };
        let reader = reads.reader.clone().ok_or_else(unavailable)?;
        let permit = reads.slots.clone().try_acquire_owned().map_err(|_| {
            CapabilityError::new(
                CapabilityErrorCode::SourceUnavailable,
                "HISTORY_BUSY",
                "Historical read admission limit reached; retry later",
            )
        })?;
        let canceled = Arc::new(AtomicBool::new(false));
        let _cancel = Cancel(canceled.clone());
        let task = tokio::task::spawn_blocking(move || {
            let _permit = permit;
            let c = reader.open(canceled).map_err(history_error)?;
            let snapshot = match &prior {
                Some(p) => p.snapshot.clone(),
                None => HistoryReader::snapshot(&c, &sources).map_err(history_error)?,
            };
            let position = prior
                .as_ref()
                .map(|p| p.position.clone())
                .unwrap_or(HistoryPosition {
                    at_ms: i64::MIN,
                    key: String::new(),
                });
            let created = prior.as_ref().map_or_else(Instant::now, |p| p.created);
            let chain = prior
                .as_ref()
                .map(|p| p.chain.clone())
                .unwrap_or(random_cursor()?);
            if id == CapabilityId::EvidenceRead {
                let anchor = if q.event_id.is_some() {
                    let r = HistoryReader::read(
                        &c,
                        HistoryKind::Events,
                        &sources,
                        &q,
                        &snapshot,
                        &position,
                        1,
                    )
                    .map_err(history_error)?;
                    match r.rows.into_iter().next() {
                        Some((_, DiagnosticItem::Event(e))) => Some(*e),
                        _ => return Err(inaccessible()),
                    }
                } else {
                    if q.source.is_none() {
                        return Err(diagnostic_invalid());
                    }
                    None
                };
                if let Some(a) = &anchor {
                    sources.retain(|s| s == &a.source);
                }
                q.event_id = None;
                let mut pages = Vec::new();
                for (k, cap) in [
                    (HistoryKind::Events, CapabilityId::EventHistoryRead),
                    (
                        HistoryKind::Observations,
                        CapabilityId::ObservationHistoryRead,
                    ),
                    (HistoryKind::Gaps, CapabilityId::DataGapsRead),
                    (HistoryKind::Health, CapabilityId::SourceHealthHistoryRead),
                ] {
                    pages.push(
                        page(
                            HistoryReader::read(
                                &c,
                                k,
                                &sources,
                                &q,
                                &snapshot,
                                &position,
                                limit / 4,
                            )
                            .map_err(history_error)?,
                            cap,
                        )
                        .0,
                    );
                }
                let mut iter = pages.into_iter();
                let events = iter.next().unwrap();
                let observations = iter.next().unwrap();
                let gaps = iter.next().unwrap();
                let health = iter.next().unwrap();
                let mut missing=vec!["Temporal/contextual association is not evidence of root cause; clocks may differ".into(),"Health history before schema4 and between uncommitted/crashed publishes is unavailable".into()];
                if observations.items.is_empty() {
                    missing.push(
                        "No observations with recorded receive time in the selected window".into(),
                    );
                }
                if gaps.items.is_empty() {
                    missing
                        .push("No documented gap found; absence is not proof of continuity".into());
                }
                return Ok(CapabilityOutput::Evidence(Box::new(EvidenceSet {
                    anchor,
                    events,
                    observations,
                    gaps,
                    health,
                    relation: "same_authorized_source_and_requested_time_window; not causal".into(),
                    missing_evidence: missing,
                })));
            }
            let rows = HistoryReader::read(&c, kind(id), &sources, &q, &snapshot, &position, limit)
                .map_err(history_error)?;
            if id == CapabilityId::EventDetailRead && rows.rows.is_empty() {
                return Err(inaccessible());
            }
            let (mut output, last) = page(rows, id);
            if id == CapabilityId::ObservationHistoryRead {
                output.missing_evidence.push("Samples without receive time are excluded; source/server clocks may not match the runtime clock".into());
            }
            if id == CapabilityId::SourceHealthHistoryRead {
                output.missing_evidence.push("No historical state transitions are reconstructed before schema4 or across process boundaries".into());
            }
            if output.truncated {
                let token = random_cursor()?;
                let mut cache = reads.cursors.lock().map_err(|_| unavailable())?;
                cache.retain(|_, v| v.created.elapsed() < Duration::from_secs(300));
                let chains = cache
                    .values()
                    .filter(|c| c.owner == owner)
                    .map(|c| &c.chain)
                    .collect::<BTreeSet<_>>();
                if cache.len() >= 1024 || (!chains.contains(&chain) && chains.len() >= 64) {
                    return Err(CapabilityError::new(
                        CapabilityErrorCode::SourceUnavailable,
                        "CURSOR_CAPACITY",
                        "Historical cursor capacity reached; restart after expiry",
                    ));
                }
                // Retain two most recent continuations per chain for response retries;
                // arbitrarily long traversals cannot consume all principal capacity.
                while cache.values().filter(|c| c.chain == chain).count() >= 2 {
                    let old = cache
                        .iter()
                        .filter(|(_, c)| c.chain == chain)
                        .min_by_key(|(_, c)| c.issued)
                        .map(|(t, _)| t.clone())
                        .unwrap();
                    cache.remove(&old);
                }
                cache.insert(
                    token.clone(),
                    Cursor {
                        binding,
                        owner,
                        snapshot,
                        position: last.ok_or_else(unavailable)?,
                        created,
                        issued: Instant::now(),
                        chain,
                    },
                );
                output.next_cursor = Some(token);
            }
            Ok(CapabilityOutput::DiagnosticPage(output))
        });
        tokio::time::timeout(Duration::from_secs(3), task)
            .await
            .map_err(|_| {
                CapabilityError::new(
                    CapabilityErrorCode::SourceUnavailable,
                    "HISTORY_TIMEOUT",
                    "Historical query deadline exceeded",
                )
            })?
            .map_err(|_| unavailable())?
    }
}
fn random_cursor() -> Result<String, CapabilityError> {
    use std::io::Read;
    let mut bytes = [0u8; 32];
    std::fs::File::open("/dev/urandom")
        .and_then(|mut f| f.read_exact(&mut bytes))
        .map_err(|_| unavailable())?;
    Ok(bytes.iter().map(|b| format!("{b:02x}")).collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn expired_cursor_is_pruned_and_fails_before_storage() {
        let state = crate::state::AppState::legacy(
            oip_storage::SqliteStore::open_in_memory().unwrap(),
            None,
        )
        .unwrap();
        let service = ApplicationServices::new(state.clone());
        let context = service.local_context();
        let old = Instant::now() - Duration::from_secs(301);
        let token = "f".repeat(64);
        state.history.cursors.lock().unwrap().insert(
            token.clone(),
            Cursor {
                binding: "expired".into(),
                owner: context.actor.clone(),
                snapshot: HistorySnapshot::default(),
                position: HistoryPosition::default(),
                created: old,
                issued: old,
                chain: "expired-chain".into(),
            },
        );
        let error = service
            .execute(
                &context,
                CapabilityRequest::EventHistoryRead(DiagnosticQuery {
                    cursor: Some(token),
                    ..Default::default()
                }),
            )
            .await
            .unwrap_err();
        assert_eq!(error.code, "INVALID_DIAGNOSTIC_QUERY");
        assert!(state.history.cursors.lock().unwrap().is_empty());
        assert!(state.shutdown().await.clean);
    }
}
