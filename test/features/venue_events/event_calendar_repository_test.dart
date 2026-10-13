import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/performance/performance_diagnostics.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_repository.dart';

class _Api extends ApiClient {
  final calls = <({String path, Map<String, String>? headers})>[];
  dynamic response = <dynamic>[];
  @override
  Future<dynamic> get(
    String path, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    calls.add((path: path, headers: headers));
    return response;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'access_token': 'test-owner',
    }),
  );
  Map<String, dynamic> event(int i) => {
    'id': 'event-$i',
    'title': 'Full event $i',
    'description': 'Complete description',
    'startAt': '2026-10-06T09:00:00Z',
    'endAt': '2026-10-06T10:00:00Z',
    'photo': 'signed-cover',
    'photos': ['signed-first', 'signed-second'],
    'priceAed': 75,
    'currency': 'AED',
    'capacity': 30,
    'rsvpCount': 12,
    'recurringRuleId': 'series',
    'recurrence': {'frequency': 'weekly', 'interval': 2, 'maxOccurrences': 52},
    'partnershipCount': 1,
    'partnershipBenefits': [
      {
        'id': 'partner',
        'platform': 'OTHER',
        'platformLabel': 'Partner',
        'offerType': 'PERCENT_OFF',
        'offerLabel': 'Save 15%',
      },
    ],
    'offerId': 'offer',
    'offerTitle': 'Lunch',
    'offerType': 'PERCENT_OFF',
    'offerDiscountValue': 15,
  };

  test(
    'calendar uses authenticated lightweight endpoint and retains all dates without a cutoff',
    () async {
      final api = _Api()
        ..response = List.generate(
          250,
          (i) => {
            'id': 'event-$i',
            'startAt': '2026-10-06T09:00:00Z',
            'recurringRuleId': 'series',
          },
        );
      final rows = await VenueEventRepository(
        apiClient: api,
      ).getEventCalendar('venue-a');
      expect(rows, hasLength(250));
      expect(rows.first.startAt, DateTime.utc(2026, 10, 6, 9));
      expect(rows.first.recurringRuleId, 'series');
      expect(api.calls.single.path, '/venues/venue-a/events/calendar');
      expect(api.calls.single.headers?['Authorization'], 'Bearer test-owner');
    },
  );

  test(
    'month request sends exact local boundaries as UTC and preserves complete event fields',
    () async {
      final api = _Api()..response = [event(0)];
      final row = (await VenueEventRepository(
        apiClient: api,
      ).listEventMonth('venue-a', DateTime(2026, 10, 22))).single;
      final uri = Uri.parse(api.calls.single.path);
      expect(uri.path, '/venues/venue-a/events');
      expect(
        DateTime.parse(uri.queryParameters['from']!),
        DateTime(2026, 10).toUtc(),
      );
      expect(
        DateTime.parse(uri.queryParameters['to']!),
        DateTime(2026, 11).toUtc(),
      );
      expect(api.calls.single.headers?['Authorization'], 'Bearer test-owner');
      expect(row.title, 'Full event 0');
      expect(row.description, 'Complete description');
      expect(row.photo, 'signed-cover');
      expect(row.photos, ['signed-first', 'signed-second']);
      expect(row.priceAed, 75);
      expect(row.currency, 'AED');
      expect(row.capacity, 30);
      expect(row.rsvpCount, 12);
      expect(row.recurrence?.interval, 2);
      expect(row.recurrence?.maxOccurrences, 52);
      expect(row.partnershipBenefits.single.platformLabel, 'Partner');
      expect(row.offerId, 'offer');
      expect(row.offerDiscountValue, 15);
    },
  );

  test(
    'December month crosses year correctly; legacy full read remains unchanged and uncapped',
    () async {
      final api = _Api()..response = List.generate(200, event);
      final repo = VenueEventRepository(apiClient: api);
      expect(await repo.listEvents('venue-a'), hasLength(200));
      expect(api.calls.first.path, '/venues/venue-a/events');
      await repo.listEventMonth('venue-a', DateTime(2026, 12));
      final uri = Uri.parse(api.calls.last.path);
      expect(
        DateTime.parse(uri.queryParameters['to']!),
        DateTime(2027, 1).toUtc(),
      );
    },
  );

  test(
    'calendar/window diagnostics log route templates, never IDs or date query values',
    () {
      expect(
        performanceRoute('/venues/private-venue/events/calendar'),
        '/venues/:id/events/calendar',
      );
      expect(
        performanceRoute(
          '/venues/private-venue/events?from=private-date&to=private-date',
        ),
        '/venues/:id/events',
      );
    },
  );
}
