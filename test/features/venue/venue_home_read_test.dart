import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/venue/data/venue_home_read.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_stats_model.dart';

Map<String, dynamic> _me({
  String? active = 'a',
  List<Map<String, dynamic>>? venues,
  String? next,
  bool personal = true,
  bool rejectedOnly = false,
}) => {
  'activeVenueId': active,
  'hasPersonalProfile': personal,
  'nextAction': next,
  'hasRejectedClaimOnly': rejectedOnly,
  'memberVenues': venues ?? [_member('a')],
};
Map<String, dynamic> _member(
  String id, {
  String status = 'ACTIVE',
  String role = 'OWNER',
  bool docs = false,
}) => {
  'id': id,
  'name': 'Cafe $id',
  'role': role,
  'status': status,
  'hasDocuments': docs,
};
VenueOwnerStatsResponse _stats(String id) => VenueOwnerStatsResponse(
  venue: VenueOwnerStatsVenue(id: id, name: 'Cafe $id'),
  stats: const VenueOwnerStats(
    activeNow: 3,
    anonymousNow: 1,
    maleNow: 1,
    femaleNow: 2,
    todayTotal: 8,
    yesterdayTotal: 5,
    yesterdaySoFar: 4,
    totalAllTime: 120,
    weeklyTrend: [],
    followerCount: 41,
    storyViewsToday: 23,
  ),
  activeGuests: const [VenueActiveGuest(id: 'guest', checkinId: 'checkin')],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'private registration reuses the locked home without claiming an owner role',
    () async {
      final account = _me(venues: [], next: 'GO_TO_VENUE_HOME');
      account['venueRegistration'] = {
        'venue': {'id': 'a', 'name': 'Draft Cafe'},
        'status': 'DRAFT',
        'isVerifiedOwner': false,
        'hasDocuments': false,
      };
      final read = VenueHomeRead(
        readMe: () async => account,
        readDashboard: (_) async =>
            throw StateError('No membership permissions'),
      );
      final result = await read.load(venueId: 'a', isCurrent: () => true);
      expect(result!.context.hasClaimView, isTrue);
      expect(result.context.pendingHasDocuments, isFalse);
      expect(result.context.pendingVenue!.isRegistrationDraft, isTrue);
      expect(result.context.pendingVenue!.isPendingOwnerClaim, isFalse);
      expect(result.context.pendingVenue!.role, isNull);
      expect(result.dashboard, isNull);
    },
  );
  test(
    'known venue starts both reads immediately; fast dashboard is not exposed before account confirmation',
    () async {
      final me = Completer<Map<String, dynamic>>();
      final dashboard = Completer<VenueOwnerStatsResponse>();
      var meReads = 0;
      final venues = <String>[];
      final read = VenueHomeRead(
        readMe: () {
          meReads++;
          return me.future;
        },
        readDashboard: (id) {
          venues.add(id);
          return dashboard.future;
        },
      );
      var completed = false;
      final load = read.load(venueId: 'a', isCurrent: () => true)
        ..then((_) => completed = true);
      expect(meReads, 1);
      expect(venues, ['a']);
      final data = _stats('a');
      dashboard.complete(data);
      await Future<void>.delayed(Duration.zero);
      expect(completed, false);
      me.complete(_me());
      final result = (await load)!;
      expect(result.dashboard, same(data));
      expect(result.dashboard!.stats.followerCount, 41);
      expect(result.dashboard!.stats.storyViewsToday, 23);
      expect(result.dashboard!.activeGuests.single.id, 'guest');
      expect(result.context.hasClaimView, false);
      expect(venues, ['a']);
    },
  );

  test(
    'fast account confirmation waits for the already-started dashboard, never requests it twice',
    () async {
      final dashboard = Completer<VenueOwnerStatsResponse>();
      var count = 0;
      final read = VenueHomeRead(
        readMe: () async => _me(),
        readDashboard: (_) {
          count++;
          return dashboard.future;
        },
      );
      var completed = false;
      final load = read.load(venueId: 'a', isCurrent: () => true)
        ..then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(count, 1);
      expect(completed, false);
      dashboard.complete(_stats('a'));
      expect((await load)!.dashboard!.venue.id, 'a');
      expect(count, 1);
    },
  );

  for (final requested in [null, '']) {
    test(
      'unknown/empty venue keeps sequential resolution from confirmed context ($requested)',
      () async {
        final me = Completer<Map<String, dynamic>>();
        final ids = <String>[];
        final read = VenueHomeRead(
          readMe: () => me.future,
          readDashboard: (id) async {
            ids.add(id);
            return _stats(id);
          },
        );
        final load = read.load(venueId: requested, isCurrent: () => true);
        expect(ids, isEmpty);
        me.complete(_me(active: 'b', venues: [_member('a'), _member('b')]));
        expect((await load)!.dashboard!.venue.id, 'b');
        expect(ids, ['b']);
      },
    );
  }

  test(
    'first-member fallback and no-active-venue semantics stay intact',
    () async {
      final ids = <String>[];
      var account = _me(active: null, venues: [_member('b'), _member('a')]);
      final read = VenueHomeRead(
        readMe: () async => account,
        readDashboard: (id) async {
          ids.add(id);
          return _stats(id);
        },
      );
      expect((await read.load(isCurrent: () => true))!.context.venueId, 'b');
      account = _me(active: null, venues: []);
      final empty = (await read.load(isCurrent: () => true))!;
      expect(empty.context.hasVenue, false);
      expect(empty.dashboard, isNull);
      expect(ids, ['b']);
    },
  );

  test(
    'pending claim returns immediately; late denied speculative dashboard is consumed without an unhandled error',
    () async {
      final dashboard = Completer<VenueOwnerStatsResponse>();
      final read = VenueHomeRead(
        readMe: () async => _me(
          venues: [_member('a', status: 'PENDING', docs: true)],
          personal: false,
        ),
        readDashboard: (_) => dashboard.future,
      );
      final result = (await read.load(venueId: 'a', isCurrent: () => true))!;
      expect(dashboard.isCompleted, false);
      expect(result.dashboard, isNull);
      expect(result.context.isPendingClaim, true);
      expect(result.context.isRejectedClaim, false);
      expect(result.context.showPersonalBanner, true);
      expect(result.context.pendingHasDocuments, true);
      expect(result.context.pendingVenue!.id, 'a');
      dashboard.completeError(StateError('not an active member'));
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'rejected claim hides even a successful speculative dashboard and retains rejected view/banner behavior',
    () async {
      final read = VenueHomeRead(
        readMe: () async =>
            _me(venues: [_member('a', status: 'REJECTED')], personal: false),
        readDashboard: (_) async => _stats('a'),
      );
      final result = (await read.load(venueId: 'a', isCurrent: () => true))!;
      expect(result.dashboard, isNull);
      expect(result.context.isRejectedClaim, true);
      expect(result.context.showPersonalBanner, false);
      expect(result.context.rejectedVenue!.id, 'a');
    },
  );

  for (final otherStatus in ['PENDING', 'REJECTED']) {
    test(
      'another venue $otherStatus claim cannot hide the selected ACTIVE venue',
      () async {
        final read = VenueHomeRead(
          readMe: () async => _me(
            active: 'other',
            venues: [
              _member('other', status: otherStatus),
              _member('a'),
            ],
            next: 'AWAIT_VENUE_APPROVAL',
            personal: false,
          ),
          readDashboard: (_) async => _stats('a'),
        );
        final result = (await read.load(venueId: 'a', isCurrent: () => true))!;
        expect(result.context.venueId, 'a');
        expect(result.context.hasClaimView, false);
        expect(result.context.showPersonalBanner, true);
        expect(result.dashboard!.venue.id, 'a');
      },
    );
  }

  test(
    'global pending/rejected fallback without a membership keeps existing claim precedence',
    () async {
      final ids = <String>[];
      var account = _me(active: null, venues: [], next: 'AWAIT_VENUE_APPROVAL');
      final read = VenueHomeRead(
        readMe: () async => account,
        readDashboard: (id) async {
          ids.add(id);
          return _stats(id);
        },
      );
      expect(
        (await read.load(isCurrent: () => true))!.context.isPendingClaim,
        true,
      );
      account = _me(
        active: null,
        venues: [],
        rejectedOnly: true,
        personal: false,
      );
      final rejected = (await read.load(isCurrent: () => true))!;
      expect(rejected.context.isRejectedClaim, true);
      expect(rejected.context.showPersonalBanner, false);
      expect(ids, isEmpty);
    },
  );

  test(
    'pending STAFF invite is not an owner claim; actual backend denial remains an error',
    () async {
      final denied = StateError('VIEW_STATS denied');
      final read = VenueHomeRead(
        readMe: () async => _me(
          venues: [_member('a', status: 'PENDING', role: 'STAFF')],
        ),
        readDashboard: (_) async => throw denied,
      );
      await expectLater(
        read.load(venueId: 'a', isCurrent: () => true),
        throwsA(same(denied)),
      );
    },
  );

  test(
    'account failure never falls back to a successful dashboard; later dashboard errors stay handled',
    () async {
      final dashboard = Completer<VenueOwnerStatsResponse>();
      final denied = StateError('account validation failed');
      final read = VenueHomeRead(
        readMe: () async => throw denied,
        readDashboard: (_) => dashboard.future,
      );
      await expectLater(
        read.load(venueId: 'a', isCurrent: () => true),
        throwsA(same(denied)),
      );
      dashboard.completeError(StateError('dashboard unavailable'));
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'synchronous dashboard error is handled and propagated only after confirmed active account',
    () async {
      final denied = StateError('forbidden');
      final read = VenueHomeRead(
        readMe: () async => _me(),
        readDashboard: (_) => throw denied,
      );
      await expectLater(
        read.load(venueId: 'a', isCurrent: () => true),
        throwsA(same(denied)),
      );
    },
  );

  test(
    'no reads start for an invalid session; session changes suppress late data or errors',
    () async {
      var current = false;
      var reads = 0;
      final me = Completer<Map<String, dynamic>>();
      final dashboard = Completer<VenueOwnerStatsResponse>();
      final read = VenueHomeRead(
        readMe: () {
          reads++;
          return me.future;
        },
        readDashboard: (_) {
          reads++;
          return dashboard.future;
        },
      );
      expect(await read.load(venueId: 'a', isCurrent: () => current), isNull);
      expect(reads, 0);
      current = true;
      final load = read.load(venueId: 'a', isCurrent: () => current);
      me.complete(_me());
      await Future<void>.delayed(Duration.zero);
      current = false;
      dashboard.completeError(StateError('late forbidden'));
      expect(await load, isNull);
    },
  );

  test(
    'session change before account resolution cannot start a newly-resolved venue read',
    () async {
      var current = true;
      final me = Completer<Map<String, dynamic>>();
      var dashboards = 0;
      final read = VenueHomeRead(
        readMe: () => me.future,
        readDashboard: (id) async {
          dashboards++;
          return _stats(id);
        },
      );
      final load = read.load(isCurrent: () => current);
      current = false;
      me.complete(_me());
      expect(await load, isNull);
      expect(dashboards, 0);
    },
  );

  test('dashboard with another venue ID fails closed', () async {
    final read = VenueHomeRead(
      readMe: () async => _me(),
      readDashboard: (_) async => _stats('other'),
    );
    await expectLater(
      read.load(venueId: 'a', isCurrent: () => true),
      throwsStateError,
    );
  });

  test(
    'refreshes and different venue loads never reuse a dashboard/approval response cache',
    () async {
      var meReads = 0;
      final ids = <String>[];
      final read = VenueHomeRead(
        readMe: () async {
          meReads++;
          return _me(venues: [_member('a'), _member('b')]);
        },
        readDashboard: (id) async {
          ids.add(id);
          return _stats(id);
        },
      );
      for (final id in ['a', 'a', 'b']) {
        expect(
          (await read.load(
            venueId: id,
            isCurrent: () => true,
          ))!.dashboard!.venue.id,
          id,
        );
      }
      expect(meReads, 3);
      expect(ids, ['a', 'a', 'b']);
    },
  );
}
