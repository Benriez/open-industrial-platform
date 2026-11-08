import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/app.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/models/contracts.dart';

import 'support.dart';

Future<void> _bootstrap(WidgetTester tester,
    {Size size = const Size(1440, 900)}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.binding.setSurfaceSize(size);
  final api = FakeApi();
  final controller = OipController(api)
    ..snapshot = Snapshot.fromJson(api.data)
    ..connection = 'live'
    ..workspaces.setExpertWorkspace(WorkspaceId.devices, true)
    ..workspaces.setInspectorOpen(WorkspaceId.devices, true);
  await tester.pumpWidget(OipApp(controller: controller, autoStart: false));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.binding.setSurfaceSize(null);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _navigate(WidgetTester tester, double width) async {
  if (width < 1080) {
    await tester.tap(find.byKey(const Key('open-navigation')));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const Key('nav-1')));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

/// Density contract of the Devices & Services workstation.
///
/// The numbers are measured from the rendered layout, not from constants, so
/// a regression in the spacing is visible as a failing assertion.
void main() {
  group('Devices & Services 2027 density contract', () {
    testWidgets('the toolbar is one compact row with aligned controls',
        (tester) async {
      await _bootstrap(tester, size: const Size(1440, 900));
      await _navigate(tester, 1440);

      // Every toolbar control shares one control height.
      expect(tester.getSize(find.byKey(const Key('device-search'))).height, 36);
      for (final key in [
        'device-type-filter',
        'device-source-filter',
        'filter-Standort',
        'device-sort',
        'device-more-filters',
        'device-filter-reset',
      ]) {
        expect(
            tester.getSize(find.byKey(Key(key))).height, lessThanOrEqualTo(36),
            reason: '$key keeps the 36 px control height');
      }

      // The primary filters share one row with the search field.
      final search = tester.getTopLeft(find.byKey(const Key('device-search')));
      final sort = tester.getTopLeft(find.byKey(const Key('device-sort')));
      expect((sort.dy - search.dy).abs(), lessThanOrEqualTo(1),
          reason: 'search, type, source, location and sorting share one row');

      // The toolbar is one row tall; the panel padding adds the rest.
      final bar = tester.getSize(find.byKey(const Key('device-filter-bar')));
      expect(bar.height, lessThanOrEqualTo(72),
          reason: 'the filter bar stays a single compact row');

      // The secondary filters are reachable through the disclosure.
      expect(find.byKey(const Key('device-quality-filter')), findsNothing);
      expect(find.byKey(const Key('device-freshness-filter')), findsNothing);
      expect(find.byKey(const Key('device-connectivity-filter')), findsNothing);
      await tester.tap(find.byKey(const Key('device-more-filters')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('device-quality-filter')), findsOneWidget);
      expect(find.byKey(const Key('device-freshness-filter')), findsOneWidget);
      expect(
          find.byKey(const Key('device-connectivity-filter')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the inventory explorer reaches the first row early',
        (tester) async {
      await _bootstrap(tester, size: const Size(1440, 900));
      await _navigate(tester, 1440);

      final header =
          tester.getTopLeft(find.byKey(const Key('devices-page-header')));
      final explorer =
          tester.getTopLeft(find.byKey(const Key('device-inventory-explorer')));
      final distance = explorer.dy - header.dy;
      // The widget test renders with the wide fallback test font, so the
      // bound is the conservative one; the browser measurement is the
      // product number.
      expect(distance, lessThanOrEqualTo(250),
          reason: 'header to inventory stays below 250 px');

      // The compact device row uses the documented row height.
      final row = tester.getSize(find.byKey(const Key('device-M-01')));
      expect(row.height, 44);

      // The scope segments, the grouping control and the density control share
      // the control height.
      expect(tester.getSize(find.byKey(const Key('device-scope-all'))).height,
          lessThanOrEqualTo(36));
      expect(tester.getSize(find.byKey(const Key('device-group'))).height,
          lessThanOrEqualTo(36));
      expect(tester.getSize(find.byKey(const Key('device-density'))).height,
          lessThanOrEqualTo(36));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the three panels share one padding and one column gap',
        (tester) async {
      await _bootstrap(tester, size: const Size(1440, 900));
      await _navigate(tester, 1440);

      final explorer =
          tester.getRect(find.byKey(const Key('device-inventory-explorer')));
      final workspace =
          tester.getRect(find.byKey(const Key('device-engineering-workspace')));
      final inspector =
          tester.getRect(find.byKey(const Key('device-context-inspector')));

      // One 12 px column gap between the panels.
      expect(workspace.left - explorer.right, closeTo(12, 0.5));
      expect(inspector.left - workspace.right, closeTo(12, 0.5));

      // 12 px panel padding plus the one pixel border of the panel.
      final search = tester.getRect(find.byKey(const Key('device-search')));
      final bar = tester.getRect(find.byKey(const Key('device-filter-bar')));
      expect(search.left - bar.left, closeTo(13, 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the comparison strip collapses and expands', (tester) async {
      await _bootstrap(tester, size: const Size(1440, 900));
      await _navigate(tester, 1440);

      final collapsed =
          tester.getSize(find.byKey(const Key('device-comparison-workspace')));
      expect(collapsed.height, lessThanOrEqualTo(70),
          reason: 'the empty comparison strip does not reserve 190 px');

      await tester.tap(find.byKey(const Key('device-M-01')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('device-compare-M-01')));
      await tester.pumpAndSettle();
      final expanded =
          tester.getSize(find.byKey(const Key('device-comparison-workspace')));
      expect(expanded.height, greaterThan(collapsed.height));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the density contract holds at every supported width',
        (tester) async {
      for (final size in [
        const Size(320, 740),
        const Size(390, 844),
        const Size(768, 1024),
        const Size(1024, 900),
        const Size(1440, 900),
        const Size(1920, 1080),
      ]) {
        await _bootstrap(tester, size: size);
        await _navigate(tester, size.width);
        expect(
            find.byKey(const Key('device-inventory-explorer')), findsOneWidget);
        expect(tester.getSize(find.byKey(const Key('device-M-01'))).height, 44);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    });
  });
}
