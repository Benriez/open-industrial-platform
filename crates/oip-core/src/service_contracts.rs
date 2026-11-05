//! Transport-independent application read models; legacy v1 JSON names are retained.
use crate::ObservationEnvelope;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct Health {
    pub reachability: String,
    pub vpn_transport: String,
    pub agent_availability: String,
    pub service_health: String,
    pub telemetry_freshness: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct Device {
    pub data_source_id: Option<crate::DataSourceId>,
    pub is_faulted: bool,
    pub id: String,
    pub name: String,
    pub kind: String,
    pub location: String,
    pub connection: String,
    pub simulated: bool,
    pub health: Health,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct Incident {
    pub id: String,
    pub title: String,
    pub category: String,
    pub device_id: String,
    pub simulated: bool,
    pub supporting: Vec<String>,
    pub contradicting: Vec<String>,
    pub missing: Vec<String>,
    pub timeline: Vec<String>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct Link {
    pub from: String,
    pub to: String,
    pub transport: String,
    pub latency_ms: Option<f64>,
    pub packet_loss_percent: Option<f64>,
    pub status: String,
    pub simulated: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct SystemStatus {
    pub primary_source_id: crate::DataSourceId,
    pub api_version: String,
    pub simulated: bool,
    pub demo_controls: bool,
    pub scenario: String,
    pub opcua_status: String,
    pub subscription_status: String,
    pub last_received_ms: Option<i64>,
    pub generated_at_ms: i64,
    pub persisted_observations: u64,
    pub cpu_percent: Option<f64>,
    pub gpu_percent: Option<f64>,
    pub ram_percent: Option<f64>,
    pub network_status: String,
    pub security_blocker: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct Snapshot {
    pub core: crate::CoreHealth,
    pub sources: Vec<crate::SourceHealth>,
    pub queue: QueueHealth,
    pub resync_required: bool,
    pub system: SystemStatus,
    pub devices: Vec<Device>,
    pub metrics: Vec<ObservationEnvelope>,
    pub incidents: Vec<Incident>,
    pub topology: Vec<Link>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct Node {
    pub data_source_id: crate::DataSourceId,
    pub node_id: String,
    pub name: String,
    pub namespace: u16,
    pub folder: String,
    pub data_type: String,
    pub access: String,
    pub observation: Option<ObservationEnvelope>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct NodePage {
    pub items: Vec<Node>,
    pub total: usize,
    pub offset: usize,
    pub limit: usize,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct DeviceDetail {
    pub device: Device,
    pub metrics: Vec<ObservationEnvelope>,
    pub history_status: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct EventsResponse {
    pub incidents: Vec<Incident>,
    pub collection_events: Vec<crate::ClientEvent>,
    pub records: Vec<crate::EventRecord>,
    pub diagnosis_history_status: String,
    pub replay_supported: bool,
    pub resync_required: bool,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct ScenarioResponse {
    pub accepted: bool,
    pub simulated: bool,
    pub scenario: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct QueueHealth {
    pub capacity: usize,
    pub depth: usize,
    pub backpressure_waits: u64,
    pub rejected_submissions: u64,
}
