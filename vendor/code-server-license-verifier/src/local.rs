use std::io::ErrorKind;
use std::path::Path;

use serde::Serialize;
use time::OffsetDateTime;

use crate::{Error, MAX_ARTIFACT, Policy, Status, read_bounded, verify};

pub fn configured_status(product: &str, policy_env: &str, license_env: &str) -> LocalStatus {
    let policy = std::env::var_os(policy_env);
    let license = std::env::var_os(license_env);
    local_status(
        product,
        policy.as_deref().map(Path::new),
        license.as_deref().map(Path::new),
        OffsetDateTime::now_utc(),
    )
}

/// Public status omits the licensee, file paths and configured keys.
#[derive(Debug, Serialize, PartialEq, Eq)]
#[serde(tag = "state", rename_all = "snake_case")]
pub enum LocalStatus {
    Unconfigured,
    Missing,
    InvalidConfiguration,
    Unreadable,
    Rejected {
        reason: Error,
    },
    Verified {
        revision: u32,
        usage_status: Status,
        support_status: Status,
    },
}

/// Both paths come from operator-controlled configuration, independently of the license.
pub fn local_status(
    expected_product: &str,
    policy_path: Option<&Path>,
    license_path: Option<&Path>,
    now: OffsetDateTime,
) -> LocalStatus {
    let (policy_path, license_path) = match (policy_path, license_path) {
        (None, None) => return LocalStatus::Unconfigured,
        (Some(policy), Some(license)) if policy.is_absolute() && license.is_absolute() => {
            (policy, license)
        }
        _ => return LocalStatus::InvalidConfiguration,
    };
    let policy = read_bounded(policy_path, 16 * 1024)
        .ok()
        .and_then(|data| serde_json::from_slice::<Policy>(&data).ok());
    let Some(policy) = policy.filter(|policy| {
        policy.product_id == expected_product && policy.issuer == "code-server.de"
    }) else {
        return LocalStatus::InvalidConfiguration;
    };
    let artifact = match read_bounded(license_path, MAX_ARTIFACT) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == ErrorKind::NotFound => return LocalStatus::Missing,
        Err(_) => return LocalStatus::Unreadable,
    };
    match verify(&artifact, &policy, now) {
        Ok(license) => LocalStatus::Verified {
            revision: license.claims.revision,
            usage_status: license.usage_status,
            support_status: license.support_status,
        },
        Err(reason) => LocalStatus::Rejected { reason },
    }
}
