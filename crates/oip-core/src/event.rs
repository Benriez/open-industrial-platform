use crate::{ObservationEnvelope, Timestamp};
use serde::{Deserialize, Serialize};

/// A documented interval without observations from a previously active source.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct DataGap {
    pub started_at: Timestamp,
    pub ended_at: Timestamp,
    pub reason: String,
}

/// Stack-neutral events emitted by a read-only collection adapter.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub enum ClientEvent {
    Observation(Box<ObservationEnvelope>),
    ConnectionLost {
        at: Timestamp,
        reason: String,
    },
    Reconnected {
        at: Timestamp,
        gap: DataGap,
    },
    SubscriptionError {
        at: Timestamp,
        reason: String,
    },
    DataLoss {
        at: Timestamp,
        gap: DataGap,
        dropped: u64,
    },
}
