import '../../models/contracts.dart';

/// UI-local state only. No registry, tenant, health or service facts are stored here.
class DevicesWorkspaceSession {
  String? selectedId;
  final Set<String> pinned = <String>{};
  final List<String> recents = <String>[];
  final List<String> compare = <String>[];
  String search = '';
  String type = 'all';
  String source = 'all';
  String location = 'all';
  String quality = 'all';
  String freshness = 'all';
  String connectivity = 'all';
  String sort = 'name';
  String group = 'source';
  String scope = 'all';
  bool compact = true;

  /// Whether the secondary filters (quality, freshness, connectivity) are
  /// revealed in the toolbar disclosure. UI-local, like every other filter
  /// state in this session.
  bool showAdvancedFilters = false;

  /// Whether the comparison strip shows its content or only its tab row.
  bool compareExpanded = false;
  int offset = 0;

  void select(Device device) {
    selectedId = device.id;
    recents
      ..remove(device.id)
      ..insert(0, device.id);
    if (recents.length > 8) recents.removeLast();
  }

  void resetFilters() {
    search = '';
    type = 'all';
    source = 'all';
    location = 'all';
    quality = 'all';
    freshness = 'all';
    connectivity = 'all';
    sort = 'name';
    group = 'source';
    scope = 'all';
    offset = 0;
  }
}
