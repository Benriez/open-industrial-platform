use crate::{AdapterError, ProductionSecurityConfig};
use opcua::crypto::CertificateStore;

/// Loads and validates local PKI material before async-opcua builds a channel.
/// This prevents upstream missing-certificate warnings and panic-capable secure
/// channel paths from being reached with malformed local credentials.
pub(crate) fn validate_production_pki(
    config: &ProductionSecurityConfig,
) -> Result<(), AdapterError> {
    config.validate_paths()?;
    let certificate_path = config.pki_dir.join(&config.certificate_path);
    let private_key_path = config.pki_dir.join(&config.private_key_path);
    let certificate = CertificateStore::read_cert(&certificate_path).map_err(|error| {
        AdapterError::InvalidSecurityConfiguration(format!("certificate cannot be parsed: {error}"))
    })?;
    CertificateStore::read_pkey(&private_key_path).map_err(|error| {
        AdapterError::InvalidSecurityConfiguration(format!("private key cannot be parsed: {error}"))
    })?;
    certificate
        .is_time_valid(&chrono::Utc::now())
        .map_err(|error| {
            AdapterError::InvalidSecurityConfiguration(format!(
                "certificate is outside its validity period: {error}"
            ))
        })?;
    Ok(())
}
