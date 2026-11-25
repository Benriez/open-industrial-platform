/// Density geometry for the Devices & Services workstation.
///
/// The values follow the operator's spacing contract (8 px between related
/// controls, 12 px between toolbar groups, 12–16 px between main panels,
/// 36–40 px control height, 44–52 px device row) and were verified against
/// the actual Flutter rendering at 320/390/768/1024/1440/1920 px.
///
/// The panel padding is 12 px rather than the 16 px nominal target: the
/// Devices workstation carries three dense columns, and 12 px is the value
/// used by the reference implementations (OPC-UA Browser 2027 Phase 2,
/// Network & VPN 2027 Phase 2) for the same relation. Section gaps use 12 px
/// for the same reason; the header and mode tabs would otherwise
/// push the inventory explorer out of the first viewport.
abstract final class DevicesLayout {
  /// Height of every interactive control in the toolbar and the explorer.
  static const controlHeight = 36.0;

  /// Gap between controls that belong to the same group.
  static const controlGap = 8.0;

  /// Gap between two toolbar groups.
  static const groupGap = 12.0;

  /// Inner padding of the explorer, workspace, inspector and comparison panels.
  static const panelPadding = 12.0;

  /// Gap between the main panels of the workstation row.
  static const panelGap = 12.0;

  /// Gap between two page sections (header, tabs, filter bar).
  static const sectionGap = 12.0;

  /// Compact device row height.
  static const rowCompact = 44.0;

  /// Comfortable device row height.
  static const rowComfortable = 52.0;

  /// Width of the fixed label column inside a filter control. The value
  /// column starts at the same x in every control, which aligns the toolbar.
  static const filterLabelWidth = 80.0;

  /// Height of the collapsed comparison strip.
  static const comparisonCollapsed = 44.0;

  /// Height of the expanded comparison workspace.
  static const comparisonExpanded = 190.0;

  /// Height of the collapsed comparison strip while no device is compared.
  /// It carries the tab row plus the instruction that explains the selection.
  static const comparisonEmpty = 66.0;
}
