use crate::adapter::FreshnessPolicy;
use crate::AdapterError;
use oip_core::{
    CollectionError, DataQuality, DataSourceId, EntityId, Freshness, MetricId, MetricValue,
    ObservationEnvelope, SimulationOrigin, Timestamp, Timestamps, Unit,
};
use oip_simulator::{MACHINE_ID, SIMULATION_ORIGIN_ID};
use opcua::types::{DataValue, DateTime, StatusCode, Variant};

/// Source metadata of the local simulation, read from the address space.
#[derive(Clone, Debug, Default)]
pub(crate) struct SimulationMetadata {
    pub origin_id: Option<String>,
    pub seed: Option<u64>,
    pub scenario: Option<String>,
    /// Virtual epoch of the simulation in Unix milliseconds.
    pub epoch_unix_ms: Option<i64>,
    /// Virtual tick duration in milliseconds.
    pub tick_duration_ms: Option<u64>,
}

impl SimulationMetadata {
    /// Returns true when the source claims the expected local simulation origin.
    pub(crate) fn has_trusted_origin(&self) -> bool {
        self.origin_id.as_deref() == Some(SIMULATION_ORIGIN_ID)
    }
}

pub(crate) fn unit_for_metric(metric_id: &str) -> Unit {
    match metric_id {
        "temperature" => Unit::Celsius,
        "pressure" => Unit::KiloPascal,
        "units_produced" => Unit::Count,
        _ => Unit::None,
    }
}

pub(crate) fn timestamp_to_datetime(timestamp: Timestamp) -> Result<DateTime, AdapterError> {
    // OPC UA DateTime is defined for 1601 through 9999. Restricting the domain
    // before conversion also prevents the upstream tick arithmetic from
    // overflowing for chrono's much wider calendar range.
    const OPC_UA_MIN_UNIX_MS: i64 = -62_135_596_800_000;
    const OPC_UA_MAX_UNIX_MS: i64 = 253_402_300_799_999;
    let unix_ms = timestamp.as_unix_millis();
    if !(OPC_UA_MIN_UNIX_MS..=OPC_UA_MAX_UNIX_MS).contains(&unix_ms) {
        return Err(AdapterError::TimestampOutOfRange);
    }
    let value = chrono::DateTime::from_timestamp_millis(unix_ms)
        .ok_or(AdapterError::Timestamp(oip_core::TimestampError::Overflow))?;
    Ok(DateTime::from(value))
}

pub(crate) fn datetime_to_timestamp(value: DateTime) -> Timestamp {
    Timestamp::from_unix_millis(value.as_chrono().timestamp_millis())
}

/// Validates an external OPC UA timestamp without replacing its raw value.
///
/// Zero is the OPC UA null timestamp and `i64::MAX` is the end-times sentinel;
/// neither is a measurement time. Values before 1601 or beyond 9999 are also
/// rejected. The conversion itself retains the original millisecond value.
pub(crate) fn external_datetime_is_valid(value: DateTime) -> bool {
    let raw_ticks = value.ticks();
    raw_ticks > 0 && raw_ticks < DateTime::endtimes_ticks()
}

pub(crate) fn metric_value_to_variant(value: &MetricValue) -> Variant {
    match value {
        MetricValue::Float(value) => Variant::from(*value),
        MetricValue::SignedInteger(value) => Variant::from(*value),
        MetricValue::UnsignedInteger(value) => Variant::from(*value),
        MetricValue::Boolean(value) => Variant::from(*value),
        MetricValue::Text(value) => Variant::from(value.clone()),
    }
}

pub(crate) fn variant_to_metric_value(value: &Variant) -> Result<MetricValue, AdapterError> {
    match value {
        Variant::Double(value) if value.is_finite() => Ok(MetricValue::Float(*value)),
        Variant::Double(_) => Err(AdapterError::InvalidValue(
            "non-finite Double is not a valid measurement".to_owned(),
        )),
        Variant::Int64(value) => Ok(MetricValue::SignedInteger(*value)),
        Variant::UInt64(value) => Ok(MetricValue::UnsignedInteger(*value)),
        Variant::Boolean(value) => Ok(MetricValue::Boolean(*value)),
        Variant::String(value) => Ok(MetricValue::Text(value.to_string())),
        other => Err(AdapterError::UnsupportedValue(format!("{other:?}"))),
    }
}

/// Encodes the domain quality and collection error into a distinguishable OPC UA
/// status code so that the client can restore the original reason.
pub(crate) fn status_code_for(observation: &ObservationEnvelope) -> StatusCode {
    match observation.collection_error {
        Some(CollectionError::InvalidMeasurement) => StatusCode::BadSensorFailure,
        Some(CollectionError::InvalidTimestamp) => StatusCode::BadInvalidTimestamp,
        Some(CollectionError::SecurityValidationFailed) => StatusCode::BadSecurityChecksFailed,
        Some(CollectionError::DeviceUnreachable) => StatusCode::BadNotConnected,
        Some(CollectionError::ConnectionInterrupted) => StatusCode::BadConnectionClosed,
        Some(CollectionError::CollectorUnavailable) => StatusCode::BadWaitingForInitialData,
        Some(CollectionError::StaleMeasurement) => StatusCode::BadWaitingForInitialData,
        Some(CollectionError::InvalidProvenance) => StatusCode::BadSecurityChecksFailed,
        Some(CollectionError::Unknown) => StatusCode::BadUnexpectedError,
        None => match observation.quality {
            DataQuality::Good => StatusCode::Good,
            DataQuality::Uncertain => StatusCode::Uncertain,
            DataQuality::Bad => StatusCode::BadSensorFailure,
            DataQuality::Unknown => StatusCode::BadUnexpectedError,
        },
    }
}

/// Restores quality and collection error from an OPC UA status code.
pub(crate) fn quality_from_status(status: StatusCode) -> (DataQuality, Option<CollectionError>) {
    if status.is_good() {
        return (DataQuality::Good, None);
    }
    if status.is_uncertain() {
        return (DataQuality::Uncertain, None);
    }
    match status {
        StatusCode::BadSensorFailure => {
            (DataQuality::Bad, Some(CollectionError::InvalidMeasurement))
        }
        StatusCode::BadNotConnected => (
            DataQuality::Unknown,
            Some(CollectionError::DeviceUnreachable),
        ),
        StatusCode::BadConnectionClosed => (
            DataQuality::Unknown,
            Some(CollectionError::ConnectionInterrupted),
        ),
        StatusCode::BadWaitingForInitialData => (
            DataQuality::Unknown,
            Some(CollectionError::CollectorUnavailable),
        ),
        StatusCode::BadInvalidTimestamp => {
            (DataQuality::Bad, Some(CollectionError::InvalidTimestamp))
        }
        StatusCode::BadSecurityChecksFailed => (
            DataQuality::Unknown,
            Some(CollectionError::SecurityValidationFailed),
        ),
        _ => (DataQuality::Bad, Some(CollectionError::Unknown)),
    }
}

pub(crate) fn observation_to_data_value(
    observation: &ObservationEnvelope,
) -> Result<DataValue, AdapterError> {
    let status = status_code_for(observation);
    Ok(DataValue {
        // async-opcua 0.19.0 drops the status while reading a valueless DataValue.
        // Variant::Empty preserves Bad/Unknown quality without inventing a numeric value.
        value: Some(match observation.value.as_ref() {
            Some(value) => metric_value_to_variant(value),
            None => Variant::Empty,
        }),
        status: Some(status),
        source_timestamp: Some(timestamp_to_datetime(observation.timestamps.source)?),
        source_picoseconds: Some(0),
        server_timestamp: Some(DateTime::now()),
        server_picoseconds: Some(0),
    })
}

/// Derives freshness from the age of the source timestamp.
///
/// The reference clock is the clock of the source:
///
/// - A source that declares its own epoch (as the local simulation does) runs
///   on a virtual clock. Its age is measured against the newest value already
///   observed for the same metric, so a deterministic simulation is not
///   mistaken for stale data only because its virtual time differs from the
///   client wall clock.
/// - A source without a declared epoch is measured against the client wall
///   clock.
///
/// A source timestamp in the future beyond the allowed skew is treated as
/// uncertain, an aged timestamp as stale.
fn derive_freshness(
    source: Timestamp,
    received: Timestamp,
    epoch_unix_ms: Option<i64>,
    latest_observed_source: Option<Timestamp>,
    policy: &FreshnessPolicy,
) -> (Freshness, Option<DataQuality>) {
    let exceeds_age = |age: i128| {
        policy
            .max_source_age
            .and_then(|max_age| i128::try_from(max_age.as_millis()).ok())
            .is_some_and(|max_age| age > max_age)
    };
    if epoch_unix_ms.is_some() {
        // A newer virtual sample is fresh regardless of how much virtual time
        // advanced since the previous sample. Only an older/out-of-order value
        // has a positive age on the source clock; wall-clock skew is unrelated.
        let age = latest_observed_source
            .map(|latest| i128::from(latest.as_unix_millis()) - i128::from(source.as_unix_millis()))
            .unwrap_or(0);
        return if exceeds_age(age) {
            (Freshness::Stale, None)
        } else {
            (Freshness::Fresh, None)
        };
    }
    let age = i128::from(received.as_unix_millis()) - i128::from(source.as_unix_millis());
    if age < 0 {
        let skew = age.saturating_abs();
        if skew > i128::try_from(policy.max_future_skew.as_millis()).unwrap_or(i128::MAX) {
            return (Freshness::Unknown, Some(DataQuality::Uncertain));
        }
        return (Freshness::Fresh, None);
    }
    if exceeds_age(age) {
        (Freshness::Stale, None)
    } else {
        (Freshness::Fresh, None)
    }
}

pub(crate) fn data_value_to_observation(
    metric_id: &MetricId,
    value: &DataValue,
    metadata: &SimulationMetadata,
    latest_observed_source: Option<Timestamp>,
    policy: &FreshnessPolicy,
) -> Result<ObservationEnvelope, AdapterError> {
    let source_datetime = value
        .source_timestamp
        .ok_or(AdapterError::MissingSourceTimestamp)?;
    let source = datetime_to_timestamp(source_datetime);
    let server = value.server_timestamp.map(datetime_to_timestamp);
    let timestamps_valid = external_datetime_is_valid(source_datetime)
        && value
            .server_timestamp
            .map(external_datetime_is_valid)
            .unwrap_or(true);
    let received = Timestamp::now()?;
    let status = value.status();
    let (mut quality, mut collection_error) = quality_from_status(status);
    let metric_value = match value.value.as_ref() {
        None | Some(Variant::Empty) => None,
        Some(value) => Some(variant_to_metric_value(value)?),
    };

    let (mut freshness, freshness_quality) = if timestamps_valid {
        derive_freshness(
            source,
            received,
            metadata.epoch_unix_ms,
            latest_observed_source,
            policy,
        )
    } else {
        (Freshness::Unknown, None)
    };
    if let Some(freshness_quality) = freshness_quality {
        quality = freshness_quality;
        collection_error = collection_error.or(Some(CollectionError::StaleMeasurement));
    }
    if !timestamps_valid {
        quality = DataQuality::Bad;
        freshness = Freshness::Unknown;
        collection_error = Some(CollectionError::InvalidTimestamp);
    }
    if collection_error.is_none() && metric_value.is_none() {
        collection_error = Some(CollectionError::Unknown);
    }
    if metric_value.is_none() {
        freshness = Freshness::Unknown;
    }

    // The provenance of a remote source is untrusted. Only the expected local
    // simulation origin may be adopted; anything else is reported instead.
    let trusted_origin = metadata.has_trusted_origin();
    let simulation_origin = if trusted_origin {
        metadata
            .origin_id
            .as_ref()
            .map(|origin_id| SimulationOrigin {
                origin_id: origin_id.clone(),
                seed: metadata.seed,
                scenario: metadata.scenario.clone(),
                virtual_time_ms: metadata.epoch_unix_ms.and_then(|epoch| {
                    u64::try_from(source.as_unix_millis().saturating_sub(epoch)).ok()
                }),
                sequence: metadata
                    .epoch_unix_ms
                    .zip(metadata.tick_duration_ms)
                    .and_then(|(epoch, tick)| {
                        let elapsed = source.as_unix_millis().saturating_sub(epoch);
                        u64::try_from(elapsed)
                            .ok()
                            .map(|elapsed| elapsed / tick.max(1))
                    }),
            })
    } else {
        if collection_error.is_none() {
            collection_error = Some(CollectionError::InvalidProvenance);
        }
        None
    };

    // An empty or malformed origin id must not silently fall back to a
    // placeholder identity; it is reported as an untrusted provenance.
    let data_source_id = match metadata.origin_id.as_deref() {
        Some(origin) if !origin.trim().is_empty() => {
            DataSourceId::new(origin).map_err(|_| AdapterError::UntrustedProvenance)?
        }
        Some(_) => return Err(AdapterError::UntrustedProvenance),
        None => DataSourceId::new("opcua").expect("fallback data source id is valid"),
    };

    Ok(ObservationEnvelope {
        entity_id: EntityId::new(MACHINE_ID).expect("static machine id is valid"),
        data_source_id,
        metric_id: metric_id.clone(),
        value: metric_value,
        unit: unit_for_metric(metric_id.as_str()),
        quality,
        freshness,
        timestamps: Timestamps {
            source,
            server,
            received: Some(received),
        },
        status_code: Some(status.bits()),
        collection_error,
        simulation_origin,
    })
}
