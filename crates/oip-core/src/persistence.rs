use crate::{ClientEvent, DataGap, DataSourceId, EntityId, MetricId, ObservationEnvelope};
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum OriginClass {
    Simulation,
    External,
}

/// Source identity required for connection events and gaps, which do not carry
/// an ObservationEnvelope of their own.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct EventContext {
    pub data_source_id: DataSourceId,
    pub origin_class: OriginClass,
}

impl EventContext {
    pub fn for_observation(observation: &ObservationEnvelope) -> Self {
        Self {
            data_source_id: observation.data_source_id.clone(),
            origin_class: if observation.simulation_origin.is_some() {
                OriginClass::Simulation
            } else {
                OriginClass::External
            },
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum IngestOutcome {
    Inserted,
    Duplicate,
}

#[derive(Clone, Debug, PartialEq)]
pub struct StoredObservation {
    pub observation: ObservationEnvelope,
    pub duplicate_count: u64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct StoredEvent {
    pub context: EventContext,
    pub event: ClientEvent,
    pub duplicate_count: u64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct StoredGap {
    pub context: EventContext,
    pub gap: DataGap,
    pub duplicate_count: u64,
}

/// Stack- and database-neutral ingestion boundary for SQLite or a later TSDB.
pub trait ObservationSink {
    type Error;
    fn ingest_observation(
        &mut self,
        observation: &ObservationEnvelope,
    ) -> Result<IngestOutcome, Self::Error>;
}

pub trait EventSink {
    type Error;
    fn ingest_event(
        &mut self,
        context: &EventContext,
        event: &ClientEvent,
    ) -> Result<IngestOutcome, Self::Error>;
}

pub trait ObservationRepository {
    type Error;
    fn latest_observation(
        &self,
        entity_id: &EntityId,
        data_source_id: &DataSourceId,
        metric_id: &MetricId,
    ) -> Result<Option<ObservationEnvelope>, Self::Error>;
    fn observations(&self) -> Result<Vec<StoredObservation>, Self::Error>;
}

pub trait EventRepository {
    type Error;
    fn events_for_source(
        &self,
        data_source_id: &DataSourceId,
    ) -> Result<Vec<StoredEvent>, Self::Error>;
    fn gaps_for_source(&self, data_source_id: &DataSourceId)
        -> Result<Vec<StoredGap>, Self::Error>;
}
