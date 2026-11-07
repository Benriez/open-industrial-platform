import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/app.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/core/sse.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/widgets/trend.dart';
import 'support.dart';

void main() {
  testWidgets(
      'The managed overview shows the authorized source and its real measurement',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    final events = StreamController<ServerEvent>.broadcast();
    final api = ManagedApi(managedClient(scopedSnapshot), events);
    // The session of the server marks the client as managed.
    await api.session();
    final controller = OipController(api,
        retryDelay: const Duration(milliseconds: 1))
      ..snapshot = Snapshot.fromScopedJson(scopedSnapshot())
      ..connection = 'live';
    // The series the controller measured from that projection. The test above
    // proves that the controller derives exactly this series from the Core
    // payload; here it is the input of the rendering.
    controller.series.add(TrendSeries(
        'source-ssh',
        'device-a',
        'host.memory_total_bytes',
        'bytes',
        (scopedSnapshot()['observations'] as List)
            .cast<Json>()
            .where((observation) =>
                observation['metric_id'] == 'host.memory_total_bytes')
            .map(Observation.fromJson)
            .toList()));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await events.close();
      await tester.binding.setSurfaceSize(null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    expect(controller.managed, isTrue);
    await tester.pumpWidget(OipApp(controller: controller, autoStart: false));
    await tester.pumpAndSettle();

    // The source registry of the session is shown with its real health.
    expect(find.text('SSH host device-a'), findsWidgets);
    expect(find.textContaining('source-ssh'), findsWidgets);
    expect(find.text('Verbunden'), findsWidgets);
    expect(find.text('Aktuell'), findsWidgets);
    // The placement of the source in the authorized hierarchy is shown.
    expect(find.textContaining('org-a · infra-a1 · site-a1'), findsOneWidget);
    // The measured value of the source is shown with its unit.
    expect(find.textContaining('17179869184 bytes'), findsWidgets);
    // The demo coordinates are gone in the managed mode.
    expect(find.textContaining('Temperatur M-01'), findsNothing);
    expect(find.textContaining('M-01'), findsNothing);
    // The chart names the metric it measured.
    expect(
        find.textContaining('host.memory_total_bytes · SSH host device-a'),
        findsOneWidget);
  });

  test('The managed mode measures one series per authorized source', () async {
    final events = StreamController<ServerEvent>.broadcast();
    var snapshot = scopedSnapshot();
    final controller = OipController(
        ManagedApi(managedClient(() => snapshot), events),
        retryDelay: const Duration(milliseconds: 1));
    final running = controller.start();
    for (var i = 0; i < 100 && controller.snapshot == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(controller.series, hasLength(1));
    final series = controller.series.single;
    expect(series.sourceId, 'source-ssh');
    expect(series.entityId, 'device-a');
    // The measured metric is named, it is never a silent choice.
    expect(series.metricId, 'host.memory_total_bytes');
    expect(series.samples, hasLength(1));
    expect(series.samples.single.value, 17179869184);

    // A later measurement of the same source extends the series.
    snapshot = scopedSnapshot(sourceMs: 1700000030000, memory: 17179860992);
    events.add(ServerEvent('snapshot', jsonEncode(snapshot)));
    for (var i = 0;
        i < 100 && controller.series.single.samples.length < 2;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(controller.series, hasLength(1));
    expect(controller.series.single.samples, hasLength(2));
    expect(controller.series.single.samples.last.sourceMs, 1700000030000);
    await events.close();
    await running;
  });

  test('The measured series of a real cadence is not broken by the demo limit',
      () async {
    // A real source publishes every 30 s. The legacy demo limit of 2.5 s
    // would break the line at every point.
    final samples = [
      Observation.fromJson(scopedObservation(
          metricId: 'host.uptime_seconds',
          value: {'float': 1.0},
          unit: {'custom': 'seconds'},
          sourceMs: 1700000000000,
          receivedMs: 1700000000000)),
      Observation.fromJson(scopedObservation(
          metricId: 'host.uptime_seconds',
          value: {'float': 31.0},
          unit: {'custom': 'seconds'},
          sourceMs: 1700000030000,
          receivedMs: 1700000030000)),
    ];
    expect(seriesGapLimit(samples), 45000);
    expect(
        continuesSeries(samples.first, samples.last, seriesGapLimit(samples)),
        isTrue);
    // The legacy rule keeps its own limit.
    expect(continuesTrend(samples.first, samples.last), isFalse);
  });
}
