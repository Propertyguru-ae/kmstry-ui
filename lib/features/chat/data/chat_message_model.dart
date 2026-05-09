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
  final DateTime? deletedAt;
  final DateTime? readAt;
  final String? clientMessageId;

  ChatMessage({
    required this.id,
    required this.messageType,
    this.text,
    this.imageUrl,
    required this.createdAt,
    this.senderId,
    this.isMe,
    this.editedAt,
    this.deletedAt,
    this.readAt,
    this.clientMessageId,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at'] ?? json['createdAt'];
    final editedAtRaw = json['edited_at'] ?? json['editedAt'];
    final deletedAtRaw = json['deleted_at'] ?? json['deletedAt'];
    final readAtRaw = json['read_at'] ?? json['readAt'];

    return ChatMessage(
      id: (json['id'] ?? '').toString(),
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
      deletedAt: _parseDateTime(deletedAtRaw),
      readAt: _parseDateTime(readAtRaw),
      clientMessageId:
          (json['client_message_id'] ?? json['clientMessageId'])?.toString(),
    );
  }

  static DateTime? _parseDateTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) return DateTime.tryParse(raw);
    return DateTime.tryParse(raw.toString());
  }

  /// Use when backend does not return is_me. Call with current user id.
  bool isSentByMe(String? currentUserId) {
    if (isMe != null) return isMe!;
    if (currentUserId == null || senderId == null) return false;
    return senderId == currentUserId;
  }

  ChatMessage copyWith({
    String? id,
    String? messageType,
    String? text,
    String? imageUrl,
    DateTime? createdAt,
    String? senderId,
    bool? isMe,
    DateTime? editedAt,
    DateTime? deletedAt,
    DateTime? readAt,
    String? clientMessageId,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      messageType: messageType ?? this.messageType,
      text: text ?? this.text,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
      senderId: senderId ?? this.senderId,
      isMe: isMe ?? this.isMe,
      editedAt: editedAt ?? this.editedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      readAt: readAt ?? this.readAt,
      clientMessageId: clientMessageId ?? this.clientMessageId,
    );
  }
}
