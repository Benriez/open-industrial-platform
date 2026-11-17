import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/core/sse.dart';
import 'package:oip_dashboard/features/operator_login.dart';
import 'package:oip_dashboard/models/infrastructure.dart';
import 'package:oip_dashboard/models/onboarding.dart';
import 'package:oip_dashboard/services/api.dart';

import 'infrastructure_support.dart';
import 'support.dart';

const _touchIdChannel = MethodChannel('org.openindustrial.oip/touch_id');

class _PairingFailureApi extends RestApi {
  final StreamController<ServerEvent> events = StreamController.broadcast();
  int bootstrapCalls = 0;
  bool pairAttempted = false;

  _PairingFailureApi() : super(Uri.parse('http://127.0.0.1:18848'));

  @override
  Future<BrowserSession> login(String code) async => BrowserSession.fromJson({
        'principal_id': 'operator-a',
        'authenticated': true,
        'mode': 'local_operator_session',
        'csrf_token': 'csrf-a',
      });

  @override
  Future<BrowserSession> session() async => BrowserSession.fromJson({
        'principal_id': 'operator-a',
        'authenticated': true,
        'mode': 'local_operator_session',
        'csrf_token': 'csrf-a',
      });

  @override
  Future<void> pairDeviceCredential(String credential) async {
    pairAttempted = true;
    throw const ApiFailure('Core-Endpunkt nicht verfügbar.',
        code: 'NOT_FOUND', statusCode: 404);
  }

  @override
  Future<InfrastructureBootstrap> infrastructureBootstrap() async {
    bootstrapCalls++;
    return infrastructureFixture();
  }

  @override
  Stream<ServerEvent> infrastructureStream() => events.stream;

  @override
  void close() {
    events.close();
    super.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_touchIdChannel, null);
  });

  testWidgets('Touch ID login is hidden until this Mac has a paired key',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_touchIdChannel, (call) async {
      return switch (call.method) {
        'available' => true,
        'credentialExists' => false,
        _ => null,
      };
    });
    final controller = OipController(FakeApi());
    await tester.pumpWidget(MaterialApp(home: OperatorLogin(controller)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('enable-touch-id')), findsOneWidget);
    expect(find.byKey(const Key('operator-login-touch-id')), findsNothing);
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const Key('enable-touch-id')))
          .value,
      isTrue,
      reason:
          'a supported Mac should select Touch ID enrollment for first login',
    );
    controller.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Touch ID login is shown when the Mac keychain has a paired key',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_touchIdChannel, (call) async {
      return switch (call.method) {
        'available' => true,
        'credentialExists' => true,
        _ => null,
      };
    });
    final controller = OipController(FakeApi());
    await tester.pumpWidget(MaterialApp(home: OperatorLogin(controller)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('enable-touch-id')), findsOneWidget);
    expect(find.byKey(const Key('operator-login-touch-id')), findsOneWidget);
    expect(
      tester
          .widget<CheckboxListTile>(find.byKey(const Key('enable-touch-id')))
          .value,
      isFalse,
      reason:
          'an already paired credential should not trigger another enrollment',
    );
    controller.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Touch ID login shows the native biometric failure reason',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_touchIdChannel, (call) async {
      return switch (call.method) {
        'available' => true,
        'credentialExists' => true,
        'readCredential' => throw PlatformException(
            code: 'TOUCH_ID_CANCELLED', message: 'Touch ID wurde abgebrochen.'),
        _ => null,
      };
    });
    final controller = OipController(RestApi(Uri.parse('http://127.0.0.1')));
    await tester.pumpWidget(MaterialApp(home: OperatorLogin(controller)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('operator-login-touch-id')));
    await tester.pumpAndSettle();

    expect(find.text('Touch ID wurde abgebrochen.'), findsOneWidget);
    controller.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
      'a failed Touch ID pairing keeps the code login and bootstraps once',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_touchIdChannel, (call) async {
      return switch (call.method) {
        'createCredential' => 'a' * 64,
        'deleteCredential' => null,
        _ => null,
      };
    });
    final api = _PairingFailureApi();
    final controller = OipController(api,
        retryDelay: const Duration(seconds: 30),
        streamTimeout: const Duration(seconds: 30));

    await controller.login('one-use-code', enableTouchId: true);
    await tester.pump();

    expect(api.pairAttempted, isTrue);
    expect(api.bootstrapCalls, 1,
        reason:
            'post-login bootstrap must not be repeated before stream start');
    expect(controller.loginRequired, isFalse,
        reason: 'a failed optional pairing must not strand the consumed code');
    expect(controller.error, contains('Angemeldet, aber Touch ID'));
    controller.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
