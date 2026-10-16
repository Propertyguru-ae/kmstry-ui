import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/reports/presentation/child_safety_report.dart';
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

Future<void> _open(
  WidgetTester tester,
  _ReportApi api,
  String field, {
  void Function(bool)? onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final result = await showReportUserSheet(
                context,
                repository: CheckinRepository(apiClient: api),
                targetUserId: field == 'target_user_id' ? 'target' : null,
                messageId: field == 'message_id' ? 'target' : null,
                storyId: field == 'story_id' ? 'target' : null,
                checkinMediaId: field == 'checkin_media_id' ? 'target' : null,
                venueId: field == 'venue_id' ? 'target' : null,
                venueStoryId: field == 'venue_story_id' ? 'target' : null,
                venueGalleryItemId: field == 'venue_gallery_item_id'
                    ? 'target'
                    : null,
                venuePhotoId: field == 'venue_photo_id' ? 'target' : null,
                venuePhotoUrl: field == 'venue_photo_id'
                    ? 'https://media.invalid/fixture.jpg'
                    : null,
                googlePhotoToken: field == 'google_photo_token'
                    ? 'target'
                    : null,
                eventId: field == 'event_id' ? 'target' : null,
                venueOfferId: field == 'venue_offer_id' ? 'target' : null,
                venueBenefitId: field == 'venue_benefit_id' ? 'target' : null,
                venueMenuItemId: field == 'venue_menu_item_id'
                    ? 'target'
                    : null,
              );
              onResult?.call(result);
            },
            child: const Text('Open report'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open report'));
  await tester.pumpAndSettle();
  expect(
    tester
        .widget<ReportSubmitButton>(find.byType(ReportSubmitButton))
        .onPressed,
    isNull,
  );
  await tester.scrollUntilVisible(
    find.text(childSafetyReportLabel),
    100,
    scrollable: find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.tap(find.text(childSafetyReportLabel));
  await tester.pumpAndSettle();
  expect(find.text(childSafetyReportHelp), findsOneWidget);
}

void main() {
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'access_token': 'test-token',
    }),
  );

  for (final field in [
    'target_user_id',
    'message_id',
    'story_id',
    'checkin_media_id',
    'venue_id',
    'venue_story_id',
    'venue_gallery_item_id',
    'venue_photo_id',
    'google_photo_token',
    'event_id',
    'venue_offer_id',
    'venue_benefit_id',
    'venue_menu_item_id',
  ]) {
    testWidgets(
      '$field submits a child-safety concern with the exact content reference',
      (tester) async {
        final api = _ReportApi();
        bool? result;
        await _open(tester, api, field, onResult: (value) => result = value);
        await tester.tap(find.byType(ReportSubmitButton));
        await tester.pumpAndSettle();
        expect(
          api.reportBody?[field == 'target_user_id'
              ? 'reported_user_id'
              : field],
          'target',
        );
        expect(api.reportBody?['reason'], childSafetyReportReason);
        expect(api.reportBody?['details'], childSafetyReportLabel);
        expect(find.text('Thanks for your report'), findsOneWidget);
        // Content reports do not block their author; profile reports retain the existing block.
        expect(
          api.requests,
          field == 'target_user_id'
              ? ['/reports/users', '/blocks']
              : ['/reports/users'],
        );
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(result, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('cancel sends no report and child help fits a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _ReportApi();
    bool? result;
    await _open(
      tester,
      api,
      'venue_gallery_item_id',
      onResult: (value) => result = value,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(api.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'duplicate child-safety concern is informational, not a new success',
    (tester) async {
      final api = _ReportApi(
        ApiException(
          statusCode: 400,
          data: {'errorCode': 'ALREADY_REPORTED_RECENTLY'},
        ),
      );
      bool? result;
      await _open(
        tester,
        api,
        'venue_story_id',
        onResult: (value) => result = value,
      );
      await tester.tap(find.byType(ReportSubmitButton));
      await tester.pumpAndSettle();
      expect(find.text('Already reported'), findsOneWidget);
      expect(find.text('Thanks for your report'), findsNothing);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
      expect(api.requests, ['/reports/users']);
      expect(tester.takeException(), isNull);
    },
  );
}
