//! Bounded read-only historical evidence adapter; a separate connection never owns a writer.
use super::*;
use oip_core::*;
use std::{
    collections::BTreeSet,
    path::PathBuf,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
    time::{Duration, Instant},
};
pub(crate) const HISTORY_SQL: &str = r#"
CREATE INDEX history_events ON collection_events(data_source_id,at_ms,event_key);
CREATE INDEX history_events_kind ON collection_events(data_source_id,kind,at_ms,event_key);
CREATE INDEX history_observations_receive ON observations(data_source_id,received_ts_ms,observation_key);
CREATE INDEX history_gaps ON data_gaps(data_source_id,started_at_ms,gap_key);
CREATE TABLE source_health_history (
 id TEXT PRIMARY KEY,source_id TEXT NOT NULL REFERENCES core_sources(source_id),
 run_id INTEGER NOT NULL REFERENCES core_runs(id),at_ms INTEGER NOT NULL, payload_json TEXT NOT NULL
) STRICT;
CREATE INDEX history_health ON source_health_history(source_id,at_ms,id);
"#;
#[derive(Clone, Copy, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum HistoryKind {
    Events,
    Observations,
    Gaps,
    Health,
}
#[derive(Clone, Default, Debug)]
pub struct HistorySnapshot {
    pub highwater: [i64; 4],
}
#[derive(Clone, Debug)]
pub struct HistoryPosition {
    pub at_ms: i64,
    pub key: String,
}
#[derive(Clone)]
pub struct HistoryReader {
    path: PathBuf,
}
impl Default for HistoryPosition {
    fn default() -> Self {
        Self {
            at_ms: i64::MIN,
            key: String::new(),
        }
    }
}
pub struct HistoryRows {
    pub rows: Vec<(HistoryPosition, DiagnosticItem)>,
    pub more: bool,
}
impl SqliteStore {
    pub fn history_reader(&self) -> Result<Option<HistoryReader>, StorageError> {
        let path: String = self.connection.query_row(
            "SELECT file FROM pragma_database_list WHERE name='main'",
            [],
            |r| r.get(0),
        )?;
        Ok(if path.is_empty() {
            None
        } else {
            Some(HistoryReader {
                path: PathBuf::from(path),
            })
        })
    }
    pub fn record_health(
        &mut self,
        run_id: i64,
        transitions: &[SourceHealthTransition],
    ) -> Result<(), StorageError> {
        if transitions.is_empty() {
            return Ok(());
        }
        let tx = self.write_transaction()?;
        for t in transitions {
            tx.execute(
                "INSERT INTO source_health_history VALUES(?1,?2,?3,?4,?5)",
                params![
                    t.id,
                    t.source.as_str(),
                    run_id,
                    t.at_ms,
                    serde_json::to_string(t)?
                ],
            )?;
        }
        tx.commit()?;
        Ok(())
    }
}
impl HistoryReader {
    pub fn open(&self, cancel: Arc<AtomicBool>) -> Result<Connection, StorageError> {
        let c = Connection::open_with_flags(
            &self.path,
            rusqlite::OpenFlags::SQLITE_OPEN_READ_ONLY | rusqlite::OpenFlags::SQLITE_OPEN_NO_MUTEX,
        )?;
        c.busy_timeout(Duration::from_millis(100))?;
        c.execute_batch("PRAGMA query_only=ON; BEGIN DEFERRED;")?;
        let start = Instant::now();
        c.progress_handler(
            1000,
            Some(move || {
                cancel.load(Ordering::Relaxed) || start.elapsed() > Duration::from_secs(2)
            }),
        )?;
        Ok(c)
    }
    pub fn snapshot(
        c: &Connection,
        sources: &BTreeSet<DataSourceId>,
    ) -> Result<HistorySnapshot, StorageError> {
        let mut snapshot = HistorySnapshot::default();
        // Internal insertion watermarks only, never returned or counted for tenants.
        // MAX(rowid) is a table-tail lookup, not a scan of source history.
        let _ = sources;
        for (i, table) in [
            "collection_events",
            "observations",
            "data_gaps",
            "source_health_history",
        ]
        .into_iter()
        .enumerate()
        {
            snapshot.highwater[i] = c.query_row(
                &format!("SELECT COALESCE(max(rowid),0) FROM {table}"),
                [],
                |r| r.get(0),
            )?;
        }
        Ok(snapshot)
    }
    pub fn read(
        c: &Connection,
        kind: HistoryKind,
        sources: &BTreeSet<DataSourceId>,
        q: &DiagnosticQuery,
        snapshot: &HistorySnapshot,
        position: &HistoryPosition,
        limit: usize,
    ) -> Result<HistoryRows, StorageError> {
        let (i, table, source_col, time, key, cols) = match kind {
            HistoryKind::Events => (
                0,
                "collection_events",
                "data_source_id",
                "at_ms",
                "event_key",
                "origin_class,payload_json,observation_key,gap_key",
            ),
            HistoryKind::Observations => (
                1,
                "observations",
                "data_source_id",
                "received_ts_ms",
                "observation_key",
                "payload_json",
            ),
            HistoryKind::Gaps => (
                2,
                "data_gaps",
                "data_source_id",
                "started_at_ms",
                "gap_key",
                "origin_class,ended_at_ms,reason",
            ),
            HistoryKind::Health => (
                3,
                "source_health_history",
                "source_id",
                "at_ms",
                "id",
                "payload_json",
            ),
        };
        let mut result = Vec::new();
        let mut read_bytes = 0usize;
        for source in sources {
            // Per-source indexed keyset reads bound work and memory before cross-source merge.
            let bounded_payload =
                "CASE WHEN octet_length(payload_json)<=65536 THEN payload_json ELSE NULL END";
            let bounded_reason = "CASE WHEN octet_length(reason)<=65536 THEN reason ELSE NULL END";
            let cols = cols
                .replace("payload_json", bounded_payload)
                .replace("reason", bounded_reason);
            let mut sql=format!("SELECT {key},{time},{cols} FROM {table} WHERE {source_col}=?1 AND {time}>=?2 AND {time}<=?3 AND rowid<=?4 AND ({time},{key})>(?5,?6)");
            let mut params: Vec<rusqlite::types::Value> = vec![
                source.as_str().to_owned().into(),
                q.start_ms.unwrap_or(i64::MIN).into(),
                q.end_ms.unwrap_or(i64::MAX).into(),
                snapshot.highwater[i].into(),
                position.at_ms.into(),
                position.key.clone().into(),
            ];
            if let Some(id) = &q.event_id {
                if kind == HistoryKind::Events {
                    sql.push_str(" AND event_key=?");
                    params.push(id.clone().into());
                }
            }
            if let Some(metric) = &q.metric {
                if kind == HistoryKind::Observations {
                    sql.push_str(" AND metric_id=?");
                    params.push(metric.as_str().to_owned().into());
                }
            }
            if let Some(k) = q.event_type {
                if kind == HistoryKind::Events {
                    // DataLoss shares the legacy SQL kind subscription_error. JSON variant distinguishes it safely.
                    let db = match k {
                        CollectionEventKind::Observation => "observation",
                        CollectionEventKind::ConnectionLost => "connection_lost",
                        CollectionEventKind::Reconnected => "reconnected",
                        CollectionEventKind::SubscriptionError | CollectionEventKind::DataLoss => {
                            "subscription_error"
                        }
                    };
                    sql.push_str(" AND kind=?");
                    params.push(db.to_owned().into());
                    if k == CollectionEventKind::DataLoss {
                        sql.push_str(" AND gap_key IS NOT NULL");
                    }
                    if k == CollectionEventKind::SubscriptionError {
                        sql.push_str(" AND gap_key IS NULL");
                    }
                }
            }
            sql.push_str(&format!(" ORDER BY {time},{key} LIMIT ?"));
            params.push((((limit + 1).min(101)) as i64).into());
            let mut st = c.prepare(&sql)?;
            let mut rows = st.query(rusqlite::params_from_iter(params))?;
            while let Some(row) = rows.next()? {
                let id: String = row.get(0)?;
                let at_ms: i64 = row.get(1)?;
                let item = match kind {
                    HistoryKind::Events => {
                        let origin: String = row.get(2)?;
                        let payload = bounded_text(row, 3, &mut read_bytes)?;
                        let mut event: ClientEvent = serde_json::from_str(&payload)?;
                        if q.event_type
                            .is_some_and(|k| k != CollectionEventKind::of(&event))
                        {
                            return Err(StorageError::Hierarchy("inconsistent event kind"));
                        }
                        if let ClientEvent::Observation(o) = &mut event {
                            o.freshness = Freshness::Stale;
                        }
                        DiagnosticItem::Event(Box::new(DiagnosticEvent {
                            id,
                            source: source.clone(),
                            origin: decode_context(source.as_str(), &origin)?.origin_class,
                            at_ms,
                            kind: CollectionEventKind::of(&event),
                            event,
                            observation_id: row.get(4)?,
                            gap_id: row.get(5)?,
                        }))
                    }
                    HistoryKind::Observations => {
                        let payload = bounded_text(row, 2, &mut read_bytes)?;
                        let mut observation: ObservationEnvelope = serde_json::from_str(&payload)?;
                        observation.freshness = Freshness::Stale;
                        DiagnosticItem::Observation(Box::new(HistoricalObservation {
                            id,
                            observation,
                        }))
                    }
                    HistoryKind::Gaps => {
                        let origin: String = row.get(2)?;
                        DiagnosticItem::Gap(CollectionGap {
                            id,
                            source: source.clone(),
                            origin: decode_context(source.as_str(), &origin)?.origin_class,
                            documented_start_ms: at_ms,
                            documented_end_ms: row.get(3)?,
                            reason: bounded_text(row, 4, &mut read_bytes)?,
                        })
                    }
                    HistoryKind::Health => {
                        let payload = bounded_text(row, 2, &mut read_bytes)?;
                        DiagnosticItem::Health(serde_json::from_str(&payload)?)
                    }
                };
                result.push((
                    HistoryPosition {
                        at_ms,
                        key: row.get(0)?,
                    },
                    item,
                ));
            }
        }
        result.sort_by(|a, b| (a.0.at_ms, &a.0.key).cmp(&(b.0.at_ms, &b.0.key)));
        let more = result.len() > limit;
        result.truncate(limit);
        Ok(HistoryRows { rows: result, more })
    }
}

fn bounded_text(
    row: &rusqlite::Row<'_>,
    column: usize,
    bytes: &mut usize,
) -> Result<String, StorageError> {
    let text: Option<String> = row.get(column)?;
    let text = text.ok_or(StorageError::HistoryLimit)?;
    *bytes = bytes
        .checked_add(text.len())
        .ok_or(StorageError::HistoryLimit)?;
    if *bytes > 512 * 1024 {
        return Err(StorageError::HistoryLimit);
    }
    Ok(text)
}

#[cfg(test)]
mod tests {
    use super::*;
    fn ctx() -> EventContext {
        EventContext {
            data_source_id: DataSourceId::new("s").unwrap(),
            origin_class: OriginClass::Simulation,
        }
    }
    fn add(db: &mut SqliteStore, at: i64, reason: &str) {
        db.ingest_event(
            &ctx(),
            &ClientEvent::ConnectionLost {
                at: Timestamp::from_unix_millis(at),
                reason: reason.into(),
            },
        )
        .unwrap();
    }
    fn ids(rows: &HistoryRows) -> Vec<String> {
        rows.rows.iter().map(|r| r.0.key.clone()).collect()
    }
    #[test]
    fn keyset_snapshot_excludes_backfill_and_duplicate_pages() {
        let mut db = SqliteStore::open_in_memory().unwrap();
        for i in 0..9 {
            add(&mut db, 100 + i / 3, &format!("r{i}"));
        }
        let sources = [ctx().data_source_id].into();
        let snap = HistoryReader::snapshot(&db.connection, &sources).unwrap();
        let q = DiagnosticQuery::default();
        let first = HistoryReader::read(
            &db.connection,
            HistoryKind::Events,
            &sources,
            &q,
            &snap,
            &HistoryPosition {
                at_ms: -1,
                key: String::new(),
            },
            3,
        )
        .unwrap();
        assert!(first.more);
        add(&mut db, 100, "backfill");
        add(&mut db, 103, "later");
        let second = HistoryReader::read(
            &db.connection,
            HistoryKind::Events,
            &sources,
            &q,
            &snap,
            &first.rows.last().unwrap().0,
            100,
        )
        .unwrap();
        assert!(!second.more);
        let all = ids(&first)
            .into_iter()
            .chain(ids(&second))
            .collect::<BTreeSet<_>>();
        assert_eq!(all.len(), 9);
        let again = HistoryReader::read(
            &db.connection,
            HistoryKind::Events,
            &sources,
            &q,
            &snap,
            &HistoryPosition {
                at_ms: -1,
                key: String::new(),
            },
            3,
        )
        .unwrap();
        assert_eq!(ids(&first), ids(&again));
    }
    #[test]
    fn schema3_upgrade_preserves_historical_keys_and_atomic_failure() {
        let c = Connection::open_in_memory().unwrap();
        c.pragma_update(None, "foreign_keys", true).unwrap();
        let mut db = SqliteStore { connection: c };
        db.migrate_to(3).unwrap();
        add(&mut db, 10, "original");
        let key: String = db
            .connection
            .query_row("select event_key from collection_events", [], |r| r.get(0))
            .unwrap();
        db.connection
            .execute_batch("CREATE TABLE source_health_history (conflict TEXT)")
            .unwrap();
        assert!(db.migrate().is_err());
        assert_eq!(db.schema_version().unwrap(), 3);
        assert_eq!(
            db.connection
                .query_row(
                    "select count(*) from sqlite_master where name='history_events'",
                    [],
                    |r| r.get::<_, i64>(0)
                )
                .unwrap(),
            0
        );
        db.connection
            .execute_batch("DROP TABLE source_health_history")
            .unwrap();
        assert_eq!(db.migrate().unwrap(), 5);
        assert_eq!(db.migrate().unwrap(), 5);
        assert_eq!(
            db.connection
                .query_row("select event_key from collection_events", [], |r| r
                    .get::<_, String>(0))
                .unwrap(),
            key
        );
        assert_eq!(
            db.connection
                .query_row("pragma integrity_check", [], |r| r.get::<_, String>(0))
                .unwrap(),
            "ok"
        );
    }
    #[test]
    fn gaps_and_loss_are_honest_distinct_from_subscription_errors() {
        let mut db = SqliteStore::open_in_memory().unwrap();
        let gap = DataGap {
            started_at: Timestamp::from_unix_millis(20),
            ended_at: Timestamp::from_unix_millis(20),
            reason: "unknown duration marker".into(),
        };
        db.ingest_event(
            &ctx(),
            &ClientEvent::DataLoss {
                at: Timestamp::from_unix_millis(20),
                gap,
                dropped: 1,
            },
        )
        .unwrap();
        db.ingest_event(
            &ctx(),
            &ClientEvent::SubscriptionError {
                at: Timestamp::from_unix_millis(20),
                reason: "error".into(),
            },
        )
        .unwrap();
        let sources = [ctx().data_source_id].into();
        let snap = HistoryReader::snapshot(&db.connection, &sources).unwrap();
        let position = HistoryPosition {
            at_ms: -1,
            key: String::new(),
        };
        for kind in [
            CollectionEventKind::DataLoss,
            CollectionEventKind::SubscriptionError,
        ] {
            let q = DiagnosticQuery {
                event_type: Some(kind),
                ..Default::default()
            };
            let result = HistoryReader::read(
                &db.connection,
                HistoryKind::Events,
                &sources,
                &q,
                &snap,
                &position,
                100,
            )
            .unwrap();
            assert_eq!(result.rows.len(), 1);
            let DiagnosticItem::Event(e) = &result.rows[0].1 else {
                panic!()
            };
            assert_eq!(e.kind, kind);
        }
        let rows = HistoryReader::read(
            &db.connection,
            HistoryKind::Gaps,
            &sources,
            &DiagnosticQuery::default(),
            &snap,
            &position,
            100,
        )
        .unwrap();
        let DiagnosticItem::Gap(g) = &rows.rows[0].1 else {
            panic!()
        };
        assert_eq!(g.documented_start_ms, g.documented_end_ms);
    }
    #[test]
    fn history_uses_receive_time_and_marks_stale_without_altering_provenance() {
        let mut db = SqliteStore::open_in_memory().unwrap();
        let o = ObservationEnvelope {
            entity_id: EntityId::new("e").unwrap(),
            data_source_id: ctx().data_source_id,
            metric_id: MetricId::new("t").unwrap(),
            value: None,
            unit: Unit::None,
            quality: DataQuality::Bad,
            freshness: Freshness::Unknown,
            timestamps: Timestamps {
                source: Timestamp::from_unix_millis(10),
                server: Some(Timestamp::from_unix_millis(15)),
                received: Some(Timestamp::from_unix_millis(100)),
            },
            status_code: None,
            collection_error: None,
            simulation_origin: Some(SimulationOrigin {
                origin_id: "fixture".into(),
                seed: None,
                scenario: None,
                virtual_time_ms: None,
                sequence: None,
            }),
        };
        db.ingest_event(
            &EventContext::for_observation(&o),
            &ClientEvent::Observation(Box::new(o.clone())),
        )
        .unwrap();
        let sources = [o.data_source_id.clone()].into();
        let snap = HistoryReader::snapshot(&db.connection, &sources).unwrap();
        let rows = HistoryReader::read(
            &db.connection,
            HistoryKind::Observations,
            &sources,
            &DiagnosticQuery {
                start_ms: Some(90),
                end_ms: Some(110),
                ..Default::default()
            },
            &snap,
            &HistoryPosition {
                at_ms: -1,
                key: String::new(),
            },
            100,
        )
        .unwrap();
        let DiagnosticItem::Observation(h) = &rows.rows[0].1 else {
            panic!()
        };
        assert_eq!(h.observation.value, None);
        assert_eq!(h.observation.timestamps, o.timestamps);
        assert_eq!(h.observation.quality, DataQuality::Bad);
        assert_eq!(h.observation.freshness, Freshness::Stale);
    }
    #[test]
    fn indexed_source_time_queries_and_cancellation() {
        let db = SqliteStore::open_in_memory().unwrap();
        for (sql,index) in [("SELECT event_key FROM collection_events WHERE data_source_id='s' AND at_ms>=0 ORDER BY at_ms,event_key LIMIT 10","history_events"),("SELECT observation_key FROM observations WHERE data_source_id='s' AND received_ts_ms>=0 ORDER BY received_ts_ms,observation_key LIMIT 10","history_observations_receive"),("SELECT gap_key FROM data_gaps WHERE data_source_id='s' AND started_at_ms>=0 ORDER BY started_at_ms,gap_key LIMIT 10","history_gaps")] {
   let mut s=db.connection.prepare(&format!("EXPLAIN QUERY PLAN {sql}")).unwrap();let plan=s.query_map([],|r|r.get::<_,String>(3)).unwrap().collect::<Result<Vec<_>,_>>().unwrap().join(" ");assert!(plan.contains(index),"{plan}");
  }
        db.connection.progress_handler(1, Some(|| true)).unwrap();
        assert!(db.connection.query_row("WITH RECURSIVE n(x) AS (VALUES(0) UNION ALL SELECT x+1 FROM n WHERE x<100000) SELECT sum(x) FROM n",[],|r|r.get::<_,i64>(0)).is_err());
    }
}

#[cfg(test)]
mod byte_tests {
    use super::*;
    #[test]
    fn oversized_and_cumulative_payloads_are_bounded_before_deserialization() {
        let mut db = SqliteStore::open_in_memory().unwrap();
        let source = DataSourceId::new("large").unwrap();
        let ctx = EventContext {
            data_source_id: source.clone(),
            origin_class: OriginClass::Simulation,
        };
        db.ingest_event(
            &ctx,
            &ClientEvent::ConnectionLost {
                at: Timestamp::from_unix_millis(1),
                reason: "x".repeat(70000),
            },
        )
        .unwrap();
        let sources = [source].into();
        let snap = HistoryReader::snapshot(&db.connection, &sources).unwrap();
        assert!(matches!(
            HistoryReader::read(
                &db.connection,
                HistoryKind::Events,
                &sources,
                &DiagnosticQuery::default(),
                &snap,
                &HistoryPosition::default(),
                1
            ),
            Err(StorageError::HistoryLimit)
        ));
        let filtered = DiagnosticQuery {
            event_type: Some(CollectionEventKind::ConnectionLost),
            ..Default::default()
        };
        assert!(matches!(
            HistoryReader::read(
                &db.connection,
                HistoryKind::Events,
                &sources,
                &filtered,
                &snap,
                &HistoryPosition::default(),
                1
            ),
            Err(StorageError::HistoryLimit)
        ));
        db.connection
            .execute_batch("DELETE FROM control_event_index; DELETE FROM collection_events;")
            .unwrap();
        for i in 1..20 {
            db.ingest_event(
                &ctx,
                &ClientEvent::ConnectionLost {
                    at: Timestamp::from_unix_millis(i),
                    reason: "x".repeat(60000),
                },
            )
            .unwrap();
        }
        let snap = HistoryReader::snapshot(&db.connection, &sources).unwrap();
        assert!(matches!(
            HistoryReader::read(
                &db.connection,
                HistoryKind::Events,
                &sources,
                &DiagnosticQuery::default(),
                &snap,
                &HistoryPosition::default(),
                100
            ),
            Err(StorageError::HistoryLimit)
        ));
    }
}

#[cfg(test)]
mod negative_time_tests {
    use super::*;
    #[test]
    fn exact_event_and_unfiltered_history_preserve_negative_and_invalid_sentinel_times() {
        let mut db = SqliteStore::open_in_memory().unwrap();
        let source = DataSourceId::new("s").unwrap();
        let ctx = EventContext {
            data_source_id: source.clone(),
            origin_class: OriginClass::Simulation,
        };
        for at in [i64::MIN, -1, 1] {
            db.ingest_event(
                &ctx,
                &ClientEvent::ConnectionLost {
                    at: Timestamp::from_unix_millis(at),
                    reason: "retained timestamp fixture".into(),
                },
            )
            .unwrap();
        }
        let sources = [source].into();
        let snap = HistoryReader::snapshot(&db.connection, &sources).unwrap();
        let all = HistoryReader::read(
            &db.connection,
            HistoryKind::Events,
            &sources,
            &DiagnosticQuery::default(),
            &snap,
            &HistoryPosition::default(),
            100,
        )
        .unwrap();
        assert_eq!(all.rows.len(), 3);
        let key = all.rows[0].0.key.clone();
        let one = HistoryReader::read(
            &db.connection,
            HistoryKind::Events,
            &sources,
            &DiagnosticQuery {
                event_id: Some(key),
                ..Default::default()
            },
            &snap,
            &HistoryPosition::default(),
            1,
        )
        .unwrap();
        assert_eq!(one.rows[0].0.at_ms, i64::MIN);
    }
}

#[cfg(test)]
mod cancellation_tests {
    use super::*;
    #[test]
    fn actual_read_connection_cancellation_interrupts_sqlite_work() {
        let path =
            std::env::temp_dir().join(format!("oip0082-read-cancel-{}.sqlite", std::process::id()));
        assert!(!path.exists());
        let db = SqliteStore::open(&path).unwrap();
        let reader = db.history_reader().unwrap().unwrap();
        let cancel = Arc::new(AtomicBool::new(true));
        let connection = reader.open(cancel).unwrap();
        let result=connection.query_row("WITH RECURSIVE n(x) AS (VALUES(0) UNION ALL SELECT x+1 FROM n WHERE x<1000000) SELECT sum(x) FROM n",[],|r|r.get::<_,i64>(0));
        assert!(
            matches!(result,Err(rusqlite::Error::SqliteFailure(e,_)) if e.code==rusqlite::ErrorCode::OperationInterrupted)
        );
        drop(connection);
        drop(db);
        std::fs::remove_file(path).unwrap();
    }
}

#[cfg(test)]
mod deadline_tests {
    use super::*;
    #[test]
    fn actual_read_connection_enforces_its_sql_deadline() {
        let path = std::env::temp_dir().join(format!(
            "oip0082-read-deadline-{}.sqlite",
            std::process::id()
        ));
        assert!(!path.exists());
        let db = SqliteStore::open(&path).unwrap();
        let reader = db.history_reader().unwrap().unwrap();
        let connection = reader.open(Arc::new(AtomicBool::new(false))).unwrap();
        let start = Instant::now();
        let result=connection.query_row("WITH RECURSIVE n(x) AS (VALUES(0) UNION ALL SELECT x+1 FROM n WHERE x<100000000) SELECT sum(x) FROM n",[],|r|r.get::<_,i64>(0));
        assert!(
            matches!(result,Err(rusqlite::Error::SqliteFailure(e,_)) if e.code==rusqlite::ErrorCode::OperationInterrupted)
        );
        assert!(start.elapsed() < Duration::from_secs(4));
        drop(connection);
        drop(db);
        std::fs::remove_file(path).unwrap();
    }
}
