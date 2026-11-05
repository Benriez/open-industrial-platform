//! Stable, infrastructure-neutral application contracts.
use crate::*;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use thiserror::Error;

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum Lifecycle {
    Initializing,
    Ready,
    Degraded,
    Stopping,
    Stopped,
    Failed,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum Reachability {
    Reachable,
    Unreachable,
    Unknown,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum ConnectionHealth {
    Connected,
    Disconnected,
    Unknown,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum ServiceHealth {
    Healthy,
    Degraded,
    Unknown,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum Validity {
    Valid,
    Invalid,
    Unknown,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum ValueKind {
    Float,
    SignedInteger,
    UnsignedInteger,
    Boolean,
    Text,
}
impl ValueKind {
    pub fn matches(self, value: &MetricValue) -> bool {
        matches!(
            (self, value),
            (Self::Float, MetricValue::Float(_))
                | (Self::SignedInteger, MetricValue::SignedInteger(_))
                | (Self::UnsignedInteger, MetricValue::UnsignedInteger(_))
                | (Self::Boolean, MetricValue::Boolean(_))
                | (Self::Text, MetricValue::Text(_))
        )
    }
}
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct SourceDefinition {
    pub id: DataSourceId,
    pub name: String,
    pub entity_id: EntityId,
    /// Opaque stable adapter binding; only infrastructure interprets it.
    pub binding: String,
    pub simulation_origin_id: String,
    pub origin_class: OriginClass,
    pub metrics: BTreeMap<MetricId, ValueKind>,
    #[serde(default)]
    pub required_metrics: BTreeSet<MetricId>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct SourceHealth {
    pub id: DataSourceId,
    pub name: String,
    pub entity_id: EntityId,
    pub simulated: bool,
    pub reachability: Reachability,
    pub connection: ConnectionHealth,
    pub service: ServiceHealth,
    pub freshness: Freshness,
    pub validity: Validity,
    pub last_received_ms: Option<i64>,
    pub accepted: u64,
    pub duplicates: u64,
    pub out_of_order: u64,
    pub rejected: u64,
    pub reconnect_attempts: u64,
    pub dropped: u64,
    pub last_error: Option<String>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct CoreHealth {
    pub lifecycle: Lifecycle,
    pub live: bool,
    pub ready: bool,
    pub persistence_healthy: bool,
    pub persistence_errors: u64,
    pub last_persistence_error: Option<String>,
    pub revision: u64,
    pub run_id: i64,
    pub persisted_observations: u64,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct EventRecord {
    pub sequence: i64,
    pub context: EventContext,
    pub event: ClientEvent,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct CoreView {
    pub health: CoreHealth,
    pub sources: Vec<SourceHealth>,
    pub observations: Vec<ObservationEnvelope>,
    pub events: Vec<EventRecord>,
}
#[derive(Debug, Error)]
pub enum ApplicationError {
    #[error("source is not registered")]
    UnknownSource,
    #[error("observation does not match registered source, entity or provenance")]
    Provenance,
    #[error("observation timestamp is invalid")]
    Timestamp,
    #[error("metric type is not registered or does not match")]
    DataType,
    #[error("non-finite observation")]
    NonFinite,
    #[error("data gap has negative duration")]
    NegativeGap,
    #[error("source registration differs from persisted identity")]
    RegistrationConflict,
    #[error("persistence unavailable: {0}")]
    Persistence(PersistenceFailure),
}
/// Redacted, stable operation code across the storage port. The concrete
/// adapter retains its internal database error type; no credentials/payloads
/// cross the application boundary in error messages.
#[derive(Clone, Debug, Error)]
#[error("{operation}")]
pub struct PersistenceFailure {
    pub operation: &'static str,
}
impl From<&'static str> for PersistenceFailure {
    fn from(operation: &'static str) -> Self {
        Self { operation }
    }
}

/// Atomic evidence + optional latest checkpoint, not a concrete database API.
pub trait CoreRepository: Send {
    fn definitions(&self) -> Result<Vec<SourceDefinition>, PersistenceFailure>;
    fn register(&mut self, definition: &SourceDefinition) -> Result<(), PersistenceFailure>;
    fn restore_latest(&self) -> Result<Vec<ObservationEnvelope>, PersistenceFailure>;
    fn recent_events(&self, limit: usize) -> Result<Vec<EventRecord>, PersistenceFailure>;
    fn commit(
        &mut self,
        context: &EventContext,
        event: &ClientEvent,
        latest: Option<&ObservationEnvelope>,
    ) -> Result<(IngestOutcome, i64), PersistenceFailure>;
    fn count(&self) -> Result<u64, PersistenceFailure>;
    fn start_run(&mut self, at: i64) -> Result<i64, PersistenceFailure>;
    fn finish_run(&mut self, id: i64, at: i64, result: &str) -> Result<(), PersistenceFailure>;
}
