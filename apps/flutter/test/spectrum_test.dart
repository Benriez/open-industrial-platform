import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/app.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/design_system/theme.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/widgets/components.dart';
import 'support.dart';

void main() {
  testWidgets('Spectrum, Daylight and Graphite remain selectable',
      (tester) async {
    final controller = OipController(FakeApi())
      ..snapshot = Snapshot.fromJson(fixture())
      ..connection = 'live';
    await tester.pumpWidget(OipApp(controller: controller, autoStart: false));
    await tester.pumpAndSettle();
    expect(find.text('SPECTRUM'), findsOneWidget);
    for (final label in ['DAYLIGHT', 'GRAPHITE', 'SPECTRUM']) {
      await tester.tap(find.byKey(const Key('theme-toggle')));
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('Tinted card and status indicator expose Spectrum semantics',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: OipTokens.theme(Brightness.dark),
      home: const Scaffold(
        body: GradientCard(
          accent: OipTokens.violet,
          child: StatusDot('reachable'),
        ),
      ),
    ));
    final container = tester.widget<Container>(find
        .descendant(
            of: find.byType(GradientCard), matching: find.byType(Container))
        .first);
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.gradient, isA<LinearGradient>());
    expect(find.bySemanticsLabel('Status: Erreichbar'), findsOneWidget);
  });

  testWidgets('Real backend wording never falls back to simulation labels',
      (tester) async {
    final data = fixture();
    (data['system'] as Json)['simulated'] = false;
    data['devices'] = (data['devices'] as List).map((device) {
      final copy = Map<String, dynamic>.from(device as Json);
      copy['simulated'] = false;
      return copy;
    }).toList();
    data['incidents'] = [
      {
        'id': 'backend-incident',
        'title': 'Backend-Befund',
        'category': 'Test',
        'device_id': 'M-01',
        'simulated': false,
        'supporting': <String>[],
        'contradicting': <String>[],
        'missing': <String>[],
        'timeline': <String>[],
      }
    ];
    final controller = OipController(FakeApi())
      ..snapshot = Snapshot.fromJson(data)
      ..connection = 'live';
    await tester.pumpWidget(OipApp(controller: controller, autoStart: false));
    await tester.pumpAndSettle();
    expect(find.textContaining('simulierte Zustände'), findsNothing);
    expect(find.textContaining('Backend-Befund · Backend'), findsOneWidget);
    expect(find.textContaining('Backend-Befund · Simulation'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('Evidence timeline selects real events and list stays available',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1000);
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      return tester.binding.setSurfaceSize(null);
    });
    final controller = OipController(FakeApi())
      ..snapshot = Snapshot.fromJson(fixture())
      ..connection = 'live';
    await tester.pumpWidget(OipApp(controller: controller, autoStart: false));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav-4')));
    await tester.pumpAndSettle();
    expect(find.byType(DataTimeline), findsOneWidget);
    final clip = find.byWidgetPredicate((widget) =>
        widget.key is ValueKey<String> &&
        (widget.key as ValueKey<String>).value.startsWith('timeline-'));
    expect(clip, findsWidgets);
    await tester.tap(clip.first);
    await tester.pumpAndSettle();
    expect(
        find.text('COLLECTION EVENT · KEINE KAUSALBEHAUPTUNG'), findsOneWidget);
    expect(find.text('Verbindung verloren'), findsWidgets);
    await tester.tap(find.text('Spuren ausblenden'));
    await tester.pumpAndSettle();
    expect(find.byType(DataTimeline), findsNothing);
    expect(find.text('Verbindung verloren'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('Reduced motion disables inspector transition', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: OipTokens.theme(Brightness.dark),
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: InteractiveInspector(
          accent: OipTokens.violet,
          onTap: () {},
          child: const Text('Inspector'),
        ),
      ),
    ));
    final animated = tester.widget<AnimatedContainer>(
      find.descendant(
          of: find.byType(InteractiveInspector),
          matching: find.byType(AnimatedContainer)),
    );
    expect(animated.duration, Duration.zero);
  });

  testWidgets('Daylight category accents meet text contrast on white',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(
      theme: OipTokens.theme(Brightness.light),
      home: Builder(builder: (value) {
        context = value;
        return const SizedBox();
      }),
    ));
    for (final color in const [
      OipTokens.violet,
      OipTokens.pink,
      OipTokens.cyan,
      OipTokens.blue,
      OipTokens.yellow,
      OipTokens.lime,
    ]) {
      final readable = OipTokens.readableAccent(context, color);
      final contrast = (Colors.white.computeLuminance() + .05) /
          (readable.computeLuminance() + .05);
      expect(contrast, greaterThanOrEqualTo(4.5), reason: color.toString());
    }
  });

  test('Spectrum accent contrast on the application background', () {
    const accents = [
      OipTokens.violet,
      OipTokens.pink,
      OipTokens.cyan,
      OipTokens.blue,
      OipTokens.yellow,
      OipTokens.lime,
      OipTokens.mainText,
      OipTokens.secondaryText,
    ];
    for (final color in accents) {
      final contrast = (color.computeLuminance() + .05) /
          (OipTokens.appBackground.computeLuminance() + .05);
      expect(contrast, greaterThanOrEqualTo(4.5), reason: color.toString());
    }
  });
}
