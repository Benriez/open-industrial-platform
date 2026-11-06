//! Typed configuration. No credential, listener, authorization or source-connection keys.
use crate::*;
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum SettingCategory {
    General,
    McpAgents,
    Infrastructure,
    DataStorage,
    Diagnostics,
    SecurityAccess,
    System,
}
#[derive(Clone, Copy, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum SettingsApplyMode {
    RequiresRestart,
}
#[derive(Clone, Copy, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum SettingsApplyStatus {
    ActiveStartupSnapshot,
    PersistedRequiresRestart,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct SettingsCategoryDefinition {
    pub category: SettingCategory,
    pub status: String,
    pub capabilities: Vec<CapabilityId>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum SettingKey {
    InstanceName,
    InstanceDescription,
    HistoryPageSize,
}
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(
    tag = "type",
    content = "value",
    rename_all = "snake_case",
    deny_unknown_fields
)]
pub enum SettingValue {
    Text(String),
    Integer(u16),
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct SettingDefinition {
    pub key: SettingKey,
    pub category: SettingCategory,
    pub description: String,
    pub default: SettingValue,
    pub data_type: String,
    pub validation: String,
    pub scopes: Vec<SettingScopeKind>,
    pub inherited: bool,
    pub read_permission: Permission,
    pub write_permission: Permission,
    pub sensitivity: String,
    pub persistence: String,
    pub apply_mode: SettingsApplyMode,
    pub change_channel: String,
}
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum SettingScopeKind {
    #[default]
    Platform,
    Organization,
    Infrastructure,
    Site,
    Source,
}
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(default, deny_unknown_fields)]
pub struct SettingsQuery {
    pub scope: SettingScopeKind,
    pub scope_id: Option<String>,
    pub key: Option<SettingKey>,
    pub catalog: bool,
}
impl SettingsQuery {
    pub fn target(&self) -> Result<AccessScope, CapabilityError> {
        let bad = || {
            CapabilityError::new(
                CapabilityErrorCode::InvalidInput,
                "SETTINGS_INPUT",
                "Invalid settings scope",
            )
        };
        let id = self.scope_id.as_deref().ok_or_else(bad);
        Ok(match self.scope {
            SettingScopeKind::Platform => {
                if self.scope_id.is_some() {
                    return Err(bad());
                }
                AccessScope::Platform
            }
            SettingScopeKind::Organization => {
                AccessScope::Organization(OrganizationId::new(id?).map_err(|_| bad())?)
            }
            SettingScopeKind::Infrastructure => {
                AccessScope::Infrastructure(InfrastructureId::new(id?).map_err(|_| bad())?)
            }
            SettingScopeKind::Site => AccessScope::Site(SiteId::new(id?).map_err(|_| bad())?),
            SettingScopeKind::Source => {
                let s = id?;
                if s.len() > 128
                    || s.is_empty()
                    || !s
                        .bytes()
                        .all(|b| b.is_ascii_alphanumeric() || b"-_.".contains(&b))
                {
                    return Err(bad());
                }
                AccessScope::Source(DataSourceId::new(s).map_err(|_| bad())?)
            }
        })
    }
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(deny_unknown_fields)]
pub struct SettingsChange {
    pub principal: PrincipalId,
    pub scope: AccessScope,
    pub key: SettingKey,
    pub value: SettingValue,
    pub expected_revision: u64,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct SettingRecord {
    pub scope: AccessScope,
    pub key: SettingKey,
    pub value: SettingValue,
    pub revision: u64,
    pub updated_ms: i64,
    pub actor: Option<PrincipalId>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct EffectiveSetting {
    pub key: SettingKey,
    pub requested_scope: AccessScope,
    pub persisted: Option<SettingRecord>,
    pub effective: SettingValue,
    pub origin: Option<AccessScope>,
    pub effective_revision: u64,
    pub apply_status: SettingsApplyStatus,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct SettingsSnapshot {
    pub definitions: Vec<SettingDefinition>,
    pub categories: Vec<SettingsCategoryDefinition>,
    pub settings: Vec<EffectiveSetting>,
    pub loaded_at_ms: Option<i64>,
    pub inheritance: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct SettingsChangeResult {
    pub record: SettingRecord,
    pub apply_status: SettingsApplyStatus,
    pub effective_runtime_value: Option<SettingValue>,
}
impl SettingKey {
    pub const ALL: [Self; 3] = [
        Self::InstanceName,
        Self::InstanceDescription,
        Self::HistoryPageSize,
    ];
    pub fn definition(self) -> SettingDefinition {
        let (description, default, data_type, validation, inherited) = match self {
            Self::InstanceName => (
                "Non-sensitive local instance display name",
                SettingValue::Text("Open Industrial Platform".into()),
                "text",
                "1..80 UTF-8 bytes; no control characters",
                false,
            ),
            Self::InstanceDescription => (
                "Non-sensitive local instance description",
                SettingValue::Text(String::new()),
                "text",
                "0..256 UTF-8 bytes; no control characters",
                false,
            ),
            Self::HistoryPageSize => (
                "Default historical diagnostics page size when the request omits limit",
                SettingValue::Integer(50),
                "integer",
                "4..100 inclusive",
                true,
            ),
        };
        SettingDefinition {
            key: self,
            category: if self == Self::HistoryPageSize {
                SettingCategory::Diagnostics
            } else {
                SettingCategory::General
            },
            description: description.into(),
            default,
            data_type: data_type.into(),
            validation: validation.into(),
            scopes: if inherited {
                vec![
                    SettingScopeKind::Platform,
                    SettingScopeKind::Organization,
                    SettingScopeKind::Infrastructure,
                    SettingScopeKind::Site,
                    SettingScopeKind::Source,
                ]
            } else {
                vec![SettingScopeKind::Platform]
            },
            inherited,
            read_permission: Permission::SettingsRead,
            write_permission: Permission::SettingsWrite,
            sensitivity: "non_sensitive; never enter secrets".into(),
            persistence: "sqlite".into(),
            apply_mode: SettingsApplyMode::RequiresRestart,
            change_channel: "exclusive_local_operator_cli".into(),
        }
    }
    pub fn validate(
        self,
        scope: &AccessScope,
        value: &SettingValue,
    ) -> Result<(), CapabilityError> {
        let valid_scope = self == Self::HistoryPageSize || matches!(scope, AccessScope::Platform);
        let valid = match (self, value) {
            (Self::InstanceName, SettingValue::Text(s)) => {
                !s.trim().is_empty() && s.len() <= 80 && !s.chars().any(char::is_control)
            }
            (Self::InstanceDescription, SettingValue::Text(s)) => {
                s.len() <= 256 && !s.chars().any(char::is_control)
            }
            (Self::HistoryPageSize, SettingValue::Integer(v)) => (4..=100).contains(v),
            _ => false,
        };
        if valid_scope && valid {
            Ok(())
        } else {
            Err(CapabilityError::new(
                CapabilityErrorCode::InvalidInput,
                "SETTINGS_VALIDATION",
                "Setting type, scope or bounds are invalid",
            ))
        }
    }
}
/// Resolution is deterministic; only HistoryPageSize inherits. All records validated before runtime starts.
pub fn effective_setting(
    records: &[SettingRecord],
    h: Option<&HierarchyRegistry>,
    scope: &AccessScope,
    key: SettingKey,
) -> EffectiveSetting {
    let mut ancestors = vec![scope.clone()];
    if key.definition().inherited {
        match scope {
            AccessScope::Source(s) => {
                if let Some(l) = h.and_then(|h| h.location(s)) {
                    ancestors.extend([
                        AccessScope::Site(l.site_id.clone()),
                        AccessScope::Infrastructure(l.infrastructure_id.clone()),
                        AccessScope::Organization(l.organization_id.clone()),
                    ])
                }
            }
            AccessScope::Site(s) => {
                if let Some(h) = h {
                    if let Some(s) = h.plan.sites.iter().find(|x| &x.id == s) {
                        ancestors.push(AccessScope::Infrastructure(s.infrastructure_id.clone()));
                        if let Some(i) = h
                            .plan
                            .infrastructures
                            .iter()
                            .find(|i| i.id == s.infrastructure_id)
                        {
                            ancestors.push(AccessScope::Organization(i.organization_id.clone()))
                        }
                    }
                }
            }
            AccessScope::Infrastructure(i) => {
                if let Some(i) = h.and_then(|h| h.plan.infrastructures.iter().find(|x| &x.id == i))
                {
                    ancestors.push(AccessScope::Organization(i.organization_id.clone()))
                }
            }
            _ => {}
        }
        if !matches!(scope, AccessScope::Platform) {
            ancestors.push(AccessScope::Platform)
        }
    }
    let found = ancestors
        .iter()
        .find_map(|s| records.iter().find(|r| &r.scope == s && r.key == key));
    EffectiveSetting {
        key,
        requested_scope: scope.clone(),
        persisted: records
            .iter()
            .find(|r| &r.scope == scope && r.key == key)
            .cloned(),
        effective: found.map_or_else(|| key.definition().default, |r| r.value.clone()),
        origin: found.map(|r| r.scope.clone()),
        apply_status: SettingsApplyStatus::ActiveStartupSnapshot,
        effective_revision: found.map_or(0, |r| r.revision),
    }
}
#[derive(Clone, Copy, Debug, Default, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(rename_all = "snake_case")]
pub enum ManagementSection {
    #[default]
    Server,
    Tools,
    Permissions,
    Sessions,
    ClientConfiguration,
    Diagnostics,
    System,
    Storage,
    Security,
    DiagnosticRules,
}
#[derive(Clone, Debug, Default, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
#[serde(default, deny_unknown_fields)]
pub struct ManagementQuery {
    pub section: ManagementSection,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct ManagementReport {
    pub section: ManagementSection,
    pub availability: String,
    pub facts: Vec<ManagementFact>,
    pub tools: Vec<ManagedTool>,
    pub client_configuration: Option<ClientConfigurationPreview>,
    pub limitations: Vec<String>,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct ManagementFact {
    pub name: String,
    pub value: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct ManagedTool {
    pub name: String,
    pub description: String,
    pub capability: CapabilityId,
    pub permissions: Vec<Permission>,
    pub registered: bool,
    pub available_to_principal: bool,
    pub runtime_available: bool,
    pub availability: String,
    pub supported_scopes: Vec<String>,
    pub classification: String,
    pub input_schema_json: String,
    pub output_schema_json: String,
}
#[derive(Clone, Debug, Serialize, Deserialize)]
#[cfg_attr(feature = "schemas", derive(schemars::JsonSchema))]
pub struct ClientConfigurationPreview {
    pub executable: Option<String>,
    pub args: Vec<String>,
    pub usable_without_replacement: bool,
    pub credential_provisioned: bool,
    pub configuration_json: String,
}
