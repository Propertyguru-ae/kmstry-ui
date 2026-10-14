import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/core/venue/venue_read_changes.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_stats_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_account_home_page.dart';

class _Auth extends AuthRepository {
  _Auth(this.read);
  final Future<Map<String, dynamic>> Function() read;
  int calls = 0;
  @override
  Future<Map<String, dynamic>> getMe({bool forceRefresh = false}) {
    calls++;
    return read();
  }
}

class _Owner extends VenueOwnerRepository {
  _Owner(this.read);
  final Future<VenueOwnerStatsResponse> Function(String) read;
  final calls = <String>[];
  @override
  Future<VenueOwnerStatsResponse> getOwnerDashboard(
    String venueId, {
    DateTime? now,
  }) {
    calls.add(venueId);
    return read(venueId);
  }
}

Map<String, dynamic> _me({String status = 'ACTIVE', bool empty = false}) => {
  'hasPersonalProfile': true,
  'memberVenues': empty
      ? []
      : [
          for (final id in ['a', 'b'])
            {
              'id': id,
              'name': 'Cafe $id',
              'role': 'OWNER',
              'status': status,
              'hasDocuments': true,
            },
        ],
};
VenueOwnerStatsResponse _stats(
  String id, {
  int today = 117,
  List<VenueActiveGuest> guests = const [
    VenueActiveGuest(id: 'guest', username: 'guest', checkinId: 'checkin'),
  ],
}) => VenueOwnerStatsResponse(
  venue: VenueOwnerStatsVenue(id: id, name: 'Cafe $id'),
  stats: VenueOwnerStats(
    activeNow: 3,
    maleNow: 1,
    femaleNow: 2,
    todayTotal: today,
    totalAllTime: 120,
    followerCount: 41,
    weeklyTrend: [],
  ),
  activeGuests: guests,
);

Future<void> _pump(
  WidgetTester tester,
  _Auth auth,
  _Owner owner, {
  String? venue = 'a',
  bool active = true,
}) => tester.pumpWidget(
  MaterialApp(
    home: VenueAccountHomePage(
      key: const ValueKey('home'),
      venueId: venue,
      authRepository: auth,
      repository: owner,
      isActive: active,
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    VenueSession.instance.clear();
    PendingPublicMediaService.instance.clear();
  });
  tearDown(() => PendingPublicMediaService.instance.clear());

  testWidgets(
    'fast tab returns reuse dashboard; hidden changes refresh once on return without hiding old data',
    (tester) async {
      final next = Completer<VenueOwnerStatsResponse>();
      var read = 0;
      final auth = _Auth(() async => _me());
      final owner = _Owner(
        (id) => ++read == 1 ? Future.value(_stats(id)) : next.future,
      );
      await _pump(tester, auth, owner);
      await tester.pumpAndSettle();
      await _pump(tester, auth, owner, active: false);
      await _pump(tester, auth, owner);
      await tester.pumpAndSettle();
      expect(owner.calls, ['a']);
      await _pump(tester, auth, owner, active: false);
      final session = PendingPublicMediaService.instance.sessionGeneration;
      VenueReadChanges.committed('a', {VenueReadSection.events}, session);
      VenueReadChanges.committed('a', {VenueReadSection.identity}, session);
      await tester.pumpAndSettle();
      expect(owner.calls, ['a']);
      await _pump(tester, auth, owner);
      await tester.pump();
      expect(find.text('117'), findsOneWidget);
      expect(find.text('RIGHT NOW'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(owner.calls, ['a', 'a']);
      next.complete(_stats('a', today: 118));
      await tester.pumpAndSettle();
      expect(find.text('118'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'other-venue metadata does not refresh the retained dashboard; revoked access removes the old dashboard',
    (tester) async {
      var denied = false;
      final auth = _Auth(() async => _me());
      final owner = _Owner((id) async {
        if (denied) throw ApiException(statusCode: 403, data: {});
        return _stats(id);
      });
      await _pump(tester, auth, owner);
      await tester.pumpAndSettle();
      final session = PendingPublicMediaService.instance.sessionGeneration;
      VenueReadChanges.committed('b', {VenueReadSection.events}, session);
      await tester.pumpAndSettle();
      expect(owner.calls, ['a']);
      denied = true;
      VenueReadChanges.committed('a', {VenueReadSection.events}, session);
      await tester.pumpAndSettle();
      expect(find.text('RIGHT NOW'), findsNothing);
      expect(
        find.text('Could not load venue stats. Tap to retry.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Home starts account/dashboard together, but paints full dashboard only after both succeed',
    (tester) async {
      tester.view.physicalSize = const Size(440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // Production binds the venue role before opening Home. With no token the
      // permission repository makes no HTTP request; the existing owner role
      // is enough to exercise the unchanged Story/Gallery card visibility.
      await VenueSession.instance.load('a', VenueMemberRole.owner);
      final account = Completer<Map<String, dynamic>>();
      final stats = Completer<VenueOwnerStatsResponse>();
      final auth = _Auth(() => account.future);
      final owner = _Owner((_) => stats.future);
      await _pump(tester, auth, owner);
      expect(auth.calls, 1);
      expect(owner.calls, ['a']);
      stats.complete(_stats('a'));
      await tester.pump();
      expect(find.text('RIGHT NOW'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      account.complete(_me());
      await tester.pumpAndSettle();
      expect(find.text('RIGHT NOW'), findsOneWidget);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('117'), findsOneWidget);
      expect(find.text('41'), findsOneWidget);
      expect(find.text('Story'), findsWidgets);
      expect(find.text('Gallery'), findsWidgets);
      expect(owner.calls, ['a']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending claim renders without waiting for the speculative dashboard; its late error stays harmless',
    (tester) async {
      final stats = Completer<VenueOwnerStatsResponse>();
      final auth = _Auth(() async => _me(status: 'PENDING'));
      final owner = _Owner((_) => stats.future);
      await _pump(tester, auth, owner);
      await tester.pumpAndSettle();
      expect(find.text('Claim Under Review'), findsOneWidget);
      expect(find.text('RIGHT NOW'), findsNothing);
      expect(stats.isCompleted, false);
      stats.completeError(StateError('VIEW_STATS denied'));
      await tester.pumpAndSettle();
      expect(find.text('Claim Under Review'), findsOneWidget);
      expect(
        find.text('Could not load venue stats. Tap to retry.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'account error cannot be overridden by an early successful dashboard',
    (tester) async {
      final auth = _Auth(() async => throw StateError('not authenticated'));
      final owner = _Owner((id) async => _stats(id));
      await _pump(tester, auth, owner);
      await tester.pumpAndSettle();
      expect(
        find.text('Could not load venue stats. Tap to retry.'),
        findsOneWidget,
      );
      expect(find.text('RIGHT NOW'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'no active venue preserves its explicit error and never starts an unknown-venue dashboard',
    (tester) async {
      final auth = _Auth(() async => _me(empty: true));
      final owner = _Owner((id) async => _stats(id));
      await _pump(tester, auth, owner, venue: null);
      await tester.pumpAndSettle();
      expect(find.text('No active venue found.'), findsOneWidget);
      expect(owner.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'same page switching venue starts a fresh read; late former-venue error cannot replace the new dashboard',
    (tester) async {
      final first = Completer<VenueOwnerStatsResponse>();
      final second = Completer<VenueOwnerStatsResponse>();
      final auth = _Auth(() async => _me());
      final owner = _Owner((id) => id == 'a' ? first.future : second.future);
      await _pump(tester, auth, owner);
      await tester.pump();
      await _pump(tester, auth, owner, venue: 'b');
      await tester.pump();
      expect(owner.calls, ['a', 'b']);
      second.complete(_stats('b', today: 227));
      await tester.pumpAndSettle();
      expect(find.text('227'), findsOneWidget);
      first.completeError(StateError('late forbidden'));
      await tester.pumpAndSettle();
      expect(find.text('227'), findsOneWidget);
      expect(find.text('117'), findsNothing);
      expect(
        find.text('Could not load venue stats. Tap to retry.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'refresh starts new account/dashboard reads and keeps existing statistics/card contract',
    (tester) async {
      final auth = _Auth(() async => _me());
      var today = 117;
      final owner = _Owner((id) async => _stats(id, today: today));
      await _pump(tester, auth, owner);
      await tester.pumpAndSettle();
      expect(find.text('117'), findsOneWidget);
      today = 227;
      final refresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pumpAndSettle();
      await refresh;
      expect(auth.calls, 2);
      expect(owner.calls, ['a', 'a']);
      expect(find.text('227'), findsOneWidget);
      expect(find.text('117'), findsNothing);
      expect(find.text('41'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Right now lists only real guests, never sample ones', (
    tester,
  ) async {
    final auth = _Auth(() async => _me());
    var guests = const <VenueActiveGuest>[];
    final owner = _Owner((id) async => _stats(id, guests: guests));
    await _pump(tester, auth, owner);
    await tester.pumpAndSettle();
    expect(find.text('RIGHT NOW'), findsOneWidget);
    for (final sample in ['dnzhtoo', 'yanhtoo', 'samchehab', 'rachellem__']) {
      expect(find.text(sample), findsNothing);
    }
    expect(find.text('+2'), findsNothing);

    guests = const [
      VenueActiveGuest(id: 'g1', fullName: 'Lina', checkinId: 'c1'),
    ];
    final refresh = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    await refresh;
    expect(find.text('Lina'), findsOneWidget);
    expect(find.text('dnzhtoo'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('session changes suppress late dashboard data', (tester) async {
    final stats = Completer<VenueOwnerStatsResponse>();
    final auth = _Auth(() async => _me());
    final owner = _Owner((_) => stats.future);
    await _pump(tester, auth, owner);
    await tester.pump();
    PendingPublicMediaService.instance.clear();
    stats.complete(_stats('a'));
    await tester.pump();
    expect(find.text('RIGHT NOW'), findsNothing);
    expect(find.text('117'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leaving Home while loading safely ignores late completion', (
    tester,
  ) async {
    final stats = Completer<VenueOwnerStatsResponse>();
    final auth = _Auth(() async => _me());
    final owner = _Owner((_) => stats.future);
    await _pump(tester, auth, owner);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    stats.complete(_stats('a'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
