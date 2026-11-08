enum SettingsCategory {
  general,
  mcpAgents,
  infrastructure,
  dataStorage,
  diagnostics,
  securityAccess,
  system,
}

enum SettingsSection {
  application,
  preferences,
  mcpServer,
  clientConfiguration,
  tools,
  permissions,
  connectionDiagnostics,
  clientSessions,
  organizations,
  infrastructures,
  sites,
  sourcesDevices,
  sqlite,
  historicalData,
  retention,
  diagnosticRules,
  evidence,
  historyLimits,
  currentIdentity,
  effectivePermissions,
  auditSecurity,
  runtime,
  versions,
  capabilities,
}

enum SettingsMobilePane { navigation, workspace, inspector }

/// Session-local navigation and filter state only.
///
/// No principal, credential, management response, scope grant or server setting
/// is retained here. Data is re-read when the module is entered again.
class SettingsWorkspaceSession {
  SettingsCategory category = SettingsCategory.general;
  SettingsSection section = SettingsSection.application;
  SettingsMobilePane mobilePane = SettingsMobilePane.navigation;
  String? selectedTool;
  String? selectedSetting;
  String toolSearch = '';
  String capabilityFilter = 'all';
  String permissionFilter = 'all';
  bool showOutputSchema = false;

  void selectCategory(SettingsCategory value) {
    category = value;
    section = switch (value) {
      SettingsCategory.general => SettingsSection.application,
      SettingsCategory.mcpAgents => SettingsSection.mcpServer,
      SettingsCategory.infrastructure => SettingsSection.organizations,
      SettingsCategory.dataStorage => SettingsSection.sqlite,
      SettingsCategory.diagnostics => SettingsSection.diagnosticRules,
      SettingsCategory.securityAccess => SettingsSection.currentIdentity,
      SettingsCategory.system => SettingsSection.runtime,
    };
    mobilePane = SettingsMobilePane.workspace;
  }

  void clearAuthorizedContext() {
    selectedTool = null;
    selectedSetting = null;
    toolSearch = '';
    capabilityFilter = 'all';
    permissionFilter = 'all';
    showOutputSchema = false;
  }
}
