use async_trait::async_trait;
pub use oip_core::{ClientEvent, DataGap};
use oip_core::{EntityId, MetricId, ObservationEnvelope, TimestampError};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::time::Duration;
use thiserror::Error;

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct EndpointInfo {
    pub url: String,
    pub security_policy: String,
    pub security_mode: String,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct BrowseEntry {
    pub node_id: String,
    pub browse_name: String,
    pub display_name: String,
    pub node_class: String,
    /// The folder the node lives in: the browse name of its parent.
    ///
    /// It is the **structure of the address space of the server** and not a
    /// name derived from the node itself. A server that organises its
    /// variables in folders is browsed as it is.
    pub folder: String,
}

/// Security posture requested by the caller.
///
/// `LocalSimulation` is the only profile that may use `SecurityPolicy=None`
/// and anonymous authentication. It is bound to loopback endpoints only.
#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub enum SecurityProfile {
    LocalSimulation,
    /// Requires `Basic256Sha256`, `SignAndEncrypt` and explicit PKI paths.
    /// Unknown, invalid or expired certificates are never trusted implicitly.
    Production {
        security_policy: String,
        security_mode: String,
    },
}

impl SecurityProfile {
    pub fn is_local_simulation(&self) -> bool {
        matches!(self, Self::LocalSimulation)
    }
}

/// Explicit PKI material for `SignAndEncrypt` with `Basic256Sha256`.
///
/// Certificate and key paths are relative to `pki_dir`. Peer certificates must
/// already be present in `pki_dir/trusted`; unknown certificates are never
/// promoted automatically. Private key contents are never logged.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ProductionSecurityConfig {
    pub pki_dir: PathBuf,
    pub certificate_path: PathBuf,
    pub private_key_path: PathBuf,
}

impl ProductionSecurityConfig {
    pub fn new(
        pki_dir: impl Into<PathBuf>,
        certificate_path: impl Into<PathBuf>,
        private_key_path: impl Into<PathBuf>,
    ) -> Self {
        Self {
            pki_dir: pki_dir.into(),
            certificate_path: certificate_path.into(),
            private_key_path: private_key_path.into(),
        }
    }

    #[cfg(feature = "async-opcua-backend")]
    pub(crate) fn validate_paths(&self) -> Result<(), AdapterError> {
        if !self.pki_dir.is_absolute() {
            return Err(AdapterError::InvalidSecurityConfiguration(
                "PKI directory must be absolute".to_owned(),
            ));
        }
        for (label, path) in [
            ("certificate", &self.certificate_path),
            ("private key", &self.private_key_path),
        ] {
            if path.is_absolute()
                || path
                    .components()
                    .any(|component| !matches!(component, std::path::Component::Normal(_)))
            {
                return Err(AdapterError::InvalidSecurityConfiguration(format!(
                    "{label} path must be a traversal-free relative path"
                )));
            }
            if !self.pki_dir.join(path).is_file() {
                return Err(AdapterError::InvalidSecurityConfiguration(format!(
                    "{label} file is missing"
                )));
            }
        }
        if !self.pki_dir.join("trusted").is_dir() {
            return Err(AdapterError::InvalidSecurityConfiguration(
                "explicit trusted certificate directory is missing".to_owned(),
            ));
        }
        Ok(())
    }
}

/// Freshness policy applied to observations received from a remote source.
#[derive(Clone, Debug, PartialEq)]
pub struct FreshnessPolicy {
    /// Maximum accepted age of a source timestamp for wall-clock sources.
    /// `None` disables ageing.
    pub max_source_age: Option<Duration>,
    /// Maximum accepted clock skew of a source timestamp into the future.
    pub max_future_skew: Duration,
}

impl Default for FreshnessPolicy {
    fn default() -> Self {
        Self {
            max_source_age: Some(Duration::from_secs(10)),
            max_future_skew: Duration::from_secs(5),
        }
    }
}

/// Options for connecting a read-only adapter to an OPC UA endpoint.
#[derive(Clone, Debug, PartialEq)]
pub struct ClientOptions {
    pub endpoint: String,
    pub namespace: u16,
    pub security_profile: SecurityProfile,
    /// Required iff `security_profile` is `Production`.
    pub production_security: Option<ProductionSecurityConfig>,
    /// Maximum number of session reconnect attempts. Must be finite.
    pub session_retry_limit: i32,
    pub freshness: FreshnessPolicy,
    /// Maximum number of nodes the adapter traverses while browsing.
    pub max_browse_nodes: usize,
    /// The entity of the source: the machine the measurements of the source
    /// belong to. The adapter delivers the observations with **this** entity
    /// — the machine id of a simulation is a property of the simulation, not
    /// of the source that collects it.
    pub entity_id: Option<oip_core::EntityId>,
}

impl ClientOptions {
    /// The options of a source whose measurements belong to a named entity.
    pub fn local_simulation_of(
        endpoint: impl Into<String>,
        namespace: u16,
        entity_id: oip_core::EntityId,
    ) -> Self {
        let mut options = Self::local_simulation(endpoint, namespace);
        options.entity_id = Some(entity_id);
        options
    }

    pub fn local_simulation(endpoint: impl Into<String>, namespace: u16) -> Self {
        Self {
            endpoint: endpoint.into(),
            namespace,
            security_profile: SecurityProfile::LocalSimulation,
            production_security: None,
            session_retry_limit: 20,
            freshness: FreshnessPolicy::default(),
            max_browse_nodes: 5_000,
            entity_id: None,
        }
    }
}

#[derive(Debug, Error)]
pub enum AdapterError {
    #[error("only loopback OPC UA simulation endpoints are allowed: {0}")]
    NonLoopbackEndpoint(String),
    #[error("OPC UA connection failed: {0}")]
    Connection(String),
    #[error("OPC UA protocol operation failed: {0}")]
    Protocol(String),
    #[error("OPC UA value is not supported by the neutral model: {0}")]
    UnsupportedValue(String),
    #[error("OPC UA input value is invalid: {0}")]
    InvalidValue(String),
    #[error("OPC UA value is missing its source timestamp")]
    MissingSourceTimestamp,
    #[error("OPC UA endpoint returned no usable endpoints")]
    NoEndpoints,
    #[error("OPC UA source timestamp is outside the accepted range")]
    TimestampOutOfRange,
    #[error("OPC UA source provenance does not match the expected origin")]
    UntrustedProvenance,
    #[error("OPC UA browse exceeded the configured node limit of {0}")]
    BrowseLimitExceeded(usize),
    #[error("invalid OPC UA security configuration: {0}")]
    InvalidSecurityConfiguration(String),
    #[error(transparent)]
    Timestamp(#[from] TimestampError),
    #[error("OPC UA task failed: {0}")]
    Task(String),
}

/// Read-only OPC UA adapter boundary.
///
/// The trait intentionally exposes no write, method-call or node-management
/// operation. Observations, connection loss and data gaps are delivered through
/// [`ReadOnlyOpcUaAdapter::next_event`] so that the neutral contract covers the
/// full collection path.
#[async_trait]
pub trait ReadOnlyOpcUaAdapter: Send + Sync {
    async fn endpoints(&self) -> Result<Vec<EndpointInfo>, AdapterError>;
    async fn browse(&self) -> Result<Vec<BrowseEntry>, AdapterError>;
    async fn read(&self, metric: &MetricId) -> Result<ObservationEnvelope, AdapterError>;
    /// Reads the value of the node with the given **node id** of the server.
    ///
    /// The browse delivers the node id of every node of the address space.
    /// The value belongs to that node — not to a node that is reconstructed
    /// from its name — and it is bound to the entity that the **source**
    /// declares.
    async fn read_node(
        &self,
        node_id: &str,
        name: &MetricId,
        entity: &EntityId,
    ) -> Result<ObservationEnvelope, AdapterError>;
    async fn subscribe(&self, metrics: &[MetricId]) -> Result<(), AdapterError>;
    /// Waits for the next collection event.
    async fn next_event(&self, timeout: Duration) -> Result<ClientEvent, AdapterError>;
}
