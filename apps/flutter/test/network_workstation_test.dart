import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/app.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/features/network/network_graph.dart';
import 'package:oip_dashboard/features/network/network_model.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/widgets/workstation.dart';
import 'support.dart';

void main() {
  group('Network model honesty and deterministic layout', () {
    test('Missing RTT and loss never become zero or estimates', () {
      final link = NetworkLink.fromJson({
        'from': 'a',
        'to': 'b',
        'transport': 'LAN',
        'status': 'unknown',
        'latency_ms': null,
        'packet_loss_percent': null,
        'simulated': false,
      });
      expect(networkLinkRtt(link), 'Nicht gemessen');
      expect(networkLinkLoss(link), 'Nicht verfügbar');
      expect(networkEdgeKind(link), 'Logischer Netzwerkpfad');
    });

    test('Fixture values remain explicitly labelled', () {
      final edge = networkEdges(Snapshot.fromJson(fixture())).single;
      expect(networkLinkRtt(edge.link), '1.5 ms · Fixture');
      expect(networkLinkLoss(edge.link), '0.0 % · Fixture');
      expect(edge.id, contains('M-01'));
    });

    test('Relationship layout is stable under inventory and edge reorder', () {
      final data = fixture();
      final snapshot = Snapshot.fromJson(data);
      final edges = networkEdges(snapshot);
      final first = TopologyLayout.build(snapshot.devices, edges);
      data['devices'] = (data['devices'] as List).reversed.toList();
      data['topology'] = (data['topology'] as List).reversed.toList();
      final reordered = Snapshot.fromJson(data);
      final second =
          TopologyLayout.build(reordered.devices, networkEdges(reordered));
      expect(first.signature, second.signature);
      expect(first.positions['M-01'], const Offset(28, 28));
      expect(first.positions['evo'], const Offset(268, 28));
      expect(first.size, const Size(476, 180));
    });

    test('Demo geometry has three relationship layers and eleven unlinked IDs',
        () {
      final snapshot = _demoSnapshot();
      final edges = networkEdges(snapshot);
      final linked = networkLinkedDeviceIds(edges);
      final connected = snapshot.devices
          .where((device) => linked.contains(device.id))
          .toList();
      final layout = TopologyLayout.build(connected, edges);
      expect(snapshot.devices, hasLength(17));
      expect(edges, hasLength(5));
      expect(layout.devices, hasLength(6));
      expect(snapshot.devices.length - connected.length, 11);
      expect(layout.positions['router']!.dx, 28);
      for (final id in ['M-01', 'evo', 'remote-linux', 'remote-windows']) {
        expect(layout.positions[id]!.dx, 268, reason: id);
      }
      expect(layout.positions['rdp']!.dx, 508);
      expect(layout.size, const Size(716, 366));
    });

    test('Node bounds do not overlap and all geometry fits its content bounds',
        () {
      final snapshot = _demoSnapshot();
      final edges = networkEdges(snapshot);
      final linked = networkLinkedDeviceIds(edges);
      final layout = TopologyLayout.build(
          snapshot.devices.where((d) => linked.contains(d.id)).toList(), edges);
      final rects = layout.devices.map((d) => layout.rect(d.id)).toList();
      for (var i = 0; i < rects.length; i++) {
        expect(layout.contentBounds.contains(rects[i].topLeft), isTrue);
        expect(layout.contentBounds.contains(rects[i].bottomRight), isTrue);
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].overlaps(rects[j]), isFalse,
              reason: '${layout.devices[i].id} / ${layout.devices[j].id}');
        }
      }
    });

    test('Edges use delivered pairs and routed curves avoid unrelated nodes',
        () {
      final snapshot = _demoSnapshot();
      final edges = networkEdges(snapshot);
      final linked = networkLinkedDeviceIds(edges);
      final layout = TopologyLayout.build(
          snapshot.devices.where((d) => linked.contains(d.id)).toList(), edges);
      expect(layout.edges.map((e) => e.id),
          unorderedEquals(edges.map((e) => e.id)));
      for (final edge in edges) {
        final curve = networkEdgeCurve(layout, edge.link)!;
        for (var step = 1; step < 32; step++) {
          final point = networkEdgePoint(curve, step / 32);
          for (final device in layout.devices) {
            if (device.id == edge.link.from || device.id == edge.link.to) {
              continue;
            }
            expect(layout.rect(device.id).contains(point), isFalse,
                reason: '${edge.shortLabel} crosses ${device.id}');
          }
        }
      }
    });

    test('Fit transform contains and centres actual content bounds', () {
      const content = Rect.fromLTWH(0, 0, 820, 366);
      const viewport = Size(750, 480);
      final transform = networkFitTransform(content, viewport);
      final fitted = networkTransformedRect(content, transform);
      expect(fitted.left, greaterThanOrEqualTo(0));
      expect(fitted.top, greaterThanOrEqualTo(0));
      expect(fitted.right, lessThanOrEqualTo(viewport.width));
      expect(fitted.bottom, lessThanOrEqualTo(viewport.height));
      expect(fitted.center.dx, closeTo(viewport.width / 2, 1e-8));
      expect(fitted.center.dy, closeTo(viewport.height / 2, 1e-8));
      expect(
          networkFitScale(viewport, content.size), closeTo(.8853658536, 1e-8));
      expect(networkFitScale(Size.zero, const Size(100, 100)), 1);
    });

    test('Distance hit test handles segments and zero length', () {
      expect(
          networkDistanceToSegment(
              const Offset(5, 2), Offset.zero, const Offset(10, 0)),
          2);
      expect(
          networkDistanceToSegment(
              const Offset(3, 4), Offset.zero, Offset.zero),
          5);
    });
  });

  testWidgets('Node selection drives integrated inspector and survives updates',
      (tester) async {
    final app = await _bootstrap(tester);
    await _navigate(tester);
    await tester.tap(find.byKey(const Key('topology-evo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Details schließen'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('node-inspector')), findsOneWidget);
    expect(find.text('Device-ID'), findsOneWidget);
    expect(find.text('evo'), findsWidgets);
    expect(find.text('Direkte logische Nachbarn'), findsOneWidget);
    final canvas = tester.getTopLeft(find.byKey(const Key('topology-evo')));
    app.api.data['devices'] =
        (app.api.data['devices'] as List).reversed.toList();
    app.controller.snapshot = Snapshot.fromJson(app.api.data);
    app.controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const Key('topology-evo'))), canvas);
    expect(find.byKey(const Key('node-inspector')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('A graph edge opens the edge inspector with honest measurements',
      (tester) async {
    await _bootstrap(tester);
    await _navigate(tester);
    await tester.tap(find.text('LAN'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edge-inspector')), findsOneWidget);
    expect(find.text('Verbindungsinspektion'), findsOneWidget);
    expect(find.text('Logische Zuordnung · nicht physikalisch verifiziert'),
        findsOneWidget);
    expect(find.text('1.5 ms · Fixture'), findsOneWidget);
    expect(find.text('Nicht im Link-DTO enthalten'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Fit, reset and zoom retain explicit graph controls',
      (tester) async {
    await _bootstrap(tester);
    await _navigate(tester);
    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    final controller = viewer.transformationController!;
    await tester.tap(find.byKey(const Key('fit-topology')));
    await tester.pump();
    final fitted = controller.value.getMaxScaleOnAxis();
    expect(fitted, greaterThan(0));
    expect(fitted, lessThanOrEqualTo(1));
    final viewport = tester.getRect(find.byKey(const Key('network-viewer')));
    for (final id in ['M-01', 'evo']) {
      final rect = tester.getRect(find.byKey(Key('topology-$id')));
      expect(viewport.contains(rect.topLeft), isTrue, reason: id);
      expect(viewport.contains(rect.bottomRight), isTrue, reason: id);
    }
    await tester.tap(find.byTooltip('Vergrößern'));
    await tester.pump();
    expect(controller.value.getMaxScaleOnAxis(), greaterThan(fitted));
    await tester.tap(find.byTooltip('Ansicht zurücksetzen'));
    await tester.pump();
    expect(controller.value.getMaxScaleOnAxis(), 1);
    expect(controller.value.getTranslation().x, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Keyboard arrows select nodes and Enter preserves detail navigation',
      (tester) async {
    await _bootstrap(tester);
    await _navigate(tester);
    final focus = tester.widget<Focus>(find.byWidgetPredicate((widget) =>
        widget is Focus && widget.focusNode?.debugLabel == 'network-graph'));
    focus.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('node-inspector')), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Fünf unabhängige Statusdimensionen'), findsOneWidget);
    await tester.tap(find.byTooltip('Details schließen'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Node search and type filter reduce only delivered graph nodes',
      (tester) async {
    await _bootstrap(tester);
    await _navigate(tester);
    await tester.enterText(find.byKey(const Key('network-search')), 'evo');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('topology-evo')), findsOneWidget);
    expect(find.byKey(const Key('topology-M-01')), findsNothing);
    await tester.tap(find.byTooltip('Suche löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('network-kind-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compute').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('topology-evo')), findsOneWidget);
    expect(find.byKey(const Key('topology-M-01')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Connections select the same edge and expose endpoint navigation',
      (tester) async {
    await _bootstrap(tester);
    await _navigate(tester);
    await tester.tap(find.byKey(const Key('network-tab-connections')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('connections-list')), findsOneWidget);
    await tester.tap(find.textContaining('1.5 ms · Fixture'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edge-inspector')), findsOneWidget);
    await tester.ensureVisible(find.text('Zu AMD EVO-X2'));
    await tester.tap(find.text('Zu AMD EVO-X2'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('node-inspector')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Connection filters handle mixed provenance and null measurements',
      (tester) async {
    final app = await _bootstrap(tester);
    app.api.data['topology'] = [
      app.api.data['topology'][0],
      {
        'from': 'evo',
        'to': 'M-01',
        'transport': 'WAN',
        'status': 'unknown',
        'latency_ms': null,
        'packet_loss_percent': null,
        'simulated': false,
      }
    ];
    app.controller.snapshot = Snapshot.fromJson(app.api.data);
    app.controller.notifyListeners();
    await tester.pumpAndSettle();
    await _navigate(tester);
    await tester.tap(find.byKey(const Key('network-tab-connections')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nicht gemessen'), findsWidgets);
    expect(find.text('Nicht verfügbar'), findsWidgets);
    await tester.tap(find.byKey(const Key('network-transport-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transport: WAN').last);
    await tester.pumpAndSettle();
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('0.0 % · Fixture'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('VPN mode has a capability empty state and no invented peers',
      (tester) async {
    await _bootstrap(tester);
    await _navigate(tester);
    await tester.tap(find.byKey(const Key('network-tab-vpn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('network-vpn-empty')), findsOneWidget);
    expect(find.text('Keine VPN-Telemetrie geliefert'), findsOneWidget);
    expect(find.text('PEERS · NICHT VERFÜGBAR'), findsOneWidget);
    expect(find.text('Keine VPN-Peer-Telemetrie verfügbar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Diagnostics separates collection evidence from network unknowns',
      (tester) async {
    final app = await _bootstrap(tester);
    app.api.data['metrics'] = [observation(value: null)];
    app.controller.snapshot = Snapshot.fromJson(app.api.data);
    app.controller.notifyListeners();
    await tester.pumpAndSettle();
    await _navigate(tester);
    await tester.tap(find.byKey(const Key('network-tab-diagnostics')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('network-diagnostics')), findsOneWidget);
    expect(find.textContaining('invalid_measurement'), findsOneWidget);
    expect(find.text('Network Events / Link History'), findsOneWidget);
    expect(find.text('Nicht verfügbar'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Stale transport does not present cached freshness as current',
      (tester) async {
    final app = await _bootstrap(tester);
    app.controller.connection = 'reconnecting';
    app.controller.notifyListeners();
    await tester.pumpAndSettle();
    await _navigate(tester);
    await tester.tap(find.byKey(const Key('topology-evo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Details schließen'));
    await tester.pumpAndSettle();
    expect(find.text('API STALE / UNBEKANNT'), findsOneWidget);
    expect(find.text('Veraltet'), findsWidgets);
    expect(find.text('Datenalter nicht aktuell verifizierbar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Initial demo fit contains six endpoints and integrates eleven unknown-relation devices in Explorer',
      (tester) async {
    final app = await _bootstrap(tester, data: _demoData());
    await _navigate(tester);
    final viewer = tester.getRect(find.byKey(const Key('network-viewer')));
    for (final id in [
      'router',
      'M-01',
      'evo',
      'remote-linux',
      'remote-windows',
      'rdp'
    ]) {
      final node = tester.getRect(find.byKey(Key('topology-$id')));
      expect(viewer.contains(node.topLeft), isTrue, reason: id);
      expect(viewer.contains(node.bottomRight), isTrue, reason: id);
    }
    expect(find.byKey(const Key('network-device-explorer')), findsOneWidget);
    expect(find.byKey(const Key('network-unlinked-inventory')), findsNothing);
    expect(find.text('RELATION UNBEKANNT 11'), findsOneWidget);
    expect(find.byKey(const Key('explorer-device-router')), findsOneWidget);
    final viewerWidget =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    final before = viewerWidget.transformationController!.value.clone();
    app.api.data['devices'] =
        (app.api.data['devices'] as List).reversed.toList();
    app.controller.snapshot = Snapshot.fromJson(app.api.data);
    app.controller.notifyListeners();
    await tester.pumpAndSettle();
    expect(
        viewerWidget.transformationController!.value.storage, before.storage);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Narrow fit preserves readability and supports explicit panning',
      (tester) async {
    await _bootstrap(tester, size: const Size(390, 844), data: _demoData());
    await _navigate(tester, width: 390);
    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    expect(viewer.transformationController!.value.getMaxScaleOnAxis(), .55);
    expect(find.textContaining('horizontal pannen', skipOffstage: false),
        findsOneWidget);
    expect(find.byKey(const Key('network-tab-connections')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('Network Phase 2 engineering workflows', () {
    testWidgets('Explorer selects and focuses a known node without a dialog',
        (tester) async {
      await _bootstrap(tester, data: _demoData());
      await _navigate(tester);
      final viewer =
          tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      final before = viewer.transformationController!.value.clone();
      await tester.tap(find.byKey(const Key('explorer-device-evo')));
      await tester.pumpAndSettle();
      expect(viewer.transformationController!.value.storage, before.storage,
          reason: 'an already visible Explorer node must not move the camera');
      expect(find.byKey(const Key('neighbors-only')), findsOneWidget);
      expect(find.byKey(const Key('node-inspector')), findsOneWidget);
      expect(find.byKey(const Key('network-copy-id')), findsOneWidget);
      expect(find.byTooltip('Details schließen'), findsNothing);
      expect(find.text('Direkte logische Nachbarn'), findsOneWidget);
      expect(find.textContaining('1 gelieferte direkte Pfade'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Automatic focus preserves the user-selected zoom scale',
        (tester) async {
      await _bootstrap(tester, data: _demoData());
      await _navigate(tester);
      final viewer =
          tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      await tester.tap(find.byTooltip('Vergrößern'));
      await tester.pumpAndSettle();
      final scale = viewer.transformationController!.value.getMaxScaleOnAxis();
      await tester.tap(find.byKey(const Key('explorer-device-router')));
      await tester.pumpAndSettle();
      expect(viewer.transformationController!.value.getMaxScaleOnAxis(), scale);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Relation-unknown device remains inspectable without fake edge',
        (tester) async {
      await _bootstrap(tester, data: _demoData());
      await _navigate(tester);
      await tester.enterText(find.byKey(const Key('network-search')), 'pi3');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('explorer-device-pi3')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('topology-pi3')), findsNothing);
      expect(find.byKey(const Key('node-inspector')), findsOneWidget);
      expect(find.text('Relation unbekannt · keine bekannten Pfade'),
          findsOneWidget);
      final focus = tester
          .widget<ToolButton>(find.byKey(const Key('network-focus-node')));
      expect(focus.onPressed, isNull);
      final graph = tester
          .widget<NetworkTopologyGraph>(find.byType(NetworkTopologyGraph));
      expect(graph.selectedDeviceId, isNull);
      expect(graph.highlightedDeviceIds, isEmpty);
      expect(find.byKey(const Key('neighbors-only')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Relation filter, ID/source search, type and sorting are real',
        (tester) async {
      await _bootstrap(tester, data: _demoData());
      await _navigate(tester);
      await tester.tap(find.byKey(const Key('network-relation-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Relation: Relation unbekannt').last);
      await tester.pumpAndSettle();
      expect(find.text('11/17 Geräte'), findsOneWidget);
      expect(find.byKey(const Key('network-viewer')), findsNothing);
      await tester.enterText(find.byKey(const Key('network-search')), 'pi4');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('explorer-device-pi4')), findsOneWidget);
      expect(find.byKey(const Key('explorer-device-pi3')), findsNothing);
      await tester.tap(find.byTooltip('Suche löschen'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('network-relation-filter')));
      await tester.pumpAndSettle();
      await tester
          .tap(find.text('Relation: Bekannte Topologie-Endpunkte').last);
      await tester.pumpAndSettle();
      expect(find.text('6/17 Geräte'), findsOneWidget);
      expect(find.byKey(const Key('network-viewer')), findsOneWidget);
      await tester.tap(find.byKey(const Key('network-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sortierung: Anzahl Relationen').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('Pins, recents and device/link comparison stay session local',
        (tester) async {
      await _bootstrap(tester, data: _demoData());
      await _navigate(tester);
      await tester.tap(find.byKey(const Key('explorer-device-evo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('network-pin-toggle')));
      await tester.tap(find.byKey(const Key('network-compare-toggle')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('network-search')), 'router');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('explorer-device-router')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('network-compare-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('network-pin-evo')), findsOneWidget);
      expect(find.text('Zuletzt 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('network-tab-connections')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Pfad vergleichen').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('network-compare-open')));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const Key('network-compare-workspace')), findsOneWidget);
      expect(find.textContaining('2/4 Geräte · 1/4 Pfade'), findsOneWidget);
      expect(find.text('Unabhängige Beobachtungskontexte'), findsOneWidget);
      expect(find.text('GERÄTEVERGLEICH · 2/4'), findsOneWidget);
      await tester.drag(find.byKey(const Key('network-compare-scroll')),
          const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('VERBINDUNGSVERGLEICH · 1/4'), findsOneWidget);
      await tester.tap(find.byKey(const Key('network-compare-clear')));
      await tester.pumpAndSettle();
      expect(find.text('Noch keine Engineering-Auswahl'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Keyboard navigation, pin and compare do not steal text input',
        (tester) async {
      await _bootstrap(tester, data: _demoData());
      await _navigate(tester);
      final focus = tester.widget<Focus>(find.byWidgetPredicate((widget) =>
          widget is Focus &&
          widget.focusNode?.debugLabel == 'network-device-list'));
      focus.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('node-inspector')), findsOneWidget);
      expect(find.text('Vergleich 1'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('network-search')), 'pczz');
      await tester.pumpAndSettle();
      expect(find.text('Vergleich 1'), findsOneWidget);
      expect(find.text('Keine Geräte im Filter'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Edge labels toggle and all five links remain selectable',
        (tester) async {
      await _bootstrap(tester, data: _demoData());
      await _navigate(tester);
      expect(find.bySemanticsLabel(RegExp('Verbindung .* nach')),
          findsNWidgets(5));
      await tester.tap(find.byKey(const Key('edge-labels-toggle')));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp('Verbindung .* nach')), findsNothing);
      await tester.tap(find.byKey(const Key('network-tab-connections')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('connections-list')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Verbindungspfad .* nach')),
          findsNWidgets(5));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Snapshot updates retain pins/compare but scope changes clear them',
        (tester) async {
      final app = await _bootstrap(tester, data: _demoData());
      await _navigate(tester);
      await tester.tap(find.byKey(const Key('explorer-device-evo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('network-pin-toggle')));
      await tester.tap(find.byKey(const Key('network-compare-toggle')));
      await tester.pumpAndSettle();
      app.api.data['devices'] =
          (app.api.data['devices'] as List).reversed.toList();
      app.controller.snapshot = Snapshot.fromJson(app.api.data);
      app.controller.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Vergleich 1'), findsOneWidget);
      expect(find.byKey(const Key('network-pin-evo')), findsOneWidget);
      app.api.data['system']['primary_source_id'] = 'other-scope';
      app.controller.snapshot = Snapshot.fromJson(app.api.data);
      app.controller.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('Vergleich 0'), findsOneWidget);
      expect(find.byKey(const Key('network-pin-evo')), findsNothing);
      expect(find.byKey(const Key('network-adaptive-inspector')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Empty delivered inventory and topology stay honest',
        (tester) async {
      final data = _demoData();
      data['devices'] = [];
      data['topology'] = [];
      data['metrics'] = [];
      data['incidents'] = [];
      await _bootstrap(tester, data: data);
      await _navigate(tester);
      expect(find.text('Keine Geräte im Filter'), findsOneWidget);
      expect(
          find.textContaining(
              'Keine registrierten Geräte im aktuellen Kontext'),
          findsOneWidget);
      expect(find.bySemanticsLabel('REGISTRIERTE NODES 0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Mobile switches between primary, Explorer and Inspector',
        (tester) async {
      await _bootstrap(tester, size: const Size(390, 844), data: _demoData());
      await _navigate(tester, width: 390);
      await tester.ensureVisible(find.text('Explorer'));
      await tester.tap(find.text('Explorer'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('network-search')), 'pi3');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('explorer-device-pi3')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('node-inspector')), findsOneWidget);
      expect(find.text('Relation unbekannt · keine bekannten Pfade'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  for (final size in const [
    Size(320, 740),
    Size(375, 812),
    Size(390, 844),
    Size(768, 1024),
    Size(834, 1112),
    Size(1024, 900),
    Size(1440, 1000),
    Size(1920, 1080),
  ]) {
    testWidgets('All network workspaces remain usable at ${size.width}',
        (tester) async {
      await _bootstrap(tester, size: size);
      await _navigate(tester, width: size.width);
      for (final mode in ['connections', 'vpn', 'diagnostics', 'topology']) {
        await tester.ensureVisible(find.byKey(Key('network-tab-$mode')));
        await tester.tap(find.byKey(Key('network-tab-$mode')));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const Key('network-summary')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<_App> _bootstrap(WidgetTester tester,
    {Size size = const Size(1440, 1000), Json? data}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  await tester.binding.setSurfaceSize(size);
  final api = FakeApi()..data = data ?? fixture();
  final controller = OipController(api)
    ..snapshot = Snapshot.fromJson(api.data)
    ..connection = 'live'
    ..workspaces.setView(WorkspaceId.network, 'topology')
    ..workspaces.setAdvancedFilters(WorkspaceId.network, true)
    ..workspaces.setInspectorOpen(WorkspaceId.network, true);
  await tester.pumpWidget(OipApp(controller: controller, autoStart: false));
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.binding.setSurfaceSize(null);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  return _App(api, controller);
}

Future<void> _navigate(WidgetTester tester, {double width = 1440}) async {
  if (width < 1080) {
    await tester.tap(find.byKey(const Key('open-navigation')));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const Key('nav-2')));
  await tester.pumpAndSettle();
}

Json _demoData() {
  final data = fixture();
  const inventory = [
    ('evo', 'AMD EVO-X2', 'Compute', 'LAN'),
    ('pi3', 'Raspberry Pi 3B', 'Edge', 'LAN'),
    ('pi4', 'Raspberry Pi 4', 'Edge', 'LAN'),
    ('windows', 'Windows-PC', 'Desktop', 'LAN'),
    ('mac', 'macOS-Laptop', 'Laptop', 'LAN'),
    ('mini', 'Linux-Mini-PC', 'Compute', 'LAN'),
    ('tablet', 'Android-Tablet', 'Mobile', 'LAN'),
    ('phone', 'Android-Smartphone', 'Mobile', 'LAN'),
    ('esp32', 'ESP32', 'Sensor', 'LAN'),
    ('router', 'OpenWrt-Router', 'Gateway', 'LAN'),
    ('cast', 'Chromecast', 'Media', 'LAN'),
    ('tv', 'Smart-TV', 'Media', 'LAN'),
    ('hue', 'Philips Hue', 'Bridge', 'LAN'),
    ('remote-linux', 'Remote-Linux-Server', 'Server', 'Tailnet'),
    ('remote-windows', 'Remote-Windows-Server', 'Server', 'Remote Site'),
    ('rdp', 'RDP-Server', 'Service', 'Remote Site'),
    ('M-01', 'OPC-UA-Sensoren · M-01', 'Industrial', 'LAN'),
  ];
  data['devices'] = [
    for (final item in inventory)
      {
        'id': item.$1,
        'is_faulted': false,
        'data_source_id': null,
        'name': item.$2,
        'kind': item.$3,
        'location': item.$4,
        'connection': 'Ethernet',
        'simulated': true,
        'health': {
          'reachability': 'reachable',
          'vpn_transport': 'not_applicable',
          'agent_availability': 'unknown',
          'service_health': 'unknown',
          'telemetry_freshness': 'unknown',
        },
      },
  ];
  data['topology'] = [
    for (final link in [
      ('router', 'evo', 'LAN'),
      ('router', 'M-01', 'LAN'),
      ('router', 'remote-linux', 'Tailnet'),
      ('router', 'remote-windows', 'WireGuard'),
      ('remote-windows', 'rdp', 'Site VPN'),
    ])
      {
        'from': link.$1,
        'to': link.$2,
        'transport': link.$3,
        'status': 'connected',
        'latency_ms': 1.0,
        'packet_loss_percent': 0.2,
        'simulated': true,
      },
  ];
  return data;
}

Snapshot _demoSnapshot() => Snapshot.fromJson(_demoData());

class _App {
  final FakeApi api;
  final OipController controller;
  const _App(this.api, this.controller);
}
