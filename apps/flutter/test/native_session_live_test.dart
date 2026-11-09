import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/services/api.dart';

/// The session of the native client against a running Core.
///
/// This test runs on the VM of the Flutter test: the same Dart semantics as
/// the macOS bundle, without the cookie jar of a browser. The Core is the
/// release binary of the repository; the test is skipped when no instance is
/// named in the environment.
void main() {
  final url = Platform.environment['OIP_LIVE_CORE_URL'];
  final code = Platform.environment['OIP_LIVE_SESSION_CODE'];
  final principal = Platform.environment['OIP_LIVE_PRINCIPAL'] ?? 'reader-org-a';

  test('The native client holds a session of the real Core', () async {
    if (url == null || url.isEmpty || code == null || code.isEmpty) {
      markTestSkipped('no running Core named in the environment');
      return;
    }
    final api = RestApi(Uri.parse(url));

    // The operator authorizes the session with the one-time code.
    final session = await api.login(code);
    expect(session.authenticated, isTrue);
    expect(session.principalId, principal);

    // The reads after the login carry the session of the Core.
    final organizations = await api.hierarchy('organizations', {});
    expect(organizations, isNotEmpty);
    expect(organizations.map((item) => item.id), contains('org-a'));

    final bootstrap = await api.infrastructureBootstrap();
    // The Core has no whoami route: the identity of the session is the
    // evidence. The bootstrap of the live mode carries no principal.
    expect(bootstrap.principalIdentity, isNull);
    expect(bootstrap.snapshot.sources, isNotEmpty);
    expect(bootstrap.snapshot.sources.map((item) => item.id),
        isNot(contains('source-d')));

    // The session ends with the sign-out of the Core.
    await api.logout();
  }, timeout: const Timeout(Duration(seconds: 120)));
}
