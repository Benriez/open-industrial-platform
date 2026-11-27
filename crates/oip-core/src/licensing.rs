//! Installation licensing is an administrative status, independent of data access.
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(deny_unknown_fields)]
pub struct LicenseProof {
    pub artifact: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(deny_unknown_fields)]
pub struct LicensePreviewRequest {
    pub proof: LicenseProof,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(deny_unknown_fields)]
pub struct LicenseApplyRequest {
    pub confirmation: String,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum LicenseProofState {
    Unconfigured,
    Suspended,
    Missing,
    Invalid,
    Verified,
    Unavailable,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum EntitlementState {
    Unconfirmed,
    NotGranted,
    NotYetActive,
    Active,
    Ended,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct LicenseStatus {
    pub proof_state: LicenseProofState,
    pub commercial: EntitlementState,
    pub support: EntitlementState,
    pub license_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub revision: Option<u32>,
    pub licensee: Option<String>,
    pub organization: Option<String>,
    pub can_manage: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct LicensePreview {
    pub status: LicenseStatus,
    pub confirmation: String,
}
