use crate::{AdapterError, ProductionSecurityConfig};
use opcua::crypto::CertificateStore;

/// The supported local profile stores an identity and its peer trust files
/// inside an operator-owned private directory.
pub(crate) fn validate_private_pki(config: &ProductionSecurityConfig) -> Result<(), AdapterError> {
    use std::{fs, path::Path};

    let failure = || {
        AdapterError::InvalidSecurityConfiguration(
            "required OPC-UA PKI files must be inside the private PKI directory".into(),
        )
    };
    config.validate_paths()?;
    let root = config.pki_dir.canonicalize().map_err(|_| failure())?;
    let checked_path = |relative: &Path| {
        let path = config.pki_dir.join(relative);
        let metadata = fs::symlink_metadata(&path).map_err(|_| failure())?;
        let canonical = path.canonicalize().map_err(|_| failure())?;
        if metadata.is_symlink() || !canonical.starts_with(&root) {
            return Err(failure());
        }
        Ok(metadata)
    };
    let root_info = fs::symlink_metadata(&config.pki_dir).map_err(|_| failure())?;
    if root_info.is_symlink() || !root_info.is_dir() {
        return Err(failure());
    }
    let certificate = checked_path(&config.certificate_path)?;
    let key = checked_path(&config.private_key_path)?;
    let trusted = checked_path(Path::new("trusted"))?;
    if !certificate.is_file() || !key.is_file() || !trusted.is_dir() {
        return Err(failure());
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        if root_info.mode() & 0o077 != 0
            || key.mode() & 0o077 != 0
            || key.uid() != root_info.uid()
            || trusted.uid() != root_info.uid()
        {
            return Err(AdapterError::InvalidSecurityConfiguration(
                "OPC-UA private PKI directory and private key require owner-only permissions"
                    .into(),
            ));
        }
    }
    Ok(())
}

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
