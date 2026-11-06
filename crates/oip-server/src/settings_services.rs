//! Shared, authorized configuration reads. Configuration values are a validated startup snapshot.
use crate::{application_services::ApplicationServices, state::now_ms};
use oip_core::*;
use std::time::Instant;
#[derive(Clone)]
pub struct ManagementRuntime {
    pub mcp_mode: String,
    pub session_limit: Option<usize>,
    pub schema: u32,
    started: Instant,
}
impl ManagementRuntime {
    pub fn new(schema: u32) -> Self {
        Self {
            mcp_mode: "unavailable".into(),
            session_limit: None,
            schema,
            started: Instant::now(),
        }
    }
}
fn denied() -> CapabilityError {
    CapabilityError::new(
        CapabilityErrorCode::PermissionDenied,
        "PERMISSION_DENIED",
        "Settings capability is not authorized",
    )
}
impl ApplicationServices {
    pub(crate) fn settings_read(
        &self,
        ctx: &ExecutionContext,
        q: SettingsQuery,
    ) -> Result<CapabilityOutput, CapabilityError> {
        let target = q.target()?;
        let h = self.state.hierarchy.as_ref().ok_or_else(denied)?;
        let p = ctx.principal.as_ref().ok_or_else(denied)?;
        if !h.permits(p, CapabilityId::SettingsRead, &target, false) {
            return Err(denied());
        }
        let keys = SettingKey::ALL
            .into_iter()
            .filter(|k| q.key.is_none_or(|v| v == *k))
            .filter(|k| matches!(target, AccessScope::Platform) || k.definition().inherited)
            .collect::<Vec<_>>();
        if keys.is_empty() {
            return Err(CapabilityError::new(
                CapabilityErrorCode::InvalidInput,
                "SETTINGS_SCOPE",
                "Setting is not supported at this scope",
            ));
        }
        let settings = if q.catalog {
            vec![]
        } else {
            keys.iter()
                .map(|k| effective_setting(&self.state.settings, Some(h), &target, *k))
                .map(|mut e| {
                    // Actor identity of an ancestor override is not needed to consume an effective value.
                    if let Some(r) = &mut e.persisted {
                        if !h.platform(p, CapabilityId::McpManagementRead) {
                            r.actor = None;
                        }
                    }
                    e
                })
                .collect()
        };
        Ok(CapabilityOutput::Settings(SettingsSnapshot{definitions:keys.into_iter().map(SettingKey::definition).collect(),categories:[SettingCategory::General,SettingCategory::McpAgents,SettingCategory::Infrastructure,SettingCategory::DataStorage,SettingCategory::Diagnostics,SettingCategory::SecurityAccess,SettingCategory::System].into_iter().map(|category|SettingsCategoryDefinition{category,status:if matches!(category,SettingCategory::General|SettingCategory::Diagnostics){"offline_administration_required"}else{"read_only"}.into(),capabilities:match category {SettingCategory::General=>vec![CapabilityId::SettingsRead],SettingCategory::Infrastructure=>vec![CapabilityId::OrganizationsRead,CapabilityId::InfrastructuresRead,CapabilityId::SitesRead,CapabilityId::SourcesRead],SettingCategory::Diagnostics=>vec![CapabilityId::SettingsRead,CapabilityId::DiagnosticFindingsRead],_=>vec![CapabilityId::McpManagementRead]}}).collect(),settings,loaded_at_ms:if h.platform(p,CapabilityId::SettingsRead){Some(self.state.settings_loaded_ms)}else{None},inheritance:"only history_page_size: source > site > infrastructure > organization > platform > default; metadata platform only".into()}))
    }
    pub(crate) fn management_read(
        &self,
        ctx: &ExecutionContext,
        q: ManagementQuery,
    ) -> Result<CapabilityOutput, CapabilityError> {
        let p = ctx.principal.as_ref().ok_or_else(denied)?;
        let h = self.state.hierarchy.as_ref().ok_or_else(denied)?;
        if !h.platform(p, CapabilityId::McpManagementRead) {
            return Err(denied());
        }
        let info = self.state.management.lock().map_err(|_| denied())?.clone();
        let mut report=ManagementReport{section:q.section,availability:"read_only".into(),facts:vec![],tools:vec![],client_configuration:None,limitations:vec!["Local development identity; hostile same-UID processes are not isolated".into(),"No remote MCP or browser administrative session; no durable tamper-resistant audit".into()]};
        let mut fact = |name: &str, value: String| {
            report.facts.push(ManagementFact {
                name: name.into(),
                value,
            })
        };
        use ManagementSection::*;
        match q.section {
            Server | Diagnostics => {
                fact("runtime_mode", info.mcp_mode.clone());
                fact(
                    "core_lifecycle",
                    format!("{:?}", self.state.view().health.lifecycle),
                );
                fact("protocol", "2026-07-28; legacy 2025-11-25".into());
                fact("sdk", "rmcp 3.8.0".into());
                fact("transport", "local stdio; Unix IPC bridge only".into());
                fact(
                    "max_requests_per_session",
                    crate::mcp::MAX_REQUESTS.to_string(),
                );
                fact("max_input_bytes", crate::mcp::MAX_INPUT.to_string());
                fact("max_output_bytes", crate::mcp::MAX_OUTPUT.to_string());
                fact(
                    "session_limit",
                    info.session_limit
                        .map_or_else(|| "not applicable".into(), |v| v.to_string()),
                );
                fact("policy", "no mutating MCP tools".into());
                fact(
                    "enable_disable",
                    "unsupported; protected startup configuration only".into(),
                );
                if matches!(q.section, Diagnostics) {
                    fact("self_test","runtime observation only; no credential/file probing or handshake performed".into())
                }
            }
            Tools | Permissions => {
                let available = self.discover(ctx);
                let mapping = crate::mcp::capability_mapping();
                for v in mapping["capabilities"].as_array().ok_or_else(denied)? {
                    if let Some(name) = v["tool"].as_str() {
                        let capability: CapabilityId =
                            serde_json::from_value(v["capability"].clone())
                                .map_err(|_| denied())?;
                        report.tools.push(ManagedTool {
                            name: name.into(),
                            description: crate::mcp::tool_description(capability).into(),
                            capability,
                            permissions: capability.descriptor().permission,
                            registered: true,
                            available_to_principal: available.iter().any(|d| d.id == capability),
                            runtime_available: info.mcp_mode != "unavailable",
                            availability: if info.mcp_mode == "unavailable" {
                                "runtime_unavailable"
                            } else if available.iter().any(|d| d.id == capability) {
                                "available"
                            } else {
                                "denied_by_policy"
                            }
                            .into(),
                            supported_scopes: if capability == CapabilityId::McpManagementRead {
                                vec!["platform".into()]
                            } else {
                                vec!["centrally_authorized_hierarchy_targets".into()]
                            },
                            classification:
                                "read_only; source/hierarchy scope rechecked on every execution"
                                    .into(),
                            input_schema_json: serde_json::to_string(&v["input_schema"])
                                .map_err(|_| denied())?,
                            output_schema_json: serde_json::to_string(&v["output_schema"])
                                .map_err(|_| denied())?,
                        });
                    }
                }
                report.limitations.push(
                    "Registered does not mean authorized. No dynamic tool switches or self-grants."
                        .into(),
                );
            }
            Sessions => {
                report.availability = "unsupported".into();
                fact("reason","No queryable initialized-session registry. IPC JoinSet/log counters are not a reliable client inventory.".into());
            }
            ClientConfiguration => {
                let executable = std::env::current_exe()
                    .ok()
                    .filter(|p| p.is_absolute() && p.is_file())
                    .and_then(|p| p.into_os_string().into_string().ok());
                let command = executable
                    .clone()
                    .unwrap_or_else(|| "<ABSOLUTE_OIP_SERVER_EXECUTABLE>".into());
                let args = vec![
                    "--mcp-bridge".into(),
                    "--ipc-socket".into(),
                    "<AUTHORIZED_PRIVATE_SOCKET>".into(),
                    "--ipc-credential".into(),
                    "<AUTHORIZED_PRIVATE_CREDENTIAL_FILE>".into(),
                ];
                let configuration_json=serde_json::to_string_pretty(&serde_json::json!({"mcpServers":{"oip-local":{"command":command,"args":args}}})).map_err(|_|denied())?;
                report.client_configuration = Some(ClientConfigurationPreview {
                    executable,
                    args,
                    usable_without_replacement: false,
                    credential_provisioned: false,
                    configuration_json,
                });
                report.limitations.push("Replace placeholders using an existing authorized local profile. Preview grants nothing and performs no connection. Private paths and credential bytes are never enumerated.".into());
            }
            System => {
                fact("version", env!("CARGO_PKG_VERSION").into());
                fact("build_revision", env!("OIP_BUILD_REVISION").into());
                fact("uptime_ms", info.started.elapsed().as_millis().to_string());
                fact("observed_at_ms", now_ms().to_string());
                fact("sqlite_schema", info.schema.to_string());
                fact("rest_versions", "v1 legacy; v2 authenticated".into());
                fact(
                    "registered_core_capabilities",
                    CapabilityId::ALL.len().to_string(),
                );
                fact(
                    "operating_environment",
                    format!("{}-{}", std::env::consts::OS, std::env::consts::ARCH),
                );
                fact(
                    "runtime_sources",
                    self.state.view().sources.len().to_string(),
                );
            }
            Storage => {
                fact("sqlite_schema", info.schema.to_string());
                fact("database_path", "not exported".into());
                fact(
                    "integrity_check",
                    "not run by read endpoint; offline operator inspection required".into(),
                );
                fact("retention_cleanup", "unsupported; no data deletion".into());
                fact(
                    "backup",
                    "offline operator source/SQLite backup; no management export endpoint".into(),
                );
            }
            DiagnosticRules => {
                fact("rule_id", oip_diagnostics::DOCUMENTED_GAP_RULE_ID.into());
                fact(
                    "rule_version",
                    oip_diagnostics::DOCUMENTED_GAP_RULE_VERSION.to_string(),
                );
                fact("rule_policy","read_only deterministic; documented gap only, no cause inference or editable rules".into());
                fact(
                    "health_history",
                    "actual observed transitions since schema4; earlier history unavailable".into(),
                );
                fact(
                    "gap_semantics",
                    "documented markers; zero interval is not proof of continuity".into(),
                );
            }
            Security => {
                fact("principal", p.to_string());
                fact(
                    "identity_mode",
                    "trusted local IPC credential / REST header binding".into(),
                );
                fact("audit","local structured execution logs; settings changes atomically recorded, not tamper-proof".into());
                fact("production_blockers","RUSTSEC-2023-0071; RUSTSEC-2023-0089; RUSTSEC-2024-0449; remote/browser identity; same-UID trust; durable audit; OT safety".into());
            }
        }
        Ok(CapabilityOutput::Management(report))
    }
    pub(crate) fn history_default(&self, q: &DiagnosticQuery) -> usize {
        let scope = q
            .source
            .clone()
            .map(AccessScope::Source)
            .or_else(|| q.site.clone().map(AccessScope::Site))
            .or_else(|| q.infrastructure.clone().map(AccessScope::Infrastructure))
            .or_else(|| q.organization.clone().map(AccessScope::Organization))
            .unwrap_or(AccessScope::Platform);
        match effective_setting(
            &self.state.settings,
            self.state.hierarchy.as_deref(),
            &scope,
            SettingKey::HistoryPageSize,
        )
        .effective
        {
            SettingValue::Integer(v) => v as usize,
            _ => 50,
        }
    }
}
