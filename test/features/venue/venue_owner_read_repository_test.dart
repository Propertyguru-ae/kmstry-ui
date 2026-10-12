import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/performance/performance_diagnostics.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_stats_model.dart';

class _ReadApi extends ApiClient {
  final calls = <({String path, Map<String, String>? headers})>[];
  final dynamic Function(String path) response;
  _ReadApi(this.response);

  @override
  Future<dynamic> get(
    String path, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    calls.add((path: path, headers: headers));
    return response(path);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'access_token': 'test-owner-token',
    }),
  );

  test(
    'weekly report links are freshly authorized for the requested venue/report',
    () async {
      final api = _ReadApi(
        (_) => {
          'url': 'https://storage.example/report.pdf?signature=test',
          'expiresInSeconds': 300,
        },
      );
      final repo = VenueOwnerRepository(apiClient: api);
      await repo.getWeeklyReportDownloadUrl('venue-a', 'report-a');
      await repo.getWeeklyReportDownloadUrl('venue-a', 'report-a');
      expect(api.calls, hasLength(2));
      expect(
        api.calls.first.path,
        '/venues/venue-a/reports/report-a/download-url',
      );
      expect(api.calls.first.headers, {
        'Authorization': 'Bearer test-owner-token',
      });
    },
  );

  for (final url in [
    null,
    '',
    'http://storage.example/report.pdf',
    'https://user:pass@storage.example/report.pdf',
    'file:///tmp/report.pdf',
  ]) {
    test('rejects unsafe or missing report download URL: $url', () async {
      final api = _ReadApi((_) => {'url': url});
      await expectLater(
        VenueOwnerRepository(
          apiClient: api,
        ).getWeeklyReportDownloadUrl('venue-a', 'report-a'),
        throwsFormatException,
      );
    });
  }

  Map<String, dynamic> event(int index) => {
    'id': 'event-$index',
    'title': 'Event $index',
    'description': 'Description',
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
  Map<String, dynamic> venue() => {
    'id': 'venue-a',
    'name': 'Test Cafe',
    'photo': 'signed-venue',
    'description': 'About',
    'type': 'CAFE',
    'address': 'Address',
    'city': 'Dubai',
    'verification_level': 'VERIFIED',
    'upcomingEvents': List.generate(150, event),
  };
  Map<String, dynamic> stats() => {
    'activeNow': 3,
    'anonymousNow': 1,
    'maleNow': 1,
    'femaleNow': 2,
    'todayTotal': 8,
    'yesterdayTotal': 10,
    'yesterdaySoFar': 4,
    'todayVsYesterdayPct': 100,
    'totalAllTime': 120,
    'followerCount': 41,
    'storyViewsToday': 23,
    'weeklyTrend': [
      {'date': '2026-10-06', 'count': 8},
    ],
  };
  List<Map<String, dynamic>> guests() => [
    {
      'id': 'guest-a',
      'username': 'guest',
      'fullName': 'Guest',
      'gender': 'female',
      'photo': 'signed-avatar',
      'featuredPhoto': 'signed-moment',
      'checkinId': 'checkin-a',
      'stories': [
        {
          'id': 'story-a',
          'mediaUrl': 'signed-video',
          'thumbnailUrl': 'signed-thumb',
          'mediaType': 'video',
          'durationSecs': 12,
          'expiresAt': '2026-10-07T09:00:00Z',
          'createdAt': '2026-10-06T09:00:00Z',
          'viewedByMe': true,
        },
      ],
    },
  ];
  Map<String, dynamic> full() => {
    'venue': venue(),
    'stats': stats(),
    'activeGuests': guests(),
  };

  test(
    'profile read keeps all venue fields and every event/detail without unrelated stats payload',
    () async {
      final api = _ReadApi((_) => venue());
      final profile = await VenueOwnerRepository(
        apiClient: api,
      ).getOwnerProfile('venue-a');
      final old = VenueOwnerStatsResponse.fromJson(full()).venue;
      expect(profile.id, old.id);
      expect(profile.name, old.name);
      expect(profile.photo, old.photo);
      expect(profile.description, old.description);
      expect(profile.type, old.type);
      expect(profile.address, old.address);
      expect(profile.city, old.city);
      expect(profile.verificationLevel, old.verificationLevel);
      expect(
        profile.upcomingEvents.map((e) => e.id),
        old.upcomingEvents.map((e) => e.id),
      );
      expect(profile.upcomingEvents, hasLength(150));
      final e = profile.upcomingEvents.first;
      expect(e.description, 'Description');
      expect(e.photo, 'signed-cover');
      expect(e.photos, ['signed-first', 'signed-second']);
      expect(e.priceAed, 75);
      expect(e.currency, 'AED');
      expect(e.capacity, 30);
      expect(e.rsvpCount, 12);
      expect(e.recurrence!.frequency, 'weekly');
      expect(e.recurringRuleId, 'series');
      expect(e.partnershipBenefits, hasLength(1));
      expect(e.offerTitle, 'Lunch');
      expect(e.offerDiscountValue, 15);
      expect(api.calls.single.path, '/venues/venue-a/owner-profile');
      expect(
        api.calls.single.headers!['Authorization'],
        'Bearer test-owner-token',
      );
    },
  );

  test(
    'identity read keeps all venue fields and does not request heavy event history',
    () async {
      final fields = venue()..remove('upcomingEvents');
      final api = _ReadApi((_) => fields);
      final result = await VenueOwnerRepository(
        apiClient: api,
      ).getOwnerProfileIdentity('venue-a');
      final expected = VenueOwnerStatsVenue.fromJson(fields);
      expect(result.id, expected.id);
      expect(result.name, expected.name);
      expect(result.photo, expected.photo);
      expect(result.description, expected.description);
      expect(result.type, expected.type);
      expect(result.address, expected.address);
      expect(result.city, expected.city);
      expect(result.verificationLevel, expected.verificationLevel);
      expect(result.upcomingEvents, isEmpty);
      expect(api.calls.single.path, '/venues/venue-a/owner-profile/identity');
      expect(
        api.calls.single.headers!['Authorization'],
        'Bearer test-owner-token',
      );
    },
  );

  test(
    'profile week sends exact UTC rolling-week overlap and preserves every event/detail without a cap',
    () async {
      final api = _ReadApi((_) => List.generate(150, event));
      final now = DateTime.parse('2026-10-06T12:45:00+04:00');
      final result = await VenueOwnerRepository(
        apiClient: api,
      ).getOwnerProfileUpcomingEvents('venue-a', now: now);
      final uri = Uri.parse(api.calls.single.path);
      expect(uri.path, '/venues/venue-a/owner-profile/upcoming-events');
      expect(DateTime.parse(uri.queryParameters['from']!), now.toUtc());
      expect(
        DateTime.parse(uri.queryParameters['to']!),
        now.add(const Duration(days: 7)).toUtc(),
      );
      expect(result, hasLength(150));
      expect(result.first.photos, ['signed-first', 'signed-second']);
      expect(result.first.description, 'Description');
      expect(result.first.offerId, 'offer');
      expect(result.first.partnershipBenefits, hasLength(1));
      expect(result.first.recurrence!.interval, 2);
    },
  );

  test(
    'split profile reads stay authenticated, fresh and identifiable without logging venue/query values',
    () async {
      final api = _ReadApi(
        (path) => path.contains('upcoming-events')
            ? []
            : (venue()..remove('upcomingEvents')),
      );
      final repo = VenueOwnerRepository(apiClient: api);
      await repo.getOwnerProfileIdentity('venue-a');
      await repo.getOwnerProfileIdentity('venue-b');
      await repo.getOwnerProfileUpcomingEvents('venue-a');
      await repo.getOwnerProfileUpcomingEvents('venue-a');
      expect(api.calls, hasLength(4));
      expect(
        performanceRoute(api.calls.first.path),
        '/venues/:id/owner-profile/identity',
      );
      expect(
        performanceRoute(api.calls.last.path),
        '/venues/:id/owner-profile/upcoming-events',
      );
      FlutterSecureStorage.setMockInitialValues({});
      await expectLater(
        repo.getOwnerProfileIdentity('venue-a'),
        throwsException,
      );
      await expectLater(
        repo.getOwnerProfileUpcomingEvents('venue-a'),
        throwsException,
      );
      expect(api.calls, hasLength(4));
    },
  );

  test(
    'guest read preserves counts, all guests, Moment and story viewing state',
    () async {
      final api = _ReadApi((_) => {'stats': stats(), 'activeGuests': guests()});
      final result = await VenueOwnerRepository(
        apiClient: api,
      ).getOwnerGuests('venue-a');
      expect(result.maleNow, 1);
      expect(result.femaleNow, 2);
      expect(result.todayTotal, 8);
      final guest = result.activeGuests.single;
      expect(guest.displayName, 'Guest');
      expect(guest.featuredPhoto, 'signed-moment');
      expect(guest.photo, 'signed-avatar');
      expect(guest.checkinId, 'checkin-a');
      expect(guest.stories.single.mediaUrl, 'signed-video');
      expect(guest.stories.single.thumbnailUrl, 'signed-thumb');
      expect(guest.stories.single.durationSecs, 12);
      expect(guest.viewedStoryIds, {'story-a'});
      expect(api.calls.single.path, '/venues/venue-a/owner-guests');
    },
  );

  test(
    'dashboard requests exactly the existing local-day window and retains all data returned',
    () async {
      final api = _ReadApi((_) => full());
      final now = DateTime(2026, 10, 6, 23, 30);
      final result = await VenueOwnerRepository(
        apiClient: api,
      ).getOwnerDashboard('venue-a', now: now);
      final uri = Uri.parse(api.calls.single.path);
      final widgetDayStart = DateTime(now.year, now.month, now.day);
      expect(uri.path, '/venues/venue-a/owner-dashboard');
      expect(
        DateTime.parse(uri.queryParameters['from']!),
        widgetDayStart.toUtc(),
      );
      expect(
        DateTime.parse(uri.queryParameters['to']!),
        widgetDayStart.add(const Duration(days: 1)).toUtc(),
      );
      expect(result.venue.upcomingEvents, hasLength(150)); // no client-side cap
      expect(result.activeGuests, hasLength(1));
      expect(result.stats.todayTotal, 8);
      expect(result.stats.totalAllTime, 120);
      expect(result.stats.followerCount, 41);
      expect(result.stats.storyViewsToday, 23);
      expect(result.stats.todayVsYesterdayPct, 100);
      expect(result.stats.weeklyTrend.single.count, 8);
    },
  );

  test(
    'reads are fresh after edits; no cross-user or cross-venue result cache is introduced',
    () async {
      var version = 0;
      final api = _ReadApi((_) => {...venue(), 'name': 'Cafe ${++version}'});
      final repo = VenueOwnerRepository(apiClient: api);
      expect((await repo.getOwnerProfile('venue-a')).name, 'Cafe 1');
      FlutterSecureStorage.setMockInitialValues({
        'access_token': 'different-owner-token',
      });
      expect((await repo.getOwnerProfile('venue-b')).name, 'Cafe 2');
      expect(
        api.calls.last.headers!['Authorization'],
        'Bearer different-owner-token',
      );
      expect(api.calls.last.path, '/venues/venue-b/owner-profile');
      expect((await repo.getOwnerProfile('venue-a')).name, 'Cafe 3');
    },
  );

  test('unauthenticated reads never send a request', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final api = _ReadApi((_) => full());
    final repo = VenueOwnerRepository(apiClient: api);
    await expectLater(repo.getOwnerProfile('venue-a'), throwsException);
    await expectLater(repo.getOwnerGuests('venue-a'), throwsException);
    await expectLater(repo.getOwnerDashboard('venue-a'), throwsException);
    expect(api.calls, isEmpty);
  });

  test(
    'new diagnostic route names are identifiable without logging IDs or day values',
    () {
      for (final endpoint in [
        'owner-profile',
        'owner-guests',
        'owner-dashboard',
      ]) {
        expect(
          performanceRoute('/venues/private-id/$endpoint?from=private-date'),
          '/venues/:id/$endpoint',
        );
      }
    },
  );
}
