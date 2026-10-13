import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/chat/data/chat_realtime_service.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/notifications/data/notification_model.dart';
import 'package:kmstry_frontend/features/notifications/data/notification_repository.dart';
import 'package:kmstry_frontend/features/notifications/data/notification_realtime_service.dart';
import 'package:kmstry_frontend/features/notifications/presentation/notifications.dart';
import 'package:kmstry_frontend/features/notifications/presentation/notification_unread_scope.dart';
import 'package:kmstry_frontend/features/people/data/match_item_model.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';

class _Auth extends AuthRepository {
  int calls = 0;
  Future<Map<String, dynamic>> Function() read = () async => {
    'lastActiveContext': 'PERSONAL',
  };
  @override
  Future<Map<String, dynamic>> getMe({bool forceRefresh = false}) {
    calls++;
    return read();
  }
}

class _Notifications extends NotificationRepository {
  int calls = 0;
  int receipts = 0;
  Future<List<NotificationModel>> Function() read = () async => [
    _item('First update'),
  ];
  Future<void> Function() receipt = () async {};
  @override
  Future<List<NotificationModel>> getNotifications({int limit = 50}) {
    calls++;
    return read();
  }

  @override
  Future<void> markAllAsRead() {
    receipts++;
    return receipt();
  }
}

class _Matches extends MatchRepository {
  int calls = 0;
  Future<List<MatchItem>> Function() read = () async => [];
  @override
  Future<List<MatchItem>> getMatches() {
    calls++;
    return read();
  }
}

NotificationModel _item(String title, {String? venue}) => NotificationModel(
  id: title,
  type: 'venue_member_response',
  title: title,
  body: 'Account update',
  contextType: venue == null ? 'PERSONAL' : 'VENUE',
  venueId: venue,
  createdAt: DateTime.now(),
);
Widget _page(
  _Auth auth,
  _Notifications repo,
  _Matches matches, {
  void Function(int)? unread,
  NotificationRealtimeService? realtime,
}) => MaterialApp(
  home: NotificationUnreadScope(
    unreadCount: 7,
    updateUnreadCount: unread ?? (_) {},
    child: NotificationPage(
      authRepository: auth,
      repository: repo,
      matchRepository: matches,
      realtimeService: realtime,
    ),
  ),
);

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    PendingPublicMediaService.instance.clear();
    VenueSession.instance.clear();
  });
  tearDown(() => PendingPublicMediaService.instance.clear());

  testWidgets(
    'connection events join the initial read; a new venue event survives the older snapshot',
    (tester) async {
      final events = StreamController<NotificationRealtimeEnvelope>.broadcast();
      final states = StreamController<ChatRealtimeConnectionState>.broadcast();
      addTearDown(events.close);
      addTearDown(states.close);
      final realtime = NotificationRealtimeService.forTest(
        events: events.stream,
        connectionState: states.stream,
      );
      final me = Completer<Map<String, dynamic>>();
      final list = Completer<List<NotificationModel>>();
      final auth = _Auth()..read = () => me.future;
      final repo = _Notifications()..read = () => list.future;
      await tester.pumpWidget(
        _page(auth, repo, _Matches(), realtime: realtime),
      );
      states.add(ChatRealtimeConnectionState.connected);
      states.add(ChatRealtimeConnectionState.reconnecting);
      events.add(
        const NotificationRealtimeEnvelope(
          event: 'socket.reconnected',
          payload: {},
        ),
      );
      events.add(
        NotificationRealtimeEnvelope(
          event: 'notification.created',
          payload: {
            'notification': {
              'id': 'new',
              'type': 'venue_member_response',
              'title': 'New venue notification',
              'body': 'New account update',
              'contextType': 'VENUE',
              'venueId': 'a',
              'createdAt': DateTime.now().toIso8601String(),
            },
          },
        ),
      );
      await tester.pump();
      expect(repo.calls, 1);
      expect(find.text('New venue notification'), findsNothing);
      me.complete({'lastActiveContext': 'VENUE', 'activeVenueId': 'a'});
      list.complete([_item('Snapshot venue notification', venue: 'a')]);
      await tester.pumpAndSettle();
      expect(find.text('New venue notification'), findsOneWidget);
      expect(find.text('Snapshot venue notification'), findsOneWidget);
      expect(repo.calls, 1);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a newer realtime unread count is never cleared by a late receipt',
    (tester) async {
      final events = StreamController<NotificationRealtimeEnvelope>.broadcast();
      final states = StreamController<ChatRealtimeConnectionState>.broadcast();
      addTearDown(events.close);
      addTearDown(states.close);
      final realtime = NotificationRealtimeService.forTest(
        events: events.stream,
        connectionState: states.stream,
      );
      final receipt = Completer<void>();
      final repo = _Notifications()..receipt = () => receipt.future;
      final unread = <int>[];
      await tester.pumpWidget(
        _page(
          _Auth(),
          repo,
          _Matches(),
          realtime: realtime,
          unread: unread.add,
        ),
      );
      await tester.pumpAndSettle();
      events.add(
        const NotificationRealtimeEnvelope(
          event: 'notification.read',
          payload: {'unreadCount': 1},
        ),
      );
      await tester.pump();
      receipt.complete();
      await tester.pumpAndSettle();
      expect(unread, [1]);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'starts all reads together and paints before read receipt completes',
    (tester) async {
      final me = Completer<Map<String, dynamic>>();
      final list = Completer<List<NotificationModel>>();
      final matches = Completer<List<MatchItem>>();
      final receipt = Completer<void>();
      final auth = _Auth()..read = () => me.future;
      final repo = _Notifications();
      repo.read = () => list.future;
      repo.receipt = () => receipt.future;
      final matchRepo = _Matches()..read = () => matches.future;
      final unread = <int>[];
      await tester.pumpWidget(_page(auth, repo, matchRepo, unread: unread.add));
      expect([auth.calls, repo.calls, matchRepo.calls], [1, 1, 1]);
      list.complete([_item('Visible update')]);
      matches.complete([]);
      await tester.pump();
      expect(find.text('Visible update'), findsNothing);
      me.complete({'lastActiveContext': 'PERSONAL'});
      await tester.pumpAndSettle();
      expect(find.text('Visible update'), findsOneWidget);
      expect(repo.receipts, 1);
      expect(unread, isEmpty);
      receipt.complete();
      await tester.pumpAndSettle();
      expect(unread, [0]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'refresh retains existing notifications and coalesces simultaneous reads',
    (tester) async {
      final auth = _Auth();
      final repo = _Notifications();
      final matches = _Matches();
      await tester.pumpWidget(_page(auth, repo, matches));
      await tester.pumpAndSettle();
      final delayed = Completer<List<NotificationModel>>();
      repo.read = () => delayed.future;
      final refresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh;
      final first = refresh();
      final second = refresh();
      await tester.pump();
      expect(repo.calls, 2);
      expect(auth.calls, 2);
      expect(matches.calls, 2);
      expect(find.text('First update'), findsOneWidget);
      delayed.complete([_item('Fresh update')]);
      await Future.wait([first, second]);
      await tester.pumpAndSettle();
      expect(find.text('Fresh update'), findsOneWidget);
      expect(find.text('First update'), findsNothing);
    },
  );

  testWidgets(
    'match enrichment failure or receipt failure does not hide the list',
    (tester) async {
      final unread = <int>[];
      final repo = _Notifications()
        ..receipt = () async => throw StateError('receipt offline');
      final matches = _Matches()
        ..read = () async => throw StateError('matches offline');
      await tester.pumpWidget(
        _page(_Auth(), repo, matches, unread: unread.add),
      );
      await tester.pumpAndSettle();
      expect(find.text('First update'), findsOneWidget);
      expect(unread, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed account validation cannot publish or mark notifications as read',
    (tester) async {
      final auth = _Auth()..read = () async => throw StateError('unauthorized');
      final repo = _Notifications();
      await tester.pumpWidget(_page(auth, repo, _Matches()));
      await tester.pumpAndSettle();
      expect(find.text('Could not load notifications'), findsOneWidget);
      expect(find.text('First update'), findsNothing);
      expect(repo.receipts, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late response after logout cannot paint the old account or write receipts',
    (tester) async {
      final delayed = Completer<List<NotificationModel>>();
      final repo = _Notifications()..read = () => delayed.future;
      await tester.pumpWidget(_page(_Auth(), repo, _Matches()));
      PendingPublicMediaService.instance.clear();
      delayed.complete([_item('Old account private update')]);
      await tester.pump();
      expect(find.text('Old account private update'), findsNothing);
      expect(repo.receipts, 0);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'personal and other venue notifications are excluded from venue context',
    (tester) async {
      final auth = _Auth()
        ..read = () async => {
          'lastActiveContext': 'VENUE',
          'activeVenueId': 'a',
        };
      final repo = _Notifications()
        ..read = () async => [
          _item('Personal'),
          _item('Other venue', venue: 'b'),
          _item('Current venue', venue: 'a'),
        ];
      await tester.pumpWidget(_page(auth, repo, _Matches()));
      await tester.pumpAndSettle();
      expect(find.text('Current venue'), findsOneWidget);
      expect(find.text('Other venue'), findsNothing);
      expect(find.text('Personal'), findsNothing);
    },
  );
}
