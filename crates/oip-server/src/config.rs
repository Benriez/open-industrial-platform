use crate::collector::METRICS;
use oip_core::{DataSourceId, EntityId, MetricId, SourceDefinition, ValueKind};
use serde::{Deserialize, Serialize};
use std::{collections::BTreeSet, path::PathBuf};
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SourceConfig {
    pub id: String,
    pub name: String,
    pub endpoint: String,
    #[serde(default = "namespace")]
    pub namespace: u16,
    /// The entity of the source: the machine the measurements belong to.
    /// The default is the legacy demo entity; an instance of the operator
    /// names its own. The plan of the instance and this configuration must
    /// name the same entity — the provisioning refuses a source whose
    /// entity differs.
    #[serde(default)]
    pub entity_id: Option<String>,
}
fn namespace() -> u16 {
    2
}
impl SourceConfig {
    pub fn primary(port: u16) -> Self {
        Self {
            id: oip_simulator::SIMULATION_ORIGIN_ID.into(),
            name: "Local OPC-UA Simulation".into(),
            endpoint: format!("opc.tcp://127.0.0.1:{port}"),
            namespace: 2,
            entity_id: None,
        }
    }
    pub fn definition(&self) -> Result<SourceDefinition, String> {
        let mut metrics = METRICS
            .iter()
            .map(|m| {
                Ok((
                    MetricId::new(*m).map_err(|_| "metric")?,
                    match *m {
                        "motor_running" | "alarm_active" => ValueKind::Boolean,
                        "operating_mode" => ValueKind::Text,
                        "units_produced" => ValueKind::UnsignedInteger,
                        _ => ValueKind::Float,
                    },
                ))
            })
            .collect::<Result<std::collections::BTreeMap<_, _>, String>>()?;
        for n in 0..1000 {
            metrics.insert(
                MetricId::new(format!("bulk.{n:04}")).map_err(|_| "metric")?,
                ValueKind::Float,
            );
        }
        Ok(SourceDefinition {
            id: DataSourceId::new(&self.id).map_err(|_| "source id")?,
            name: self.name.clone(),
            entity_id: EntityId::new(
                self.entity_id.as_deref().unwrap_or("M-01"),
            )
            .map_err(|_| "entity")?,
            binding: self.endpoint.clone(),
            origin_class: oip_core::OriginClass::Simulation,
            simulation_origin_id: oip_simulator::SIMULATION_ORIGIN_ID.into(),
            required_metrics: ["temperature", "pressure"]
                .iter()
                .map(|m| MetricId::new(*m).expect("static metric"))
                .collect(),
            metrics,
        })
    }
}
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_entity_of_a_source_is_part_of_its_definition() {
        let mut source = SourceConfig::primary(4840);
        // The legacy default: the entity of the demo machine.
        assert_eq!(
            source.definition().expect("the definition").entity_id.as_str(),
            "M-01"
        );
        // An instance of the operator names its own entity.
        source.entity_id = Some("pi-simulation".to_owned());
        assert_eq!(
            source.definition().expect("the definition").entity_id.as_str(),
            "pi-simulation"
        );
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct CoreConfig {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ssh: Option<crate::ssh::SshSettings>,
    pub legacy_single_infrastructure: bool,
    pub database: PathBuf,
    pub http_port: u16,
    pub sources: Vec<SourceConfig>,
    pub queue_capacity: usize,
    pub stale_after_ms: i64,
    pub shutdown_timeout_ms: u64,
    pub web_dir: Option<String>,
}
impl Default for CoreConfig {
    fn default() -> Self {
        Self {
            ssh: None,
            legacy_single_infrastructure: false,
            database: "oip.sqlite".into(),
            http_port: 8080,
            sources: Vec::new(),
            queue_capacity: 64,
            stale_after_ms: 5000,
            shutdown_timeout_ms: 10000,
            web_dir: None,
        }
    }
}
impl CoreConfig {
    pub fn validate(&self) -> Result<(), String> {
        if self.http_port == 0
            || self.sources.len() > 32
            || !(1..=4096).contains(&self.queue_capacity)
            || self.stale_after_ms <= 0
            || self.shutdown_timeout_ms < 100
        {
            return Err("invalid core configuration bounds".into());
        }
        let mut ids = BTreeSet::new();
        let mut endpoints = BTreeSet::new();
        for s in &self.sources {
            if s.namespace != 2
                || s.endpoint.contains(":0/")
                || s.endpoint.ends_with(":0")
                || s.id.is_empty()
                || s.id.len() > 128
                || !s
                    .id
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b"-_.".contains(&b))
                || !ids.insert(&s.id)
                || !endpoints.insert(&s.endpoint)
                || s.name.trim().is_empty()
            {
                return Err("duplicate or invalid source identity/binding".into());
            }
            oip_opcua::validate_client_endpoint(&s.endpoint, true).map_err(|_| {
                "source must be a literal loopback OPC-UA simulation endpoint without credentials"
            })?;
            s.definition()?;
        }
        Ok(())
    }
}
