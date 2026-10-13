import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/reports/presentation/report_ui.dart';
import 'package:kmstry_frontend/features/reports/presentation/report_user_sheet.dart';

class _ReportApi extends ApiClient {
  _ReportApi([this.failure]);
  final Object? failure;
  final requests = <String>[];
  Map<String, dynamic>? reportBody;

  @override
  Future<dynamic> post(
    String path, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
  }) async {
    requests.add(path);
    if (path == '/reports/users') {
      reportBody = body;
      if (failure != null) throw failure!;
    }
    return {'success': true};
  }
}

ApiException _failure(String code) => ApiException(
  statusCode: 400,
  data: {'errorCode': code, 'message': 'Backend diagnostic message'},
);

Future<void> _openAndReport(
  WidgetTester tester,
  _ReportApi api, {
  String target = 'google-photo',
  required void Function(bool) onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              onResult(
                await showReportUserSheet(
                  context,
                  repository: CheckinRepository(apiClient: api),
                  googlePhotoToken: target == 'google-photo'
                      ? 'payload.signature'
                      : null,
                  venuePhotoId: target == 'venue-photo' ? 'venue-1' : null,
                  venuePhotoUrl: target == 'venue-photo'
                      ? 'https://media.test/photo.jpg'
                      : null,
                  storyId: target == 'story' ? 'story-1' : null,
                  venueBenefitId: target == 'benefit' ? 'benefit-1' : null,
                  targetUserId: target == 'account' ? 'other-user' : null,
                ),
              );
            },
            child: const Text('Open report'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open report'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('Spam'),
    200,
    scrollable: find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.tap(find.text('Spam'));
  await tester.pump();
  await tester.tap(find.byType(ReportSubmitButton));
  await tester.pumpAndSettle();
}

void main() {
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'access_token': 'test-token',
    }),
  );

  for (final target in ['google-photo', 'venue-photo', 'story', 'account']) {
    testWidgets(
      '$target duplicate is informational, without a false success or automatic block',
      (tester) async {
        final api = _ReportApi(_failure('ALREADY_REPORTED_RECENTLY'));
        bool? result;
        await _openAndReport(
          tester,
          api,
          target: target,
          onResult: (value) => result = value,
        );
        expect(find.text('Already reported'), findsOneWidget);
        expect(find.text('Thanks for your report'), findsNothing);
        expect(
          find.text('Could not submit report. Please try again.'),
          findsNothing,
        );
        final label = target.endsWith('photo')
            ? 'this photo'
            : target == 'account'
            ? 'this account'
            : 'this content';
        expect(
          find.text(
            "You've already sent a similar report for $label in the last 24 hours. No new report was sent.",
          ),
          findsOneWidget,
        );
        expect(api.requests, ['/reports/users']);
        expect(api.reportBody?['reason'], 'SPAM_SCAM');
        expect(api.reportBody?['details'], 'Spam');
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(result, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'a new photo report keeps the standard thank-you dialog and success result',
    (tester) async {
      final api = _ReportApi();
      bool? result;
      await _openAndReport(tester, api, onResult: (value) => result = value);
      expect(find.text('Thanks for your report'), findsOneWidget);
      expect(find.text('Already reported'), findsNothing);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(api.requests, ['/reports/users']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a stale photo retains its refresh instruction, not duplicate feedback',
    (tester) async {
      bool? result;
      await _openAndReport(
        tester,
        _ReportApi(_failure('REPORTED_PHOTO_CHANGED')),
        onResult: (value) => result = value,
      );
      expect(
        find.text('This photo has changed. Refresh the venue and try again.'),
        findsOneWidget,
      );
      expect(find.text('Already reported'), findsNothing);
      expect(result, isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (target, message) in [
    ('benefit', 'You manage this venue, so you cannot report its content.'),
    ('story', 'You cannot report your own content.'),
  ]) {
    testWidgets('$target reported by its own author explains why', (
      tester,
    ) async {
      bool? result;
      final api = _ReportApi(_failure('CANNOT_REPORT_SELF'));
      await _openAndReport(
        tester,
        api,
        target: target,
        onResult: (value) => result = value,
      );
      if (target == 'benefit') {
        expect(api.reportBody?['venue_benefit_id'], 'benefit-1');
      }
      expect(find.text(message), findsOneWidget);
      expect(
        find.text('Could not submit report. Please try again.'),
        findsNothing,
      );
      expect(find.text('Thanks for your report'), findsNothing);
      expect(result, isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'real server failures remain retryable and are not presented as already reported',
    (tester) async {
      bool? result;
      final api = _ReportApi(
        ApiException(statusCode: 500, data: {'message': 'Failed'}),
      );
      await _openAndReport(tester, api, onResult: (value) => result = value);
      expect(
        find.text('Could not submit report. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Already reported'), findsNothing);
      expect(find.text('Thanks for your report'), findsNothing);
      expect(result, isNull);
      await tester.tap(find.byType(ReportSubmitButton));
      await tester.pumpAndSettle();
      expect(api.requests, ['/reports/users', '/reports/users']);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
