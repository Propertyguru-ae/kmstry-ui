import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/performance/performance_diagnostics.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final records = <Map<String, Object?>>[];
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'secret'});
    records.clear();
    PerformanceDiagnostics.enabledOverride = true;
    PerformanceDiagnostics.sinkOverride = records.add;
    PerformanceDiagnostics.setUploadCounts(transfers: 0, videos: 0, pending: 0);
  });
  tearDown(() {
    PerformanceDiagnostics.enabledOverride = null;
    PerformanceDiagnostics.sinkOverride = null;
  });

  test('disabled diagnostics do not log or alter results', () async {
    PerformanceDiagnostics.enabledOverride = false;
    expect(
      await PerformanceDiagnostics.request('GET', '/private', () async => 42),
      42,
    );
    expect(records, isEmpty);
  });

  test('routes exclude identities, signed queries and external hosts', () {
    expect(
      performanceRoute('/venues/secret-venue/events?email=secret'),
      '/venues/:id/events',
    );
    expect(
      performanceRoute('https://private-host/path/secret?token=secret'),
      '/:id/:id',
    );
    expect(performanceRoute('/users/person@example.com'), '/users/:id');
  });

  test(
    'GET measures headers and correlates without logging response/header content',
    () async {
      const id = '8a826730-f898-4d27-b347-93473e64d90b';
      final api = ApiClient(
        client: MockClient(
          (_) async => http.Response(
            '{"private":"secret"}',
            200,
            headers: {'x-kmstry-perf-id': id},
          ),
        ),
        appCheckHeaderProvider: ({bool forceRefresh = false}) async => {
          'X-Firebase-AppCheck': 'secret',
        },
      );
      expect(
        await api.get(
          '/venues/secret/owner-stats?token=secret',
          headers: {'Authorization': 'Bearer secret'},
        ),
        {'private': 'secret'},
      );
      expect(records.single, containsPair('route', '/venues/:id/owner-stats'));
      expect(records.single, containsPair('status', 200));
      expect(records.single, containsPair('backendRequestId', id));
      expect(records.single['headersMs'], isA<int>());
      expect(records.single['responseBytes'], greaterThan(0));
      expect(jsonEncode(records), isNot(contains('secret')));
    },
  );

  test('parallel request spans do not overwrite each other', () async {
    final gate = Completer<void>();
    final a = PerformanceDiagnostics.request(
      'GET',
      '/venues/a/events',
      () async {
        PerformanceDiagnostics.headersReady();
        await gate.future;
        PerformanceDiagnostics.response(status: 200, bytes: 10);
        return 'a';
      },
    );
    final b = PerformanceDiagnostics.request('GET', '/notifications', () async {
      PerformanceDiagnostics.headersReady();
      PerformanceDiagnostics.response(status: 204, bytes: 0);
      return 'b';
    });
    expect(await b, 'b');
    gate.complete();
    expect(await a, 'a');
    expect(records[0]['status'], 204);
    expect(records[1]['status'], 200);
    expect(records[1]['responseBytes'], 10);
  });

  test(
    'App Check retry remains single-shot with diagnostics enabled',
    () async {
      var requests = 0;
      var forced = 0;
      final api = ApiClient(
        client: MockClient((_) async {
          requests++;
          return requests == 1
              ? http.Response('{"errorCode":"APP_CHECK_REQUIRED"}', 401)
              : http.Response('{"ok":true}', 200);
        }),
        appCheckHeaderProvider: ({bool forceRefresh = false}) async {
          if (forceRefresh) forced++;
          return {'X-Firebase-AppCheck': forceRefresh ? 'fresh' : 'old'};
        },
      );
      expect(await api.get('/notifications'), {'ok': true});
      expect(requests, 2);
      expect(forced, 1);
      expect(records.single['responses'], 2);
      expect(records.single['status'], 200);
    },
  );

  test(
    'transfer measurements preserve failure and never include file data',
    () async {
      await expectLater(
        PerformanceDiagnostics.mediaTransfer(
          kind: 'personalStory',
          video: true,
          operation: () async => throw StateError('private-file-path'),
        ),
        throwsStateError,
      );
      expect(records.single['event'], 'media_transfer_completed');
      expect(records.single['errorType'], 'StateError');
      expect(jsonEncode(records), isNot(contains('private-file-path')));
    },
  );

  test(
    'errors rethrow without logging message; sink failures cannot break requests',
    () async {
      await expectLater(
        PerformanceDiagnostics.request(
          'GET',
          '/notifications',
          () async => throw StateError('secret'),
        ),
        throwsStateError,
      );
      expect(records.single['errorType'], 'StateError');
      expect(jsonEncode(records), isNot(contains('secret')));
      PerformanceDiagnostics.sinkOverride = (_) =>
          throw StateError('observer failed');
      expect(
        await PerformanceDiagnostics.request(
          'GET',
          '/notifications',
          () async => 'ok',
        ),
        'ok',
      );
    },
  );

  testWidgets(
    'page probe keeps content unchanged and separates UI/data events',
    (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: PerformancePageProbe(
            page: PerformancePage.venueHome,
            child: Text('Home'),
          ),
        ),
      );
      expect(find.text('Home'), findsOneWidget);
      expect(records.single['event'], 'page_first_frame');
      records.clear();
      await PerformanceDiagnostics.pageLoad(
        PerformancePage.venueHome,
        () async {},
        isMounted: () => true,
      );
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: PerformancePageProbe(
            page: PerformancePage.venueHome,
            child: Text('Loaded'),
          ),
        ),
      );
      expect(
        records.map((row) => row['event']),
        containsAllInOrder([
          'page_load_started',
          'page_load_completed',
          'page_post_load_frame',
        ]),
      );
    },
  );

  test('workload counts contain counts only', () async {
    PerformanceDiagnostics.setUploadCounts(transfers: 2, videos: 1, pending: 3);
    await PerformanceDiagnostics.request('GET', '/notifications', () async {});
    expect(records.single, containsPair('uploadTransfers', 2));
    expect(records.single, containsPair('videoTransfers', 1));
    expect(records.single, containsPair('moderationPending', 3));
  });
}
