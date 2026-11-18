//! Connection setup is explicit evidence, separate from inventory registration.
use crate::*;
use serde::{Deserialize, Serialize};
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(deny_unknown_fields)]
pub struct DeviceDraft {
    pub display_name: String,
    pub device_type: DeviceType,
    pub site_id: SiteId,
    #[serde(default)]
    pub metadata: DeviceMetadata,
}
impl DeviceDraft {
    pub fn registration(self, id: DeviceId) -> DeviceRegistration {
        DeviceRegistration {
            id,
            display_name: self.display_name,
            device_type: self.device_type,
            site_id: self.site_id,
            metadata: self.metadata,
        }
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(tag = "kind", rename_all = "snake_case", deny_unknown_fields)]
pub enum ConnectionTarget {
    Existing {
        id: DeviceId,
        expected_revision: u64,
    },
    New {
        device: Box<DeviceDraft>,
    },
}
fn port22() -> u16 {
    22
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(deny_unknown_fields)]
pub struct SshEndpoint {
    pub host: String,
    #[serde(default = "port22")]
    pub port: u16,
    pub user: String,
    pub identity_profile: String,
    #[serde(default)]
    pub alias: Option<String>,
}
impl SshEndpoint {
    pub fn validate(&self) -> Result<(), CapabilityError> {
        let host_ok = self.host.parse::<std::net::IpAddr>().is_ok()
            || (!self.host.is_empty()
                && self.host.len() <= 253
                && self.host.split('.').all(|s| {
                    !s.is_empty()
                        && s.len() <= 63
                        && s.bytes().next().is_some_and(|b| b.is_ascii_alphanumeric())
                        && s.bytes().last().is_some_and(|b| b.is_ascii_alphanumeric())
                        && s.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-')
                }));
        if !host_ok
            || self.port == 0
            || self.user == "root"
            || self.user.is_empty()
            || self.user.len() > 64
            || !self
                .user
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b"_.-".contains(&b))
            || self.user.starts_with('-')
            || self.identity_profile.is_empty()
            || self.identity_profile.len() > 64
            || !self
                .identity_profile
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b"_.-".contains(&b))
        {
            return Err(connection_error("INVALID_SSH_ENDPOINT","A single explicit host, non-root user and authorized identity profile are required"));
        }
        Ok(())
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(tag = "operation", rename_all = "snake_case", deny_unknown_fields)]
pub enum ConnectionAction {
    Start {
        target: ConnectionTarget,
        endpoint: SshEndpoint,
    },
    TrustHostKey {
        plan_id: String,
        fingerprint: String,
    },
    Verify {
        plan_id: String,
    },
    Confirm {
        plan_id: String,
        identity_confirmed: bool,
        enable_monitoring: bool,
        poll_seconds: u64,
    },
    Monitoring {
        device_id: DeviceId,
        expected_revision: u64,
        enabled: bool,
        poll_seconds: u64,
    },
    Cancel {
        plan_id: String,
    },
}
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(default, deny_unknown_fields)]
pub struct ConnectionQuery {
    pub device_id: Option<DeviceId>,
    pub plan_id: Option<String>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct DiskInformation {
    pub filesystem: String,
    pub mount: String,
    pub total_bytes: u64,
    pub used_bytes: u64,
    pub available_bytes: u64,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct NetworkInterfaceInformation {
    pub name: String,
    pub addresses: Vec<String>,
}
/// A neighbor observed by the host's kernel neighbor table. This is direct
/// network evidence; it is kept separate from addresses and never inferred
/// from inventory names or shared subnets.
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(deny_unknown_fields)]
pub struct NetworkNeighborInformation {
    pub address: String,
    pub link_address: Option<String>,
    pub state: String,
}
/// Upper bound of the stored connection record in bytes. The storage schema and
/// the server use the same value, so a verified host report is either storable
/// or rejected with an explicit fault before any write.
pub const CONNECTION_PAYLOAD_MAX_BYTES: usize = 131_072;
/// Upper bound of the stored latest connection attempt in bytes.
pub const CONNECTION_ATTEMPT_PAYLOAD_MAX_BYTES: usize = 16_384;
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct HostInformation {
    pub hostname: String,
    pub operating_system: String,
    pub architecture: String,
    pub cpu_info: Option<String>,
    pub model: Option<String>,
    pub stable_host_id_sha256: Option<String>,
    pub memory_total_bytes: Option<u64>,
    pub memory_used_bytes: Option<u64>,
    /// Adapter label and live GPU/thermal readings are optional because the
    /// host may not expose a kernel sensor for every device.
    #[serde(default)]
    pub gpu_model: Option<String>,
    #[serde(default)]
    pub gpu_utilization_percent: Option<f64>,
    #[serde(default)]
    pub gpu_temperature_c: Option<f64>,
    #[serde(default)]
    pub cpu_temperature_c: Option<f64>,
    #[serde(default)]
    pub soc_temperature_c: Option<f64>,
    #[serde(default)]
    pub memory_used_percent: Option<f64>,
    pub uptime_seconds: Option<f64>,
    pub disks: Vec<DiskInformation>,
    pub interfaces: Vec<NetworkInterfaceInformation>,
    #[serde(default)]
    pub neighbors: Vec<NetworkNeighborInformation>,
    pub captured_at_ms: i64,
    pub unavailable: Vec<String>,
    pub provenance: String,
}
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum ConnectionStage {
    Connecting,
    AwaitingHostKey,
    ReadyForAuthentication,
    Authenticating,
    ReadingDeviceInformation,
    VerificationComplete,
    Committing,
    Failed,
    Committed,
    Cancelled,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct ConnectionFault {
    pub code: String,
    pub message: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct ConnectionPlanStatus {
    pub plan_id: String,
    pub device_id: DeviceId,
    pub site_id: SiteId,
    pub stage: ConnectionStage,
    pub endpoint: SshEndpoint,
    pub host_key_fingerprint: Option<String>,
    pub host_key_trusted: bool,
    pub identity: Option<HostInformation>,
    pub error: Option<ConnectionFault>,
    pub expires_at_ms: i64,
    pub inventory_revision: u64,
}
/// Runtime-owned persisted configuration; contains public host key, never a private SSH key.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DeviceConnectionRecord {
    pub device_id: DeviceId,
    pub source_id: DataSourceId,
    pub authorized_principal: PrincipalId,
    pub endpoint: SshEndpoint,
    pub host_key: String,
    pub fingerprint: String,
    pub identity: HostInformation,
    pub verified_at_ms: i64,
    pub enabled: bool,
    pub poll_seconds: u64,
    pub revision: u64,
    pub last_attempt_ms: Option<i64>,
    pub last_success_ms: Option<i64>,
    pub last_error: Option<ConnectionFault>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct ConnectionView {
    pub device_id: DeviceId,
    pub source_id: DataSourceId,
    pub endpoint: SshEndpoint,
    pub fingerprint: String,
    pub verified_identity: HostInformation,
    pub verified_at_ms: i64,
    pub monitoring_enabled: bool,
    pub poll_seconds: u64,
    pub revision: u64,
    pub last_attempt_ms: Option<i64>,
    pub last_success_ms: Option<i64>,
    pub error: Option<ConnectionFault>,
    pub status: String,
    pub observations: Vec<ObservationEnvelope>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct SshIdentityProfileInfo {
    pub id: String,
    pub label: String,
    pub authentication: String,
    pub aliases: Vec<String>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct ConnectionAttempt {
    pub device_id: DeviceId,
    pub endpoint: SshEndpoint,
    pub at_ms: i64,
    pub stage: ConnectionStage,
    pub error: Option<ConnectionFault>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct ConnectionResult {
    pub profiles: Vec<SshIdentityProfileInfo>,
    pub plan: Option<ConnectionPlanStatus>,
    pub connection: Option<ConnectionView>,
    pub last_attempt: Option<ConnectionAttempt>,
}
#[derive(Clone, Debug)]
pub struct VerifiedConnectionCommit {
    pub principal: PrincipalId,
    pub device: DeviceRegistration,
    pub expected_revision: Option<u64>,
    pub connection: DeviceConnectionRecord,
}
pub fn connection_error(code: &str, message: &str) -> CapabilityError {
    CapabilityError::new(CapabilityErrorCode::InvalidInput, code, message)
}
pub fn ssh_inventory_connectivity(
    c: &DeviceConnectionRecord,
    source: Option<&SourceHealth>,
) -> InventoryConnectivity {
    if c.last_error
        .as_ref()
        .is_some_and(|e| matches!(e.code.as_str(), "SSH_ENDPOINT_UNREACHABLE" | "SSH_TIMEOUT"))
    {
        InventoryConnectivity::ObservedUnreachable
    } else if c.enabled
        && source.is_some_and(|s| {
            s.last_received_ms.is_some()
                && s.connection == ConnectionHealth::Connected
                && s.freshness == Freshness::Fresh
        })
    {
        InventoryConnectivity::ObservedReachable
    } else {
        InventoryConnectivity::Unknown
    }
}
pub fn validate_poll_seconds(seconds: u64) -> Result<(), CapabilityError> {
    if !(10..=3600).contains(&seconds) {
        return Err(connection_error(
            "INVALID_POLL_INTERVAL",
            "Polling must be between10 and3600 seconds",
        ));
    }
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn endpoints_cannot_be_commands_root_or_ranges() {
        for host in [
            "-oProxyCommand=evil",
            "127.0.0.1;id",
            "a b",
            "192.168.1.0/24",
            "a..b",
        ] {
            assert!(SshEndpoint {
                host: host.into(),
                port: 22,
                user: "operator".into(),
                identity_profile: "key".into(),
                alias: None
            }
            .validate()
            .is_err());
        }
        let mut e = SshEndpoint {
            host: "pi.local".into(),
            port: 22,
            user: "pi".into(),
            identity_profile: "key".into(),
            alias: None,
        };
        assert!(e.validate().is_ok());
        e.user = "root".into();
        assert!(e.validate().is_err());
        assert!(validate_poll_seconds(1).is_err());
    }
}
