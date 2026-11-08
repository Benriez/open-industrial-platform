/// Application-lifetime, per-workstation presentation preferences.
///
/// No credentials, protected rows, queries or API objects are stored. State is
/// deliberately memory-only: browser storage is not a secure preference
/// backend and a reload must not invent a persisted Core preference.
enum WorkspaceId { overview, devices, network, opcua, diagnostics, settings }

class WorkspaceLayoutPreference {
  /// Null means automatic: open when an object is selected, closed otherwise.
  bool? inspectorOpen;
  bool inspectorPinned;
  bool expertWorkspace;
  bool advancedFilters;
  String? view;
  bool? dense;
  final Map<String, String> options;

  WorkspaceLayoutPreference({
    this.inspectorOpen,
    this.inspectorPinned = false,
    this.expertWorkspace = false,
    this.advancedFilters = false,
    this.view,
    this.dense,
    Map<String, String>? options,
  }) : options = options ?? {};

  WorkspaceLayoutPreference copy() => WorkspaceLayoutPreference(
        inspectorOpen: inspectorOpen,
        inspectorPinned: inspectorPinned,
        expertWorkspace: expertWorkspace,
        advancedFilters: advancedFilters,
        view: view,
        dense: dense,
        options: Map.of(options),
      );
}

class AdaptiveWorkspaces {
  final Map<WorkspaceId, WorkspaceLayoutPreference> _layouts = {
    for (final id in WorkspaceId.values) id: WorkspaceLayoutPreference(),
  };

  WorkspaceLayoutPreference layout(WorkspaceId id) => _layouts[id]!;

  bool inspectorVisible(WorkspaceId id, bool hasSelection) {
    final value = layout(id);
    return value.inspectorPinned || (value.inspectorOpen ?? hasSelection);
  }

  void setInspectorOpen(WorkspaceId id, bool open) {
    final value = layout(id);
    value.inspectorOpen = open;
    if (!open) value.inspectorPinned = false;
  }

  void revealInspector(WorkspaceId id) {
    // A fresh object action restores automatic disclosure. Deselecting closes
    // an unpinned inspector again; an explicit X remains closed until the next
    // object action. Pinning always keeps the chosen layout visible.
    layout(id).inspectorOpen = null;
  }

  void toggleInspectorPin(WorkspaceId id) {
    final value = layout(id);
    value.inspectorPinned = !value.inspectorPinned;
    value.inspectorOpen = true;
  }

  /// Context invalidation removes object data, not the expert's preferred
  /// layout. A pinned empty inspector is allowed; it can never show old data.
  void invalidateObjects() {
    for (final value in _layouts.values) {
      if (!value.inspectorPinned) value.inspectorOpen = null;
    }
  }

  void setExpertWorkspace(WorkspaceId id, bool open) =>
      layout(id).expertWorkspace = open;

  void setAdvancedFilters(WorkspaceId id, bool open) =>
      layout(id).advancedFilters = open;

  void setView(WorkspaceId id, String? view) => layout(id).view = view;

  void setDensity(WorkspaceId id, bool dense) => layout(id).dense = dense;

  String? option(WorkspaceId id, String key) => layout(id).options[key];

  void setOption(WorkspaceId id, String key, String? value) {
    if (value == null) {
      layout(id).options.remove(key);
    } else {
      layout(id).options[key] = value;
    }
  }
}
