//! Deterministic, local-only industrial test plant.

use oip_core::{
    CollectionError, DataQuality, DataSourceId, EntityId, Freshness, MetricId, MetricValue,
    ObservationEnvelope, SimulationOrigin, Timestamp, Timestamps, Unit,
};
use serde::{Deserialize, Serialize};

pub const MACHINE_ID: &str = "M-01";
pub const SIMULATION_ORIGIN_ID: &str = "oip-local-simulation-v1";
pub const DEFAULT_BULK_NODE_COUNT: usize = 1_000;
pub const SIMULATION_EPOCH_UNIX_MS: i64 = 1_700_000_000_000;

/// Value-level scenario of the simulated plant.
///
/// These scenarios change the reported measurement values, quality and
/// collection errors. They do not open or close a socket and they do not stop
/// or start a server process. The transport-level equivalents — an actual
/// disconnect, a server restart and the subsequent reconnect — are exercised by
/// the adapter integration tests, which stop and restart the local server on
/// the same loopback port.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Scenario {
    /// Nominal operation.
    Normal,
    /// Temperature rises over the simulated time span.
    TemperatureRise,
    /// The temperature sensor reports a critical value and the alarm is active.
    CriticalSensor,
    /// The temperature sensor reports an invalid measurement.
    SensorFault,
    /// The collector is unavailable because the server is restarting.
    ServerRestart,
    /// The connection to the collector is interrupted.
    ConnectionInterrupted,
    /// Values are reported again after a reconnect.
    Reconnect,
}

#[derive(Debug, thiserror::Error)]
#[error("unknown simulation scenario: {0}")]
pub struct ScenarioParseError(String);

impl std::str::FromStr for Scenario {
    type Err = ScenarioParseError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "normal" => Ok(Self::Normal),
            "temperature_rise" => Ok(Self::TemperatureRise),
            "critical_sensor" => Ok(Self::CriticalSensor),
            "sensor_fault" => Ok(Self::SensorFault),
            "server_restart" => Ok(Self::ServerRestart),
            "connection_interrupted" => Ok(Self::ConnectionInterrupted),
            "reconnect" => Ok(Self::Reconnect),
            _ => Err(ScenarioParseError(value.to_owned())),
        }
    }
}

impl Scenario {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Normal => "normal",
            Self::TemperatureRise => "temperature_rise",
            Self::CriticalSensor => "critical_sensor",
            Self::SensorFault => "sensor_fault",
            Self::ServerRestart => "server_restart",
            Self::ConnectionInterrupted => "connection_interrupted",
            Self::Reconnect => "reconnect",
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct SimulationConfig {
    pub seed: u64,
    pub tick_duration_ms: u64,
    pub bulk_node_count: usize,
}

impl Default for SimulationConfig {
    fn default() -> Self {
        Self {
            seed: 42,
            tick_duration_ms: 1_000,
            bulk_node_count: DEFAULT_BULK_NODE_COUNT,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SimulationEvent {
    Normal,
    TemperatureRise,
    CriticalSensor,
    SensorFault,
    ServerRestartRequested,
    ConnectionInterrupted,
    Reconnected,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct BulkNode {
    pub index: usize,
    pub value: f64,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct SimulationFrame {
    pub tick: u64,
    pub virtual_time_ms: u64,
    pub scenario: Scenario,
    pub event: SimulationEvent,
    pub origin: SimulationOrigin,
    pub observations: Vec<ObservationEnvelope>,
    pub bulk_nodes: Vec<BulkNode>,
}

impl SimulationFrame {
    pub fn observation(&self, metric_id: &str) -> Option<&ObservationEnvelope> {
        self.observations
            .iter()
            .find(|observation| observation.metric_id.as_str() == metric_id)
    }
}

#[derive(Clone, Debug)]
pub struct Simulation {
    config: SimulationConfig,
    scenario: Scenario,
    next_tick: u64,
}

impl Simulation {
    pub fn new(config: SimulationConfig, scenario: Scenario) -> Self {
        Self {
            config,
            scenario,
            next_tick: 0,
        }
    }

    pub fn config(&self) -> &SimulationConfig {
        &self.config
    }

    pub fn scenario(&self) -> Scenario {
        self.scenario
    }

    pub fn set_scenario(&mut self, scenario: Scenario) {
        self.scenario = scenario;
    }

    pub fn next_frame(&mut self) -> SimulationFrame {
        let tick = self.next_tick;
        self.next_tick = self.next_tick.saturating_add(1);
        self.frame_at(tick)
    }

    pub fn frame_at(&self, tick: u64) -> SimulationFrame {
        let virtual_time_ms = tick.saturating_mul(self.config.tick_duration_ms);
        let sequence = tick;
        let origin = SimulationOrigin {
            origin_id: SIMULATION_ORIGIN_ID.to_owned(),
            seed: Some(self.config.seed),
            scenario: Some(self.scenario.as_str().to_owned()),
            virtual_time_ms: Some(virtual_time_ms),
            sequence: Some(sequence),
        };
        let source = Timestamp::from_unix_millis(
            SIMULATION_EPOCH_UNIX_MS
                .saturating_add(i64::try_from(virtual_time_ms).unwrap_or(i64::MAX)),
        );
        let event = match self.scenario {
            Scenario::Normal => SimulationEvent::Normal,
            Scenario::TemperatureRise => SimulationEvent::TemperatureRise,
            Scenario::CriticalSensor => SimulationEvent::CriticalSensor,
            Scenario::SensorFault => SimulationEvent::SensorFault,
            Scenario::ServerRestart => SimulationEvent::ServerRestartRequested,
            Scenario::ConnectionInterrupted => SimulationEvent::ConnectionInterrupted,
            Scenario::Reconnect => SimulationEvent::Reconnected,
        };

        // `server_restart` and `connection_interrupted` describe the state of
        // the collector, not a socket operation: the values become unavailable
        // and the collection error names the actual reason.
        let unavailable = matches!(
            self.scenario,
            Scenario::ConnectionInterrupted | Scenario::ServerRestart
        );
        let temperature_invalid = matches!(self.scenario, Scenario::SensorFault);
        let alarm_active = matches!(
            self.scenario,
            Scenario::CriticalSensor | Scenario::SensorFault
        );
        let motor_running = !matches!(self.scenario, Scenario::ServerRestart);
        let operating_mode = if matches!(self.scenario, Scenario::ServerRestart) {
            "stopped"
        } else {
            "automatic"
        };

        let temperature_tenths = match self.scenario {
            Scenario::CriticalSensor => 950 + triangle(tick, 12),
            Scenario::TemperatureRise => {
                600 + triangle(tick, 20)
                    + i64::try_from(tick.saturating_mul(5))
                        .unwrap_or(i64::MAX)
                        .min(300)
            }
            _ => 600 + triangle(tick, 20) + noise(self.config.seed, tick, 1),
        };
        let pressure_tenths = 3_200 + triangle(tick, 16) + noise(self.config.seed, tick, 2);

        let observations = vec![
            self.observation(
                "temperature",
                if unavailable || temperature_invalid {
                    None
                } else {
                    Some(MetricValue::Float(temperature_tenths as f64 / 10.0))
                },
                Unit::Celsius,
                temperature_invalid,
                unavailable,
                source,
                &origin,
            ),
            self.observation(
                "pressure",
                if unavailable {
                    None
                } else {
                    Some(MetricValue::Float(pressure_tenths as f64 / 10.0))
                },
                Unit::KiloPascal,
                false,
                unavailable,
                source,
                &origin,
            ),
            self.observation(
                "motor_running",
                if unavailable {
                    None
                } else {
                    Some(MetricValue::Boolean(motor_running))
                },
                Unit::None,
                false,
                unavailable,
                source,
                &origin,
            ),
            self.observation(
                "operating_mode",
                if unavailable {
                    None
                } else {
                    Some(MetricValue::Text(operating_mode.to_owned()))
                },
                Unit::None,
                false,
                unavailable,
                source,
                &origin,
            ),
            self.observation(
                "alarm_active",
                if unavailable {
                    None
                } else {
                    Some(MetricValue::Boolean(alarm_active))
                },
                Unit::None,
                false,
                unavailable,
                source,
                &origin,
            ),
            self.observation(
                "units_produced",
                if unavailable {
                    None
                } else {
                    Some(MetricValue::UnsignedInteger(tick / 10))
                },
                Unit::Count,
                false,
                unavailable,
                source,
                &origin,
            ),
        ];

        let bulk_nodes = (0..self.config.bulk_node_count)
            .map(|index| BulkNode {
                index,
                value: deterministic_hash(self.config.seed, tick, index as u64 + 100) as f64
                    / 1_000_000.0,
            })
            .collect();

        SimulationFrame {
            tick,
            virtual_time_ms,
            scenario: self.scenario,
            event,
            origin,
            observations,
            bulk_nodes,
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn observation(
        &self,
        metric_id: &str,
        value: Option<MetricValue>,
        unit: Unit,
        invalid: bool,
        unavailable: bool,
        source: Timestamp,
        origin: &SimulationOrigin,
    ) -> ObservationEnvelope {
        let (quality, freshness, collection_error) = if unavailable {
            let error = match self.scenario {
                Scenario::ServerRestart => CollectionError::CollectorUnavailable,
                _ => CollectionError::ConnectionInterrupted,
            };
            (DataQuality::Unknown, Freshness::Unknown, Some(error))
        } else if invalid {
            (
                DataQuality::Bad,
                Freshness::Fresh,
                Some(CollectionError::InvalidMeasurement),
            )
        } else {
            (DataQuality::Good, Freshness::Fresh, None)
        };

        ObservationEnvelope {
            entity_id: EntityId::new(MACHINE_ID).expect("static machine id is valid"),
            data_source_id: DataSourceId::new(SIMULATION_ORIGIN_ID)
                .expect("static data source id is valid"),
            metric_id: MetricId::new(metric_id).expect("static metric id is valid"),
            value,
            unit,
            quality,
            freshness,
            timestamps: Timestamps {
                source,
                server: None,
                received: None,
            },
            status_code: None,
            collection_error,
            simulation_origin: Some(origin.clone()),
        }
    }
}

fn triangle(tick: u64, period: u64) -> i64 {
    let phase = tick % period;
    let half = period / 2;
    i64::try_from(if phase <= half { phase } else { period - phase }).unwrap_or(i64::MAX)
}

fn noise(seed: u64, tick: u64, channel: u64) -> i64 {
    (deterministic_hash(seed, tick, channel) % 3) as i64 - 1
}

fn deterministic_hash(seed: u64, tick: u64, channel: u64) -> u64 {
    let mut value = seed
        ^ tick.wrapping_mul(0x9E37_79B9_7F4A_7C15)
        ^ channel.wrapping_mul(0xBF58_476D_1CE4_E5B9);
    value = (value ^ (value >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    value = (value ^ (value >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    value ^ (value >> 31)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn same_seed_and_virtual_time_reproduce_the_same_frame() {
        let config = SimulationConfig::default();
        let first = Simulation::new(config.clone(), Scenario::TemperatureRise);
        let second = Simulation::new(config, Scenario::TemperatureRise);
        assert_eq!(first.frame_at(17), second.frame_at(17));
    }

    #[test]
    fn different_seed_changes_measurements() {
        let first = Simulation::new(SimulationConfig::default(), Scenario::Normal).frame_at(4);
        let second = Simulation::new(
            SimulationConfig {
                seed: 43,
                ..SimulationConfig::default()
            },
            Scenario::Normal,
        )
        .frame_at(4);
        assert_ne!(first, second);
    }

    #[test]
    fn default_frame_contains_machine_metrics_and_scalable_address_space() {
        let frame = Simulation::new(SimulationConfig::default(), Scenario::Normal).frame_at(0);
        assert_eq!(frame.observations.len(), 6);
        assert_eq!(frame.bulk_nodes.len(), 1_000);
        for metric in [
            "temperature",
            "pressure",
            "motor_running",
            "operating_mode",
            "alarm_active",
            "units_produced",
        ] {
            assert!(frame.observation(metric).is_some(), "missing {metric}");
        }
        assert!(frame
            .observations
            .iter()
            .all(|observation| observation.simulation_origin == Some(frame.origin.clone())));
    }

    #[test]
    fn sensor_fault_is_bad_and_never_numeric_zero() {
        let frame = Simulation::new(SimulationConfig::default(), Scenario::SensorFault).frame_at(8);
        let temperature = frame.observation("temperature").expect("temperature");
        assert_eq!(temperature.value, None);
        assert_eq!(temperature.quality, DataQuality::Bad);
        assert_eq!(
            temperature.collection_error,
            Some(CollectionError::InvalidMeasurement)
        );
        assert!(!temperature.is_usable());
    }

    #[test]
    fn interrupted_connection_is_unknown_not_offline() {
        let frame = Simulation::new(SimulationConfig::default(), Scenario::ConnectionInterrupted)
            .frame_at(8);
        let pressure = frame.observation("pressure").expect("pressure");
        assert_eq!(pressure.value, None);
        assert_eq!(pressure.quality, DataQuality::Unknown);
        assert_eq!(pressure.freshness, Freshness::Unknown);
        assert_eq!(
            pressure.collection_error,
            Some(CollectionError::ConnectionInterrupted)
        );
    }

    #[test]
    fn virtual_time_controls_source_timestamp() {
        let simulation = Simulation::new(SimulationConfig::default(), Scenario::Normal);
        let frame = simulation.frame_at(3);
        assert_eq!(frame.virtual_time_ms, 3_000);
        assert_eq!(
            frame
                .observation("temperature")
                .expect("temperature")
                .timestamps
                .source,
            Timestamp::from_unix_millis(SIMULATION_EPOCH_UNIX_MS + 3_000)
        );
    }
}
