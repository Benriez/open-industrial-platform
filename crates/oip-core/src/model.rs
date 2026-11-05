use serde::{Deserialize, Serialize};
use std::fmt;
use std::time::{SystemTime, UNIX_EPOCH};
use thiserror::Error;

#[derive(Debug, Error, Clone, Copy, PartialEq, Eq)]
pub enum IdError {
    #[error("identifier must not be empty or whitespace-only")]
    Empty,
}

macro_rules! identifier {
    ($name:ident) => {
        #[derive(Clone, Debug, Eq, Hash, Ord, PartialEq, PartialOrd, Serialize)]
        #[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
        #[serde(transparent)]
        pub struct $name(String);

        impl $name {
            pub fn new(value: impl Into<String>) -> Result<Self, IdError> {
                let value = value.into();
                let value = value.trim();
                if value.is_empty() {
                    return Err(IdError::Empty);
                }
                Ok(Self(value.to_owned()))
            }

            pub fn as_str(&self) -> &str {
                &self.0
            }
        }

        impl<'de> Deserialize<'de> for $name {
            fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
            where
                D: serde::Deserializer<'de>,
            {
                let value = String::deserialize(deserializer)?;
                Self::new(value).map_err(serde::de::Error::custom)
            }
        }

        impl fmt::Display for $name {
            fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
                formatter.write_str(&self.0)
            }
        }
    };
}

identifier!(EntityId);
identifier!(DataSourceId);
identifier!(MetricId);

#[derive(Debug, Error, Clone, Copy, PartialEq, Eq)]
pub enum TimestampError {
    #[error("system clock is before the Unix epoch")]
    BeforeUnixEpoch,
    #[error("timestamp does not fit into signed Unix milliseconds")]
    Overflow,
}

#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(transparent)]
pub struct Timestamp(i64);

impl Timestamp {
    pub const fn from_unix_millis(value: i64) -> Self {
        Self(value)
    }

    pub const fn as_unix_millis(self) -> i64 {
        self.0
    }

    pub fn now() -> Result<Self, TimestampError> {
        Self::try_from(SystemTime::now())
    }
}

impl TryFrom<SystemTime> for Timestamp {
    type Error = TimestampError;

    fn try_from(value: SystemTime) -> Result<Self, Self::Error> {
        let duration = value
            .duration_since(UNIX_EPOCH)
            .map_err(|_| TimestampError::BeforeUnixEpoch)?;
        let millis = i64::try_from(duration.as_millis()).map_err(|_| TimestampError::Overflow)?;
        Ok(Self(millis))
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct Timestamps {
    pub source: Timestamp,
    pub server: Option<Timestamp>,
    pub received: Option<Timestamp>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum MetricValue {
    Float(f64),
    SignedInteger(i64),
    UnsignedInteger(u64),
    Boolean(bool),
    Text(String),
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum Unit {
    None,
    Celsius,
    KiloPascal,
    Count,
    Custom(String),
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum DataQuality {
    Good,
    Uncertain,
    Bad,
    Unknown,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum Freshness {
    Fresh,
    Stale,
    Unknown,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum CollectionError {
    DeviceUnreachable,
    ConnectionInterrupted,
    CollectorUnavailable,
    StaleMeasurement,
    InvalidMeasurement,
    /// An external source/server timestamp was null, a sentinel, or outside
    /// the OPC UA calendar range. Its original value is retained.
    InvalidTimestamp,
    /// A certificate or transport security validation failed. This is distinct
    /// from data provenance and never downgraded to an insecure connection.
    SecurityValidationFailed,
    /// The remote source claimed a provenance that does not match the expected
    /// local simulation origin and was therefore not adopted.
    InvalidProvenance,
    Unknown,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct SimulationOrigin {
    pub origin_id: String,
    pub seed: Option<u64>,
    pub scenario: Option<String>,
    pub virtual_time_ms: Option<u64>,
    pub sequence: Option<u64>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct ObservationEnvelope {
    pub entity_id: EntityId,
    pub data_source_id: DataSourceId,
    pub metric_id: MetricId,
    pub value: Option<MetricValue>,
    pub unit: Unit,
    pub quality: DataQuality,
    pub freshness: Freshness,
    pub timestamps: Timestamps,
    pub status_code: Option<u32>,
    pub collection_error: Option<CollectionError>,
    pub simulation_origin: Option<SimulationOrigin>,
}

impl ObservationEnvelope {
    pub fn is_usable(&self) -> bool {
        self.value.is_some()
            && self.quality == DataQuality::Good
            && self.freshness == Freshness::Fresh
            && self.collection_error.is_none()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn identifiers_reject_empty_values() {
        assert_eq!(EntityId::new(" ").expect_err("must fail"), IdError::Empty);
        assert!(MetricId::new("temperature").is_ok());
        assert_eq!(EntityId::new(" M-01 ").expect("trimmed").as_str(), "M-01");
        assert!(serde_json::from_str::<EntityId>("\"   \"").is_err());
        assert_eq!(
            serde_json::from_str::<EntityId>("\" M-01 \"")
                .expect("canonical deserialization")
                .as_str(),
            "M-01"
        );
    }

    #[test]
    fn unknown_observation_has_no_numeric_or_offline_fallback() {
        let observation = ObservationEnvelope {
            entity_id: EntityId::new("M-01").expect("valid id"),
            data_source_id: DataSourceId::new("simulation").expect("valid id"),
            metric_id: MetricId::new("temperature").expect("valid id"),
            value: None,
            unit: Unit::Celsius,
            quality: DataQuality::Unknown,
            freshness: Freshness::Unknown,
            timestamps: Timestamps {
                source: Timestamp::from_unix_millis(1_000),
                server: None,
                received: None,
            },
            status_code: None,
            collection_error: Some(CollectionError::Unknown),
            simulation_origin: None,
        };

        assert!(!observation.is_usable());
        let json = serde_json::to_value(observation).expect("serialize observation");
        assert_eq!(json["value"], serde_json::Value::Null);
        assert_eq!(json["quality"], "unknown");
        assert_eq!(json["collection_error"], "unknown");
        assert!(json.get("offline").is_none());
    }
}
