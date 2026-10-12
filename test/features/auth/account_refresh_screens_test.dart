import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/features/auth/data/auth_api.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/chat/data/chat_realtime_service.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/notifications/data/notification_model.dart';
import 'package:kmstry_frontend/features/notifications/data/notification_repository.dart';
import 'package:kmstry_frontend/features/notifications/data/notification_realtime_service.dart';
import 'package:kmstry_frontend/features/notifications/presentation/notifications.dart';
import 'package:kmstry_frontend/features/people/data/match_item_model.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_stats_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_account_home_page.dart';

Map<String, dynamic> _account(String context) => {
  'id': 'owner-a',
  'lastActiveContext': context,
  'activeVenueId': context == 'VENUE' ? 'a' : null,
  'hasPersonalProfile': true,
  'memberVenues': [
    {
      'id': 'a',
      'name': 'Cafe a',
      'role': 'OWNER',
      'status': 'ACTIVE',
      'hasDocuments': true,
    },
  ],
};

class _Api extends AuthApi {
  _Api(this.context);
  final String context;
  final pending = Completer<Map<String, dynamic>>();
  int calls = 0;
  @override
  Future<Map<String, dynamic>> me({required String accessToken}) {
    calls++;
    return calls == 1 ? pending.future : Future.value(_account(context));
  }
}

class _Notifications extends NotificationRepository {
  _Notifications(this.context);
  final String context;
  int calls = 0;
  @override
  Future<List<NotificationModel>> getNotifications({int limit = 50}) async {
    calls++;
    return [
      NotificationModel(
        id: 'one',
        type: 'venue_member_response',
        title: 'Successful notification',
        body: 'Account update',
        contextType: context,
        venueId: context == 'VENUE' ? 'a' : null,
        createdAt: DateTime.now(),
      ),
    ];
  }

  @override
  Future<void> markAllAsRead() async {}
}

class _Matches extends MatchRepository {
  @override
  Future<List<MatchItem>> getMatches() async => [];
}

class _Owner extends VenueOwnerRepository {
  int calls = 0;
  @override
  Future<VenueOwnerStatsResponse> getOwnerDashboard(
    String venueId, {
    DateTime? now,
  }) async {
    calls++;
    return VenueOwnerStatsResponse(
      venue: VenueOwnerStatsVenue(id: venueId, name: 'Cafe a'),
      stats: VenueOwnerStats(
        activeNow: 3,
        maleNow: 1,
        femaleNow: 2,
        todayTotal: 117,
        totalAllTime: 120,
        followerCount: 41,
        weeklyTrend: [],
      ),
      activeGuests: const [
        VenueActiveGuest(id: 'guest', username: 'guest', checkinId: 'checkin'),
      ],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    final payload = base64Url.encode(
      utf8.encode(jsonEncode({'sub': 'owner-a'})),
    );
    FlutterSecureStorage.setMockInitialValues({
      'access_token': 'header.$payload.signature',
    });
    SharedPreferences.setMockInitialValues({});
    VenueSession.instance.clear();
    PendingPublicMediaService.instance.clear();
    AuthRepository.invalidateMeCache();
    // Complete device-store cleanup outside the widget test's fake clock.
    await PendingPublicMediaService.instance.flushPersistence();
    await PendingPublicMediaService.instance.restoreAuthenticatedSession(
      'header.$payload.signature',
      expectedGeneration: PendingPublicMediaService.instance.sessionGeneration,
    );
    await PendingPublicMediaService.instance.flushPersistence();
  });
  tearDown(() async {
    PendingPublicMediaService.instance.clear();
    AuthRepository.invalidateMeCache();
    await PendingPublicMediaService.instance.flushPersistence();
  });

  for (final context in ['PERSONAL', 'VENUE']) {
    testWidgets(
      '$context notifications: same-owner cache invalidation silently recovers while keeping the successful notification read',
      (tester) async {
        final api = _Api(context);
        final notifications = _Notifications(context);
        final realtime = NotificationRealtimeService.forTest(
          events: const Stream<NotificationRealtimeEnvelope>.empty(),
          connectionState: const Stream<ChatRealtimeConnectionState>.empty(),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: NotificationPage(
              authRepository: AuthRepository(api: api),
              repository: notifications,
              matchRepository: _Matches(),
              realtimeService: realtime,
            ),
          ),
        );
        await tester.pump();
        expect(api.calls, 1);
        expect(notifications.calls, 1);
        final session = PendingPublicMediaService.instance.sessionGeneration;
        AuthRepository.invalidateMeCache();
        expect(PendingPublicMediaService.instance.sessionGeneration, session);
        api.pending.complete(_account(context));
        await tester.pumpAndSettle();
        expect(find.text('Could not load notifications'), findsNothing);
        expect(find.text('Successful notification'), findsOneWidget);
        expect(api.calls, 2);
        expect(notifications.calls, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'venue dashboard: same-owner invalidation silently recovers while keeping successful stats',
    (tester) async {
      tester.view.physicalSize = const Size(440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _Api('VENUE');
      final owner = _Owner();
      await tester.pumpWidget(
        MaterialApp(
          home: VenueAccountHomePage(
            venueId: 'a',
            authRepository: AuthRepository(api: api),
            repository: owner,
          ),
        ),
      );
      await tester.pump();
      expect(api.calls, 1);
      expect(owner.calls, 1);
      final session = PendingPublicMediaService.instance.sessionGeneration;
      AuthRepository.invalidateMeCache();
      expect(PendingPublicMediaService.instance.sessionGeneration, session);
      api.pending.complete(_account('VENUE'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not load venue stats. Tap to retry.'),
        findsNothing,
      );
      expect(find.text('117'), findsOneWidget);
      expect(api.calls, 2);
      expect(owner.calls, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
