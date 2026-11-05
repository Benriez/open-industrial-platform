use super::*;

impl oip_core::CoreRepository for SqliteStore {
    fn definitions(&self) -> Result<Vec<oip_core::SourceDefinition>, oip_core::PersistenceFailure> {
        let mut q = self
            .connection
            .prepare("SELECT payload_json FROM core_sources ORDER BY source_id")
            .map_err(|_| "read_sources")?;
        let result = q
            .query_map([], |r| r.get::<_, String>(0))
            .map_err(|_| "read_sources")?
            .map(|r| {
                serde_json::from_str(&r.map_err(|_| "read_sources")?)
                    .map_err(|_| "decode_sources".into())
            })
            .collect();
        result
    }
    fn register(
        &mut self,
        d: &oip_core::SourceDefinition,
    ) -> Result<(), oip_core::PersistenceFailure> {
        let payload = serde_json::to_string(d).map_err(|_| "encode_source")?;
        self.connection
            .execute(
                "INSERT INTO core_sources VALUES (?1,?2) ON CONFLICT(source_id) DO NOTHING",
                params![d.id.as_str(), payload],
            )
            .map_err(|_| "register_source")?;
        Ok(())
    }
    fn restore_latest(&self) -> Result<Vec<ObservationEnvelope>, oip_core::PersistenceFailure> {
        // Bounded by distinct metric identities, not by historical row count.
        let mut q=self.connection.prepare("SELECT payload_json FROM observations WHERE rowid IN (SELECT max(rowid) FROM observations GROUP BY data_source_id,entity_id,metric_id) AND NOT EXISTS(SELECT 1 FROM core_latest c WHERE c.source_id=observations.data_source_id AND c.entity_id=observations.entity_id AND c.metric_id=observations.metric_id) UNION ALL SELECT payload_json FROM core_latest").map_err(|_|"restore_latest")?;
        let result = q
            .query_map([], |r| r.get::<_, String>(0))
            .map_err(|_| "restore_latest")?
            .map(|r| {
                serde_json::from_str(&r.map_err(|_| "restore_latest")?)
                    .map_err(|_| "decode_latest".into())
            })
            .collect();
        result
    }
    fn recent_events(
        &self,
        limit: usize,
    ) -> Result<Vec<oip_core::EventRecord>, oip_core::PersistenceFailure> {
        let mut q=self.connection.prepare("SELECT rowid,data_source_id,origin_class,payload_json FROM collection_events WHERE kind != 'observation' ORDER BY rowid DESC LIMIT ?1").map_err(|_|"read_events")?;
        let result = q
            .query_map([limit.min(100) as i64], |r| {
                Ok((
                    r.get::<_, i64>(0)?,
                    r.get::<_, String>(1)?,
                    r.get::<_, String>(2)?,
                    r.get::<_, String>(3)?,
                ))
            })
            .map_err(|_| "read_events")?
            .map(|r| {
                let (sequence, source, origin, payload) = r.map_err(|_| "read_events")?;
                Ok(oip_core::EventRecord {
                    sequence,
                    context: decode_context(&source, &origin).map_err(|_| "decode_context")?,
                    event: serde_json::from_str(&payload).map_err(|_| "decode_event")?,
                })
            })
            .collect::<Result<Vec<_>, oip_core::PersistenceFailure>>()?;
        let mut result = result;
        result.reverse();
        Ok(result)
    }
    fn commit(
        &mut self,
        context: &EventContext,
        event: &ClientEvent,
        latest: Option<&ObservationEnvelope>,
    ) -> Result<(IngestOutcome, i64), oip_core::PersistenceFailure> {
        let tx = self.write_transaction().map_err(|_| "begin_transaction")?;
        let outcome = ingest_event_in(&tx, context, event).map_err(|_| "commit_evidence")?;
        if let Some(o) = latest {
            tx.execute("INSERT INTO core_latest VALUES (?1,?2,?3,?4) ON CONFLICT(source_id,entity_id,metric_id) DO UPDATE SET payload_json=excluded.payload_json",params![o.data_source_id.as_str(),o.entity_id.as_str(),o.metric_id.as_str(),serde_json::to_string(o).map_err(|_|"encode_checkpoint")?]).map_err(|_|"write_checkpoint")?;
        }
        let sequence = tx
            .query_row("SELECT max(rowid) FROM collection_events", [], |r| {
                r.get::<_, i64>(0)
            })
            .map_err(|_| "event_sequence")?;
        tx.commit().map_err(|_| "commit_transaction")?;
        Ok((outcome, sequence))
    }
    fn count(&self) -> Result<u64, oip_core::PersistenceFailure> {
        self.observation_count()
            .map_err(|_| "observation_count".into())
    }
    fn start_run(&mut self, at: i64) -> Result<i64, oip_core::PersistenceFailure> {
        self.connection
            .execute(
                "UPDATE core_runs SET result='interrupted' WHERE result='running'",
                [],
            )
            .map_err(|_| "recover_run_journal")?;
        self.connection
            .execute(
                "INSERT INTO core_runs(started_ms,result) VALUES (?1,'running')",
                [at],
            )
            .map_err(|_| "start_run")?;
        self.connection
            .busy_timeout(std::time::Duration::from_millis(100))
            .map_err(|_| "busy_timeout")?;
        Ok(self.connection.last_insert_rowid())
    }
    fn finish_run(
        &mut self,
        id: i64,
        at: i64,
        result: &str,
    ) -> Result<(), oip_core::PersistenceFailure> {
        self.connection
            .execute(
                "UPDATE core_runs SET ended_ms=?1,result=?2 WHERE id=?3",
                params![at, result, id],
            )
            .map_err(|_| "finish_run")?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use oip_core::CoreRepository;
    fn observation() -> ObservationEnvelope {
        ObservationEnvelope {
            entity_id: EntityId::new("test").unwrap(),
            data_source_id: DataSourceId::new("test-source").unwrap(),
            metric_id: MetricId::new("temperature").unwrap(),
            value: Some(MetricValue::Float(4.2)),
            unit: oip_core::Unit::Celsius,
            quality: oip_core::DataQuality::Good,
            freshness: oip_core::Freshness::Fresh,
            timestamps: oip_core::Timestamps {
                source: Timestamp::from_unix_millis(1000),
                server: None,
                received: Some(Timestamp::from_unix_millis(2000)),
            },
            status_code: Some(0),
            collection_error: None,
            simulation_origin: Some(oip_core::SimulationOrigin {
                origin_id: "fixture".into(),
                seed: Some(1),
                scenario: None,
                virtual_time_ms: Some(0),
                sequence: Some(0),
            }),
        }
    }
    #[test]
    fn checkpoint_and_event_are_one_atomic_transaction() {
        let mut store = SqliteStore::open_in_memory().unwrap();
        let o = observation();
        let context = EventContext::for_observation(&o);
        let event = ClientEvent::Observation(Box::new(o.clone()));
        store.connection.execute_batch("CREATE TRIGGER fail_checkpoint BEFORE INSERT ON core_latest BEGIN SELECT RAISE(ABORT,'injected checkpoint failure'); END;").unwrap();
        assert!(store.commit(&context, &event, Some(&o)).is_err());
        assert_eq!(store.observation_count().unwrap(), 0);
        assert_eq!(store.event_count().unwrap(), 0);
        store
            .connection
            .execute_batch("DROP TRIGGER fail_checkpoint")
            .unwrap();
        store.commit(&context, &event, Some(&o)).unwrap();
        assert_eq!(store.observation_count().unwrap(), 1);
        assert_eq!(store.restore_latest().unwrap(), vec![o]);
    }
    #[test]
    fn valid_version_one_database_upgrades_without_losing_evidence() {
        let mut store = SqliteStore::open_in_memory().unwrap();
        store.ingest_observation(&observation()).unwrap();
        // Test-owned fixture: exactly the prior release's tables and migration record.
        store.connection.execute_batch("DROP TABLE core_sources; DROP TABLE core_latest; DROP TABLE core_runs; DELETE FROM schema_migrations WHERE version=2; PRAGMA user_version=1;").unwrap();
        assert_eq!(store.migrate().unwrap(), 2);
        assert_eq!(store.observation_count().unwrap(), 1);
        assert_eq!(store.restore_latest().unwrap(), vec![observation()]);
        assert_eq!(store.migrate().unwrap(), 2);
    }
}
