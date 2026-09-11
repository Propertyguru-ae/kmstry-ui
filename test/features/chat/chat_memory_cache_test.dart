import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/chat/data/chat_memory_cache.dart';
import 'package:kmstry_frontend/features/chat/data/chat_detail_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_list_item_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_message_model.dart';

ChatMessage message(
  String id,
  int minute, {
  String type = 'text',
  String? clientId,
}) => ChatMessage(
  id: id,
  messageType: type,
  text: id,
  createdAt: DateTime.utc(2026, 9, 9, 10, minute),
  clientMessageId: clientId,
  imageUrl: type == 'image' ? 'https://example.com/signed-image' : null,
);
ChatDetail detail(List<ChatMessage> messages) =>
    ChatDetail(id: 'chat', messages: messages);

void main() {
  late ChatMemoryCache cache;
  setUp(() => cache = ChatMemoryCache());

  test('send protection expires so authoritative deletions are not hidden', () {
    var now = DateTime.utc(2026, 9, 9);
    cache = ChatMemoryCache(now: () => now);
    cache.acceptRows([ChatListItem(id: 'chat')]);
    cache.confirmedMessage('chat', message('new', 5));
    now = now.add(const Duration(seconds: 11));
    final refreshed = cache.acceptDetail(
      detail([message('old', 1)]),
      cache.detail('chat'),
    );
    expect(refreshed.messages.map((m) => m.id), ['old']);
    final rows = cache.acceptRows([
      ChatListItem(id: 'chat', lastMessagePreview: 'old'),
    ]);
    expect(rows.single.lastMessagePreview, 'old');
  });

  test('confirmed image is immediately available when reopening the chat', () {
    cache.remember(detail([message('old', 1)]));
    cache.confirmedMessage('chat', message('photo', 5, type: 'image'));
    expect(cache.detail('chat')!.messages.first.id, 'photo');
    expect(cache.detail('chat')!.messages.first.imageUrl, isNotNull);
  });

  test(
    'confirmed send moves a lower conversation to top without a GET',
    () async {
      cache.acceptRows([
        ChatListItem(id: 'other', lastMessageAt: message('a', 3).createdAt),
        ChatListItem(
          id: 'chat',
          lastMessageAt: message('b', 1).createdAt,
          isBlocked: true,
        ),
      ]);
      final event = cache.changes.first;
      cache.confirmedMessage('chat', message('photo', 5, type: 'image'));
      expect(await event, 'chat');
      expect(cache.chats!.first.id, 'chat');
      expect(cache.chats!.first.lastMessagePreview, '[Photo]');
      expect(cache.chats!.first.isBlocked, isTrue);
    },
  );

  test(
    'late list response cannot roll back a sent message preview or order',
    () {
      final rows = [
        ChatListItem(id: 'chat', lastMessageAt: message('old', 1).createdAt),
      ];
      cache.acceptRows(rows);
      cache.confirmedMessage('chat', message('new', 5));
      final result = cache.acceptRows(rows);
      expect(result.single.lastMessagePreview, 'new');
      expect(result.single.lastMessageAt, message('new', 5).createdAt);
    },
  );

  test('network details cannot erase a send completed during the request', () {
    cache.remember(detail([message('old', 1)]));
    final snapshot = cache.detail('chat');
    cache.confirmedMessage('chat', message('new', 5));
    final result = cache.acceptDetail(detail([message('old', 1)]), snapshot);
    expect(result.messages.map((m) => m.id), ['new', 'old']);
  });

  test('reopening keeps a confirmed message newer than a stale response', () {
    cache.confirmedMessage('chat', message('new', 5));
    final result = cache.acceptDetail(
      detail([message('old', 1)]),
      cache.detail('chat'),
    );
    expect(result.messages.first.id, 'new');
  });

  test(
    'duplicate acknowledgement/realtime messages do not duplicate bubbles',
    () {
      cache.confirmedMessage('chat', message('new', 5, clientId: 'client-1'));
      cache.confirmedMessage('chat', message('new', 5, clientId: 'client-1'));
      expect(cache.detail('chat')!.messages.length, 1);
    },
  );

  test(
    'old out-of-order acknowledgement cannot move a conversation backwards',
    () {
      cache.acceptRows([ChatListItem(id: 'chat')]);
      cache.confirmedMessage('chat', message('latest', 5));
      cache.confirmedMessage('chat', message('older', 2));
      expect(cache.chats!.single.lastMessagePreview, 'latest');
      expect(cache.detail('chat')!.messages.first.id, 'latest');
    },
  );

  test('delete during refresh does not resurrect a message', () {
    final old = message('old', 1);
    cache.remember(detail([old]));
    final snapshot = cache.detail('chat');
    cache.removeMessage('chat', 'old');
    expect(cache.acceptDetail(detail([old]), snapshot).messages, isEmpty);
  });

  test('fresh server edit and blocked state replace an unchanged snapshot', () {
    final old = message('old', 1);
    cache.remember(detail([old]));
    final result = cache.acceptDetail(
      detail([
        old.copyWith(text: 'edited'),
      ]).copyWith(isBlocked: true, canSendMessages: false),
      cache.detail('chat'),
    );
    expect(result.messages.single.text, 'edited');
    expect(result.canSendMessages, isFalse);
    expect(result.isBlocked, isTrue);
  });

  test('banned recipient keeps history visible and disables the composer', () {
    final result = ChatDetail.fromJson({
      'id': 'chat',
      'messages': [
        {
          'id': 'old-message',
          'message_type': 'text',
          'text': 'history remains',
          'created_at': '2026-09-11T09:00:00.000Z',
        },
      ],
      'is_active': true,
      'other_user_unavailable': true,
      'can_send_messages': false,
    });

    expect(result.messages, hasLength(1));
    expect(result.otherUserUnavailable, isTrue);
    expect(result.canSendMessages, isFalse);
  });

  test('cache excludes pending local files and stays bounded', () {
    cache.remember(
      detail([
        message('temp-local', 1, type: 'image'),
        for (var i = 0; i < 120; i++) message('message-$i', i),
      ]),
    );
    expect(cache.detail('chat')!.messages.length, 90);
    expect(
      cache.detail('chat')!.messages.any((m) => m.id.startsWith('temp-')),
      isFalse,
    );
    expect(cache.detail('chat')!.messages.first.id, 'message-119');
  });

  test(
    'session reset removes user data and invalidates in-flight generations',
    () {
      cache.acceptRows([ChatListItem(id: 'chat')]);
      cache.confirmedMessage('chat', message('new', 5));
      final generation = cache.generation;
      cache.clear();
      expect(cache.chats, isNull);
      expect(cache.detail('chat'), isNull);
      expect(cache.generation, isNot(generation));
    },
  );

  test('search membership and server unread/block updates are preserved', () {
    final result = ChatMemoryCache.reconcileRows(
      [ChatListItem(id: 'chat', unreadCount: 0, isBlocked: true)],
      [
        ChatListItem(id: 'other'),
        ChatListItem(
          id: 'chat',
          unreadCount: 3,
          lastMessageAt: message('new', 5).createdAt,
          lastMessagePreview: 'new',
        ),
      ],
    );
    expect(result.map((r) => r.id), ['chat']);
    expect(result.single.unreadCount, 0);
    expect(result.single.isBlocked, isTrue);
  });
}
