import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/app.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/features/diagnostics.dart';
import 'package:oip_dashboard/features/diagnostics/diagnostics_model.dart';
import 'package:oip_dashboard/features/diagnostics/diagnostics_workspaces.dart';
import 'package:oip_dashboard/features/diagnostics/event_explorer.dart';
import 'package:oip_dashboard/features/diagnostics/evidence_inspector.dart';
import 'package:oip_dashboard/features/diagnostics/evidence_timeline.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/services/api.dart';
import 'support.dart';

Json eventJson(String kind, int? at,
        {String? reason, int? gapStart, int? gapEnd, int? dropped}) =>
    {
      kind: {
        if (at != null) 'at': at,
        if (reason != null) 'reason': reason,
        if (dropped != null) 'dropped': dropped,
        if (gapStart != null || gapEnd != null)
          'gap': {
            if (gapStart != null) 'started_at': gapStart,
            if (gapEnd != null) 'ended_at': gapEnd,
            'reason': 'not projected by the shared Flutter DTO',
          },
      }
    };

Json recordJson(String source, int sequence, String kind, int? at,
        {String? reason, int? gapStart, int? gapEnd, int? dropped}) =>
    {
      'sequence': sequence,
      'context': {'data_source_id': source, 'origin_class': 'test_fixture'},
      'event': eventJson(kind, at,
          reason: reason, gapStart: gapStart, gapEnd: gapEnd, dropped: dropped),
    };

CollectionEvent record(String source, int sequence, String kind, int? at,
        {String? reason, int? gapStart, int? gapEnd, int? dropped}) =>
    CollectionEvent.fromRecord(recordJson(source, sequence, kind, at,
        reason: reason, gapStart: gapStart, gapEnd: gapEnd, dropped: dropped));
CollectionEvent fallback(String kind, int? at,
        {String? reason, int? gapStart, int? gapEnd, int? dropped}) =>
    CollectionEvent.fromJson(eventJson(kind, at,
        reason: reason, gapStart: gapStart, gapEnd: gapEnd, dropped: dropped));

class DiagnosticsFakeApi extends FakeApi {
  List<CollectionEvent> delivered = [];
  int eventCalls = 0;
  bool failEventRead = false;
  Completer<List<CollectionEvent>>? pendingEvents;

  @override
  Future<List<CollectionEvent>> collectionEvents() {
    eventCalls++;
    if (failEventRead) {
      return Future.error(const ApiFailure('Diagnostics read failed',
          code: 'TEST_TIMEOUT', path: '/api/v1/events'));
    }
    final pending = pendingEvents;
    if (pending != null) return pending.future;
    return Future.value(List.of(delivered));
  }
}

class Harness {
  final DiagnosticsFakeApi api;
  final OipController controller;
  Harness(this.api) : controller = OipController(api) {
    controller.snapshot = Snapshot.fromJson(api.data);
    controller.connection = 'live';
    controller.workspaces.setView(WorkspaceId.diagnostics, 'timeline');
    controller.workspaces.setAdvancedFilters(WorkspaceId.diagnostics, true);
    controller.workspaces.setExpertWorkspace(WorkspaceId.diagnostics, true);
    controller.workspaces.setInspectorOpen(WorkspaceId.diagnostics, true);
  }
}

Future<Harness> bootstrap(WidgetTester tester,
    {List<CollectionEvent>? events,
    Json? data,
    double width = 1440,
    double height = 1000}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  await tester.binding.setSurfaceSize(Size(width, height));
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    return tester.binding.setSurfaceSize(null);
  });
  final api = DiagnosticsFakeApi()
    ..delivered = events ??
        [
          record('sim-a', 1, 'ConnectionLost', 1700000000000),
          record('sim-a', 2, 'Reconnected', 1700000002500,
              gapStart: 1700000000000, gapEnd: 1700000002500)
        ];
  if (data != null) api.data = data;
  final harness = Harness(api);
  await tester
      .pumpWidget(OipApp(controller: harness.controller, autoStart: false));
  await tester.pumpAndSettle();
  if (width < 1080) {
    await tester.tap(find.byKey(const Key('open-navigation')));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const Key('nav-4')));
  await tester.pumpAndSettle();
  return harness;
}

Future<void> closeHarness(WidgetTester tester, Harness harness) async {
  await tester.pumpWidget(const SizedBox());
  harness.controller.dispose();
}

Future<void> selectRecord(WidgetTester tester, String recordId) async {
  await tester.enterText(find.byKey(const Key('diagnostics-search')), recordId);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(Key('diagnostics-event-$recordId')));
  await tester.tap(find.byKey(Key('diagnostics-event-$recordId')));
  await tester.pumpAndSettle();
}

void main() {
  group('Diagnostics model and data honesty', () {
    test('Record duplicates consolidate without inventing a second fact', () {
      final duplicate = record('a', 7, 'ConnectionLost', 100, reason: 'lost');
      final result = diagnosticEventsFromApi([duplicate, duplicate]);
      expect(result, hasLength(1));
      expect(result.single.recordId, 'a#7');
      expect(result.single.deliveryCount, 2);
    });

    test(
        'Fallback duplicates remain distinct and sequence conflicts stay visible',
        () {
      final result = diagnosticEventsFromApi([
        fallback('ConnectionLost', 100),
        fallback('ConnectionLost', 100),
        record('a', 7, 'ConnectionLost', 100),
        record('a', 7, 'ConnectionLost', 100, reason: 'different'),
      ]);
      expect(result, hasLength(4));
      expect(result.take(2).map((item) => item.key).toSet(), hasLength(2));
      expect(result.last.identityConflict, isTrue);
      expect(result.last.recordId, 'a#7');
    });

    test(
        'Search, source/type filters, out-of-order sorting and loaded time window',
        () {
      final items = diagnosticEventsFromApi([
        record('a', 1, 'ConnectionLost', 100, reason: 'socket closed'),
        record('b', 2, 'Reconnected', 300000),
        record('a', 3, 'DataLoss', 200, dropped: 9),
      ]);
      expect(
          filterDiagnosticEvents(items, sort: DiagnosticEventSort.newest)
              .map((item) => item.event.sequence),
          [2, 3, 1]);
      expect(filterDiagnosticEvents(items, query: 'socket'), hasLength(1));
      expect(filterDiagnosticEvents(items, source: 'a'), hasLength(2));
      expect(filterDiagnosticEvents(items, type: 'DataLoss'), hasLength(1));
      expect(
          filterDiagnosticEvents(items, window: DiagnosticTimeWindow.oneMinute),
          hasLength(1));
      expect(filterDiagnosticEvents(items, query: 'not-in-history'), isEmpty);
    });

    test('Dense groups retain exact members and zoom resolves near events', () {
      final items = diagnosticEventsFromApi([
        record('a', 1, 'ConnectionLost', 1000),
        record('a', 2, 'Reconnected', 1100)
      ]);
      final fitted = diagnosticsTimelineRange(items);
      final grouped = diagnosticTimelineClusters(items, fitted, 100);
      expect(grouped.single.events, hasLength(2));
      expect(grouped.single.firstMs, 1000);
      expect(grouped.single.lastMs, 1100);
      const zoomed = DiagnosticsTimelineRange(
          dataStartMs: 1000,
          dataEndMs: 1100,
          startMs: 900,
          endMs: 1200,
          zoom: 2,
          panMs: 0);
      final resolved = diagnosticTimelineClusters(items, zoomed, 1000);
      expect(resolved, hasLength(2));
    });

    test('Missing timestamps never enter timeline and clock gaps remain honest',
        () {
      final items = diagnosticEventsFromApi([
        fallback('FutureEvent', null),
        record('a', 1, 'Reconnected', 100, gapStart: 200, gapEnd: 100)
      ]);
      final range = diagnosticsTimelineRange(items);
      expect(range.dataStartMs, 100);
      expect(range.dataEndMs, 100);
      expect(items[1].gapIsInverted, isTrue);
      expect(items[1].event.gapMs, isNull);
    });
  });

  group('Diagnostics workstation workflows', () {
    testWidgets(
        'Desktop three panes share Explorer, timeline and Inspector selection',
        (tester) async {
      final harness = await bootstrap(tester);
      expect(find.byType(DiagnosticsEventExplorer), findsOneWidget);
      expect(find.byType(DiagnosticsEventTimeline), findsOneWidget);
      expect(find.byType(DiagnosticsEvidenceInspector), findsOneWidget);
      await tester
          .ensureVisible(find.byKey(const Key('diagnostics-event-sim-a#1')));
      await tester.tap(find.byKey(const Key('diagnostics-event-sim-a#1')));
      await tester.pumpAndSettle();
      expect(find.text('COLLECTION EVENT · KEINE KAUSALBEHAUPTUNG'),
          findsOneWidget);
      expect(find.text('Nicht vom Core geliefert'), findsWidgets); // severity
      expect(find.text('Für CollectionEvent nicht geliefert'), findsOneWidget);
      expect(find.text('Keine Server-Record-ID'), findsNothing);
      await tester.tap(find.byTooltip('In Timeline fokussieren'));
      await tester.pumpAndSettle();
      expect(find.byType(DiagnosticsEventTimeline), findsOneWidget);
      expect(tester.takeException(), isNull);
      await closeHarness(tester, harness);
    });

    testWidgets(
        'Multiple sources, zoom, fit, pan and dense group disclosure preserve every event',
        (tester) async {
      final events = [
        for (var index = 0; index < 12; index++)
          record(index.isEven ? 'sim-a' : 'sim-b', index + 1,
              index.isEven ? 'ConnectionLost' : 'Reconnected', 1700000000000),
      ];
      final harness = await bootstrap(tester, events: events);
      expect(find.text('sim-a'), findsWidgets);
      expect(find.text('sim-b'), findsWidgets);
      final group = find.byWidgetPredicate((widget) =>
          widget.key is ValueKey<String> &&
          (widget.key as ValueKey<String>).value.startsWith('timeline-group-'));
      expect(group, findsWidgets);
      await tester.tap(group.first);
      await tester.pumpAndSettle();
      expect(find.textContaining('zeitnahe Ereignisse'), findsOneWidget);
      expect(
          find.byWidgetPredicate((widget) =>
              widget.key is ValueKey<String> &&
              (widget.key as ValueKey<String>)
                  .value
                  .startsWith('diagnostics-timeline-group-event-')),
          findsWidgets);
      await tester.tap(find.text('Schließen'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Timeline vergrößern'));
      await tester.pumpAndSettle();
      expect(find.text('2.0×'), findsOneWidget);
      await tester.tap(find.byTooltip('Timeline nach rechts'));
      await tester.tap(find.byTooltip('Fit to Available Data'));
      await tester.pumpAndSettle();
      expect(find.text('1.0×'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await closeHarness(tester, harness);
    });

    testWidgets(
        'Missing timestamp and unknown type stay searchable without fake marker',
        (tester) async {
      final harness = await bootstrap(tester,
          events: [record('a', 1, 'FutureEvent', null)]);
      expect(find.byKey(const Key('diagnostics-event-a#1')), findsOneWidget);
      expect(find.text('Unbekanntes Collection-Ereignis'), findsWidgets);
      expect(find.text('Keine zeitgestempelten Ereignisse'), findsOneWidget);
      expect(
          find.byWidgetPredicate((widget) =>
              widget.key is ValueKey<String> &&
              (widget.key as ValueKey<String>).value.startsWith('timeline-a#')),
          findsNothing);
      await tester.tap(find.byKey(const Key('diagnostics-event-a#1')));
      await tester.pumpAndSettle();
      expect(find.text('Nicht vom Server geliefert'),
          findsNothing); // record ID exists
      expect(find.text('Unbekannt'), findsWidgets);
      expect(tester.takeException(), isNull);
      await closeHarness(tester, harness);
    });

    testWidgets('DataLoss, zero gap and inverted gap expose distinct semantics',
        (tester) async {
      final harness = await bootstrap(tester, events: [
        record('a', 1, 'DataLoss', 100, gapStart: 100, gapEnd: 100, dropped: 9),
        record('a', 2, 'Reconnected', 200, gapStart: 200, gapEnd: 200),
        record('a', 3, 'Reconnected', 300, gapStart: 400, gapEnd: 300),
      ]);
      await selectRecord(tester, 'a#1');
      expect(find.text('9'), findsOneWidget);
      expect(find.textContaining('verlorenes Intervall nicht bestimmbar'),
          findsOneWidget);
      await selectRecord(tester, 'a#2');
      await tester.scrollUntilVisible(
          find.textContaining('0 ms · dokumentierte Null-Dauer'), 200,
          scrollable: find.descendant(
              of: find.byType(DiagnosticsEvidenceInspector),
              matching: find.byType(Scrollable)));
      await tester.pumpAndSettle();
      expect(find.textContaining('0 ms · dokumentierte Null-Dauer'),
          findsOneWidget);
      await selectRecord(tester, 'a#3');
      expect(find.textContaining('Ende liegt vor Beginn'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await closeHarness(tester, harness);
    });

    testWidgets('Keyboard navigation, pin and compare do not steal text input',
        (tester) async {
      final harness = await bootstrap(tester);
      await tester.tap(find.byKey(const Key('diagnostics-search')));
      await tester.enterText(
          find.byKey(const Key('diagnostics-search')), 'Reconnected');
      await tester.pumpAndSettle();
      expect(
          find.byKey(const Key('diagnostics-event-sim-a#2')), findsOneWidget);
      expect(find.byKey(const Key('diagnostics-event-sim-a#1')), findsNothing);
      expect(harness.controller.snapshot, isNotNull);
      tester
          .widget<Focus>(find.byKey(const Key('diagnostics-list-focus')))
          .focusNode!
          .requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pumpAndSettle();
      expect(find.byType(DiagnosticsCompareWorkspace), findsOneWidget);
      expect(find.byKey(const Key('compare-event-sim-a#2')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('1/4 Ereignisse · session-lokal'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await closeHarness(tester, harness);
    });

    testWidgets(
        'Compare is bounded at four and duplicate compare is deduplicated',
        (tester) async {
      final harness = await bootstrap(tester, events: [
        for (var i = 0; i < 6; i++)
          record('a', i + 1, 'ConnectionLost', 1000 + i * 1000)
      ]);
      for (var i = 1; i <= 4; i++) {
        await selectRecord(tester, 'a#$i');
        await tester
            .ensureVisible(find.byTooltip('Zu Compare hinzufügen').first);
        await tester
            .ensureVisible(find.byTooltip('Zu Compare hinzufügen').first);
        await tester.tap(find.byTooltip('Zu Compare hinzufügen').first);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('diagnostics-mode-timeline')));
        await tester.pumpAndSettle();
      }
      await selectRecord(tester, 'a#5');
      await tester.ensureVisible(find.byTooltip('Zu Compare hinzufügen').first);
      await tester.tap(find.byTooltip('Zu Compare hinzufügen').first);
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Maximal 4 Ereignisse pro Vergleich. Erst einen Eintrag entfernen.'),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('diagnostics-mode-compare')));
      await tester.pumpAndSettle();
      expect(find.text('4/4 Ereignisse · session-lokal'), findsOneWidget);
      final compareScrollable = find.descendant(
          of: find.byType(DiagnosticsCompareWorkspace),
          matching: find.byType(Scrollable));
      await tester.scrollUntilVisible(
          find.byKey(const Key('compare-event-a#4')), 250,
          scrollable: compareScrollable);
      expect(find.byKey(const Key('compare-event-a#4')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await closeHarness(tester, harness);
    });

    testWidgets(
        'Failed refresh marks old evidence stale and recovery restores it',
        (tester) async {
      final harness = await bootstrap(tester);
      harness.api.failEventRead = true;
      await tester.tap(find.byTooltip('Diagnosedaten aktualisieren'));
      await tester.pumpAndSettle();
      expect(
          find.text('Collection-Ereignisse nicht verfügbar'), findsOneWidget);
      expect(
          find.textContaining('LETZTER ERFOLGREICHER STAND'), findsOneWidget);
      expect(find.byType(DiagnosticsEventTimeline), findsOneWidget);
      harness.api.failEventRead = false;
      await tester.tap(find.byTooltip('Diagnosedaten aktualisieren'));
      await tester.pumpAndSettle();
      expect(find.text('Collection-Ereignisse nicht verfügbar'), findsNothing);
      expect(tester.takeException(), isNull);
      await closeHarness(tester, harness);
    });

    testWidgets(
        'Scope change clears selection, pins, recents, compare and old events',
        (tester) async {
      final harness = await bootstrap(tester);
      await tester
          .ensureVisible(find.byKey(const Key('diagnostics-event-sim-a#1')));
      await tester.tap(find.byKey(const Key('diagnostics-event-sim-a#1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Ereignis anheften').first);
      await tester.ensureVisible(find.byTooltip('Zu Compare hinzufügen').first);
      await tester.tap(find.byTooltip('Zu Compare hinzufügen').first);
      await tester.pumpAndSettle();
      final changed = fixture();
      (changed['system'] as Json)['primary_source_id'] = 'other-source';
      harness.api.delivered = [
        record('other-source', 1, 'Reconnected', 1700000003000)
      ];
      harness.controller.snapshot = Snapshot.fromJson(changed);
      harness.controller.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('1/4 Ereignisse · session-lokal'), findsNothing);
      expect(find.byKey(const Key('diagnostics-event-sim-a#1')), findsNothing);
      expect(find.byKey(const Key('diagnostics-adaptive-inspector')),
          findsNothing);
      expect(tester.takeException(), isNull);
      await closeHarness(tester, harness);
    });

    testWidgets(
        'In-flight reads coalesce and stale completion cannot cross a scope change',
        (tester) async {
      final harness = await bootstrap(tester);
      final pending = Completer<List<CollectionEvent>>();
      harness.api.pendingEvents = pending;
      await tester.tap(find.byTooltip('Diagnosedaten aktualisieren'));
      await tester.pump();
      await tester.tap(find.byTooltip('Diagnosedaten aktualisieren'));
      await tester.pump();
      expect(harness.api.eventCalls, 2,
          reason: 'initial plus one coalesced refresh');

      harness.api.pendingEvents = null;
      harness.api.delivered = [record('other-source', 1, 'Reconnected', 3000)];
      final changed = fixture();
      (changed['system'] as Json)['primary_source_id'] = 'other-source';
      harness.controller.snapshot = Snapshot.fromJson(changed);
      harness.controller.notifyListeners();
      await tester.pumpAndSettle();
      pending.complete([record('sim-a', 99, 'ConnectionLost', 9999)]);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('diagnostics-event-other-source#1')),
          findsOneWidget);
      expect(find.byKey(const Key('diagnostics-event-sim-a#99')), findsNothing);
      expect(tester.takeException(), isNull);
      await closeHarness(tester, harness);
    });

    testWidgets(
        'Collection Health uses actual source fields and opens gap evidence',
        (tester) async {
      final harness = await bootstrap(tester);
      await tester.tap(find.byKey(const Key('diagnostics-mode-health')));
      await tester.pumpAndSettle();
      expect(find.text('Source-Diagnostik & dokumentierte Datenlücken'),
          findsOneWidget);
      expect(find.text('Local OPC-UA Simulation'), findsOneWidget);
      expect(find.textContaining('2500 ms'), findsWidgets);
      await tester
          .ensureVisible(find.byKey(const Key('collection-gap-sim-a#2')));
      await tester.tap(find.byKey(const Key('collection-gap-sim-a#2')));
      await tester.pumpAndSettle();
      expect(find.byType(DiagnosticsEvidenceInspector), findsOneWidget);
      expect(find.text('Verbindung wiederhergestellt'), findsWidgets);
      expect(tester.takeException(), isNull);
      await closeHarness(tester, harness);
    });

    testWidgets(
        'Incident remains a demo finding without reconstructed rule evaluation',
        (tester) async {
      final data = fixture();
      data['incidents'] = [
        {
          'id': 'demo-1',
          'title': 'Demo finding',
          'category': 'Industrial',
          'device_id': 'M-01',
          'simulated': true,
          'supporting': ['Observed fixture A'],
          'contradicting': ['Counter fixture B'],
          'missing': ['Unknown C'],
          'timeline': ['T+0 fixture'],
        }
      ];
      final harness = await bootstrap(tester, data: data);
      expect(find.text('Demo finding'), findsOneWidget);
      expect(find.text('SIMULIERTER VORFALL'), findsOneWidget);
      expect(find.text('KEINE REGEL-ID / VERSION GELIEFERT'), findsOneWidget);
      expect(find.text('Diagnosehistorie: demo_only'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await closeHarness(tester, harness);
    });

    testWidgets(
        'Empty and single-event states do not invent incidents or history',
        (tester) async {
      final harness = await bootstrap(tester, events: []);
      expect(
          find.text('Keine Collection-Ereignisse geliefert'), findsOneWidget);
      expect(find.text('Kein aktiver Demo-Vorfall'), findsOneWidget);
      expect(find.text('Keine zeitgestempelte Ereignisse'), findsNothing);
      expect(tester.takeException(), isNull);
      await closeHarness(tester, harness);
    });

    testWidgets(
        'Large UI fixture uses a virtualized Explorer and bounded timeline objects',
        (tester) async {
      final harness = await bootstrap(tester, events: [
        for (var i = 0; i < 250; i++)
          record('bulk', i + 1, 'ConnectionLost', 1700000000000 + i * 100)
      ]);
      expect(find.text('250/250 im geladenen Fenster'), findsOneWidget);
      expect(tester.widgetList(find.byType(InkWell)).length, lessThan(100));
      expect(find.byType(DiagnosticsEventTimeline), findsOneWidget);
      expect(tester.takeException(), isNull);
      await closeHarness(tester, harness);
    });
  });

  group('Diagnostics responsive and themes', () {
    for (final width in [
      320.0,
      375.0,
      390.0,
      768.0,
      834.0,
      1024.0,
      1440.0,
      1920.0
    ]) {
      testWidgets('Diagnostics remains usable at $width px', (tester) async {
        final harness = await bootstrap(tester, width: width, height: 1000);
        expect(find.byType(DiagnosticsPage), findsOneWidget);
        if (width < 600) {
          expect(find.byType(DiagnosticsEventExplorer), findsOneWidget);
          await tester.ensureVisible(find.text('Timeline').last);
          await tester.tap(find.text('Timeline').last);
          await tester.pumpAndSettle();
          expect(find.byType(DiagnosticsEventTimeline), findsOneWidget);
          await tester.ensureVisible(find.text('Inspector'));
          await tester.tap(find.text('Inspector'));
          await tester.pumpAndSettle();
          expect(find.byType(DiagnosticsEvidenceInspector), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await closeHarness(tester, harness);
      });
    }

    testWidgets(
        'Spectrum, Graphite and Daylight preserve workstation semantics',
        (tester) async {
      final harness = await bootstrap(tester);
      for (final label in ['DAYLIGHT', 'GRAPHITE', 'SPECTRUM']) {
        await tester.tap(find.byKey(const Key('theme-toggle')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(find.byType(DiagnosticsEventTimeline), findsOneWidget);
        expect(find.text('EVIDENCE INSPECTOR'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await closeHarness(tester, harness);
    });
  });
}
