import 'package:firebase_core/firebase_core.dart';
// Firebase's official platform-channel test adapter; no real project/network.
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/ui/app_sheet.dart';
import 'package:kmstry_frontend/core/ui/branded_notice.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
import 'package:kmstry_frontend/features/chat/data/chat_detail_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_list_item_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_memory_cache.dart';
import 'package:kmstry_frontend/features/chat/data/chat_repository.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/messageDetail/presentation/message_detail.dart';
import 'package:kmstry_frontend/features/people/data/friendship_changes.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Chats extends ChatRepository {
  _Chats() : super(cache: ChatMemoryCache());
  bool blockedByMe = false;

  @override
  Future<ChatDetail> getChat(
    String chatId, {
    bool markRead = true,
    String? beforeId,
    int? take,
  }) async => ChatDetail(
    id: 'chat',
    messages: const [],
    otherUser: ChatListItemUser(id: 'other'),
    isBlocked: blockedByMe,
    blockedByMe: blockedByMe,
  );

  @override
  Future<void> markChatRead(String chatId) async {}
}

class _Checkins extends CheckinRepository {
  _Checkins(this.chats);
  final _Chats chats;
  final blocked = <String>[];
  final unblocked = <String>[];
  bool fail = false;

  @override
  Future<void> blockUser(String targetUserId) async {
    if (fail) throw Exception('offline');
    blocked.add(targetUserId);
    chats.blockedByMe = true;
  }

  @override
  Future<void> unblockUser(String targetUserId) async {
    if (fail) throw Exception('offline');
    unblocked.add(targetUserId);
    chats.blockedByMe = false;
  }
}

/// The header shows a spinner while a popup is open, so nothing ever settles.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _openMenu(
  WidgetTester tester,
  _Chats chats,
  _Checkins checkins,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MessageDetailPage(
        chatId: 'chat',
        otherUserId: 'other',
        otherName: 'Other User',
        otherPhotoUrl: '',
        repository: chats,
        checkinRepository: checkins,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Conversation options'));
  await _settle(tester);
}

Future<void> _blockFromMenu(
  WidgetTester tester,
  _Chats chats,
  _Checkins checkins,
) async {
  await _openMenu(tester, chats, checkins);
  await tester.tap(find.text('Block'));
  await _settle(tester);
  expect(find.text('Block this user?'), findsOneWidget);
  await tester.tap(find.text('Block user'));
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async => Firebase.initializeApp());
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('the chat menu is the standard sheet with Report and Block', (
    tester,
  ) async {
    final chats = _Chats();
    await _openMenu(tester, chats, _Checkins(chats));
    expect(find.byType(PopupMenuItem<String>), findsNothing);
    expect(
      [
        for (final row in tester.widgetList<AppSheetRow>(
          find.byType(AppSheetRow),
        ))
          row.title,
      ],
      ['Report', 'Block'],
    );
    await tester.tap(find.text('Report'));
    await _settle(tester);
    expect(find.text('What do you want to report?'), findsOneWidget);
    expect(find.byType(AppSheetRow), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('blocking from a chat shows the standard card', (tester) async {
    final chats = _Chats();
    final checkins = _Checkins(chats);
    final revision = FriendshipChanges.revision;
    await _blockFromMenu(tester, chats, checkins);
    expect(checkins.blocked, ['other']);
    expect(FriendshipChanges.revision, revision + 1);
    expect(
      find.widgetWithText(BrandedNoticeCard, 'User blocked'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a failed block from a chat says so and changes nothing', (
    tester,
  ) async {
    final chats = _Chats();
    final checkins = _Checkins(chats)..fail = true;
    final revision = FriendshipChanges.revision;
    await _blockFromMenu(tester, chats, checkins);
    expect(FriendshipChanges.revision, revision);
    expect(
      find.widgetWithText(BrandedNoticeCard, 'Could not block user'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(BrandedNoticeCard, 'User blocked'),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a blocked chat offers Unblock, then Block again', (
    tester,
  ) async {
    final chats = _Chats()..blockedByMe = true;
    final checkins = _Checkins(chats);
    await _openMenu(tester, chats, checkins);
    expect(find.text('Block'), findsNothing);
    await tester.tap(find.text('Unblock'));
    await _settle(tester);
    expect(find.text('Unblock this user?'), findsOneWidget);
    await tester.tap(find.widgetWithText(PrimaryButton, 'Unblock'));
    await _settle(tester);
    expect(checkins.unblocked, ['other']);
    expect(
      find.widgetWithText(BrandedNoticeCard, 'User unblocked'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Conversation options'));
    await _settle(tester);
    expect(find.text('Block'), findsOneWidget);
    expect(find.text('Unblock'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
