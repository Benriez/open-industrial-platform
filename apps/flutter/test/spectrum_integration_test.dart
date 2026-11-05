import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/app.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'support.dart';

void main() {
  const sizes = [
    Size(320, 740),
    Size(375, 812),
    Size(390, 844),
    Size(768, 1024),
    Size(834, 1112),
    Size(1024, 900),
    Size(1440, 1000),
    Size(1920, 1080),
  ];
  for (final size in sizes) {
    for (final theme in ['Spectrum', 'Daylight', 'Graphite']) {
      testWidgets('Integrated $theme renders five views at ${size.width}',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        await tester.binding.setSurfaceSize(size);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          return tester.binding.setSurfaceSize(null);
        });
        final controller = OipController(FakeApi())
          ..snapshot = Snapshot.fromJson(fixture())
          ..connection = 'live';
        await tester
            .pumpWidget(OipApp(controller: controller, autoStart: false));
        await tester.pumpAndSettle();
        final clicks = ['Spectrum', 'Daylight', 'Graphite'].indexOf(theme);
        for (var i = 0; i < clicks; i++) {
          await tester.tap(find.byKey(const Key('theme-toggle')));
          await tester.pumpAndSettle();
        }
        for (var page = 0; page < 5; page++) {
          if (size.width < 1080) {
            await tester.tap(find.byKey(const Key('open-navigation')));
            await tester.pumpAndSettle();
          }
          await tester.tap(find.byKey(Key('nav-$page')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: '$theme at ${size.width}, view $page');
        }
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      });
    }
  }
}
