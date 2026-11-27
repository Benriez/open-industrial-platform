//! Apply License Center artifacts without coupling collection to entitlement status.
mod verification;

use oip_core::*;
use sha2::{Digest, Sha256};
use std::{
    collections::{BTreeMap, BTreeSet},
    io::{self, Read},
    path::PathBuf,
    sync::Mutex,
    time::{Duration, Instant},
};
use time::OffsetDateTime;
use verification::{is_identifier, verified_key, verify, Policy, Status, Verified};

pub(crate) use verification::MAX_ARTIFACT;

pub(crate) const MAX_PREVIEW_REQUEST: usize = 50 * 1024;
const MAX_POLICY: usize = 16 * 1024;
const CONFIRMATION_LIFETIME: Duration = Duration::from_secs(300);

/// Check a policy before initial provisioning or deliberate local maintenance.
pub fn check_license_policy(input: impl Read, allow_no_trusted_keys: bool) -> io::Result<()> {
    let mut bytes = Vec::new();
    input
        .take((MAX_POLICY + 1) as u64)
        .read_to_end(&mut bytes)?;
    let policy = parse_policy(&bytes)
        .map_err(|reason| io::Error::new(io::ErrorKind::InvalidData, reason))?;
    if policy.keys.is_empty() && !allow_no_trusted_keys {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "The initial license policy requires at least one trusted key.",
        ));
    }
    Ok(())
}

fn parse_policy(bytes: &[u8]) -> Result<Policy, &'static str> {
    if bytes.len() > MAX_POLICY {
        return Err("The license policy exceeds 16 KiB.");
    }
    let policy: Policy = serde_json::from_slice(bytes)
        .map_err(|_| "The license policy is not a valid License Center policy.")?;
    if policy.issuer != "code-server.de" || policy.product_id != "oip" {
        return Err("The license policy must be for OIP from code-server.de.");
    }
    if policy.kinds.is_empty()
        || !policy.kinds.iter().all(|kind| is_identifier(kind))
        || policy.kinds.iter().collect::<BTreeSet<_>>().len() != policy.kinds.len()
    {
        return Err("The license policy must have unique, valid license kinds.");
    }
    if !policy
        .rights
        .iter()
        .all(|(name, limit)| is_identifier(name) && (1..=999_999).contains(limit))
    {
        return Err("The license policy contains an invalid right or limit.");
    }
    if !policy
        .keys
        .iter()
        .all(|(kid, key)| verified_key(kid, key).is_some())
    {
        return Err("The license policy must have valid Ed25519 keys with matching key IDs.");
    }
    Ok(policy)
}

enum TrustAnchor {
    Unconfigured,
    Suspended,
    Invalid,
    Policy(Policy),
}

impl TrustAnchor {
    fn new(policy: Option<&str>, commercial_kinds: &[String]) -> Self {
        let Some(policy) = policy else {
            return if commercial_kinds.is_empty() {
                Self::Unconfigured
            } else {
                Self::Invalid
            };
        };
        match parse_policy(policy.as_bytes()) {
            Ok(policy)
                if commercial_kinds
                    .iter()
                    .all(|kind| policy.kinds.contains(kind)) =>
            {
                if policy.keys.is_empty() {
                    Self::Suspended
                } else {
                    Self::Policy(policy)
                }
            }
            _ => Self::Invalid,
        }
    }
}

struct Pending {
    proof: LicenseProof,
    previous: Option<[u8; 32]>,
    confirmation: String,
    expires: Instant,
}

pub(crate) struct Licensing {
    trust: TrustAnchor,
    commercial_kinds: Vec<String>,
    proof_path: PathBuf,
    pending: Mutex<BTreeMap<PrincipalId, Pending>>,
}

impl Licensing {
    pub(crate) fn new(
        policy: Option<&str>,
        commercial_kinds: &[String],
        proof_path: PathBuf,
    ) -> Self {
        Self {
            trust: TrustAnchor::new(policy, commercial_kinds),
            commercial_kinds: commercial_kinds.to_vec(),
            proof_path,
            pending: Mutex::default(),
        }
    }

    fn current(&self) -> io::Result<Option<Vec<u8>>> {
        let Some(file) = crate::private_state::open(&self.proof_path)? else {
            return Ok(None);
        };
        let mut bytes = Vec::new();
        file.take((MAX_ARTIFACT + 1) as u64)
            .read_to_end(&mut bytes)?;
        if bytes.len() > MAX_ARTIFACT {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "license proof is too large",
            ));
        }
        Ok(Some(bytes))
    }

    fn status(&self, verified: Verified, can_manage: bool) -> LicenseStatus {
        let commercial = if self.commercial_kinds.contains(&verified.claims.kind) {
            entitlement(verified.usage_status)
        } else {
            EntitlementState::Unconfirmed
        };
        LicenseStatus {
            proof_state: LicenseProofState::Verified,
            commercial,
            support: entitlement(verified.support_status),
            license_id: Some(verified.claims.license_id),
            revision: Some(verified.claims.revision),
            licensee: Some(verified.claims.holder.name),
            organization: None,
            can_manage,
        }
    }

    pub(crate) fn read(&self, manager: bool) -> LicenseStatus {
        let proof_state = match &self.trust {
            TrustAnchor::Unconfigured => LicenseProofState::Unconfigured,
            TrustAnchor::Suspended => LicenseProofState::Suspended,
            TrustAnchor::Invalid => LicenseProofState::Unavailable,
            TrustAnchor::Policy(policy) => match self.current() {
                Ok(Some(bytes)) => match verify(&bytes, policy, OffsetDateTime::now_utc()) {
                    Ok(verified) => return self.status(verified, manager),
                    Err(_) => LicenseProofState::Invalid,
                },
                Ok(None) => LicenseProofState::Missing,
                Err(_) => LicenseProofState::Unavailable,
            },
        };
        LicenseStatus {
            proof_state,
            commercial: EntitlementState::Unconfirmed,
            support: EntitlementState::Unconfirmed,
            license_id: None,
            revision: None,
            licensee: None,
            organization: None,
            can_manage: manager
                && matches!(
                    proof_state,
                    LicenseProofState::Missing | LicenseProofState::Invalid
                ),
        }
    }

    fn replacement_status(
        &self,
        proof: &LicenseProof,
        current: Option<&[u8]>,
    ) -> Result<LicenseStatus, CapabilityError> {
        let TrustAnchor::Policy(policy) = &self.trust else {
            return Err(unavailable());
        };
        let now = OffsetDateTime::now_utc();
        let next = verify(proof.artifact.as_bytes(), policy, now).map_err(|_| {
            CapabilityError::new(
                CapabilityErrorCode::InvalidInput,
                "LICENSE_PROOF_INVALID",
                "The proof does not match the configured License Center policy or has an invalid format",
            )
        })?;
        let known = current
            .and_then(|artifact| verify(artifact, policy, now).ok())
            .filter(|known| known.claims.license_id == next.claims.license_id);
        if let Some(known) = known {
            if next.claims.revision < known.claims.revision {
                return Err(CapabilityError::new(
                    CapabilityErrorCode::InvalidInput,
                    "LICENSE_PROOF_SUPERSEDED",
                    "This licence already has a newer revision stored. Use the latest issued file.",
                ));
            }
            if next.claims.revision == known.claims.revision
                && next.payload_digest != known.payload_digest
            {
                return Err(CapabilityError::new(
                    CapabilityErrorCode::InvalidInput,
                    "LICENSE_PROOF_REVISION_CONFLICT",
                    "The same licence revision has different signed contents. Contact the issuer.",
                ));
            }
        }
        Ok(self.status(next, true))
    }

    pub(crate) fn preview(
        &self,
        principal: &PrincipalId,
        proof: LicenseProof,
    ) -> Result<LicensePreview, CapabilityError> {
        let mut pending = self.pending.lock().map_err(|_| unavailable())?;
        let current = self.current().map_err(|_| unavailable())?;
        let status = self.replacement_status(&proof, current.as_deref())?;
        let previous = current.as_deref().map(|bytes| Sha256::digest(bytes).into());
        let now = Instant::now();
        pending.retain(|_, item| now < item.expires);
        if pending.len() >= 32 && !pending.contains_key(principal) {
            return Err(unavailable());
        }
        let confirmation = crate::browser_session::random_token().map_err(|_| unavailable())?;
        pending.insert(
            principal.clone(),
            Pending {
                proof,
                previous,
                confirmation: confirmation.clone(),
                expires: now + CONFIRMATION_LIFETIME,
            },
        );
        Ok(LicensePreview {
            status,
            confirmation,
        })
    }

    pub(crate) fn apply(
        &self,
        principal: &PrincipalId,
        confirmation: &str,
    ) -> Result<LicenseStatus, CapabilityError> {
        let mut pending = self.pending.lock().map_err(|_| unavailable())?;
        let item = pending
            .get(principal)
            .filter(|item| Instant::now() < item.expires && item.confirmation == confirmation)
            .ok_or_else(confirmation_required)?;
        let current = self.current().map_err(|_| unavailable())?;
        let current_digest = current.as_deref().map(|bytes| Sha256::digest(bytes).into());
        if item.previous != current_digest {
            pending.remove(principal);
            return Err(confirmation_required());
        }
        let item = pending.remove(principal).expect("confirmation is locked");
        let status = self.replacement_status(&item.proof, current.as_deref())?;
        crate::private_state::replace_bytes(&self.proof_path, item.proof.artifact.as_bytes())
            .map_err(|_| unavailable())?;
        Ok(status)
    }
}

fn entitlement(status: Status) -> EntitlementState {
    match status {
        Status::None => EntitlementState::NotGranted,
        Status::NotYetValid => EntitlementState::NotYetActive,
        Status::Active => EntitlementState::Active,
        Status::Ended => EntitlementState::Ended,
    }
}

fn unavailable() -> CapabilityError {
    CapabilityError::new(
        CapabilityErrorCode::PersistenceUnavailable,
        "LICENSE_UNAVAILABLE",
        "The local license proof or issuer configuration is unavailable",
    )
}

fn confirmation_required() -> CapabilityError {
    CapabilityError::new(
        CapabilityErrorCode::InvalidInput,
        "LICENSE_CONFIRMATION_REQUIRED",
        "Review the license proof again before saving it",
    )
}
