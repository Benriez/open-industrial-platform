//! Local, explicitly authorized setup of one bounded read-only OPC-UA source.
use crate::{DataSourceId, DeviceId, MetricId, SiteId, ValueKind};
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(deny_unknown_fields)]
pub struct OpcuaSetupPoint {
    pub metric: MetricId,
    pub node_id: String,
    pub value_kind: ValueKind,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(deny_unknown_fields)]
pub struct OpcuaSourceSetup {
    pub endpoint: String,
    pub server_application_uri: String,
    pub namespace_uri: String,
    pub poll_seconds: u16,
    pub points: Vec<OpcuaSetupPoint>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(deny_unknown_fields)]
pub struct OpcuaSetupRequest {
    pub site: SiteId,
    pub device: DeviceId,
    pub operation: OpcuaSetupOperation,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(tag = "action", rename_all = "snake_case", deny_unknown_fields)]
pub enum OpcuaSetupOperation {
    Status,
    Preview {
        /// Required for a new source. Omit for certificate rotation.
        configuration: Option<OpcuaSourceSetup>,
        server_certificate_pem: String,
    },
    Apply {
        confirmation: String,
        verified_sha256: String,
    },
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct OpcuaCertificateDetails {
    pub sha256: String,
    pub subject: String,
    pub valid_until: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum OpcuaSetupResult {
    Unconfigured,
    Preview {
        configuration: OpcuaSourceSetup,
        certificate: OpcuaCertificateDetails,
        previous_sha256: Option<String>,
        confirmation: String,
    },
    Configured {
        source: DataSourceId,
        configuration: OpcuaSourceSetup,
        server_sha256: String,
        client_certificate_pem: String,
        collector_enabled: bool,
    },
}
