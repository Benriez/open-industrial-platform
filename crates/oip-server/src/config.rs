use crate::collector::METRICS;
use oip_core::{DataSourceId, EntityId, MetricId, SourceDefinition, ValueKind};
use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, BTreeSet},
    path::PathBuf,
};
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
    /// Explicit read-only OPC UA polling profile. An absent profile is the
    /// existing local simulator contract.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub opcua: Option<OpcUaReadProfile>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct OpcUaReadProfile {
    pub namespace_uri: String,
    pub server_application_uri: String,
    pub poll_ms: u64,
    pub pki_dir: PathBuf,
    pub certificate_path: PathBuf,
    pub private_key_path: PathBuf,
    pub points: Vec<OpcUaReadPoint>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct OpcUaReadPoint {
    pub metric: MetricId,
    /// The identifier part of a NodeId (e.g. `s=Temperature` or `i=123`).
    /// The namespace index never belongs in persisted configuration.
    pub node_id: String,
    pub value_kind: ValueKind,
}

impl OpcUaReadProfile {
    fn validate(&self) -> Result<(), String> {
        let valid_uri = |uri: &str| {
            uri.len() <= 512
                && !uri.chars().any(char::is_whitespace)
                && uri
                    .split_once(':')
                    .is_some_and(|(scheme, rest)| !scheme.is_empty() && !rest.is_empty())
        };
        if !valid_uri(&self.namespace_uri)
            || !valid_uri(&self.server_application_uri)
            || !self.pki_dir.is_absolute()
            || !(5_000..=60_000).contains(&self.poll_ms)
            || !(1..=16).contains(&self.points.len())
        {
            return Err("invalid OPC-UA read profile: require explicit URIs, PKI, 1–16 points and a 5–60 second interval".into());
        }
        for path in [&self.certificate_path, &self.private_key_path] {
            if path.as_os_str().is_empty()
                || path
                    .components()
                    .any(|component| !matches!(component, std::path::Component::Normal(_)))
            {
                return Err("OPC-UA identity files must be relative to the PKI directory".into());
            }
        }
        let mut metrics = BTreeSet::new();
        let mut nodes = BTreeSet::new();
        for point in &self.points {
            let identifier = oip_opcua::async_opcua::canonical_node_identifier(&point.node_id)
                .ok_or(
                "invalid OPC-UA point identifier: provide an identifier without a namespace index",
            )?;
            if !metrics.insert(&point.metric) || !nodes.insert(identifier) {
                return Err("duplicate metric or OPC-UA point identifier".into());
            }
        }
        Ok(())
    }
}
/// An OPC-UA browser binding for a source already registered by another OIP
/// integration (for example the SSH host collector). It never provisions a
/// source or changes its identity; the endpoint must be a loopback address,
/// normally reached through a local SSH forward.
#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct OpcUaBrowseSource {
    pub id: String,
    pub endpoint: String,
    #[serde(default = "namespace")]
    pub namespace: u16,
    pub entity_id: String,
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
            opcua: None,
        }
    }
    pub fn definition(&self) -> Result<SourceDefinition, String> {
        if let Some(profile) = &self.opcua {
            profile.validate()?;
            let points = profile
                .points
                .iter()
                .map(|point| {
                    let canonical =
                        oip_opcua::async_opcua::canonical_node_identifier(&point.node_id)
                            .expect("validated point identifier");
                    (&point.metric, canonical)
                })
                .collect::<BTreeMap<_, _>>();
            // The persisted source definition rejects reusing a source identity
            // for a different server, namespace or point mapping during restore
            // or restart. Cadence and credential file paths are operational.
            let binding = serde_json::to_string(&(
                &self.endpoint,
                &profile.server_application_uri,
                &profile.namespace_uri,
                points,
            ))
            .map_err(|_| "OPC-UA source binding")?;
            let metrics = profile
                .points
                .iter()
                .map(|point| (point.metric.clone(), point.value_kind))
                .collect::<BTreeMap<_, _>>();
            return Ok(SourceDefinition {
                id: DataSourceId::new(&self.id).map_err(|_| "source id")?,
                name: self.name.clone(),
                entity_id: EntityId::new(
                    self.entity_id
                        .as_deref()
                        .ok_or("OPC-UA source requires an entity")?,
                )
                .map_err(|_| "entity")?,
                binding,
                origin_class: oip_core::OriginClass::External,
                simulation_origin_id: String::new(),
                required_metrics: metrics.keys().cloned().collect(),
                metrics,
            });
        }
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
            entity_id: EntityId::new(self.entity_id.as_deref().unwrap_or("M-01"))
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
            source
                .definition()
                .expect("the definition")
                .entity_id
                .as_str(),
            "M-01"
        );
        // An instance of the operator names its own entity.
        source.entity_id = Some("pi-simulation".to_owned());
        assert_eq!(
            source
                .definition()
                .expect("the definition")
                .entity_id
                .as_str(),
            "pi-simulation"
        );
    }
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default, deny_unknown_fields)]
pub struct CoreConfig {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub ssh: Option<crate::ssh::SshSettings>,
    /// Read-only Philips Hue bridges whose identity is verified against the
    /// pinned certificate of the bridge. Without a profile there is no Hue
    /// collector: the instance never reads a bridge it has not been told to.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hue: Option<crate::hue::HueSettings>,
    pub legacy_single_infrastructure: bool,
    /// Read local Tailscale peer membership and project only matches onto the
    /// authorized device inventory. Disabled unless the operator opts in.
    #[serde(default)]
    pub tailscale_peer_status: bool,
    pub database: PathBuf,
    /// Private sidecar that persists only digests of native device credentials
    /// and their authorized principals. Session cookies and login grants remain
    /// ephemeral. If omitted, CoreRuntime derives it beside the database.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub browser_credentials_file: Option<PathBuf>,
    pub http_port: u16,
    pub sources: Vec<SourceConfig>,
    /// Installation-wide authoritative permission for incoming OPC-UA
    /// operations. Existing installations retain their current permission model.
    pub opcua_read_only: bool,
    #[serde(default)]
    pub opcua_browse_sources: Vec<OpcUaBrowseSource>,
    pub queue_capacity: usize,
    pub stale_after_ms: i64,
    pub shutdown_timeout_ms: u64,
    pub web_dir: Option<String>,
}
impl Default for CoreConfig {
    fn default() -> Self {
        Self {
            ssh: None,
            hue: None,
            legacy_single_infrastructure: false,
            tailscale_peer_status: false,
            database: "oip.sqlite".into(),
            browser_credentials_file: None,
            http_port: 8080,
            sources: Vec::new(),
            opcua_read_only: false,
            opcua_browse_sources: Vec::new(),
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
            || self
                .browser_credentials_file
                .as_ref()
                .is_some_and(|path| path.as_os_str().is_empty())
            || self.sources.len() > 32
            || self.opcua_browse_sources.len() > 64
            || !(1..=4096).contains(&self.queue_capacity)
            || self.stale_after_ms <= 0
            || self.shutdown_timeout_ms < 100
        {
            return Err("invalid core configuration bounds".into());
        }
        let mut ids = BTreeSet::new();
        let mut endpoints = BTreeSet::new();
        for s in &self.sources {
            if (s.opcua.is_none() && s.namespace != 2)
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
            oip_opcua::validate_client_endpoint(&s.endpoint, s.opcua.is_none())
                .map_err(|_| "OPC-UA source must use an explicit IP endpoint without credentials; simulation requires loopback")?;
            s.definition()?;
        }
        if self
            .sources
            .iter()
            .filter(|source| source.opcua.is_some())
            .count()
            > 1
            || (self.sources.iter().any(|source| source.opcua.is_some())
                && (!self.opcua_read_only || self.legacy_single_infrastructure))
        {
            return Err("only one secured read-only OPC-UA source is supported; explicit scoped provisioning is required".into());
        }
        let mut browse_ids = BTreeSet::new();
        for source in &self.opcua_browse_sources {
            if source.id.is_empty()
                || source.id.len() > 128
                || !source
                    .id
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b"-_:.".contains(&b))
                || source.namespace == 0
                || source.entity_id.is_empty()
                || source.entity_id.len() > 128
                || !browse_ids.insert(&source.id)
                || ids.contains(&source.id)
            {
                return Err("duplicate or invalid OPC-UA browser source binding".into());
            }
            oip_opcua::validate_client_endpoint(&source.endpoint, true)
                .map_err(|_| "OPC-UA browser source must use a literal loopback endpoint")?;
        }
        if let Some(hue) = &self.hue {
            hue.validate(None)
                .map_err(|error| format!("hue profile: {}", error.code))?;
        }
        Ok(())
    }
}
