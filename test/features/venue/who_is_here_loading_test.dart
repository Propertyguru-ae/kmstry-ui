import 'dart:async';
import 'package:kmstry_frontend/features/checkin/services/active_checkin_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/user/user_session.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/venue/data/attendee_filter.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_reporsitory.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_stats_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_people_page.dart';

class _People extends VenueCheckinRepository {
  final calls = <String>[];
  Future<List<VenueCheckin>> Function(String, AttendeeFilter?) read =
      (_, _) async => [_person('First person')];
  @override
  Future<List<VenueCheckin>> getWhoIsHere(
    String venueId, {
    AttendeeFilter? filter,
  }) {
    calls.add('$venueId:${filter?.gender ?? 'all'}');
    return read(venueId, filter);
  }
}

class _Stats extends VenueContextRepository {
  final calls = <String>[];
  Future<VenueCheckinStats> Function(String) read = (venue) async =>
      VenueCheckinStats(
        venueId: venue,
        checkinCountActive: 3,
        male: 1,
        female: 2,
      );
  @override
  Future<VenueCheckinStats> getVenueCheckinStats(String venueId) {
    calls.add(venueId);
    return read(venueId);
  }
}

VenueCheckin _person(String name) =>
    VenueCheckin(id: name, userId: name, fullName: name, userPhoto: '');
Widget _page(_People people, _Stats stats, {String venue = 'venue-a'}) =>
    MaterialApp(
      home: VenuePeoplePage(
        venue: Venue(
          id: venue,
          name: 'Test Cafe',
          type: 'CAFE',
          status: 'active',
          address: '',
          city: '',
          photoUrl: '',
          latitude: 25,
          longitude: 55,
          tag: '',
        ),
        repository: people,
        contextRepository: stats,
      ),
    );

void main() {
  setUp(() {
    ActiveCheckinService().clear();
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    PendingPublicMediaService.instance.clear();
    UserSession.instance.applyFromMe({'isPremium': true});
  });
  tearDown(() {
    ActiveCheckinService().clear();
    PendingPublicMediaService.instance.clear();
    UserSession.instance.clear();
  });

  for (final completeAfterPaint in [false, true]) {
    testWidgets(
      'same-check-in owner hydration keeps the room open (painted=$completeAfterPaint)',
      (tester) async {
        final active = ActiveCheckinService();
        // The upload page currently sets the approved check-in before /me
        // fills in its user ID. Neither painted nor in-flight reads are stale.
        active.setActiveCheckin('active', venueId: 'venue-a');
        final result = Completer<List<VenueCheckin>>();
        final people = _People()..read = (_, _) => result.future;
        final stats = _Stats();
        await tester.pumpWidget(_page(people, stats));
        if (completeAfterPaint) {
          result.complete([_person('First person')]);
          await tester.pumpAndSettle();
          expect(find.text('First person'), findsOneWidget);
        }
        active.syncForUser(
          userId: 'handan',
          checkinId: 'active',
          venueId: 'venue-a',
        );
        active.notifyMediaUpdated();
        if (!completeAfterPaint) {
          result.complete([_person('First person')]);
        }
        await tester.pumpAndSettle();
        expect(find.text('Your check-in has ended.'), findsNothing);
        expect(find.text('First person'), findsOneWidget);
        expect(people.calls, ['venue-a:all']);
        expect(stats.calls, ['venue-a']);
        expect(active.isCheckedInAt('venue-a'), isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final change in ['owner', 'venue', 'checkin', 'clear-and-restore']) {
    testWidgets('real $change change closes the room and rejects late reads', (
      tester,
    ) async {
      final active = ActiveCheckinService();
      active.setActiveCheckin('active', userId: 'handan', venueId: 'venue-a');
      final people = _People();
      await tester.pumpWidget(_page(people, _Stats()));
      await tester.pumpAndSettle();
      expect(find.text('First person'), findsOneWidget);
      final late = Completer<List<VenueCheckin>>();
      people.read = (_, _) => late.future;
      final refresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      if (change == 'clear-and-restore') active.clear();
      active.setActiveCheckin(
        change == 'checkin' ? 'new-checkin' : 'active',
        userId: change == 'owner' ? 'other' : 'handan',
        venueId: change == 'venue' ? 'venue-b' : 'venue-a',
      );
      await tester.pump();
      expect(find.text('Your check-in has ended.'), findsOneWidget);
      expect(find.text('First person'), findsNothing);
      late.complete([_person('Late private person')]);
      await refresh;
      await tester.pumpAndSettle();
      expect(find.text('Late private person'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'expiry immediately removes painted people and discards a late refresh',
    (tester) async {
      ActiveCheckinService().setActiveCheckin(
        'active',
        userId: 'hilal',
        venueId: 'venue-a',
      );
      final people = _People();
      final stats = _Stats();
      await tester.pumpWidget(_page(people, stats));
      await tester.pumpAndSettle();
      expect(find.text('First person'), findsOneWidget);
      final late = Completer<List<VenueCheckin>>();
      people.read = (_, _) => late.future;
      final refresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      ActiveCheckinService().clear();
      await tester.pump();
      expect(find.text('First person'), findsNothing);
      expect(find.text('Your check-in has ended.'), findsOneWidget);
      late.complete([_person('Late person')]);
      await refresh;
      await tester.pumpAndSettle();
      expect(find.text('Late person'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('people paint before independent statistics complete', (
    tester,
  ) async {
    final delayed = Completer<VenueCheckinStats>();
    final stats = _Stats()..read = (_) => delayed.future;
    final people = _People();
    await tester.pumpWidget(_page(people, stats));
    await tester.pump();
    expect(people.calls, ['venue-a:all']);
    expect(stats.calls, ['venue-a']);
    expect(find.text('First person'), findsOneWidget);
    delayed.complete(
      const VenueCheckinStats(
        venueId: 'venue-a',
        checkinCountActive: 3,
        male: 1,
        female: 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'same-filter refresh retains cards and combines concurrent requests',
    (tester) async {
      final people = _People();
      final stats = _Stats();
      await tester.pumpWidget(_page(people, stats));
      await tester.pumpAndSettle();
      final delayed = Completer<List<VenueCheckin>>();
      people.read = (_, _) => delayed.future;
      final refresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh;
      final first = refresh();
      final second = refresh();
      await tester.pump();
      expect(people.calls, hasLength(2));
      expect(stats.calls, hasLength(2));
      expect(find.text('First person'), findsOneWidget);
      delayed.complete([_person('Fresh person')]);
      await Future.wait([first, second]);
      await tester.pumpAndSettle();
      expect(find.text('Fresh person'), findsOneWidget);
    },
  );

  testWidgets(
    'filter changes reuse counts and an old filter response cannot replace the current list',
    (tester) async {
      final people = _People();
      final stats = _Stats();
      await tester.pumpWidget(_page(people, stats));
      await tester.pumpAndSettle();
      final old = Completer<List<VenueCheckin>>();
      people.read = (_, filter) => filter?.gender == 'female'
          ? old.future
          : Future.value([_person('Current men')]);
      await tester.tap(find.text('Women · 2'));
      await tester.pump();
      expect(find.text('First person'), findsNothing);
      await tester.tap(find.text('Men · 1'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Current men'), findsOneWidget);
      old.complete([_person('Old women')]);
      await tester.pumpAndSettle();
      expect(stats.calls, ['venue-a']);
      expect(people.calls, ['venue-a:all', 'venue-a:female', 'venue-a:male']);
      expect(find.text('Old women'), findsNothing);
      expect(find.text('Current men'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'loss of room authorization clears cards instead of retaining stale people',
    (tester) async {
      final people = _People();
      final stats = _Stats();
      await tester.pumpWidget(_page(people, stats));
      await tester.pumpAndSettle();
      people.read = (_, _) async => throw ApiException(
        statusCode: 403,
        data: {'message': 'Active check-in required'},
      );
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pumpAndSettle();
      expect(find.text('First person'), findsNothing);
      expect(find.text('Failed to load people'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a late old-venue response cannot replace the new venue', (
    tester,
  ) async {
    final old = Completer<List<VenueCheckin>>();
    final people = _People()
      ..read = (venue, _) => venue == 'venue-a'
          ? old.future
          : Future.value([_person('New venue person')]);
    final stats = _Stats();
    await tester.pumpWidget(_page(people, stats));
    await tester.pumpWidget(_page(people, stats, venue: 'venue-b'));
    await tester.pumpAndSettle();
    old.complete([_person('Old venue person')]);
    await tester.pumpAndSettle();
    expect(find.text('Old venue person'), findsNothing);
    expect(find.text('New venue person'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late response after logout cannot reveal the previous room', (
    tester,
  ) async {
    final late = Completer<List<VenueCheckin>>();
    final people = _People()..read = (_, _) => late.future;
    await tester.pumpWidget(_page(people, _Stats()));
    PendingPublicMediaService.instance.clear();
    late.complete([_person('Private old person')]);
    await tester.pumpAndSettle();
    expect(find.text('Private old person'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
