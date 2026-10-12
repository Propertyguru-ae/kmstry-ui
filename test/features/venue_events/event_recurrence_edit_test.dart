import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_repository.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_mutation.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/add_venue_event_page.dart';
import 'add_event_background_upload_test.dart' show PartnershipsFake;

class RecordingApi extends ApiClient {
  Map<String, dynamic>? lastBody;
  @override
  Future<dynamic> patch(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    lastBody = body;
    return {
      'id': 'selected',
      'title': 'Bicycle',
      'startAt': '2026-11-09T18:00:00Z',
      'endAt': '2026-11-09T20:00:00Z',
      'recurringRuleId':
          body?.containsKey('recurrence') == true && body?['recurrence'] == null
          ? null
          : 'rule',
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({'access_token': 'test'}),
  );

  test(
    'PATCH distinguishes omitted recurrence from explicitly stopping repeat',
    () async {
      final api = RecordingApi();
      final repo = VenueEventRepository(apiClient: api);
      await repo.updateEvent(
        venueId: 'venue',
        eventId: 'selected',
        title: 'Bicycle',
      );
      expect(api.lastBody!.containsKey('recurrence'), false);
      await repo.updateEvent(
        venueId: 'venue',
        eventId: 'selected',
        editScope: 'all',
        clearRecurrence: true,
      );
      expect(api.lastBody!.containsKey('recurrence'), true);
      expect(api.lastBody!['recurrence'], isNull);
    },
  );

  test(
    'scoped PATCH distinguishes unchanged deals from additions and clearing',
    () async {
      final api = RecordingApi();
      final repo = VenueEventRepository(apiClient: api);
      await repo.updateEvent(venueId: 'venue', eventId: 'selected');
      expect(api.lastBody!.containsKey('partnershipIds'), false);
      expect(api.lastBody!.containsKey('offer'), false);
      for (final scope in ['this', 'thisAndFollowing', 'all']) {
        await repo.updateEvent(
          venueId: 'venue',
          eventId: 'selected',
          editScope: scope,
          partnershipIds: ['deal-a'],
          offer: {'type': 'BUFFET', 'price': 75.5},
        );
        expect(api.lastBody!['editScope'], scope);
        expect(api.lastBody!['partnershipIds'], ['deal-a']);
        expect(api.lastBody!['offer'], {'type': 'BUFFET', 'price': 75.5});
      }
      await repo.updateEvent(
        venueId: 'venue',
        eventId: 'selected',
        editScope: 'all',
        partnershipIds: [],
        clearOffer: true,
      );
      expect(api.lastBody!['partnershipIds'], []);
      expect(api.lastBody!.containsKey('offer'), true);
      expect(api.lastBody!['offer'], isNull);
    },
  );

  testWidgets(
    'repeat-off requires confirmation; cancel does not write; confirmation sends explicit null',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = RecordingApi();
      VenueEventMutation? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: AddVenueEventPage(
            venueId: 'venue',
            editScope: 'all',
            existing: VenueUpcomingEvent(
              id: 'selected',
              title: 'Bicycle',
              startAt: DateTime(2026, 11, 9, 18),
              endAt: DateTime(2026, 11, 9, 20),
              recurringRuleId: 'rule',
              recurrence: RecurrenceInfo(
                frequency: 'weekly',
                interval: 1,
                maxOccurrences: 5,
              ),
            ),
            repository: VenueEventRepository(apiClient: api),
            partnershipRepository: PartnershipsFake(),
            onUpdated: (result) => saved = result,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final repeat = find.byKey(const ValueKey('event-repeat-toggle'));
      await tester.ensureVisible(repeat);
      await tester.tap(repeat);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Changes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Stop repeating this event?'), findsOneWidget);
      expect(find.textContaining('past events will be kept'), findsOneWidget);
      expect(api.lastBody, isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.lastBody, isNull);
      await tester.tap(find.text('Save Changes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('Stop repeating'));
      await tester.pumpAndSettle();
      expect(api.lastBody!['recurrence'], isNull);
      expect(api.lastBody!['editScope'], 'all');
      expect(saved!.event.recurringRuleId, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('weekly-to-monthly sends the newly selected rule when saved', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = RecordingApi();
    await tester.pumpWidget(
      MaterialApp(
        home: AddVenueEventPage(
          venueId: 'venue',
          editScope: 'all',
          existing: VenueUpcomingEvent(
            id: 'selected',
            title: 'Bicycle',
            startAt: DateTime(2026, 11, 9, 18),
            endAt: DateTime(2026, 11, 9, 20),
            recurringRuleId: 'rule',
            recurrence: RecurrenceInfo(
              frequency: 'weekly',
              interval: 1,
              maxOccurrences: 5,
            ),
          ),
          repository: VenueEventRepository(apiClient: api),
          partnershipRepository: PartnershipsFake(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Monthly'));
    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(api.lastBody!['recurrence'], {
      'frequency': 'monthly',
      'interval': 1,
      'maxOccurrences': 5,
    });
    expect(tester.takeException(), isNull);
  });
}
