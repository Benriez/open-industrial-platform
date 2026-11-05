use super::mapping::{
    data_value_to_observation, datetime_to_timestamp, timestamp_to_datetime, SimulationMetadata,
};
use crate::{AdapterError, FreshnessPolicy};
use oip_core::{CollectionError, DataQuality, Freshness, MetricId, MetricValue, Timestamp};
use oip_simulator::{SIMULATION_EPOCH_UNIX_MS, SIMULATION_ORIGIN_ID};
use opcua::types::{BinaryDecodable, ContextOwned, DataValue, DateTime, StatusCode, Variant};
use proptest::prelude::*;

fn metadata() -> SimulationMetadata {
    SimulationMetadata {
        origin_id: Some(SIMULATION_ORIGIN_ID.to_owned()),
        seed: Some(1),
        scenario: Some("normal".to_owned()),
        epoch_unix_ms: Some(SIMULATION_EPOCH_UNIX_MS),
        tick_duration_ms: Some(50),
    }
}

fn value_with(source: DateTime, server: DateTime) -> DataValue {
    DataValue {
        value: Some(Variant::from(60.0)),
        status: Some(StatusCode::Good),
        source_timestamp: Some(source),
        source_picoseconds: Some(0),
        server_timestamp: Some(server),
        server_picoseconds: Some(0),
    }
}

fn map(value: &DataValue) -> Result<oip_core::ObservationEnvelope, AdapterError> {
    data_value_to_observation(
        &MetricId::new("temperature").expect("metric"),
        value,
        &metadata(),
        None,
        &FreshnessPolicy::default(),
    )
}

fn decode_without_panic(ticks: i64) {
    let bytes = ticks.to_le_bytes();
    let decoded = std::panic::catch_unwind(|| {
        let context = ContextOwned::default();
        DateTime::decode(&mut &bytes[..], &context.context())
    });
    assert!(decoded.is_ok(), "decoder panicked for ticks={ticks}");
    decoded
        .expect("checked above")
        .expect("an i64 timestamp must decode without a panic");
}

#[test]
fn binary_datetime_decoder_handles_wire_boundaries_without_panic() {
    for ticks in [i64::MIN, i64::MIN + 1, -1, 0, 1, i64::MAX - 1, i64::MAX] {
        decode_without_panic(ticks);
    }
}

#[test]
fn invalid_source_timestamps_are_marked_and_original_time_is_retained() {
    for ticks in [i64::MIN, 0, i64::MAX] {
        let raw = DateTime::from(ticks);
        let expected = datetime_to_timestamp(raw);
        let observation = map(&value_with(raw, DateTime::now())).expect("invalid input is data");
        assert_eq!(observation.timestamps.source, expected);
        assert_ne!(observation.timestamps.source.as_unix_millis(), 0);
        assert_eq!(observation.quality, DataQuality::Bad);
        assert_eq!(observation.freshness, Freshness::Unknown);
        assert_eq!(
            observation.collection_error,
            Some(CollectionError::InvalidTimestamp)
        );
        assert!(!observation.is_usable());
    }
}

#[test]
fn invalid_server_timestamp_does_not_replace_or_hide_source_time() {
    let source = DateTime::from(10_000_000); // 1601-01-01T00:00:01
    let server = DateTime::from(i64::MAX);
    let observation = map(&value_with(source, server)).expect("invalid input is data");
    assert_eq!(observation.timestamps.source, datetime_to_timestamp(source));
    assert_eq!(
        observation.timestamps.server,
        Some(datetime_to_timestamp(server))
    );
    assert_eq!(
        observation.collection_error,
        Some(CollectionError::InvalidTimestamp)
    );
    assert_eq!(observation.freshness, Freshness::Unknown);
}

#[test]
fn non_finite_measurements_are_rejected_explicitly() {
    let mut value = value_with(DateTime::now(), DateTime::now());
    value.value = Some(Variant::from(f64::NAN));
    assert!(matches!(map(&value), Err(AdapterError::InvalidValue(_))));
}

#[test]
fn malformed_binary_input_is_an_error_not_a_panic() {
    let decoded = std::panic::catch_unwind(|| {
        let context = ContextOwned::default();
        DateTime::decode(&mut &[1_u8, 2, 3][..], &context.context())
    });
    assert!(decoded.is_ok());
    assert!(decoded.expect("no panic").is_err());
}

proptest! {
    #[test]
    fn arbitrary_wire_datetime_ticks_never_panic(ticks in any::<i64>()) {
        decode_without_panic(ticks);
    }

    #[test]
    fn arbitrary_domain_timestamps_encode_without_panic(unix_ms in any::<i64>()) {
        let converted = std::panic::catch_unwind(|| {
            timestamp_to_datetime(Timestamp::from_unix_millis(unix_ms))
        });
        assert!(converted.is_ok(), "encoder panicked for unix_ms={unix_ms}");
        let converted = converted.expect("checked above");
        if (-62_135_596_800_000..=253_402_300_799_999).contains(&unix_ms) {
            assert!(converted.is_ok(), "valid OPC UA time was rejected");
        } else {
            assert!(matches!(converted, Err(AdapterError::TimestampOutOfRange)));
        }
    }

    #[test]
    fn arbitrary_decoded_datetimes_map_without_panic(ticks in any::<i64>()) {
        let bytes = ticks.to_le_bytes();
        let context = ContextOwned::default();
        let decoded = DateTime::decode(&mut &bytes[..], &context.context())
            .expect("i64 wire value");
        let mapped = std::panic::catch_unwind(|| {
            map(&value_with(decoded, DateTime::now()))
        });
        assert!(mapped.is_ok(), "mapping panicked for ticks={ticks}");
        let observation = mapped.expect("checked above").expect("mapping result");
        if observation.collection_error == Some(CollectionError::InvalidTimestamp) {
            assert_eq!(observation.quality, DataQuality::Bad);
            assert_eq!(observation.freshness, Freshness::Unknown);
            assert_eq!(observation.timestamps.source, datetime_to_timestamp(decoded));
        }
    }
}

#[test]
fn virtual_clock_new_samples_are_fresh_and_old_samples_can_be_stale() {
    let source = timestamp_to_datetime(Timestamp::from_unix_millis(
        SIMULATION_EPOCH_UNIX_MS + 10_000,
    ))
    .expect("source timestamp");
    let value = value_with(source, DateTime::now());
    let metric = MetricId::new("temperature").expect("metric");
    let fresh = data_value_to_observation(
        &metric,
        &value,
        &metadata(),
        Some(Timestamp::from_unix_millis(SIMULATION_EPOCH_UNIX_MS)),
        &FreshnessPolicy::default(),
    )
    .expect("new virtual sample");
    assert_eq!(fresh.freshness, Freshness::Fresh);
    assert_eq!(fresh.quality, DataQuality::Good);

    let stale = data_value_to_observation(
        &metric,
        &value,
        &metadata(),
        Some(Timestamp::from_unix_millis(
            SIMULATION_EPOCH_UNIX_MS + 30_000,
        )),
        &FreshnessPolicy::default(),
    )
    .expect("old virtual sample");
    assert_eq!(stale.freshness, Freshness::Stale);
}

#[test]
fn finite_measurement_type_is_preserved() {
    let observation = map(&value_with(DateTime::now(), DateTime::now())).expect("valid input");
    assert!(matches!(observation.value, Some(MetricValue::Float(60.0))));
}
