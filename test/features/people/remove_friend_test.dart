import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/ui/app_sheet.dart';
import 'package:kmstry_frontend/core/ui/branded_notice.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/features/people/data/match_item_model.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';
import 'package:kmstry_frontend/features/people/data/friendship_changes.dart';
import 'package:kmstry_frontend/features/people/presentation/find_friends_page.dart';
import 'package:kmstry_frontend/features/people/presentation/friends_list_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/profile_preview_page.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_profile_model.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/chat/data/chat_memory_cache.dart';
import 'package:kmstry_frontend/features/chat/data/chat_detail_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_list_item_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_message_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_repository.dart';

final friend = MatchItem(
  matchId: 'match',
  connectionVersion: 'version-1',
  userId: 'bob',
  fullName: 'Bob',
  username: 'bob',
  chatId: 'chat',
);

class FriendsRepo extends MatchRepository {
  final friends = [friend];
  int removals = 0;
  bool fail = false;
  Completer<void>? pending;
  @override
  Future<List<MatchItem>> getMatches() async => List.of(friends);
  @override
  Future<MatchItem?> getFriendship(String userId) async =>
      friends.isEmpty ? null : friend;
  @override
  Future<void> removeFriend(MatchItem match) async {
    removals++;
    if (pending != null) await pending!.future;
    if (fail) throw Exception('offline');
    friends.clear();
    FriendshipChanges.changed(match.userId, active: false);
  }
}

class ProfileRepo extends CheckinRepository {
  @override
  Future<Set<String>> getBlockedUserIds() async => {};
  @override
  Future<PublicUserProfile> getPublicUserProfile(String id) async =>
      PublicUserProfile(
        id: id,
        fullName: 'Bob',
        gender: 'male',
        isVerified: false,
        isPremium: false,
        friendCount: 1,
        followedVenueCount: 0,
      );
}

/// Backend engellenenleri listelemediği için engelleme kişiyi listeden de düşürür.
class SafetyRepo extends CheckinRepository {
  SafetyRepo(this.friends);
  final FriendsRepo friends;
  final blocked = <String>[];
  final reports = <String>[];
  bool failBlock = false;

  @override
  Future<void> blockUser(String targetUserId) async {
    if (failBlock) throw Exception('offline');
    blocked.add(targetUserId);
    friends.friends.clear();
  }

  @override
  Future<void> reportUser({
    String? targetUserId,
    required String reason,
    String? details,
    String? messageId,
    String? storyId,
    String? venueStoryId,
    String? checkinMediaId,
    String? venueId,
    String? venuePhotoId,
    String? venuePhotoUrl,
    String? googlePhotoToken,
    String? venueGalleryItemId,
    String? eventId,
    String? venueOfferId,
    String? venueMenuItemId,
    String? venueBenefitId,
  }) async => reports.add(reason);
}

Future<SafetyRepo> _pumpFriends(
  WidgetTester tester,
  FriendsRepo repo, {
  ThemeData? theme,
}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final safety = SafetyRepo(repo);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: FriendsListPage(repository: repo, checkinRepository: safety),
    ),
  );
  await tester.pumpAndSettle();
  return safety;
}

Future<void> _openMenuRow(WidgetTester tester, String row) async {
  await tester.tap(find.byTooltip('Friend options'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(row));
  await tester.pumpAndSettle();
}

class _FailingFriendsRepo extends MatchRepository {
  @override
  Future<List<MatchItem>> getMatches() async => throw Exception('offline');
}

class RemovalApi extends ApiClient {
  String? deletedPath;
  bool fail = false;
  final removal = Completer<dynamic>();
  final getResult = Completer<dynamic>();
  @override
  Future<dynamic> delete(String path, {Map<String, String>? headers}) {
    deletedPath = path;
    return fail ? Future.error(Exception('offline')) : removal.future;
  }

  @override
  Future<dynamic> get(
    String path, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 10),
  }) => getResult.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    ChatMemoryCache.shared.clear();
    ProfilePreviewPage.clearActionStateCache();
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final dark in [false, true]) {
      testWidgets(
        '$platform ${dark ? 'dark' : 'light'} cancel then remove from Friends',
        (tester) async {
          final repo = FriendsRepo();
          tester.view.physicalSize = const Size(393, 852);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MaterialApp(
              theme: (dark ? AppTheme.darkTheme : AppTheme.lightTheme).copyWith(
                platform: platform,
              ),
              home: FriendsListPage(repository: repo),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Friend options'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Remove friend'));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('They won’t be notified.'),
            findsOneWidget,
          );
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(repo.removals, 0);
          expect(find.text('Bob'), findsOneWidget);
          await tester.tap(find.byTooltip('Friend options'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Remove friend'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Remove friend'));
          await tester.pumpAndSettle();
          expect(repo.removals, 1);
          expect(find.text('No friends yet'), findsOneWidget);
          expect(
            find.widgetWithText(BrandedNoticeCard, 'Friend removed'),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('network failure preserves friend and offers a retry', (
    tester,
  ) async {
    final repo = FriendsRepo()..fail = true;
    await tester.pumpWidget(
      MaterialApp(home: FriendsListPage(repository: repo)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Friend options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove friend'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove friend'));
    await tester.pumpAndSettle();
    expect(find.text('Bob'), findsOneWidget);
    expect(
      find.widgetWithText(BrandedNoticeCard, 'Could not remove friend'),
      findsOneWidget,
    );
    expect(find.byTooltip('Friend options'), findsOneWidget);
  });

  testWidgets(
    'profile menu removes friend and does not restore stale matched hint',
    (tester) async {
      final repo = FriendsRepo();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: ProfilePreviewPage(
            userId: 'bob',
            userName: 'Bob',
            isMatchedHint: true,
            checkinRepository: ProfileRepo(),
            matchRepository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove friend'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove friend'));
      await tester.pumpAndSettle();
      expect(repo.removals, 1);
      expect(
        find.widgetWithText(BrandedNoticeCard, 'Friend removed'),
        findsOneWidget,
      );
      expect(
        ProfilePreviewPage.peekCachedActionState('bob'),
        isNot(ProfileActionState.matched),
      );
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Remove friend'), findsNothing);
      expect(find.text('Report'), findsOneWidget);
      expect(find.text('Block'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'removal includes connection version and emits only after confirmed success',
    () async {
      final api = RemovalApi();
      final repo = MatchRepository(
        api: api,
        tokenProvider: () async => 'token',
      );
      final revision = FriendshipChanges.revision;
      final removing = repo.removeFriend(friend);
      await Future<void>.delayed(Duration.zero);
      expect(api.deletedPath, '/matches/match?connectionVersion=version-1');
      expect(FriendshipChanges.revision, revision);
      api.removal.complete({'success': true});
      await removing;
      expect(FriendshipChanges.revision, revision + 1);
    },
  );

  test(
    'friendship invalidation preserves messages but prevents a late fetch from reopening chat',
    () async {
      final api = RemovalApi();
      final cache = ChatMemoryCache();
      final message = ChatMessage.fromJson({
        'id': 'm',
        'message_type': 'text',
        'text': 'History',
        'created_at': '2026-11-03T00:00:00Z',
      });
      cache.remember(
        ChatDetail(
          id: 'chat',
          messages: [message],
          otherUser: ChatListItemUser(id: 'bob'),
        ),
      );
      cache.acceptRows([
        ChatListItem(
          id: 'chat',
          otherUser: ChatListItemUser(id: 'bob'),
        ),
      ]);
      final repo = ChatRepository(
        api: api,
        cache: cache,
        tokenProvider: () async => 'token',
      );
      final staleFetch = repo.getChat('chat');
      await Future<void>.delayed(Duration.zero);
      cache.invalidateFriendship('bob');
      expect(cache.detail('chat')!.messages.single.text, 'History');
      expect(cache.chats!.single.canSendMessages, false);
      api.getResult.complete({
        'id': 'chat',
        'is_active': true,
        'can_send_messages': true,
        'messages': [],
      });
      expect((await staleFetch).canSendMessages, false);
      expect(cache.detail('chat')!.canSendMessages, false);
    },
  );

  test(
    'an open recipient list excludes removed friend and other conversations stay usable',
    () {
      final cache = ChatMemoryCache();
      final bob = ChatListItem(
        id: 'bob-chat',
        otherUser: ChatListItemUser(id: 'bob'),
      );
      final other = ChatListItem(
        id: 'other-chat',
        otherUser: ChatListItemUser(id: 'other'),
      );
      cache.acceptRows([bob, other]);
      cache.remember(
        ChatDetail(id: 'other-chat', messages: [], otherUser: other.otherUser),
      );
      final repo = ChatRepository(cache: cache);
      final session = cache.generation;
      cache.invalidateFriendship('bob');
      expect(repo.canMessage(bob), false); // Previously fetched popup row.
      expect(repo.canMessage(other), true);
      expect(cache.detail('other-chat')!.canSendMessages, true);
      expect(cache.generation, session); // Do not cancel another chat's upload.
    },
  );

  testWidgets('double tap confirms only one removal request', (tester) async {
    final repo = FriendsRepo()..pending = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(home: FriendsListPage(repository: repo)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Friend options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove friend'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove friend'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.removals, 1);
    expect(find.byTooltip('Friend options'), findsNothing);
    repo.pending!.complete();
    await tester.pumpAndSettle();
    expect(repo.removals, 1);
    expect(find.text('No friends yet'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets('friend menu names the person and lists three actions; '
        'dark=$dark', (tester) async {
      await _pumpFriends(
        tester,
        FriendsRepo(),
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      );
      // Message comes first; the menu sits at the far right of the row.
      expect(
        tester.getCenter(find.byTooltip('Message')).dx,
        lessThan(tester.getCenter(find.byTooltip('Friend options')).dx),
      );
      await tester.tap(find.byTooltip('Friend options'));
      await tester.pumpAndSettle();
      expect(find.text('Bob'), findsNWidgets(2));
      expect(find.text('@bob'), findsNWidgets(2));
      final rows = find.byType(AppSheetRow);
      expect(rows, findsNWidgets(3));
      expect(
        [for (final row in tester.widgetList<AppSheetRow>(rows)) row.title],
        ['Remove friend', 'Report', 'Block'],
      );
      expect(find.text('View profile'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cancelling Block changes nothing', (tester) async {
    final repo = FriendsRepo();
    final safety = await _pumpFriends(tester, repo);
    await _openMenuRow(tester, 'Block');
    expect(find.text('Block this user?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(safety.blocked, isEmpty);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.byTooltip('Friend options'), findsOneWidget);
  });

  testWidgets('Block removes the friend and tells the rest of the app', (
    tester,
  ) async {
    final repo = FriendsRepo();
    final safety = await _pumpFriends(tester, repo);
    final revision = FriendshipChanges.revision;
    await _openMenuRow(tester, 'Block');
    await tester.tap(find.text('Block user'));
    await tester.pumpAndSettle();
    expect(safety.blocked, ['bob']);
    expect(repo.removals, 0);
    expect(FriendshipChanges.revision, revision + 1);
    expect(find.text('No friends yet'), findsOneWidget);
    expect(
      find.widgetWithText(BrandedNoticeCard, 'User blocked'),
      findsOneWidget,
    );
    expect(
      find.text('You can unblock them in Settings → Blocked users.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed Block keeps the friend and says so', (tester) async {
    final repo = FriendsRepo();
    final safety = await _pumpFriends(tester, repo);
    safety.failBlock = true;
    final revision = FriendshipChanges.revision;
    await _openMenuRow(tester, 'Block');
    await tester.tap(find.text('Block user'));
    await tester.pumpAndSettle();
    expect(FriendshipChanges.revision, revision);
    expect(find.text('Bob'), findsOneWidget);
    expect(
      find.widgetWithText(BrandedNoticeCard, 'Could not block user'),
      findsOneWidget,
    );
    expect(find.text('User blocked'), findsNothing);
    expect(find.byTooltip('Friend options'), findsOneWidget);
  });

  testWidgets('Report also blocks, so the friend leaves the list', (
    tester,
  ) async {
    final repo = FriendsRepo();
    final safety = await _pumpFriends(tester, repo);
    await _openMenuRow(tester, 'Report');
    expect(find.text('What do you want to report?'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Scam or fraud'),
      100,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(find.text('Scam or fraud'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scam or fraud'));
    await tester.pump();
    await tester.tap(find.text('Report & block'));
    await tester.pumpAndSettle();
    expect(safety.reports, ['SPAM_SCAM']);
    expect(safety.blocked, ['bob']);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('No friends yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling Report keeps the friend', (tester) async {
    final repo = FriendsRepo();
    final safety = await _pumpFriends(tester, repo);
    await _openMenuRow(tester, 'Report');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(safety.reports, isEmpty);
    expect(safety.blocked, isEmpty);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.byTooltip('Friend options'), findsOneWidget);
  });

  group('no friends', () {
    final cta = find.widgetWithText(PrimaryButton, 'Find friends');

    for (final dark in [false, true]) {
      testWidgets('offers only the Find friends CTA; dark=$dark', (
        tester,
      ) async {
        await _pumpFriends(
          tester,
          FriendsRepo()..friends.clear(),
          theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        );
        expect(find.text('No friends yet'), findsOneWidget);
        expect(cta, findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(find.textContaining('Sort by'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the CTA opens Find Friends and the list reloads on return', (
      tester,
    ) async {
      final repo = FriendsRepo()..friends.clear();
      await _pumpFriends(tester, repo);
      await tester.tap(cta);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(FindFriendsPage), findsOneWidget);

      repo.friends.add(friend);
      Navigator.of(tester.element(find.byType(FindFriendsPage))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(FindFriendsPage), findsNothing);
      expect(find.text('Bob'), findsOneWidget);
      expect(cta, findsNothing);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('fits a small screen with large text', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: FriendsListPage(repository: FriendsRepo()..friends.clear()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(cta);
      await tester.pump();
      expect(cta.hitTestable(), findsOneWidget);
    });

    testWidgets('a failed load offers Retry, not the CTA', (tester) async {
      final repo = _FailingFriendsRepo();
      await tester.pumpWidget(
        MaterialApp(home: FriendsListPage(repository: repo)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Could not load friends.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(cta, findsNothing);
      expect(find.text('No friends yet'), findsNothing);
    });

    testWidgets('friends keep search and sort; a search miss has no CTA', (
      tester,
    ) async {
      await _pumpFriends(tester, FriendsRepo());
      expect(cta, findsNothing);
      expect(find.textContaining('Sort by'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'nobody');
      await tester.pump();
      expect(find.text('No friends match "nobody".'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(cta, findsNothing);
    });

    testWidgets('removing the last friend during a search shows the CTA', (
      tester,
    ) async {
      final repo = FriendsRepo();
      await _pumpFriends(tester, repo);
      await tester.enterText(find.byType(TextField), 'Bo');
      await tester.pump();
      await _openMenuRow(tester, 'Remove friend');
      await tester.tap(find.text('Remove friend'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No friends match'), findsNothing);
      expect(find.text('No friends yet'), findsOneWidget);
      expect(cta, findsOneWidget);
    });
  });

  group('Sort by', () {
    FriendsRepo twoFriends() => FriendsRepo()
      ..friends.add(
        MatchItem(
          matchId: 'match-2',
          connectionVersion: 'version-1',
          userId: 'older',
          fullName: 'Older Friend',
          chatId: 'chat-2',
        ),
      );

    Finder checkIn(String label) => find.descendant(
      of: find.widgetWithText(AppSheetRow, label),
      matching: find.byIcon(Icons.check_rounded),
    );

    for (final dark in [false, true]) {
      testWidgets('uses the standard sheet and marks the choice; dark=$dark', (
        tester,
      ) async {
        await _pumpFriends(
          tester,
          twoFriends(),
          theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        );
        await tester.tap(find.byTooltip('Sort'));
        await tester.pumpAndSettle();
        expect(find.text('Sort by'), findsOneWidget);
        expect(
          tester.widget<BottomSheet>(find.byType(BottomSheet)).backgroundColor,
          dark ? const Color(0xFF121A2B) : Colors.white,
        );
        expect(
          [
            for (final row in tester.widgetList<AppSheetRow>(
              find.byType(AppSheetRow),
            ))
              row.title,
          ],
          ['Latest', 'Earliest'],
        );
        expect(find.text('Newest friends first'), findsOneWidget);
        expect(find.text('Oldest friends first'), findsOneWidget);
        expect(checkIn('Latest'), findsOneWidget);
        expect(checkIn('Earliest'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('choosing reorders the list and moves the tick', (
      tester,
    ) async {
      await _pumpFriends(tester, twoFriends());
      expect(
        tester.getTopLeft(find.text('Bob')).dy,
        lessThan(tester.getTopLeft(find.text('Older Friend')).dy),
      );
      await tester.tap(find.byTooltip('Sort'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Earliest'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        tester.getTopLeft(find.text('Older Friend')).dy,
        lessThan(tester.getTopLeft(find.text('Bob')).dy),
      );
      await tester.tap(find.byTooltip('Sort'));
      await tester.pumpAndSettle();
      expect(checkIn('Earliest'), findsOneWidget);
      expect(checkIn('Latest'), findsNothing);
    });
  });
}
