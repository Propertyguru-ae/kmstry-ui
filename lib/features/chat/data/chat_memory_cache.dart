import 'dart:async';

import 'chat_detail_model.dart';
import 'chat_list_item_model.dart';
import 'chat_message_model.dart';

/// Session-only snapshots. Network refreshes must not rewind a confirmed send.
class ChatMemoryCache {
  ChatMemoryCache({DateTime Function()? now}) : _now = now ?? DateTime.now;
  static final shared = ChatMemoryCache();
  final DateTime Function() _now;
  final _recentConfirmations = <String, DateTime>{};
  final _details = <String, ChatDetail>{};
  List<ChatListItem>? _chats;
  final _changes = StreamController<String>.broadcast();
  Stream<String> get changes => _changes.stream;
  int generation = 0;

  List<ChatListItem>? get chats => _chats == null ? null : List.of(_chats!);
  ChatDetail? detail(String id) => _details[id];

  void clear() {
    generation++;
    _details.clear();
    _recentConfirmations.clear();
    _chats = null;
  }

  static List<ChatListItem> sorted(Iterable<ChatListItem> rows) =>
      rows.toList()..sort((a, b) {
        final order = (b.lastMessageAt ?? DateTime(1970)).compareTo(
          a.lastMessageAt ?? DateTime(1970),
        );
        return order == 0 ? a.id.compareTo(b.id) : order;
      });

  static List<ChatListItem> reconcileRows(
    List<ChatListItem> fetched,
    List<ChatListItem> current,
  ) {
    final byId = {for (final row in current) row.id: row};
    return sorted(
      fetched.map((row) {
        final local = byId[row.id];
        if (local?.lastMessageAt == null ||
            (row.lastMessageAt != null &&
                !local!.lastMessageAt!.isAfter(row.lastMessageAt!))) {
          return row;
        }
        return ChatListItem(
          id: row.id,
          lastMessageAt: local!.lastMessageAt,
          lastMessagePreview: local.lastMessagePreview,
          unreadCount: row.unreadCount,
          otherUser: row.otherUser,
          user1: row.user1,
          user2: row.user2,
          isBlocked: row.isBlocked,
        );
      }),
    );
  }

  bool _recent(String chatId) {
    final until = _recentConfirmations[chatId];
    return until != null && _now().isBefore(until);
  }

  List<ChatListItem> acceptRows(
    List<ChatListItem> rows, {
    List<ChatListItem>? snapshot,
  }) {
    final before = {
      for (final row in snapshot ?? <ChatListItem>[]) row.id: row,
    };
    _chats = reconcileRows(
      rows,
      (_chats ?? [])
          .where(
            (row) =>
                _recent(row.id) ||
                (snapshot != null && !identical(row, before[row.id])),
          )
          .toList(),
    );
    return chats!;
  }

  void remember(ChatDetail value) {
    // Pending local file paths are owned by the sending page, not persisted.
    final messages =
        value.messages.where((m) => !m.id.startsWith('temp-')).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _details.remove(value.id);
    _details[value.id] = value.copyWith(messages: messages.take(90).toList());
    if (_details.length > 100) _details.remove(_details.keys.first);
  }

  ChatDetail acceptDetail(ChatDetail fetched, ChatDetail? atRequestStart) {
    final current = detail(fetched.id);
    final messages = {for (final m in fetched.messages) m.id: m};
    final before = {
      for (final m in atRequestStart?.messages ?? <ChatMessage>[]) m.id: m,
    };
    DateTime? newest;
    for (final m in fetched.messages) {
      if (newest == null || m.createdAt.isAfter(newest)) newest = m.createdAt;
    }
    for (final m in current?.messages ?? <ChatMessage>[]) {
      if (!identical(before[m.id], m) ||
          (_recent(fetched.id) &&
              newest != null &&
              m.createdAt.isAfter(newest))) {
        messages[m.id] = m;
      }
    }
    // A deletion while this request was in flight must not resurrect a bubble.
    if (current != null) {
      final ids = current.messages.map((m) => m.id).toSet();
      for (final id in before.keys) {
        if (!ids.contains(id)) messages.remove(id);
      }
    }
    final result = fetched.copyWith(messages: messages.values.toList());
    remember(result);
    return detail(fetched.id)!;
  }

  void confirmedMessage(String chatId, ChatMessage message) {
    _recentConfirmations.removeWhere((_, until) => !_now().isBefore(until));
    _recentConfirmations[chatId] = _now().add(const Duration(seconds: 10));
    final previous = detail(chatId);
    remember(
      (previous ?? ChatDetail(id: chatId, messages: [])).copyWith(
        messages: [
          ...?previous?.messages.where(
            (m) =>
                m.id != message.id &&
                (message.clientMessageId == null ||
                    m.clientMessageId != message.clientMessageId),
          ),
          message,
        ],
      ),
    );
    _chats = _chats == null
        ? null
        : sorted(
            _chats!.map((row) {
              if (row.id != chatId ||
                  (row.lastMessageAt?.isAfter(message.createdAt) ?? false)) {
                return row;
              }
              final preview = switch (message.messageType) {
                'image' => '[Photo]',
                'file' => '[Document]',
                'venue' => '[Venue]',
                _ => message.text ?? '',
              };
              return ChatListItem(
                id: row.id,
                lastMessageAt: message.createdAt,
                lastMessagePreview: preview,
                unreadCount: row.unreadCount,
                otherUser: row.otherUser,
                user1: row.user1,
                user2: row.user2,
                isBlocked: row.isBlocked,
              );
            }),
          );
    _changes.add(chatId);
  }

  void removeMessage(String chatId, String messageId) {
    _recentConfirmations.remove(chatId);
    final current = detail(chatId);
    if (current != null) {
      remember(
        current.copyWith(
          messages: current.messages.where((m) => m.id != messageId).toList(),
        ),
      );
    }
  }

  void removeChat(String id) {
    _recentConfirmations.remove(id);
    _details.remove(id);
    _chats?.removeWhere((row) => row.id == id);
  }
}
