import 'chat_message_model.dart';
import 'chat_list_item_model.dart';

/// Response of GET /chats/:id — chat + messages (created_at DESC from backend).
class ChatDetail {
  final String id;
  final List<ChatMessage> messages;
  final ChatListItemUser? otherUser;
  final List<ChatListItemUser>? participants;
  final bool isActive;

  ChatDetail({
    required this.id,
    required this.messages,
    this.otherUser,
    this.participants,
    this.isActive = true,
  });

  ChatDetail copyWith({
    String? id,
    List<ChatMessage>? messages,
    ChatListItemUser? otherUser,
    List<ChatListItemUser>? participants,
    bool? isActive,
  }) {
    return ChatDetail(
      id: id ?? this.id,
      messages: messages ?? this.messages,
      otherUser: otherUser ?? this.otherUser,
      participants: participants ?? this.participants,
      isActive: isActive ?? this.isActive,
    );
  }

  factory ChatDetail.fromJson(Map<String, dynamic> json) {
    final messagesRaw = json['messages'] as List? ?? [];
    final list = messagesRaw
        .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
        .toList();

    ChatListItemUser? parseUser(dynamic v) {
      if (v == null || v is! Map<String, dynamic>) return null;
      return ChatListItemUser.fromJson(v);
    }

    final otherUserRaw = json['other_user'] ?? json['otherUser'];
    final participantsRaw = json['participants'] as List?;
    List<ChatListItemUser>? participantsList;
    if (participantsRaw != null) {
      participantsList = participantsRaw
          .map((e) => ChatListItemUser.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return ChatDetail(
      id: json['id'] as String,
      messages: list,
      otherUser: parseUser(otherUserRaw),
      participants: participantsList,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  /// Other participant for display (other_user or first of participants excluding current).
  ChatListItemUser? get displayOtherUser {
    if (otherUser != null) return otherUser;
    if (participants != null && participants!.isNotEmpty) {
      return participants!.first;
    }
    return null;
  }
}
