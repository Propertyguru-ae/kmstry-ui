import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/venue/data/venue_profile_read.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_stats_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';

Map<String, dynamic> _member(
  String id, {
  String status = 'ACTIVE',
  String role = 'OWNER',
}) => {
  'id': id,
  'name': 'Cafe $id',
  'status': status,
  'role': role,
  'address': 'Address',
};
Map<String, dynamic> _me({
  String? active = 'a',
  List<Map<String, dynamic>>? venues,
  String? next,
}) => {
  'activeVenueId': active,
  'memberVenues': venues ?? [_member('a')],
  'username': 'owner',
  'hasPersonalProfile': true,
  'nextAction': next,
};
VenueOwnerStatsVenue _identity(String id) => VenueOwnerStatsVenue(
  id: id,
  name: 'Cafe $id',
  photo: 'approved-photo',
  description: 'About',
  type: 'CAFE',
  address: 'Address',
  city: 'Dubai',
  verificationLevel: 'VERIFIED',
);

void main() {
  test(
    'explicit venue starts account and identity in parallel, not exposing identity before confirmation',
    () async {
      final account = Completer<Map<String, dynamic>>();
      final identity = Completer<VenueOwnerStatsVenue>();
      final reads = <String>[];
      final read = VenueProfileRead(
        readMe: (_) {
          reads.add('account');
          return account.future;
        },
        readIdentity: (id) {
          reads.add(id);
          return identity.future;
        },
      );
      var complete = false;
      final pending = read.load(venueId: 'a', isCurrent: () => true)
        ..then((_) => complete = true);
      expect(reads, ['a', 'account']);
      final data = _identity('a');
      identity.complete(data);
      await Future<void>.delayed(Duration.zero);
      expect(complete, false);
      account.complete(_me());
      final result = (await pending)!;
      expect(result.venue, same(data));
      expect(result.context.role, VenueMemberRole.owner);
      expect(result.context.personalLabel, '@owner');
      expect(result.venue!.city, 'Dubai');
      expect(result.venue!.description, 'About');
    },
  );

  test(
    'fast account waits for already-started identity without a duplicate read',
    () async {
      final identity = Completer<VenueOwnerStatsVenue>();
      var count = 0;
      final read = VenueProfileRead(
        readMe: (_) async => _me(),
        readIdentity: (_) {
          count++;
          return identity.future;
        },
      );
      final pending = read.load(venueId: 'a', isCurrent: () => true);
      await Future<void>.delayed(Duration.zero);
      expect(count, 1);
      identity.complete(_identity('a'));
      expect((await pending)!.venue!.id, 'a');
      expect(count, 1);
    },
  );

  for (final requested in [null, '']) {
    test(
      'unknown ID never guesses before account confirmation ($requested)',
      () async {
        final account = Completer<Map<String, dynamic>>();
        final ids = <String>[];
        final read = VenueProfileRead(
          readMe: (_) => account.future,
          readIdentity: (id) async {
            ids.add(id);
            return _identity(id);
          },
        );
        final pending = read.load(venueId: requested, isCurrent: () => true);
        expect(ids, isEmpty);
        account.complete(
          _me(active: 'b', venues: [_member('a'), _member('b')]),
        );
        expect((await pending)!.venue!.id, 'b');
        expect(ids, ['b']);
      },
    );
  }

  for (final status in ['PENDING', 'REJECTED']) {
    test(
      '$status owner claim keeps existing placeholder and does not wait for speculative identity',
      () async {
        final identity = Completer<VenueOwnerStatsVenue>();
        final read = VenueProfileRead(
          readMe: (_) async => _me(venues: [_member('a', status: status)]),
          readIdentity: (_) => identity.future,
        );
        final result = (await read.load(venueId: 'a', isCurrent: () => true))!;
        expect(identity.isCompleted, false);
        expect(result.context.isClaimLocked, true);
        expect(result.venue!.name, 'Cafe a');
        expect(result.venue!.address, 'Address');
        expect(result.venue!.upcomingEvents, isEmpty);
        identity.completeError(StateError('VIEW_STATS denied'));
        await Future<void>.delayed(Duration.zero);
      },
    );
  }

  test(
    'another pending owner claim never hides selected active profile',
    () async {
      final read = VenueProfileRead(
        readMe: (_) async => _me(
          active: 'b',
          venues: [
            _member('b', status: 'PENDING'),
            _member('a'),
          ],
          next: 'AWAIT_VENUE_APPROVAL',
        ),
        readIdentity: (id) async => _identity(id),
      );
      final result = (await read.load(venueId: 'a', isCurrent: () => true))!;
      expect(result.context.isClaimLocked, false);
      expect(result.venue!.photo, 'approved-photo');
    },
  );

  test(
    'first-membership fallback and empty context preserve old routing',
    () async {
      var account = _me(active: null, venues: [_member('b'), _member('a')]);
      final ids = <String>[];
      final read = VenueProfileRead(
        readMe: (_) async => account,
        readIdentity: (id) async {
          ids.add(id);
          return _identity(id);
        },
      );
      expect((await read.load(isCurrent: () => true))!.venue!.id, 'b');
      account = _me(active: null, venues: []);
      expect((await read.load(isCurrent: () => true))!.venue, isNull);
      expect(ids, ['b']);
    },
  );

  test('personal label falls back to full name and then Personal', () {
    expect(
      VenueProfileContext.fromMe({'full_name': 'Owner'}, null).personalLabel,
      'Owner',
    );
    expect(VenueProfileContext.fromMe({}, null).personalLabel, 'Personal');
  });

  test(
    'STAFF pending invite is not an owner claim and never bypasses identity authorization',
    () async {
      final denied = StateError('denied');
      final read = VenueProfileRead(
        readMe: (_) async => _me(
          venues: [_member('a', status: 'PENDING', role: 'STAFF')],
        ),
        readIdentity: (_) async => throw denied,
      );
      await expectLater(
        read.load(venueId: 'a', isCurrent: () => true),
        throwsA(same(denied)),
      );
    },
  );

  test(
    'account failure never falls back to identity; late identity errors remain handled',
    () async {
      final identity = Completer<VenueOwnerStatsVenue>();
      final denied = StateError('auth');
      final read = VenueProfileRead(
        readMe: (_) async => throw denied,
        readIdentity: (_) => identity.future,
      );
      await expectLater(
        read.load(venueId: 'a', isCurrent: () => true),
        throwsA(same(denied)),
      );
      identity.completeError(StateError('late error'));
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'session change prevents newly resolved requests and suppresses late data/errors',
    () async {
      var current = true;
      final identity = Completer<VenueOwnerStatsVenue>();
      final read = VenueProfileRead(
        readMe: (_) async => _me(),
        readIdentity: (_) => identity.future,
      );
      final pending = read.load(venueId: 'a', isCurrent: () => current);
      await Future<void>.delayed(Duration.zero);
      current = false;
      identity.completeError(StateError('late'));
      expect(await pending, isNull);
      var reads = 0;
      final account = Completer<Map<String, dynamic>>();
      current = true;
      final unknown = VenueProfileRead(
        readMe: (_) => account.future,
        readIdentity: (id) async {
          reads++;
          return _identity(id);
        },
      );
      final other = unknown.load(isCurrent: () => current);
      current = false;
      account.complete(_me());
      expect(await other, isNull);
      expect(reads, 0);
      expect(await unknown.load(venueId: 'a', isCurrent: () => false), isNull);
    },
  );

  test(
    'wrong venue identity fails closed; every valid refresh uses fresh reads and forwards forceRefresh',
    () async {
      var id = 'wrong';
      final force = <bool>[];
      var count = 0;
      final read = VenueProfileRead(
        readMe: (f) async {
          force.add(f);
          return _me();
        },
        readIdentity: (_) async {
          count++;
          return _identity(id);
        },
      );
      await expectLater(
        read.load(venueId: 'a', isCurrent: () => true),
        throwsStateError,
      );
      id = 'a';
      await read.load(venueId: 'a', forceRefresh: true, isCurrent: () => true);
      expect(count, 2);
      expect(force, [false, true]);
    },
  );
}
