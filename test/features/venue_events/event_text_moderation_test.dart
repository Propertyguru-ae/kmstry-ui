import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/network/public_content_permission.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_repository.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/add_venue_event_page.dart';
import 'add_event_background_upload_test.dart' show PartnershipsFake;

class _RejectedTextApi extends ApiClient {
  _RejectedTextApi(this.error);
  final ApiException error;
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    bodies.add(body!);
    throw error;
  }

  @override
  Future<dynamic> patch(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    bodies.add(body!);
    throw error;
  }
}

ApiException _rejection() => ApiException(
  statusCode: 400,
  data: const {
    'errorCode': 'PUBLIC_TEXT_NOT_ALLOWED',
    'textPolicyCategories': ['CONTENT_INSULTS'],
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({'access_token': 'test'}),
  );
  tearDown(() => PublicContentPermission.onRequired = null);

  for (final recurring in [false, true]) {
    test(
      'creating ${recurring ? 'a series' : 'an event'} preserves typed text rejection',
      () async {
        final error = _rejection();
        final api = _RejectedTextApi(error);
        final repo = VenueEventRepository(apiClient: api);
        await expectLater(
          repo.createEvent(
            venueId: 'venue',
            title: 'Live music',
            description: 'fuck',
            startAt: DateTime(2026, 11, 9, 18),
            endAt: DateTime(2026, 11, 9, 20),
            recurrence: recurring
                ? {'frequency': 'weekly', 'maxOccurrences': 3}
                : null,
          ),
          throwsA(same(error)),
        );
        expect(api.bodies.single['description'], 'fuck');
      },
    );
  }

  for (final scope in ['this', 'thisAndFollowing', 'all']) {
    testWidgets(
      'event description rejection in scope $scope keeps the editor and draft',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = _RejectedTextApi(_rejection());
        var allowed = false;
        PublicContentPermission.onRequired = (_) async {
          if (!allowed) throw ApiException(statusCode: 403,
            data: const {'errorCode': 'AWS_SHARING_PERMISSION_DECLINED'});
        };
        var committed = false;
        await tester.pumpWidget(
          MaterialApp(
            home: AddVenueEventPage(
              venueId: 'venue',
              editScope: scope,
              existing: VenueUpcomingEvent(
                id: 'event',
                title: 'Live music',
                description: 'Original description',
                startAt: DateTime(2026, 11, 9, 18),
                endAt: DateTime(2026, 11, 9, 20),
                recurringRuleId: 'rule',
                recurrence: RecurrenceInfo(
                  frequency: 'weekly',
                  interval: 1,
                  maxOccurrences: 3,
                ),
              ),
              repository: VenueEventRepository(apiClient: api),
              partnershipRepository: PartnershipsFake(),
              onUpdated: (_) => committed = true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final description = find.byWidgetPredicate(
          (widget) =>
              widget is TextFormField &&
              widget.controller?.text == 'Original description',
        );
        await tester.ensureVisible(description);
        await tester.enterText(description, 'fuck');
        await tester.tap(find.text('Save Changes'));
        await tester.pumpAndSettle();
        expect(api.bodies, isEmpty);
        expect(find.text('Review permission'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        allowed = true;
        await tester.tap(find.text('Review permission'));
        await tester.pumpAndSettle();
        expect(api.bodies.single['description'], 'fuck');
        expect(api.bodies.single['editScope'], scope);
        expect(find.text('Please edit your text'), findsOneWidget);
        expect(find.text(publicTextRejectionMessage), findsOneWidget);
        expect(find.text('Something went wrong'), findsNothing);
        expect(committed, isFalse);
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(find.byType(AddVenueEventPage), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is TextFormField && widget.controller?.text == 'fuck',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
