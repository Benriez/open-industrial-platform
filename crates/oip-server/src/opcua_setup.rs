//! Certificate approval and the durable placement of the bounded managed collector.
use crate::{
    config::{CoreConfig, OpcUaReadPoint, OpcUaReadProfile, SourceConfig},
    private_state,
    state::AppState,
};
use base64::{engine::general_purpose::STANDARD, Engine};
use oip_core::*;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeMap,
    fs,
    io::{self, Read},
    net::IpAddr,
    path::{Path, PathBuf},
    time::{Duration, Instant},
};
use tokio::sync::{watch, Mutex};
use x509_parser::{extensions::GeneralName, prelude::*};

const SOURCE: &str = "managed-opcua";
const BINDING: &str = "oip-managed-opcua-v1:";
pub(crate) const MAX_REQUEST: usize = 28 * 1024;
const CERT_LIMIT: usize = 16_384;
const CLIENT_CERT: &str = "client.der";
const CLIENT_KEY: &str = "client.pem";
const SERVER_CERT: &str = "trusted/server.der";

#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct ManagedSource {
    pub site: SiteId,
    pub device: DeviceId,
    configuration: OpcuaSourceSetup,
}

impl ManagedSource {
    pub(crate) fn decode(definition: &SourceDefinition) -> Result<Option<Self>, String> {
        let Some(binding) = definition.binding.strip_prefix(BINDING) else {
            return Ok(None);
        };
        let source: Self = serde_json::from_str(binding).map_err(|_| "managed OPC-UA record")?;
        if definition.id.as_str() != SOURCE
            || definition.entity_id.as_str() != source.device.as_str()
        {
            return Err("managed OPC-UA identity mismatch".into());
        }
        Ok(Some(source))
    }

    pub(crate) fn definition(&self, root: &Path) -> Result<SourceDefinition, String> {
        let mut definition = self.config(root).definition()?;
        definition.binding = format!(
            "{BINDING}{}",
            serde_json::to_string(self).map_err(|_| "managed OPC-UA binding")?
        );
        Ok(definition)
    }

    pub(crate) fn config(&self, root: &Path) -> SourceConfig {
        let q = &self.configuration;
        SourceConfig {
            id: SOURCE.into(),
            name: "OPC UA".into(),
            endpoint: q.endpoint.clone(),
            namespace: 0,
            entity_id: Some(self.device.to_string()),
            opcua: Some(OpcUaReadProfile {
                namespace_uri: q.namespace_uri.clone(),
                server_application_uri: q.server_application_uri.clone(),
                poll_ms: u64::from(q.poll_seconds) * 1000,
                pki_dir: root.into(),
                certificate_path: CLIENT_CERT.into(),
                private_key_path: CLIENT_KEY.into(),
                points: q
                    .points
                    .iter()
                    .map(|point| OpcUaReadPoint {
                        metric: point.metric.clone(),
                        node_id: point.node_id.clone(),
                        value_kind: point.value_kind,
                    })
                    .collect(),
            }),
        }
    }

    pub(crate) fn cadence_ms(&self) -> i64 {
        i64::from(self.configuration.poll_seconds) * 2000 + 5000
    }
}

pub(crate) fn source_id() -> DataSourceId {
    DataSourceId::new(SOURCE).expect("fixed source ID")
}

fn error(kind: CapabilityErrorCode, code: &str, message: &str) -> CapabilityError {
    CapabilityError::new(kind, code, message)
}
fn bad(code: &str, message: &str) -> CapabilityError {
    error(CapabilityErrorCode::InvalidInput, code, message)
}
pub(crate) fn denied() -> CapabilityError {
    error(
        CapabilityErrorCode::PermissionDenied,
        "OPCUA_SETUP_DENIED",
        "OPC-UA setup requires inventory management and OPC-UA permissions for this device's site.",
    )
}
pub(crate) fn unavailable() -> CapabilityError {
    error(CapabilityErrorCode::PersistenceUnavailable, "OPCUA_SETUP_STORAGE", "OIP could not securely save or read the OPC-UA configuration. Check the installation storage and retry.")
}
fn fingerprint(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}
fn pem(label: &str, bytes: &[u8]) -> String {
    use std::fmt::Write;
    let mut result = format!("-----BEGIN {label}-----\n");
    for chunk in STANDARD.encode(bytes).as_bytes().chunks(64) {
        writeln!(
            result,
            "{}",
            std::str::from_utf8(chunk).expect("base64 is ASCII")
        )
        .expect("string write");
    }
    writeln!(result, "-----END {label}-----").expect("string write");
    result
}

fn validate_certificate(
    input: &str,
    source: &ManagedSource,
) -> Result<(Vec<u8>, OpcuaCertificateDetails), CapabilityError> {
    let invalid = || {
        bad(
            "OPCUA_CERT_INVALID",
            "Provide one valid, self-signed RSA server certificate in PEM format.",
        )
    };
    if input.len() > CERT_LIMIT {
        return Err(invalid());
    }
    let body = input
        .trim()
        .strip_prefix("-----BEGIN CERTIFICATE-----")
        .and_then(|s| s.strip_suffix("-----END CERTIFICATE-----"))
        .ok_or_else(invalid)?;
    let encoded: Vec<_> = body.bytes().filter(|b| !b.is_ascii_whitespace()).collect();
    let der = STANDARD.decode(encoded).map_err(|_| invalid())?;
    let (rest, cert) = X509Certificate::from_der(&der).map_err(|_| invalid())?;
    if !rest.is_empty()
        || cert.version() != X509Version::V3
        || cert.issuer() != cert.subject()
        || cert.signature_algorithm != cert.tbs_certificate.signature
        || !matches!(
            cert.signature_algorithm.algorithm.to_id_string().as_str(),
            "1.2.840.113549.1.1.11" | "1.2.840.113549.1.1.12" | "1.2.840.113549.1.1.13"
        )
        || cert.verify_signature(None).is_err()
    {
        return Err(invalid());
    }
    match cert.public_key().parsed() {
        Ok(x509_parser::public_key::PublicKey::RSA(key))
            if (2048..=4096).contains(&key.key_size()) =>
        {
            ()
        }
        _ => return Err(invalid()),
    };
    if cert.extensions_map().is_err()
        || cert.extensions().iter().any(|extension| {
            matches!(
                extension.parsed_extension(),
                x509_parser::extensions::ParsedExtension::ParseError { .. }
            ) || extension.critical
                && matches!(
                    extension.parsed_extension(),
                    x509_parser::extensions::ParsedExtension::UnsupportedExtension { .. }
                )
        })
        || !cert
            .key_usage()
            .map_err(|_| invalid())?
            .is_some_and(|usage| {
                usage.value.digital_signature()
                    && usage.value.key_encipherment()
                    && usage.value.data_encipherment()
            })
        || !cert
            .extended_key_usage()
            .map_err(|_| invalid())?
            .is_some_and(|usage| usage.value.server_auth)
    {
        return Err(invalid());
    }
    if !cert.validity().is_valid() {
        return Err(bad(
            "OPCUA_CERT_TIME",
            "The server certificate is expired or its validity period has not started.",
        ));
    }
    let endpoint = &source.configuration.endpoint;
    let authority = endpoint
        .strip_prefix("opc.tcp://")
        .and_then(|value| value.split('/').next())
        .ok_or_else(invalid)?;
    let (host, _) = authority.rsplit_once(':').ok_or_else(invalid)?;
    let host: IpAddr = host
        .trim_matches(['[', ']'])
        .parse()
        .map_err(|_| invalid())?;
    let san = cert.subject_alternative_name().map_err(|_| invalid())?;
    let matches = san.is_some_and(|san| {
        let names = &san.value.general_names;
        let ip_matches = names.iter().skip(1).any(|name| match (name, host) {
            (GeneralName::IPAddress(bytes), IpAddr::V4(ip)) => *bytes == ip.octets(),
            (GeneralName::IPAddress(bytes), IpAddr::V6(ip)) => *bytes == ip.octets(),
            _ => false,
        });
        let mut uris = names.iter().filter_map(|name| match name {
            GeneralName::URI(uri) => Some(*uri),
            _ => None,
        });
        ip_matches
            && matches!(names.first(), Some(GeneralName::URI(_)))
            && uris.next() == Some(source.configuration.server_application_uri.as_str())
            && uris.next().is_none()
    });
    if !matches {
        return Err(bad("OPCUA_CERT_IDENTITY", "The server certificate must name the configured IP address and server application URI."));
    }
    let details = OpcuaCertificateDetails {
        sha256: fingerprint(&der),
        subject: cert.subject().to_string(),
        valid_until: cert.validity().not_after.to_string(),
    };
    Ok((der, details))
}

fn private_directory(path: &Path) -> io::Result<()> {
    use std::os::unix::fs::{DirBuilderExt, MetadataExt};
    match fs::DirBuilder::new().mode(0o700).create(path) {
        Ok(()) => (),
        Err(error) if error.kind() == io::ErrorKind::AlreadyExists => (),
        Err(error) => return Err(error),
    }
    let metadata = fs::symlink_metadata(path)?;
    if !metadata.is_dir()
        || metadata.mode() & 0o077 != 0
        || metadata.uid() != private_state::user_id()?
    {
        return Err(io::Error::new(
            io::ErrorKind::PermissionDenied,
            "invalid private OPC-UA directory",
        ));
    }
    Ok(())
}

pub(crate) fn client_application_uri(root: &Path) -> io::Result<String> {
    let invalid = || io::Error::from(io::ErrorKind::InvalidData);
    let bytes = read_certificate(&root.join(CLIENT_CERT))?;
    let (_, certificate) = X509Certificate::from_der(&bytes).map_err(|_| invalid())?;
    let names = certificate
        .subject_alternative_name()
        .map_err(|_| invalid())?
        .ok_or_else(invalid)?;
    match names.value.general_names.as_slice() {
        [GeneralName::URI(uri)] if uri.starts_with("urn:oip:managed-client:") => Ok((*uri).into()),
        _ => Err(invalid()),
    }
}

pub(crate) fn server_certificate(root: &Path) -> io::Result<Vec<u8>> {
    read_certificate(&root.join(SERVER_CERT))
}
fn read_certificate(path: &Path) -> io::Result<Vec<u8>> {
    let file = private_state::open(path)?.ok_or(io::ErrorKind::NotFound)?;
    let mut bytes = Vec::new();
    file.take(CERT_LIMIT as u64 + 1).read_to_end(&mut bytes)?;
    if bytes.is_empty() || bytes.len() > CERT_LIMIT {
        return Err(io::ErrorKind::InvalidData.into());
    }
    Ok(bytes)
}

pub(crate) fn authorize(
    hierarchy: &HierarchyRegistry,
    principal: &PrincipalId,
    site: &SiteId,
) -> bool {
    hierarchy.permits(
        principal,
        CapabilityId::OpcuaSetup,
        &AccessScope::Site(site.clone()),
        false,
    )
}

pub(crate) fn may_use_device(
    hierarchy: &HierarchyRegistry,
    inventory: &[InventoryRecord],
    site: &SiteId,
    device: &DeviceId,
) -> bool {
    inventory.iter().any(|record| {
        record.device.id == *device
            && record.device.site_id == *site
            && record.registration == RegistrationStatus::Registered
    }) && hierarchy
        .source_for_device(device.as_str())
        .is_none_or(|source| source.as_str() == SOURCE)
}

struct Preview {
    principal: PrincipalId,
    source: ManagedSource,
    der: Vec<u8>,
    previous_sha256: Option<String>,
    expires: Instant,
}

pub(crate) struct Setup {
    pub root: PathBuf,
    pub enabled: bool,
    pub configured: watch::Sender<Option<ManagedSource>>,
    previews: Mutex<BTreeMap<String, Preview>>,
}

impl Setup {
    pub(crate) fn new(config: &CoreConfig, source: Option<ManagedSource>) -> Result<Self, String> {
        let mut root = std::path::absolute(&config.database)
            .map_err(|_| "managed OPC-UA storage path")?
            .into_os_string();
        root.push(".managed-opcua");
        let static_profile = config
            .sources
            .iter()
            .any(|source| source.opcua.is_some() || source.id == SOURCE);
        if static_profile && source.is_some() {
            return Err("managed OPC-UA slot collides with configured source".into());
        }
        Ok(Self {
            root: root.into(),
            enabled: !static_profile && !config.disable_managed_opcua,
            configured: watch::channel(source).0,
            previews: Mutex::new(BTreeMap::new()),
        })
    }

    pub(crate) fn save_certificate(
        &self,
        der: &[u8],
        replacing: bool,
    ) -> Result<(), CapabilityError> {
        private_directory(&self.root).map_err(|_| unavailable())?;
        private_directory(&self.root.join("trusted")).map_err(|_| unavailable())?;
        let cert = self.root.join(CLIENT_CERT);
        let key = self.root.join(CLIENT_KEY);
        let cert_exists = private_state::open(&cert)
            .map_err(|_| unavailable())?
            .is_some();
        let key_exists = private_state::open(&key)
            .map_err(|_| unavailable())?
            .is_some();
        if !(cert_exists && key_exists) {
            if replacing {
                return Err(unavailable());
            }
            let identity = crate::browser_session::random_token().map_err(|_| unavailable())?;
            let uri = format!("urn:oip:managed-client:{identity}");
            let (client, secret) =
                oip_opcua::async_opcua::local_client_identity(&uri).map_err(|_| unavailable())?;
            private_state::replace_bytes(&key, pem("PRIVATE KEY", &secret).as_bytes())
                .map_err(|_| unavailable())?;
            private_state::replace_bytes(&cert, &client).map_err(|_| unavailable())?;
        }
        private_state::replace_bytes(&self.root.join(SERVER_CERT), der).map_err(|_| unavailable())
    }

    fn configured_result(
        &self,
        source: ManagedSource,
    ) -> Result<OpcuaSetupResult, CapabilityError> {
        let server = server_certificate(&self.root).map_err(|_| unavailable())?;
        let client = read_certificate(&self.root.join(CLIENT_CERT)).map_err(|_| unavailable())?;
        Ok(OpcuaSetupResult::Configured {
            source: source_id(),
            configuration: source.configuration,
            server_sha256: fingerprint(&server),
            client_certificate_pem: pem("CERTIFICATE", &client),
            collector_enabled: self.enabled,
        })
    }

    pub(crate) async fn execute(
        &self,
        state: &AppState,
        hierarchy: &HierarchyRegistry,
        principal: &PrincipalId,
        request: OpcuaSetupRequest,
    ) -> Result<OpcuaSetupResult, CapabilityError> {
        if !authorize(hierarchy, principal, &request.site) {
            return Err(denied());
        }
        let configured = self.configured.borrow().clone();
        if configured
            .as_ref()
            .is_some_and(|source| source.site != request.site || source.device != request.device)
            || !may_use_device(
                hierarchy,
                &state.inventory(),
                &request.site,
                &request.device,
            )
        {
            return Err(denied());
        }
        if let OpcuaSetupOperation::Status = request.operation {
            return configured.map_or_else(
                || {
                    if self.enabled {
                        Ok(OpcuaSetupResult::Unconfigured)
                    } else {
                        Err(disabled())
                    }
                },
                |source| self.configured_result(source),
            );
        }
        if !self.enabled {
            return Err(disabled());
        }
        let mut previews = self.previews.lock().await;
        let now = Instant::now();
        previews.retain(|_, preview| preview.expires > now);
        match request.operation {
            OpcuaSetupOperation::Status => unreachable!(),
            OpcuaSetupOperation::Preview {
                configuration,
                server_certificate_pem,
            } => {
                let previous_sha256 = configured
                    .as_ref()
                    .map(|_| server_certificate(&self.root).map(|der| fingerprint(&der)))
                    .transpose()
                    .map_err(|_| unavailable())?;
                let source = match (configured, configuration) {
                    (Some(source), None) => source,
                    (None, Some(configuration)) => ManagedSource { site: request.site, device: request.device, configuration },
                    _ => return Err(bad("OPCUA_SETUP_CONFIGURATION", "Provide connection settings for a new source. For certificate replacement keep the saved connection settings.")),
                };
                if source.configuration.endpoint.len() > 512
                    || source
                        .configuration
                        .points
                        .iter()
                        .any(|p| p.node_id.len() > 256)
                {
                    return Err(bad(
                        "OPCUA_SETUP_CONFIGURATION",
                        "The endpoint or point identifiers exceed the supported length.",
                    ));
                }
                oip_opcua::validate_client_endpoint(&source.configuration.endpoint, false)
                    .map_err(|_| {
                        bad(
                            "OPCUA_SETUP_ENDPOINT",
                            "Enter an OPC-UA endpoint with a literal IP address and explicit port.",
                        )
                    })?;
                source.definition(&self.root).map_err(|_| bad("OPCUA_SETUP_CONFIGURATION", "Specify both URIs, 1–16 unique data points and an interval of 5–60 seconds."))?;
                let (der, certificate) = validate_certificate(&server_certificate_pem, &source)?;
                previews.retain(|_, preview| &preview.principal != principal);
                if previews.len() >= 32 {
                    return Err(bad(
                        "OPCUA_SETUP_BUSY",
                        "Too many pending certificate approvals. Try again shortly.",
                    ));
                }
                let confirmation =
                    crate::browser_session::random_token().map_err(|_| unavailable())?;
                previews.insert(
                    confirmation.clone(),
                    Preview {
                        principal: principal.clone(),
                        source: source.clone(),
                        der,
                        previous_sha256: previous_sha256.clone(),
                        expires: now + Duration::from_secs(300),
                    },
                );
                Ok(OpcuaSetupResult::Preview {
                    configuration: source.configuration,
                    certificate,
                    previous_sha256,
                    confirmation,
                })
            }
            OpcuaSetupOperation::Apply {
                confirmation,
                verified_sha256,
            } => {
                let invalid = || {
                    bad("OPCUA_CONFIRMATION_INVALID", "The certificate approval is invalid, expired or superseded. Start a new review if needed.")
                };
                let preview = previews.get(&confirmation).ok_or_else(invalid)?;
                if &preview.principal != principal
                    || preview.source.site != request.site
                    || preview.source.device != request.device
                {
                    return Err(invalid());
                }
                if verified_sha256.len() > 95
                    || !fingerprint(&preview.der)
                        .eq_ignore_ascii_case(&verified_sha256.trim().replace(':', ""))
                {
                    return Err(bad("OPCUA_FINGERPRINT_MISMATCH", "The independently verified SHA-256 fingerprint does not match the server certificate."));
                }
                validate_certificate(&pem("CERTIFICATE", &preview.der), &preview.source)?;
                let preview = previews.remove(&confirmation).ok_or_else(invalid)?;
                state
                    .apply_opcua_setup(
                        principal.clone(),
                        preview.source.clone(),
                        preview.der,
                        preview.previous_sha256,
                    )
                    .await?;
                self.configured_result(preview.source)
            }
        }
    }

    pub(crate) fn check_revision(
        &self,
        source: &ManagedSource,
        previous_sha256: Option<&str>,
    ) -> Result<(), CapabilityError> {
        let current = self.configured.borrow().clone();
        match (current, previous_sha256) {
            (None, None) => Ok(()),
            (Some(saved), Some(previous))
                if saved == *source
                    && fingerprint(&server_certificate(&self.root).map_err(|_| unavailable())?)
                        == previous =>
            {
                Ok(())
            }
            _ => Err(bad(
                "OPCUA_CONFIRMATION_INVALID",
                "The saved OPC-UA configuration changed. Review the certificate again.",
            )),
        }
    }
}

fn disabled() -> CapabilityError {
    error(CapabilityErrorCode::SourceUnavailable, "OPCUA_SETUP_DISABLED", "This installation already has a locally configured OPC-UA profile or is running in isolated recovery.")
}
