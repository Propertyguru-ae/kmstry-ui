/// Model for GET /chats list item.
/// Backend returns user1 + user2 (Prisma include); "other" is the one that isn't current user.
class ChatListItem {
  final String id;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final String? lastMessagePreview;
  final ChatListItemUser? otherUser;
  final ChatListItemUser? user1;
  final ChatListItemUser? user2;

  ChatListItem({
    required this.id,
    this.lastMessageAt,
    this.unreadCount = 0,
    this.lastMessagePreview,
    this.otherUser,
    this.user1,
    this.user2,
  });

  /// The other participant (for display). Prefer [otherUser]; else derive from user1/user2 by [currentUserId].
  ChatListItemUser? getDisplayUser(String? currentUserId) {
    if (otherUser != null) return otherUser;
    if (currentUserId == null) return user1 ?? user2;
    if (user1?.id == currentUserId) return user2;
    return user1;
  }

  factory ChatListItem.fromJson(Map<String, dynamic> json) {
    DateTime? parseLastMessageAt(dynamic v) {
      if (v == null) return null;
      if (v is String) {
        try {
          return DateTime.parse(v);
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    ChatListItemUser? parseUser(dynamic v) {
      if (v == null || v is! Map<String, dynamic>) return null;
      return ChatListItemUser.fromJson(v);
    }

    final lastMessageAtRaw =
        json['last_message_at'] ?? json['lastMessageAt'];
    final unreadCountRaw = json['unread_count'] ?? json['unreadCount'] ?? 0;
    final lastPreview =
        json['last_message_preview'] as String? ??
        json['lastMessagePreview'] as String?;

    final u1 = parseUser(json['user1']);
    final u2 = parseUser(json['user2']);
    final otherUserRaw = json['other_user'] ?? json['otherUser'];
    final other = parseUser(otherUserRaw);

    if (otherUserRaw == null && json['participants'] != null) {
      final participants = json['participants'] as List?;
      if (participants != null && participants.isNotEmpty) {
        final first = participants.first;
        if (first is Map<String, dynamic>) {
          return ChatListItem(
            id: json['id'] as String,
            lastMessageAt: parseLastMessageAt(lastMessageAtRaw),
            unreadCount: (unreadCountRaw is int)
                ? unreadCountRaw
                : int.tryParse(unreadCountRaw.toString()) ?? 0,
            lastMessagePreview: lastPreview,
            otherUser: ChatListItemUser.fromJson(first),
            user1: u1,
            user2: u2,
          );
        }
      }
    }

    return ChatListItem(
      id: json['id'] as String,
      lastMessageAt: parseLastMessageAt(lastMessageAtRaw),
      unreadCount: (unreadCountRaw is int)
          ? unreadCountRaw
          : int.tryParse(unreadCountRaw.toString()) ?? 0,
      lastMessagePreview: lastPreview,
      otherUser: other,
      user1: u1,
      user2: u2,
    );
  }
}

class ChatListItemUser {
  final String id;
  final String? fullName;
  final String? photo;

  ChatListItemUser({
    required this.id,
    this.fullName,
    this.photo,
  });

  factory ChatListItemUser.fromJson(Map<String, dynamic> json) {
    return ChatListItemUser(
      id: json['id'] as String,
      fullName: json['full_name'] as String? ?? json['fullName'] as String?,
      photo: json['photo'] as String? ?? json['photoUrl'] as String?,
    );
  }
}
