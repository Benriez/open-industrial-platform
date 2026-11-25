//! Versioned SQLite evidence storage for stack-neutral OIP observations.

use oip_core::{
    ClientEvent, DataGap, DataSourceId, EntityId, EventContext, MetricId, MetricValue,
    ObservationEnvelope, OriginClass, Timestamp,
};
pub use oip_core::{
    EventRepository, EventSink, IngestOutcome, ObservationRepository, ObservationSink, StoredEvent,
    StoredGap, StoredObservation,
};
use rusqlite::{params, Connection, OptionalExtension, Transaction, TransactionBehavior};
use serde::Serialize;
use sha2::{Digest, Sha256};
use std::path::Path;
use thiserror::Error;
mod connection;
mod device_sources;
mod history;
mod inventory;
mod settings;
pub use history::*;
mod ownership;
pub use ownership::DatabaseOwnership;
mod hierarchy;
pub use hierarchy::{LegacyAdoption, ProvisioningResult};

#[derive(Clone, Copy)]
struct Migration {
    version: u32,
    name: &'static str,
    sql: &'static str,
}

const INITIAL_SQL: &str = r#"
CREATE TABLE IF NOT EXISTS source_identities (
    data_source_id TEXT PRIMARY KEY,
    origin_class TEXT NOT NULL CHECK(origin_class IN ('simulation', 'external'))
) STRICT;
CREATE TABLE IF NOT EXISTS device_identities (
    entity_id TEXT NOT NULL,
    data_source_id TEXT NOT NULL REFERENCES source_identities(data_source_id),
    PRIMARY KEY(entity_id, data_source_id)
) STRICT;
CREATE TABLE IF NOT EXISTS observations (
    observation_key TEXT PRIMARY KEY,
    entity_id TEXT NOT NULL,
    data_source_id TEXT NOT NULL,
    metric_id TEXT NOT NULL,
    source_ts_ms INTEGER NOT NULL,
    server_ts_ms INTEGER,
    received_ts_ms INTEGER,
    quality TEXT NOT NULL,
    freshness TEXT NOT NULL,
    collection_error TEXT,
    origin_class TEXT NOT NULL CHECK(origin_class IN ('simulation', 'external')),
    payload_json TEXT NOT NULL,
    duplicate_count INTEGER NOT NULL DEFAULT 0 CHECK(duplicate_count >= 0),
    FOREIGN KEY(entity_id, data_source_id)
        REFERENCES device_identities(entity_id, data_source_id)
) STRICT;
CREATE INDEX IF NOT EXISTS observations_by_device_source_metric_time
    ON observations(entity_id, data_source_id, metric_id, source_ts_ms DESC);
CREATE TABLE IF NOT EXISTS data_gaps (
    gap_key TEXT PRIMARY KEY,
    data_source_id TEXT NOT NULL REFERENCES source_identities(data_source_id),
    origin_class TEXT NOT NULL CHECK(origin_class IN ('simulation', 'external')),
    started_at_ms INTEGER NOT NULL,
    ended_at_ms INTEGER NOT NULL,
    reason TEXT NOT NULL,
    duplicate_count INTEGER NOT NULL DEFAULT 0 CHECK(duplicate_count >= 0)
) STRICT;
CREATE TABLE IF NOT EXISTS collection_events (
    event_key TEXT PRIMARY KEY,
    data_source_id TEXT NOT NULL REFERENCES source_identities(data_source_id),
    origin_class TEXT NOT NULL CHECK(origin_class IN ('simulation', 'external')),
    kind TEXT NOT NULL CHECK(kind IN
        ('observation', 'connection_lost', 'reconnected', 'subscription_error')),
    at_ms INTEGER NOT NULL,
    observation_key TEXT REFERENCES observations(observation_key),
    gap_key TEXT REFERENCES data_gaps(gap_key),
    payload_json TEXT NOT NULL,
    duplicate_count INTEGER NOT NULL DEFAULT 0 CHECK(duplicate_count >= 0)
) STRICT;
CREATE INDEX IF NOT EXISTS collection_events_by_source_time
    ON collection_events(data_source_id, at_ms, kind);
"#;

// Append only. Never edit an applied migration; add a new version instead.
const MIGRATIONS: &[Migration] = &[
    // Applied in version order below.
    Migration {
        version: 1,
        name: "initial_observation_event_evidence",
        sql: INITIAL_SQL,
    },
    Migration {
        version: 2,
        name: "core_registration_checkpoints_runs",
        sql: r#"
 CREATE TABLE core_sources (source_id TEXT PRIMARY KEY, payload_json TEXT NOT NULL) STRICT;
 CREATE TABLE core_latest (source_id TEXT NOT NULL, entity_id TEXT NOT NULL, metric_id TEXT NOT NULL, payload_json TEXT NOT NULL, PRIMARY KEY(source_id,entity_id,metric_id)) STRICT;
 CREATE TABLE core_runs (id INTEGER PRIMARY KEY, started_ms INTEGER NOT NULL, ended_ms INTEGER, result TEXT NOT NULL) STRICT;
 "#,
    },
    Migration {
        version: 3,
        name: "hierarchy_identity_control_sequences",
        sql: hierarchy::HIERARCHY_SQL,
    },
    Migration {
        version: 4,
        name: "diagnostic_history_indexes_health",
        sql: history::HISTORY_SQL,
    },
    Migration {
        version: 5,
        name: "typed_application_settings",
        sql: settings::SETTINGS_SQL,
    },
    Migration {
        version: 6,
        name: "independent_device_inventory",
        sql: inventory::INVENTORY_SQL,
    },
    Migration {
        version: 7,
        name: "verified_device_connections",
        sql: connection::CONNECTION_SQL,
    },
    Migration {
        version: 8,
        name: "declared_service_inventory",
        sql: hierarchy::SERVICES_SQL,
    },
];

#[derive(Debug, Error)]
pub enum StorageError {
    #[error("Historical evidence byte limit exceeded; narrow the query")]
    HistoryLimit,
    #[error("local storage ownership I/O failed")]
    Io(#[from] std::io::Error),
    #[error("{0}")]
    Hierarchy(&'static str),
    #[error("SQLite operation failed: {0}")]
    Sqlite(#[from] rusqlite::Error),
    #[error("stored payload cannot be decoded: {0}")]
    Serialization(#[from] serde_json::Error),
    #[error("non-finite floating point values cannot be persisted losslessly")]
    NonFiniteFloat,
    #[error("source {0} was already registered with another origin class")]
    OriginClassConflict(String),
    #[error("event context does not match the carried observation")]
    EventSourceMismatch,
    #[error("identifier is empty or not in canonical trimmed form")]
    InvalidIdentifier,
    #[error("enum did not serialize to its snake_case name")]
    InvalidEnumSerialization,
    #[error("migration {version} checksum or name mismatch")]
    MigrationChecksumMismatch { version: u32 },
    #[error("database schema version {found} is newer than supported version {supported}")]
    UnsupportedSchemaVersion { found: u32, supported: u32 },
    #[error("PRAGMA user_version {pragma} differs from migration table version {table}")]
    SchemaVersionMismatch { pragma: u32, table: u32 },
    #[error("stored counter is outside the supported unsigned range")]
    CounterOutOfRange,
}

pub struct SqliteStore {
    connection: Connection,
}

impl SqliteStore {
    pub fn open(path: impl AsRef<Path>) -> Result<Self, StorageError> {
        Self::from_connection(Connection::open(path)?)
    }

    pub fn open_in_memory() -> Result<Self, StorageError> {
        Self::from_connection(Connection::open_in_memory()?)
    }

    fn from_connection(connection: Connection) -> Result<Self, StorageError> {
        connection.execute_batch(
            "PRAGMA foreign_keys = ON;
             PRAGMA busy_timeout = 5000;
             PRAGMA journal_mode = WAL;
             PRAGMA synchronous = FULL;",
        )?;
        let mut store = Self { connection };
        store.migrate()?;
        Ok(store)
    }

    fn write_transaction(&mut self) -> Result<Transaction<'_>, StorageError> {
        Ok(self
            .connection
            .transaction_with_behavior(TransactionBehavior::Immediate)?)
    }

    pub fn migrate(&mut self) -> Result<u32, StorageError> {
        self.migrate_to(8)
    }
    fn migrate_to(&mut self, maximum: u32) -> Result<u32, StorageError> {
        // Validate history BEFORE any DDL. A corrupt migration ledger must never
        // be "repaired" by applying earlier migrations over existing data.
        let initial = self.pragma_version()?;
        let supported = MIGRATIONS.last().map_or(0, |m| m.version);
        if initial > supported {
            return Err(StorageError::UnsupportedSchemaVersion {
                found: initial,
                supported,
            });
        }
        let history: bool = self.connection.query_row(
            "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE name='schema_migrations')",
            [],
            |r| r.get(0),
        )?;
        if initial > 0 && !history {
            return Err(StorageError::Hierarchy(
                "missing migration history; restore a verified backup",
            ));
        }
        if history {
            let (version, count, minimum): (u32, u32, i64) = self.connection.query_row(
                "SELECT COALESCE(MAX(version),0),count(*),COALESCE(MIN(version),0) FROM schema_migrations",
                [],
                |r| Ok((r.get(0)?, r.get(1)?,r.get(2)?)),
            )?;
            if version != initial {
                return Err(StorageError::SchemaVersionMismatch {
                    pragma: initial,
                    table: version,
                });
            }
            if count != version || (version > 0 && minimum != 1) {
                return Err(StorageError::Hierarchy(
                    "incomplete migration history; restore a verified backup",
                ));
            }
        }
        if maximum >= 3 && initial == 1 {
            return Err(StorageError::Hierarchy(
                "schema1 requires a separately verified OIP-007 upgrade before adoption",
            ));
        }
        if initial==0 && self.connection.query_row("SELECT count(*) FROM sqlite_master WHERE type='table' AND name!='schema_migrations' AND name NOT LIKE 'sqlite_%'",[],|r|r.get::<_,i64>(0))?>0 {return Err(StorageError::Hierarchy("unversioned existing database is not an empty installation"));}
        self.connection.execute_batch(
            "CREATE TABLE IF NOT EXISTS schema_migrations (
                version INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                checksum TEXT NOT NULL
            ) STRICT;",
        )?;
        let supported = MIGRATIONS.last().map_or(0, |migration| migration.version);
        let pragma_version = self.pragma_version()?;
        if pragma_version > supported {
            return Err(StorageError::UnsupportedSchemaVersion {
                found: pragma_version,
                supported,
            });
        }
        for migration in MIGRATIONS {
            let applied = self
                .connection
                .query_row(
                    "SELECT name, checksum FROM schema_migrations WHERE version = ?1",
                    [migration.version],
                    |row| Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?)),
                )
                .optional()?;
            let checksum = content_hash(migration.sql.as_bytes());
            if let Some((name, applied_checksum)) = applied {
                if name != migration.name || applied_checksum != checksum {
                    return Err(StorageError::MigrationChecksumMismatch {
                        version: migration.version,
                    });
                }
                continue;
            }
            if migration.version > maximum {
                continue;
            }
            if migration.version == 3
                && [
                    "observations",
                    "core_sources",
                    "collection_events",
                    "data_gaps",
                    "source_identities",
                    "core_latest",
                ]
                .iter()
                .try_fold(0i64, |sum, table| {
                    self.connection
                        .query_row(&format!("SELECT count(*) FROM {table}"), [], |r| {
                            r.get::<_, i64>(0)
                        })
                        .map(|n| sum + n)
                })? > 0
            {
                return Err(StorageError::Hierarchy(
                    "legacy database requires explicit offline provisioning/adoption",
                ));
            }
            let transaction = self.write_transaction()?;
            if migration.version == 6 {
                let invalid:i64=transaction.query_row("SELECT count(*) FROM core_sources WHERE octet_length(json_extract(payload_json,'$.name'))>16384 OR length(trim(json_extract(payload_json,'$.name')))=0",[],|r|r.get(0))?;
                if invalid != 0 {
                    return Err(StorageError::Hierarchy("Legacy source names require explicit operator review; migration6 not applied"));
                }
            }
            transaction.execute_batch(migration.sql)?;
            transaction.execute(
                "INSERT INTO schema_migrations(version, name, checksum) VALUES (?1, ?2, ?3)",
                params![migration.version, migration.name, checksum],
            )?;
            transaction.execute_batch(&format!("PRAGMA user_version = {}", migration.version))?;
            transaction.commit()?;
        }
        let table_version = self.connection.query_row(
            "SELECT COALESCE(MAX(version), 0) FROM schema_migrations",
            [],
            |row| row.get::<_, u32>(0),
        )?;
        if table_version > supported {
            return Err(StorageError::UnsupportedSchemaVersion {
                found: table_version,
                supported,
            });
        }
        let pragma_version = self.pragma_version()?;
        if pragma_version != table_version {
            return Err(StorageError::SchemaVersionMismatch {
                pragma: pragma_version,
                table: table_version,
            });
        }
        Ok(table_version)
    }

    fn pragma_version(&self) -> Result<u32, StorageError> {
        Ok(self
            .connection
            .query_row("PRAGMA user_version", [], |row| row.get(0))?)
    }

    pub fn schema_version(&self) -> Result<u32, StorageError> {
        self.connection
            .query_row(
                "SELECT COALESCE(MAX(version), 0) FROM schema_migrations",
                [],
                |row| row.get(0),
            )
            .map_err(Into::into)
    }

    pub fn observation_count(&self) -> Result<u64, StorageError> {
        self.count("observations")
    }

    pub fn event_count(&self) -> Result<u64, StorageError> {
        self.count("collection_events")
    }

    fn count(&self, table: &str) -> Result<u64, StorageError> {
        // Only internal constant table names are supplied.
        let count =
            self.connection
                .query_row(&format!("SELECT COUNT(*) FROM {table}"), [], |row| {
                    row.get::<_, i64>(0)
                })?;
        u64::try_from(count).map_err(|_| StorageError::CounterOutOfRange)
    }

    pub fn observations(&self) -> Result<Vec<StoredObservation>, StorageError> {
        <Self as ObservationRepository>::observations(self)
    }

    pub fn latest_observation(
        &self,
        entity_id: &EntityId,
        data_source_id: &DataSourceId,
        metric_id: &MetricId,
    ) -> Result<Option<ObservationEnvelope>, StorageError> {
        <Self as ObservationRepository>::latest_observation(
            self,
            entity_id,
            data_source_id,
            metric_id,
        )
    }

    pub fn events(&self) -> Result<Vec<StoredEvent>, StorageError> {
        self.query_events(None)
    }

    pub fn events_for_source(
        &self,
        data_source_id: &DataSourceId,
    ) -> Result<Vec<StoredEvent>, StorageError> {
        <Self as EventRepository>::events_for_source(self, data_source_id)
    }

    fn query_events(
        &self,
        data_source_id: Option<&DataSourceId>,
    ) -> Result<Vec<StoredEvent>, StorageError> {
        let mut statement = self.connection.prepare(
            "SELECT data_source_id, origin_class, payload_json, duplicate_count
             FROM collection_events
             WHERE (?1 IS NULL OR data_source_id = ?1) ORDER BY at_ms, rowid",
        )?;
        let rows = statement.query_map([data_source_id.map(DataSourceId::as_str)], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, i64>(3)?,
            ))
        })?;
        rows.map(|row| {
            let (source, origin, payload, duplicates) = row?;
            Ok(StoredEvent {
                context: decode_context(&source, &origin)?,
                event: serde_json::from_str(&payload)?,
                duplicate_count: decode_counter(duplicates)?,
            })
        })
        .collect()
    }

    pub fn gaps(&self) -> Result<Vec<StoredGap>, StorageError> {
        self.query_gaps(None)
    }

    pub fn gaps_for_source(
        &self,
        data_source_id: &DataSourceId,
    ) -> Result<Vec<StoredGap>, StorageError> {
        <Self as EventRepository>::gaps_for_source(self, data_source_id)
    }

    fn query_gaps(
        &self,
        data_source_id: Option<&DataSourceId>,
    ) -> Result<Vec<StoredGap>, StorageError> {
        let mut statement = self.connection.prepare(
            "SELECT data_source_id, origin_class, started_at_ms, ended_at_ms, reason,
                    duplicate_count
             FROM data_gaps
             WHERE (?1 IS NULL OR data_source_id = ?1) ORDER BY started_at_ms, rowid",
        )?;
        let rows = statement.query_map([data_source_id.map(DataSourceId::as_str)], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, i64>(2)?,
                row.get::<_, i64>(3)?,
                row.get::<_, String>(4)?,
                row.get::<_, i64>(5)?,
            ))
        })?;
        rows.map(|row| {
            let (source, origin, started, ended, reason, duplicates) = row?;
            Ok(StoredGap {
                context: decode_context(&source, &origin)?,
                gap: DataGap {
                    started_at: Timestamp::from_unix_millis(started),
                    ended_at: Timestamp::from_unix_millis(ended),
                    reason,
                },
                duplicate_count: decode_counter(duplicates)?,
            })
        })
        .collect()
    }

    pub fn ingest_observation(
        &mut self,
        observation: &ObservationEnvelope,
    ) -> Result<IngestOutcome, StorageError> {
        <Self as ObservationSink>::ingest_observation(self, observation)
    }

    pub fn ingest_event(
        &mut self,
        context: &EventContext,
        event: &ClientEvent,
    ) -> Result<IngestOutcome, StorageError> {
        <Self as EventSink>::ingest_event(self, context, event)
    }

    /// Persists all events and referenced evidence atomically in source order.
    pub fn ingest_batch(
        &mut self,
        context: &EventContext,
        events: &[ClientEvent],
    ) -> Result<usize, StorageError> {
        let transaction = self.write_transaction()?;
        let mut inserted = 0;
        for event in events {
            if ingest_event_in(&transaction, context, event)? == IngestOutcome::Inserted {
                inserted += 1;
            }
        }
        transaction.commit()?;
        Ok(inserted)
    }
}

impl ObservationSink for SqliteStore {
    type Error = StorageError;

    fn ingest_observation(
        &mut self,
        observation: &ObservationEnvelope,
    ) -> Result<IngestOutcome, Self::Error> {
        let transaction = self.write_transaction()?;
        let (_, outcome) = insert_observation(&transaction, observation)?;
        transaction.commit()?;
        Ok(outcome)
    }
}

impl EventSink for SqliteStore {
    type Error = StorageError;

    fn ingest_event(
        &mut self,
        context: &EventContext,
        event: &ClientEvent,
    ) -> Result<IngestOutcome, Self::Error> {
        let transaction = self.write_transaction()?;
        let outcome = ingest_event_in(&transaction, context, event)?;
        transaction.commit()?;
        Ok(outcome)
    }
}

impl EventRepository for SqliteStore {
    type Error = StorageError;

    fn events_for_source(
        &self,
        data_source_id: &DataSourceId,
    ) -> Result<Vec<StoredEvent>, Self::Error> {
        self.query_events(Some(data_source_id))
    }

    fn gaps_for_source(
        &self,
        data_source_id: &DataSourceId,
    ) -> Result<Vec<StoredGap>, Self::Error> {
        self.query_gaps(Some(data_source_id))
    }
}

impl ObservationRepository for SqliteStore {
    type Error = StorageError;

    fn latest_observation(
        &self,
        entity_id: &EntityId,
        data_source_id: &DataSourceId,
        metric_id: &MetricId,
    ) -> Result<Option<ObservationEnvelope>, Self::Error> {
        self.connection
            .query_row(
                "SELECT payload_json FROM observations
                 WHERE entity_id = ?1 AND data_source_id = ?2 AND metric_id = ?3
                 ORDER BY source_ts_ms DESC, observation_key DESC LIMIT 1",
                params![
                    entity_id.as_str(),
                    data_source_id.as_str(),
                    metric_id.as_str()
                ],
                |row| row.get::<_, String>(0),
            )
            .optional()?
            .map(|payload| serde_json::from_str(&payload).map_err(Into::into))
            .transpose()
    }

    fn observations(&self) -> Result<Vec<StoredObservation>, Self::Error> {
        let mut statement = self.connection.prepare(
            "SELECT payload_json, duplicate_count FROM observations
             ORDER BY source_ts_ms, observation_key",
        )?;
        let rows = statement.query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?))
        })?;
        rows.map(|row| {
            let (payload, duplicate_count) = row?;
            Ok(StoredObservation {
                observation: serde_json::from_str(&payload)?,
                duplicate_count: decode_counter(duplicate_count)?,
            })
        })
        .collect()
    }
}

fn validate_observation(observation: &ObservationEnvelope) -> Result<(), StorageError> {
    if matches!(observation.value, Some(MetricValue::Float(value)) if !value.is_finite()) {
        return Err(StorageError::NonFiniteFloat);
    }
    for noncanonical in [
        EntityId::new(observation.entity_id.as_str())
            .map(|id| id.as_str() != observation.entity_id.as_str()),
        DataSourceId::new(observation.data_source_id.as_str())
            .map(|id| id.as_str() != observation.data_source_id.as_str()),
        MetricId::new(observation.metric_id.as_str())
            .map(|id| id.as_str() != observation.metric_id.as_str()),
    ] {
        if noncanonical.unwrap_or(true) {
            return Err(StorageError::InvalidIdentifier);
        }
    }
    Ok(())
}

fn register_source(
    transaction: &Transaction<'_>,
    data_source_id: &DataSourceId,
    origin_class: OriginClass,
) -> Result<(), StorageError> {
    let origin = enum_name(&origin_class)?;
    let existing = transaction
        .query_row(
            "SELECT origin_class FROM source_identities WHERE data_source_id = ?1",
            [data_source_id.as_str()],
            |row| row.get::<_, String>(0),
        )
        .optional()?;
    if existing
        .as_deref()
        .is_some_and(|existing| existing != origin)
    {
        return Err(StorageError::OriginClassConflict(
            data_source_id.as_str().to_owned(),
        ));
    }
    transaction.execute(
        "INSERT INTO source_identities(data_source_id, origin_class) VALUES (?1, ?2)
         ON CONFLICT(data_source_id) DO NOTHING",
        params![data_source_id.as_str(), origin],
    )?;
    Ok(())
}

fn insert_observation(
    transaction: &Transaction<'_>,
    observation: &ObservationEnvelope,
) -> Result<(String, IngestOutcome), StorageError> {
    validate_observation(observation)?;
    let payload = serde_json::to_string(observation)?;
    let key = observation_key(observation)?;
    let duplicate = transaction.query_row(
        "SELECT EXISTS(SELECT 1 FROM observations WHERE observation_key = ?1)",
        [&key],
        |row| row.get::<_, bool>(0),
    )?;
    let origin_class = if observation.simulation_origin.is_some() {
        OriginClass::Simulation
    } else {
        OriginClass::External
    };
    register_source(transaction, &observation.data_source_id, origin_class)?;
    transaction.execute(
        "INSERT INTO device_identities(entity_id, data_source_id) VALUES (?1, ?2)
         ON CONFLICT(entity_id, data_source_id) DO NOTHING",
        params![
            observation.entity_id.as_str(),
            observation.data_source_id.as_str()
        ],
    )?;
    transaction.execute(
        "INSERT INTO observations(
            observation_key, entity_id, data_source_id, metric_id, source_ts_ms,
            server_ts_ms, received_ts_ms, quality, freshness, collection_error,
            origin_class, payload_json
        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)
        ON CONFLICT(observation_key) DO UPDATE SET duplicate_count = duplicate_count + 1",
        params![
            key,
            observation.entity_id.as_str(),
            observation.data_source_id.as_str(),
            observation.metric_id.as_str(),
            observation.timestamps.source.as_unix_millis(),
            observation.timestamps.server.map(Timestamp::as_unix_millis),
            observation
                .timestamps
                .received
                .map(Timestamp::as_unix_millis),
            enum_name(&observation.quality)?,
            enum_name(&observation.freshness)?,
            observation
                .collection_error
                .as_ref()
                .map(enum_name)
                .transpose()?,
            enum_name(&origin_class)?,
            payload,
        ],
    )?;
    Ok((
        key,
        if duplicate {
            IngestOutcome::Duplicate
        } else {
            IngestOutcome::Inserted
        },
    ))
}

fn insert_gap(
    transaction: &Transaction<'_>,
    context: &EventContext,
    gap: &DataGap,
) -> Result<String, StorageError> {
    let payload = serde_json::to_string(gap)?;
    let key = keyed_hash(b"oip-gap-v1\0", context, &payload);
    transaction.execute(
        "INSERT INTO data_gaps(
            gap_key, data_source_id, origin_class, started_at_ms, ended_at_ms, reason
        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6)
        ON CONFLICT(gap_key) DO UPDATE SET duplicate_count = duplicate_count + 1",
        params![
            key,
            context.data_source_id.as_str(),
            enum_name(&context.origin_class)?,
            gap.started_at.as_unix_millis(),
            gap.ended_at.as_unix_millis(),
            gap.reason
        ],
    )?;
    Ok(key)
}

fn ingest_event_in(
    transaction: &Transaction<'_>,
    context: &EventContext,
    event: &ClientEvent,
) -> Result<IngestOutcome, StorageError> {
    if let ClientEvent::Observation(observation) = event {
        if EventContext::for_observation(observation) != *context {
            return Err(StorageError::EventSourceMismatch);
        }
    }
    register_source(transaction, &context.data_source_id, context.origin_class)?;
    let (kind, at, observation_key, gap_key) = match event {
        ClientEvent::Observation(observation) => {
            let (key, _) = insert_observation(transaction, observation)?;
            (
                "observation",
                observation.timestamps.source,
                Some(key),
                None,
            )
        }
        ClientEvent::ConnectionLost { at, .. } => ("connection_lost", *at, None, None),
        ClientEvent::Reconnected { at, gap } => (
            "reconnected",
            *at,
            None,
            Some(insert_gap(transaction, context, gap)?),
        ),
        ClientEvent::SubscriptionError { at, .. } => ("subscription_error", *at, None, None),
        ClientEvent::DataLoss { at, gap, .. } => (
            "subscription_error",
            *at,
            None,
            Some(insert_gap(transaction, context, gap)?),
        ),
    };
    let payload = serde_json::to_string(event)?;
    let key = observation_key.as_ref().map_or_else(
        || keyed_hash(b"oip-event-v1\0", context, &payload),
        |observation_key| keyed_hash(b"oip-event-observation-v1\0", context, observation_key),
    );
    let duplicate = transaction.query_row(
        "SELECT EXISTS(SELECT 1 FROM collection_events WHERE event_key = ?1)",
        [&key],
        |row| row.get::<_, bool>(0),
    )?;
    transaction.execute(
        "INSERT INTO collection_events(
            event_key, data_source_id, origin_class, kind, at_ms,
            observation_key, gap_key, payload_json
        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
        ON CONFLICT(event_key) DO UPDATE SET duplicate_count = duplicate_count + 1",
        params![
            key,
            context.data_source_id.as_str(),
            enum_name(&context.origin_class)?,
            kind,
            at.as_unix_millis(),
            observation_key,
            gap_key,
            payload
        ],
    )?;
    if kind != "observation" && !duplicate {
        transaction.execute("INSERT INTO control_event_heads VALUES(?1,1) ON CONFLICT(source_id) DO UPDATE SET sequence=sequence+1",[context.data_source_id.as_str()])?;
        transaction.execute("INSERT INTO control_event_index SELECT ?1,source_id,sequence FROM control_event_heads WHERE source_id=?2",params![key,context.data_source_id.as_str()])?;
    }
    Ok(if duplicate {
        IngestOutcome::Duplicate
    } else {
        IngestOutcome::Inserted
    })
}

fn observation_key(observation: &ObservationEnvelope) -> Result<String, StorageError> {
    // Source identity and source time identify the sample. Local receive/server
    // times and derived freshness are deliberately excluded from idempotency.
    let identity = serde_json::to_string(&(
        observation.entity_id.as_str(),
        observation.data_source_id.as_str(),
        observation.metric_id.as_str(),
        observation.timestamps.source.as_unix_millis(),
        &observation.value,
        &observation.unit,
        &observation.quality,
        &observation.status_code,
        &observation.collection_error,
        &observation.simulation_origin,
    ))?;
    Ok(content_hash(
        &[b"oip-observation-v1\0", identity.as_bytes()].concat(),
    ))
}

fn keyed_hash(domain: &[u8], context: &EventContext, payload: &str) -> String {
    let context = format!(
        "{}:{:?}",
        context.data_source_id.as_str(),
        context.origin_class
    );
    content_hash(&[domain, context.as_bytes(), b"\0", payload.as_bytes()].concat())
}

fn content_hash(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

fn enum_name<T: Serialize>(value: &T) -> Result<String, StorageError> {
    serde_json::to_value(value)?
        .as_str()
        .map(str::to_owned)
        .ok_or(StorageError::InvalidEnumSerialization)
}

fn decode_context(source: &str, origin: &str) -> Result<EventContext, StorageError> {
    Ok(EventContext {
        data_source_id: DataSourceId::new(source).map_err(|_| StorageError::InvalidIdentifier)?,
        origin_class: serde_json::from_value(serde_json::Value::String(origin.to_owned()))?,
    })
}

fn decode_counter(value: i64) -> Result<u64, StorageError> {
    u64::try_from(value).map_err(|_| StorageError::CounterOutOfRange)
}

mod application;

#[cfg(test)]
mod tests {
    use super::*;
    use oip_core::{CollectionError, DataQuality, Freshness, SimulationOrigin, Timestamps, Unit};
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU64, Ordering};

    static NEXT_PATH: AtomicU64 = AtomicU64::new(0);
    const SOURCE: &str = "oip-local-simulation-v1";

    pub(super) fn observation(source_ms: i64) -> ObservationEnvelope {
        ObservationEnvelope {
            entity_id: EntityId::new("M-01").expect("entity"),
            data_source_id: DataSourceId::new(SOURCE).expect("source"),
            metric_id: MetricId::new("temperature").expect("metric"),
            value: Some(MetricValue::Float(60.0)),
            unit: Unit::Celsius,
            quality: DataQuality::Good,
            freshness: Freshness::Fresh,
            timestamps: Timestamps {
                source: Timestamp::from_unix_millis(source_ms),
                server: Some(Timestamp::from_unix_millis(source_ms + 1)),
                received: Some(Timestamp::from_unix_millis(source_ms + 2)),
            },
            status_code: Some(0),
            collection_error: None,
            simulation_origin: Some(SimulationOrigin {
                origin_id: SOURCE.to_owned(),
                seed: Some(u64::MAX),
                scenario: Some("normal".to_owned()),
                virtual_time_ms: Some(source_ms as u64),
                sequence: Some(u64::MAX),
            }),
        }
    }

    fn context() -> EventContext {
        EventContext::for_observation(&observation(0))
    }

    fn test_path(name: &str) -> PathBuf {
        let sequence = NEXT_PATH.fetch_add(1, Ordering::Relaxed);
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../target/oip-002-tests")
            .join(format!("{name}-{}-{sequence}.sqlite", std::process::id()))
    }

    fn remove_database(path: &Path) {
        for suffix in ["", "-wal", "-shm"] {
            let _ = std::fs::remove_file(PathBuf::from(format!("{}{}", path.display(), suffix)));
        }
    }

    #[test]
    fn migrations_are_versioned_idempotent_checksum_checked_and_desync_rejected() {
        let path = test_path("migration");
        std::fs::create_dir_all(path.parent().expect("parent")).expect("create test dir");
        let mut store = SqliteStore::open(&path).expect("open");
        assert_eq!(store.schema_version().expect("version"), 8);
        assert_eq!(store.migrate().expect("second migration"), 8);
        store
            .connection
            .execute("PRAGMA user_version = 0", [])
            .expect("desync fixture");
        assert!(matches!(
            store.migrate(),
            Err(StorageError::SchemaVersionMismatch { .. })
        ));
        store
            .connection
            .execute("PRAGMA user_version = 8", [])
            .expect("restore version");
        store
            .connection
            .execute(
                "UPDATE schema_migrations SET checksum = 'corrupt' WHERE version = 1",
                [],
            )
            .expect("corrupt test fixture");
        assert!(matches!(
            store.migrate(),
            Err(StorageError::MigrationChecksumMismatch { version: 1 })
        ));
        drop(store);
        remove_database(&path);
    }

    #[test]
    fn ingestion_is_idempotent_and_restart_recovers_observations_events_and_gaps() {
        let path = test_path("restart");
        std::fs::create_dir_all(path.parent().expect("parent")).expect("create test dir");
        let observation = observation(1_000);
        let gap = DataGap {
            started_at: Timestamp::from_unix_millis(900),
            ended_at: Timestamp::from_unix_millis(1_100),
            reason: "test disconnect".to_owned(),
        };
        let events = vec![
            ClientEvent::Observation(Box::new(observation.clone())),
            ClientEvent::ConnectionLost {
                at: Timestamp::from_unix_millis(900),
                reason: "connection closed".to_owned(),
            },
            ClientEvent::Reconnected {
                at: Timestamp::from_unix_millis(1_100),
                gap: gap.clone(),
            },
            ClientEvent::SubscriptionError {
                at: Timestamp::from_unix_millis(1_101),
                reason: "invalid input".to_owned(),
            },
        ];
        let mut store = SqliteStore::open(&path).expect("open");
        assert_eq!(store.ingest_batch(&context(), &events).expect("ingest"), 4);
        assert_eq!(
            store.ingest_batch(&context(), &events).expect("reingest"),
            0
        );
        assert_eq!(store.observation_count().expect("count"), 1);
        assert_eq!(store.event_count().expect("count"), 4);
        assert_eq!(store.observations().expect("rows")[0].duplicate_count, 1);
        assert!(store
            .events()
            .expect("events")
            .iter()
            .all(|event| event.duplicate_count == 1));
        assert_eq!(store.gaps().expect("gaps")[0].duplicate_count, 1);
        drop(store);

        let store = SqliteStore::open(&path).expect("reopen");
        assert_eq!(
            store.observations().expect("rows")[0].observation,
            observation
        );
        let restored_events = store
            .events()
            .expect("events")
            .into_iter()
            .map(|event| event.event)
            .collect::<Vec<_>>();
        assert_eq!(
            restored_events,
            vec![
                events[1].clone(),
                events[0].clone(),
                events[2].clone(),
                events[3].clone()
            ]
        );
        assert_eq!(store.gaps().expect("gaps")[0].gap, gap);
        assert_eq!(
            store
                .latest_observation(
                    &EntityId::new("M-01").expect("entity"),
                    &DataSourceId::new(SOURCE).expect("source"),
                    &MetricId::new("temperature").expect("metric"),
                )
                .expect("latest"),
            Some(observation)
        );
        drop(store);
        remove_database(&path);
    }

    #[test]
    fn absent_values_errors_and_large_unsigned_values_round_trip_without_fabrication() {
        let mut store = SqliteStore::open_in_memory().expect("memory store");
        let mut absent = observation(2_000);
        absent.value = None;
        absent.quality = DataQuality::Unknown;
        absent.freshness = Freshness::Unknown;
        absent.collection_error = Some(CollectionError::Unknown);
        let mut unsigned = observation(2_001);
        unsigned.value = Some(MetricValue::UnsignedInteger(u64::MAX));
        store.ingest_observation(&absent).expect("absent");
        store.ingest_observation(&unsigned).expect("unsigned");
        let restored = store.observations().expect("rows");
        assert_eq!(restored[0].observation, absent);
        assert!(restored[0].observation.value.is_none());
        assert_eq!(
            restored[1].observation.value,
            Some(MetricValue::UnsignedInteger(u64::MAX))
        );
        assert_eq!(
            restored[0]
                .observation
                .simulation_origin
                .as_ref()
                .and_then(|origin| origin.seed),
            Some(u64::MAX)
        );
    }

    #[test]
    fn redelivery_with_new_local_receive_time_is_idempotent() {
        let mut store = SqliteStore::open_in_memory().expect("memory store");
        let original = observation(2_500);
        let mut redelivered = original.clone();
        redelivered.timestamps.received = Some(Timestamp::from_unix_millis(99_999));
        redelivered.timestamps.server = Some(Timestamp::from_unix_millis(88_888));
        redelivered.freshness = Freshness::Unknown;
        assert_eq!(
            store.ingest_observation(&original).expect("first"),
            IngestOutcome::Inserted
        );
        assert_eq!(
            store.ingest_observation(&redelivered).expect("redelivery"),
            IngestOutcome::Duplicate
        );
        assert_eq!(store.observation_count().expect("count"), 1);
        assert_eq!(store.observations().expect("rows")[0].duplicate_count, 1);
        store
            .ingest_event(
                &context(),
                &ClientEvent::Observation(Box::new(original.clone())),
            )
            .expect("first event");
        assert_eq!(
            store
                .ingest_event(&context(), &ClientEvent::Observation(Box::new(redelivered)),)
                .expect("redelivered event"),
            IngestOutcome::Duplicate
        );
        assert_eq!(store.event_count().expect("event count"), 1);
    }

    #[test]
    fn non_finite_values_are_rejected_and_batch_rolls_back() {
        let mut store = SqliteStore::open_in_memory().expect("memory store");
        let valid = ClientEvent::Observation(Box::new(observation(3_000)));
        let mut invalid = observation(3_001);
        invalid.value = Some(MetricValue::Float(f64::NAN));
        let invalid = ClientEvent::Observation(Box::new(invalid));
        assert!(matches!(
            store.ingest_batch(&context(), &[valid, invalid]),
            Err(StorageError::NonFiniteFloat)
        ));
        assert_eq!(store.observation_count().expect("count"), 0);
        assert_eq!(store.event_count().expect("count"), 0);
    }

    #[test]
    fn simulator_and_external_sources_cannot_be_mixed() {
        let mut store = SqliteStore::open_in_memory().expect("memory store");
        store
            .ingest_observation(&observation(4_000))
            .expect("simulation");
        let mut external = observation(4_001);
        external.simulation_origin = None;
        assert!(matches!(
            store.ingest_observation(&external),
            Err(StorageError::OriginClassConflict(_))
        ));
        assert_eq!(store.observation_count().expect("count"), 1);
    }

    #[test]
    fn latest_observation_and_identical_events_are_source_scoped() {
        let mut store = SqliteStore::open_in_memory().expect("memory store");
        let simulated = observation(5_000);
        let mut external = observation(6_000);
        external.data_source_id = DataSourceId::new("external-source").expect("source");
        external.simulation_origin = None;
        let external_source = external.data_source_id.clone();
        let external_context = EventContext::for_observation(&external);
        store.ingest_observation(&simulated).expect("simulation");
        store.ingest_observation(&external).expect("external");
        let entity = EntityId::new("M-01").expect("entity");
        let metric = MetricId::new("temperature").expect("metric");
        assert_eq!(
            store
                .latest_observation(
                    &entity,
                    &DataSourceId::new(SOURCE).expect("source"),
                    &metric
                )
                .expect("sim latest"),
            Some(simulated)
        );
        assert_eq!(
            store
                .latest_observation(&entity, &external_source, &metric)
                .expect("external latest"),
            Some(external)
        );
        let event = ClientEvent::ConnectionLost {
            at: Timestamp::from_unix_millis(5_100),
            reason: "same text".to_owned(),
        };
        store.ingest_event(&context(), &event).expect("sim event");
        store
            .ingest_event(&external_context, &event)
            .expect("external event");
        assert_eq!(store.event_count().expect("count"), 2);
        assert_eq!(
            store
                .events_for_source(&DataSourceId::new(SOURCE).expect("source"))
                .expect("simulation events")
                .len(),
            1
        );
        assert_eq!(
            store
                .events_for_source(&external_source)
                .expect("external events")
                .len(),
            1
        );
    }

    #[test]
    fn event_source_mismatch_and_corrupted_payloads_are_reported() {
        let mut store = SqliteStore::open_in_memory().expect("memory store");
        let event = ClientEvent::Observation(Box::new(observation(7_000)));
        let wrong = EventContext {
            data_source_id: DataSourceId::new("other").expect("source"),
            origin_class: OriginClass::Simulation,
        };
        assert!(matches!(
            store.ingest_event(&wrong, &event),
            Err(StorageError::EventSourceMismatch)
        ));
        store.ingest_event(&context(), &event).expect("ingest");
        store
            .connection
            .execute("UPDATE observations SET payload_json = 'broken'", [])
            .expect("corrupt payload");
        assert!(matches!(
            store.observations(),
            Err(StorageError::Serialization(_))
        ));
    }

    #[test]
    fn corrupted_database_is_reported() {
        let path = test_path("corrupt");
        std::fs::create_dir_all(path.parent().expect("parent")).expect("create test dir");
        std::fs::write(&path, b"not a sqlite database").expect("write corrupt fixture");
        assert!(SqliteStore::open(&path).is_err());
        remove_database(&path);
    }
}
