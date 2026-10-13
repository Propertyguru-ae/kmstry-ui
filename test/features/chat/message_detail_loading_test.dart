import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
// Firebase's official platform-channel test adapter; no real project/network.
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/chat/data/chat_detail_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_memory_cache.dart';
import 'package:kmstry_frontend/features/chat/data/chat_message_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_repository.dart';
import 'package:kmstry_frontend/features/messageDetail/presentation/message_detail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Repo extends ChatRepository {
  _Repo() : super(cache: ChatMemoryCache());
  final detail = Completer<ChatDetail>();
  final read = Completer<void>();
  final readFlags = <bool>[];
  int readCalls = 0;
  @override
  Future<ChatDetail> getChat(
    String chatId, {
    bool markRead = true,
    String? beforeId,
    int? take,
  }) {
    readFlags.add(markRead);
    return detail.future;
  }

  @override
  Future<void> markChatRead(String chatId) {
    readCalls++;
    return read.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async => Firebase.initializeApp());
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'cold chat displays messages while read receipt is still pending',
    (tester) async {
      final repo = _Repo();
      await tester.pumpWidget(
        MaterialApp(
          home: MessageDetailPage(
            chatId: 'chat',
            otherUserId: 'other',
            otherName: 'Other User',
            otherPhotoUrl: '',
            repository: repo,
          ),
        ),
      );
      await tester.pump();
      expect(repo.readFlags, [false]);
      expect(repo.readCalls, 0);
      expect(
        find.byKey(const ValueKey('chat-opening-placeholder')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      repo.detail.complete(
        ChatDetail(
          id: 'chat',
          messages: [
            ChatMessage.fromJson({
              'id': 'message',
              'sender_id': 'other',
              'message_type': 'text',
              'text': 'First message',
              'created_at': DateTime.now().toIso8601String(),
            }),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('First message'), findsOneWidget);
      expect(repo.readCalls, 1);
      expect(repo.read.isCompleted, false);
      repo.read.completeError(
        StateError('read receipt temporarily unavailable'),
      );
      await tester.pumpAndSettle();
      expect(find.text('First message'), findsOneWidget);
      expect(find.text('Could not load chat'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'leaving before initial response does not mark unseen chat as read',
    (tester) async {
      final repo = _Repo();
      await tester.pumpWidget(
        MaterialApp(
          home: MessageDetailPage(
            chatId: 'chat',
            otherUserId: 'other',
            otherName: 'Other User',
            otherPhotoUrl: '',
            repository: repo,
          ),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      repo.detail.complete(ChatDetail(id: 'chat', messages: []));
      await tester.pump();
      expect(repo.readCalls, 0);
    },
  );
}
