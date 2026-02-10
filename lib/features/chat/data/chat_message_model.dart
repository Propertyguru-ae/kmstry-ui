/// Single message from GET /chats/:id or POST response.
/// Backend: deleted_at IS NULL shown; is_me may be absent -> compute with sender_id == currentUserId.
class ChatMessage {
  final String id;
  final String messageType; // "text" | "image"
  final String? text;
  final String? imageUrl;
  final DateTime createdAt;
  final String? senderId;
  final bool? isMe; // from backend if present; otherwise compute in UI
  final DateTime? editedAt;

  ChatMessage({
    required this.id,
    required this.messageType,
    this.text,
    this.imageUrl,
    required this.createdAt,
    this.senderId,
    this.isMe,
    this.editedAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at'] ?? json['createdAt'];
    final editedAtRaw = json['edited_at'] ?? json['editedAt'];

    return ChatMessage(
      id: json['id'] as String,
      messageType:
          json['message_type'] as String? ?? json['messageType'] as String? ?? 'text',
      text: json['text'] as String?,
      imageUrl: json['image_url'] as String? ?? json['imageUrl'] as String?,
      createdAt: createdAtRaw != null
          ? (createdAtRaw is String
              ? DateTime.parse(createdAtRaw)
              : DateTime.tryParse(createdAtRaw.toString()) ?? DateTime.now())
          : DateTime.now(),
      senderId: json['sender_id'] as String? ?? json['senderId'] as String?,
      isMe: json['is_me'] as bool? ?? json['isMe'] as bool?,
      editedAt: editedAtRaw != null && editedAtRaw is String
          ? DateTime.tryParse(editedAtRaw)
          : null,
    );
  }

  /// Use when backend does not return is_me. Call with current user id.
  bool isSentByMe(String? currentUserId) {
    if (isMe != null) return isMe!;
    if (currentUserId == null || senderId == null) return false;
    return senderId == currentUserId;
  }
}
