import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_profile_model.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/people/data/friendship_changes.dart';
import 'package:kmstry_frontend/features/people/data/match_item_model.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';
import 'package:kmstry_frontend/features/messageDetail/presentation/message_detail.dart';
import 'package:kmstry_frontend/features/venue/presentation/profile_preview_page.dart';

final _friend = MatchItem(
  matchId: 'match-a-b',
  userId: 'a',
  connectionVersion: 'interest-b',
  fullName: 'Person A',
  chatId: 'chat-a-b',
);

class _Profiles extends CheckinRepository {
  Completer<void>? sending;
  MatchItem? confirmed;
  final actions = <String>[];

  @override
  Future<Set<String>> getBlockedUserIds() async => {};

  @override
  Future<PublicUserProfile> getPublicUserProfile(String id) async =>
      PublicUserProfile(
        id: id,
        fullName: 'Person A',
        gender: 'female',
        isVerified: false,
        isPremium: false,
        friendCount: 1,
        followedVenueCount: 0,
      );

  @override
  Future<MatchItem?> sendFeedAction({
    required String targetUserId,
    String? venueId,
    required String action,
    ({String id, DateTime version})? interestNotice,
  }) async {
    actions.add(action);
    await sending?.future;
    return confirmed;
  }
}

class _Friendships extends MatchRepository {
  final requests = <Completer<MatchItem?>>[];

  @override
  Future<MatchItem?> getFriendship(String userId) {
    final request = Completer<MatchItem?>();
    requests.add(request);
    return request.future;
  }
}

Future<void> _open(
  WidgetTester tester,
  _Friendships friendships, {
  _Profiles? profiles,
  ({String id, DateTime version})? notice,
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  ProfilePreviewPage.clearActionStateCache();
  await tester.pumpWidget(
    MaterialApp(
      home: ProfilePreviewPage(
        interestNotice: notice,
        userId: 'a',
        userName: 'Person A',
        // The same hint used when opening an old interest notification.
        actionStateHint: ProfileActionState.incomingInterested,
        checkinRepository: profiles ?? _Profiles(),
        matchRepository: friendships,
      ),
    ),
  );
  await tester.pump();
}

void _expectNoChoices() {
  expect(find.text('Interested'), findsNothing);
  expect(find.text('Pass'), findsNothing);
}

Future<void> _refresh(WidgetTester tester) async {
  unawaited(
    tester.widget<RefreshIndicator>(find.byType(RefreshIndicator)).onRefresh(),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async => Firebase.initializeApp());
  testWidgets(
    'old interest notification does not flash choices before match lookup',
    (tester) async {
      final friendships = _Friendships();
      await _open(tester, friendships);
      expect(friendships.requests, hasLength(1));
      await tester.pump(const Duration(seconds: 2));
      _expectNoChoices();
      friendships.requests.single.complete(_friend);
      await tester.pumpAndSettle();
      _expectNoChoices();
    },
  );

  testWidgets(
    'confirmed match stays hidden during refresh and socket reconnect',
    (tester) async {
      final friendships = _Friendships();
      await _open(tester, friendships);
      friendships.requests.single.complete(_friend);
      await tester.pumpAndSettle();
      await _refresh(tester);
      await tester.pump(const Duration(seconds: 2));
      _expectNoChoices();
      friendships.requests.last.complete(_friend);
      await tester.pumpAndSettle();
      FriendshipChanges.refresh();
      await tester.pump(const Duration(seconds: 2));
      _expectNoChoices();
      friendships.requests.last.complete(_friend);
      await tester.pumpAndSettle();
      _expectNoChoices();
    },
  );

  testWidgets(
    'accepting interest and receiving active friendship never restores choices',
    (tester) async {
      final friendships = _Friendships();
      final profiles = _Profiles()..sending = Completer<void>();
      await _open(tester, friendships, profiles: profiles);
      friendships.requests.single.complete(null);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Interested'));
      await tester.pump(const Duration(milliseconds: 250));
      _expectNoChoices();
      await _refresh(tester);
      if (!friendships.requests.last.isCompleted) {
        friendships.requests.last.complete(null); // Pre-accept server snapshot.
      }
      await tester.pump(const Duration(seconds: 2));
      _expectNoChoices();
      profiles.sending!.complete();
      await tester.pump();
      FriendshipChanges.changed('a', active: true);
      await tester.pump(const Duration(seconds: 2));
      _expectNoChoices();
      for (final request in friendships.requests) {
        if (!request.isCompleted) request.complete(_friend);
      }
      await tester.pumpAndSettle();
      expect(profiles.actions, ['interested']);
      _expectNoChoices();
    },
  );

  testWidgets('failed refresh preserves the confirmed match', (tester) async {
    final friendships = _Friendships();
    await _open(tester, friendships);
    friendships.requests.single.complete(_friend);
    await tester.pumpAndSettle();
    await _refresh(tester);
    friendships.requests.last.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    _expectNoChoices();
  });

  testWidgets('newer removal wins over a late match response', (tester) async {
    final friendships = _Friendships();
    await _open(tester, friendships);
    friendships.requests.single.complete(_friend);
    await tester.pumpAndSettle();
    await _refresh(tester);
    final stale = friendships.requests.last;
    FriendshipChanges.changed('a', active: false);
    await tester.pump();
    final latest = friendships.requests.last;
    expect(identical(stale, latest), isFalse);
    latest.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Interested'), findsOneWidget);
    stale.complete(_friend);
    await tester.pumpAndSettle();
    expect(find.text('Interested'), findsOneWidget);
    expect(
      ProfilePreviewPage.peekCachedActionState('a'),
      isNot(ProfileActionState.matched),
    );
  });

  testWidgets('unrelated friendship event does not interrupt current lookup', (
    tester,
  ) async {
    final friendships = _Friendships();
    await _open(tester, friendships);
    FriendshipChanges.changed('someone-else', active: true);
    friendships.requests.single.complete(null);
    await tester.pumpAndSettle();
    expect(find.text('Interested'), findsOneWidget);
    expect(find.text('Pass'), findsOneWidget);
  });
  testWidgets(
    'a request withdrawn while the profile is open never opens chat',
    (tester) async {
      final friendships = _Friendships();
      final profiles = _Profiles()..sending = Completer<void>();
      await _open(
        tester,
        friendships,
        profiles: profiles,
        notice: (id: 'original', version: DateTime.utc(2026)),
      );
      friendships.requests.single.complete(null);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Interested'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Message'), findsNothing);
      profiles.sending!.completeError(
        ApiException(
          statusCode: 409,
          data: {'errorCode': 'INTEREST_UNAVAILABLE'},
        ),
      );
      await tester.pump();
      friendships.requests.last.complete(null);
      await tester.pumpAndSettle();
      expect(find.text('This request is no longer available.'), findsOneWidget);
      _expectNoChoices();
    },
  );
  for (final delayedReply in ['success', 'timeout', 'consumed']) {
    testWidgets(
      'notice acceptance resolves to Message even with a $delayedReply reply',
      (tester) async {
        final friendships = _Friendships();
        final profiles = _Profiles()..sending = Completer<void>();
        await _open(
          tester,
          friendships,
          profiles: profiles,
          notice: (id: 'final-notice', version: DateTime.utc(2026)),
        );
        friendships.requests.single.complete(null);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Interested'));
        await tester.pump();
        expect(find.text('Connecting…'), findsOneWidget);
        _expectNoChoices();
        if (delayedReply == 'success') {
          profiles.confirmed = _friend;
          profiles.sending!.complete();
        } else {
          profiles.sending!.completeError(
            delayedReply == 'timeout'
                ? TimeoutException('response lost')
                : ApiException(
                    statusCode: 409,
                    data: {'errorCode': 'INTEREST_UNAVAILABLE'},
                  ),
          );
          await tester.pump();
          _expectNoChoices();
          friendships.requests.last.complete(_friend);
        }
        await tester.pumpAndSettle();
        expect(find.text('Message'), findsOneWidget);
        expect(find.text('This request is no longer available.'), findsNothing);
        expect(profiles.actions, ['interested']);
        _expectNoChoices();
      },
    );
  }
  testWidgets(
    'committed realtime match enables Message before the HTTP reply; a newer removal wins',
    (tester) async {
      final friendships = _Friendships();
      final profiles = _Profiles()
        ..sending = Completer<void>()
        ..confirmed = _friend;
      await _open(
        tester,
        friendships,
        profiles: profiles,
        notice: (id: 'final-notice', version: DateTime.utc(2026)),
      );
      friendships.requests.single.complete(null);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Interested'));
      await tester.pump();
      FriendshipChanges.changed('a', active: true, friendship: _friend);
      await tester.pump();
      expect(find.text('Message'), findsOneWidget);
      FriendshipChanges.changed('a', active: false);
      await tester.pump();
      profiles.sending!.complete();
      await tester.pump();
      expect(find.text('Message'), findsNothing);
      _expectNoChoices();
      expect(find.text('This request is no longer available.'), findsOneWidget);
      if (!friendships.requests.last.isCompleted) {
        friendships.requests.last.complete(null);
      }
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'offline confirmation can retry the lookup without sending a second acceptance',
    (tester) async {
      final friendships = _Friendships();
      final profiles = _Profiles()..sending = Completer<void>();
      await _open(
        tester,
        friendships,
        profiles: profiles,
        notice: (id: 'final-notice', version: DateTime.utc(2026)),
      );
      friendships.requests.single.complete(null);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Interested'));
      profiles.sending!.completeError(TimeoutException('reply lost'));
      await tester.pump();
      friendships.requests.last.completeError(Exception('still offline'));
      await tester.pumpAndSettle();
      _expectNoChoices();
      await tester.tap(
        find.text('Couldn’t confirm your connection. Try again'),
      );
      await tester.pump();
      friendships.requests.last.complete(_friend);
      await tester.pumpAndSettle();
      expect(find.text('Message'), findsOneWidget);
      expect(profiles.actions, ['interested']);
    },
  );
  testWidgets(
    'a slow accept without realtime opens the confirmed chat while the write reply is pending',
    (tester) async {
      final friendships = _Friendships();
      final profiles = _Profiles()..sending = Completer<void>();
      await _open(
        tester,
        friendships,
        profiles: profiles,
        notice: (id: 'interest', version: DateTime.utc(2026)),
      );
      friendships.requests.single.complete(null);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Interested'));
      await tester.pump();
      expect(find.text('Connecting…'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 399));
      expect(
        friendships.requests,
        hasLength(1),
      ); // Initial profile lookup only.
      await tester.pump(const Duration(milliseconds: 1));
      expect(friendships.requests, hasLength(2));
      friendships.requests.last.complete(_friend);
      await tester.idle();
      await tester.pump();
      expect(find.text('Message'), findsOneWidget);
      expect(profiles.sending!.isCompleted, isFalse);
      await tester.tap(find.text('Message'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        tester.widget<MessageDetailPage>(find.byType(MessageDetailPage)).chatId,
        _friend.chatId,
      );
      expect(friendships.requests, hasLength(2));
      profiles.sending!.completeError(TimeoutException('late write response'));
      await tester.pumpWidget(const SizedBox());
      expect(profiles.actions, ['interested']);
    },
  );

  for (final readFails in [false, true]) {
    testWidgets(
      'a slow accept keeps waiting after an inconclusive read; failed=$readFails',
      (tester) async {
        final friendships = _Friendships();
        final profiles = _Profiles()
          ..sending = Completer<void>()
          ..confirmed = _friend;
        await _open(
          tester,
          friendships,
          profiles: profiles,
          notice: (id: 'interest', version: DateTime.utc(2026)),
        );
        friendships.requests.single.complete(null);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Interested'));
        await tester.pump(const Duration(milliseconds: 400));
        if (readFails) {
          friendships.requests.last.completeError(Exception('offline'));
        } else {
          friendships.requests.last.complete(null);
        }
        await tester.pump(const Duration(seconds: 2));
        expect(friendships.requests, hasLength(2));
        expect(find.text('Message'), findsNothing);
        expect(find.text('Connecting…'), findsOneWidget);
        _expectNoChoices();
        profiles.sending!.complete();
        await tester.idle();
        await tester.pump();
        expect(find.text('Message'), findsOneWidget);
        expect(profiles.actions, ['interested']);
      },
    );
  }
}
