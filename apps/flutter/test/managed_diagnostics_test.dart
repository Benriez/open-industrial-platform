import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oip_dashboard/app/app.dart';
import 'package:oip_dashboard/app/controller.dart';
import 'package:oip_dashboard/models/contracts.dart';
import 'package:oip_dashboard/models/diagnostics.dart';
import 'package:oip_dashboard/services/api.dart';

import 'infrastructure_support.dart';
import 'support.dart';

/// The persisted evidence of the managed diagnostics view.
///
/// The rule is the contract of OIP-0082: the state of the persisted diagnosis
/// history is the answer of the Core, the documented gaps and the health
/// transitions are shown with their markers and their reasons, the limits of
/// the answer are shown, a truncated page without a cursor is explicitly
/// incomplete and a gap is never read as a proven cause.
///
/// The test is reconciled to the Spectrum-2027 workspace: it navigates through
/// the approved shell and proves the rendered evidence, never the older
/// five-view shell.
Json eventsResponse() => {
      'incidents': <dynamic>[],
      'collection_events': <dynamic>[],
      'records': [
        {
          'id': 'event-1',
          'sequence': 7,
          'context': {
            'data_source_id': 'source-ssh',
            'origin_class': 'external'
          },
          'event': {
            'ConnectionLost': {
              'at': 1700000000000,
              'reason': 'Verbindung verloren'
            }
          }
        }
      ],
      'diagnosis_history_status': 'not_implemented',
      'replay_supported': false,
      'resync_required': true,
    };

/// The documented gaps the Core stored for the authorized sources.
Json gapsResponse() => {
      'items': [
        {
          'category': 'gap',
          'record': {
            'id': 'gap-1',
            'source': 'source-ssh',
            'origin': 'external',
            'documented_start_ms': 1700000000000,
            'documented_end_ms': 1700000030000,
            'reason': 'Verbindung verloren',
          }
        }
      ],
      'truncated': false,
      'next_cursor': null,
      'missing_evidence': [
        'Keine dokumentierte Lücke heißt nicht lückenlose Überwachung'
      ],
      'time_semantics': 'Gap: documented start marker.',
    };

/// The health transitions the Core stored for the authorized sources.
Json healthResponse() => {
      'items': [
        {
          'category': 'health',
          'record': {
            'id': 'health-1',
            'source': 'source-ssh',
            'provenance': 'gemeldet',
            'at_ms': 1700000030000,
            'previous': null,
            'current': {
              'reachability': 'reachable',
              'connection': 'connected',
              'service': 'unknown',
              'freshness': 'fresh',
              'validity': 'observed',
            },
          }
        }
      ],
      'truncated': false,
      'next_cursor': null,
      'missing_evidence': [],
      'time_semantics': 'Health: runtime wall-clock observation.',
    };

/// The managed API of the test: the evidence of the Core is served, the
/// cursor of a continuation is honoured and every requested route is recorded.
class EvidenceApi extends FakeApi {
  final List<Uri> requests = [];
  bool failContinuation = true;

  /// The route of the authorized query with its limit and its opaque cursor.
  static Uri _route(String path, int limit, String? cursor) => Uri.parse(
      'http://127.0.0.1:8080$path?limit=$limit'
      '${cursor == null ? '' : '&cursor=$cursor'}');

  @override
  Future<CollectionEvents> collectionEventsWithStatus() async {
    requests.add(Uri.parse('http://127.0.0.1:8080/api/v2/events'));
    return CollectionEvents(const [], 'not_implemented');
  }

  @override
  Future<DiagnosticPage> diagnosticGaps({int limit = 50, String? cursor}) async {
    requests.add(_route('/api/v2/diagnostics/gaps', limit, cursor));
    if (cursor != null && failContinuation) {
      failContinuation = false;
      throw const ApiFailure('Cursor abgelaufen',
          code: 'INVALID_DIAGNOSTIC_QUERY', statusCode: 400);
    }
    final value = gapsResponse();
    if (cursor == null) {
      value['truncated'] = true;
      value['next_cursor'] = 'opaque-gap';
    }
    return DiagnosticPage.fromJson(value);
  }

  @override
  Future<DiagnosticPage> healthHistory({int limit = 50, String? cursor}) async {
    requests.add(_route('/api/v2/diagnostics/health-history', limit, cursor));
    final value = healthResponse();
    value['truncated'] = true;
    // A truncated page without a cursor must say so, never imply completion.
    return DiagnosticPage.fromJson(value);
  }
}

void main() {
  test(
      'Diagnostics preserve unknown marker duration and stable page identities',
      () {
    final first = DiagnosticPage.fromJson(gapsResponse());
    final next = gapsResponse();
    next['truncated'] = true;
    next['next_cursor'] = 'opaque-core-cursor';
    final merged = first.followedBy(DiagnosticPage.fromJson(next));
    expect(merged.gaps, hasLength(1));
    expect(merged.nextCursor, 'opaque-core-cursor');
    expect(merged.truncated, isTrue);
    final zero = Map<String, dynamic>.from(
        (gapsResponse()['items'] as List).single['record']);
    zero['documented_end_ms'] = zero['documented_start_ms'];
    expect(DiagnosticGap.fromJson(zero).durationMs, isNull);
    zero['documented_end_ms'] = 1;
    expect(DiagnosticGap.fromJson(zero).durationMs, isNull);
  });

  test('Diagnostic continuations merge by the stable Core IDs', () {
    final first = DiagnosticPage.fromJson(gapsResponse());
    final second = gapsResponse();
    second['items'] = [
      ...(gapsResponse()['items'] as List),
      {
        'category': 'gap',
        'record': {
          'id': 'gap-2',
          'source': 'source-ssh',
          'origin': 'external',
          'documented_start_ms': 1700000040000,
          'documented_end_ms': 1700000050000,
          'reason': 'Verbindung verloren',
        }
      }
    ];
    final merged = first.followedBy(DiagnosticPage.fromJson(second));
    // The stable ID of the Core decides; the same row is never duplicated.
    expect(merged.gaps.map((gap) => gap.id), ['gap-1', 'gap-2']);
    final repeated = first.followedBy(DiagnosticPage.fromJson(gapsResponse()));
    expect(repeated.gaps, hasLength(1));
  });

  testWidgets(
      'The managed diagnostics view shows the persisted evidence of the session',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1600);
    await tester.binding.setSurfaceSize(const Size(1440, 1600));
    final api = EvidenceApi()..infrastructure = infrastructureFixture();
    final controller = OipController(api, retryDelay: const Duration(milliseconds: 1));
    await controller.resyncInfrastructure();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await tester.binding.setSurfaceSize(null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(OipApp(controller: controller, autoStart: false));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.tap(find.text('Diagnose & Ereignisse').first);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    // The persisted evidence of the Core is shown with its markers and reason.
    expect(find.textContaining('PERSISTIERTE EVIDENZ'), findsOneWidget);
    expect(find.text('Dokumentierte Lücke · source-ssh'), findsOneWidget);
    expect(find.textContaining('Verbindung verloren'), findsWidgets);
    // A marker distance is never read as a measured outage.
    expect(find.textContaining('keine gemessene Ausfalldauer'), findsWidgets);
    // The health transition of the Core is shown with its previous and current
    // state. The first transition has no previous state, and it stays unknown.
    expect(find.text('Gesundheitsverlauf · source-ssh'), findsOneWidget);
    expect(find.textContaining('Unbekannt →'), findsOneWidget);
    // The limits of the answer are shown, not hidden.
    expect(find.textContaining('Grenzen dieser Evidenz'), findsOneWidget);
    // The state of the persisted diagnosis history is the answer of the Core.
    expect(find.textContaining('Diagnosehistorie: nicht implementiert'),
        findsOneWidget);
    expect(find.textContaining('demo_only'), findsNothing);
    // A truncated answer without a cursor is explicitly incomplete.
    expect(
        find.text(
            'Gesundheitsverlauf: Antwort gekürzt; keine Fortsetzung verfügbar.'),
        findsOneWidget);
    // The time and origin semantics of the Core are disclosed.
    final semantics = find.text('Zeit- und Herkunftssemantik');
    await tester.ensureVisible(semantics);
    await tester.tap(semantics);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Gap: documented start marker.'), findsOneWidget);
    expect(
        find.text('Health: runtime wall-clock observation.'), findsOneWidget);
  });

  testWidgets(
      'Truncated diagnostic pages continue without duplicating evidence',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1600);
    await tester.binding.setSurfaceSize(const Size(1440, 1600));
    final api = EvidenceApi()..infrastructure = infrastructureFixture();
    final controller = OipController(api, retryDelay: const Duration(milliseconds: 1));
    await controller.resyncInfrastructure();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await tester.binding.setSurfaceSize(null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(OipApp(controller: controller, autoStart: false));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.tap(find.text('Diagnose & Ereignisse').first);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    // The continuation asks the same authorized route with the opaque cursor.
    final more = find.text('Lücken: weitere Einträge laden');
    await tester.ensureVisible(more);
    await tester.tap(more);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    // The failed continuation is named and the loaded evidence stays visible.
    expect(find.textContaining('INVALID_DIAGNOSTIC_QUERY'), findsOneWidget);
    expect(find.text('Dokumentierte Lücke · source-ssh'), findsOneWidget);
    // A fresh authorized query recovers the expired cursor.
    final retry = find.text('Erneut laden');
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.ensureVisible(more);
    await tester.tap(more);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(
        api.requests
            .where((uri) => uri.queryParameters['cursor'] == 'opaque-gap'),
        hasLength(2));
    expect(find.text('Dokumentierte Lücke · source-ssh'), findsOneWidget);
  });
}
