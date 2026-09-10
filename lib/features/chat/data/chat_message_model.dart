import '../../../core/media/media_reference.dart';
import '../../venue/data/venue_model.dart';

/// Tek kullanıcı reaction'ı (WhatsApp tarzı: kullanıcı başına tek emoji).
class MessageReaction {
  final String userId;
  final String emoji;

  const MessageReaction({required this.userId, required this.emoji});

  factory MessageReaction.fromJson(Map<String, dynamic> json) {
    return MessageReaction(
      userId: (json['user_id'] ?? json['userId'] ?? '').toString(),
      emoji: (json['emoji'] ?? '').toString(),
    );
  }
}

/// Single message from GET /chats/:id or POST response.
/// Backend: deleted_at IS NULL shown; is_me may be absent -> compute with sender_id == currentUserId.
class ChatMessage {
  final String id;
  final String messageType; // "text" | "image" | "file" | "venue"
  final String? text;
  final String? imageUrl;
  final int? imageWidth;
  final int? imageHeight;
  final String? fileUrl;
  final String? fileName;
  final MediaReference? imageMedia;
  final MediaReference? fileMedia;
  final DateTime createdAt;
  final String? senderId;
  final bool? isMe; // from backend if present; otherwise compute in UI
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final DateTime? readAt;
  final String? clientMessageId;
  final String? venueId;
  final Venue? venue;

  /// Yapısal reply: yanıtlanan orijinal mesajın id'si (yoksa null). Alıntı
  /// balonuna dokununca bu id'li mesaja zıplamak için kullanılır.
  final String? replyToId;

  final List<MessageReaction> reactions;

  /// Client-only: optimistik gönderim başarısız olduysa true. Backend'den
  /// gelmez; balon silinmez, kırmızı "!" + dokun-tekrar-gönder için kullanılır.
  final bool sendFailed;

  ChatMessage({
    required this.id,
    required this.messageType,
    this.text,
    this.imageUrl,
    this.imageWidth,
    this.imageHeight,
    this.fileUrl,
    this.fileName,
    this.imageMedia,
    this.fileMedia,
    required this.createdAt,
    this.senderId,
    this.isMe,
    this.editedAt,
    this.deletedAt,
    this.readAt,
    this.clientMessageId,
    this.venueId,
    this.venue,
    this.replyToId,
    this.reactions = const <MessageReaction>[],
    this.sendFailed = false,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final createdAtRaw = json['created_at'] ?? json['createdAt'];
    final editedAtRaw = json['edited_at'] ?? json['editedAt'];
    final deletedAtRaw = json['deleted_at'] ?? json['deletedAt'];
    final readAtRaw = json['read_at'] ?? json['readAt'];

    final fallbackId = (json['id'] ?? '').toString();
    final imageMedia = MediaReference.fromJson(
      json,
      fallbackId: '$fallbackId:image',
      legacyUrlKeys: const ['image_url', 'imageUrl'],
      idKey: 'image_media_id',
      temporaryUrlKey: 'image_temporary_url',
      refreshPathKey: 'image_refresh_path',
      expiresAtKey: 'image_url_expires_at',
    );
    final fileMedia = MediaReference.fromJson(
      json,
      fallbackId: '$fallbackId:file',
      legacyUrlKeys: const ['file_url', 'fileUrl'],
      idKey: 'file_media_id',
      temporaryUrlKey: 'file_temporary_url',
      refreshPathKey: 'file_refresh_path',
      expiresAtKey: 'file_url_expires_at',
    );
    return ChatMessage(
      id: (json['id'] ?? '').toString(),
      messageType:
          json['message_type'] as String? ??
          json['messageType'] as String? ??
          'text',
      text: json['text'] as String?,
      imageUrl: imageMedia.url.isEmpty ? null : imageMedia.url,
      imageMedia: imageMedia.url.isNotEmpty || imageMedia.canRefresh
          ? imageMedia
          : null,
      imageWidth: _parseInt(json['image_width'] ?? json['imageWidth']),
      imageHeight: _parseInt(json['image_height'] ?? json['imageHeight']),
      fileUrl: fileMedia.url.isEmpty ? null : fileMedia.url,
      fileMedia: fileMedia.url.isNotEmpty || fileMedia.canRefresh
          ? fileMedia
          : null,
      fileName: json['file_name'] as String? ?? json['fileName'] as String?,
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
      clientMessageId: (json['client_message_id'] ?? json['clientMessageId'])
          ?.toString(),
      venueId: (json['venue_id'] ?? json['venueId'])?.toString(),
      venue: json['venue'] is Map
          ? Venue.fromJson(
              Map<String, dynamic>.from(json['venue'] as Map)
                ..putIfAbsent('source', () => 'db')
                ..putIfAbsent('isInDb', () => true)
                ..putIfAbsent('canCheckin', () => true),
            )
          : null,
      replyToId: (json['reply_to_id'] ?? json['replyToId'])?.toString(),
      reactions: json['reactions'] is List
          ? (json['reactions'] as List)
                .whereType<Map>()
                .map(
                  (e) => MessageReaction.fromJson(Map<String, dynamic>.from(e)),
                )
                .where((r) => r.emoji.isNotEmpty)
                .toList()
          : const <MessageReaction>[],
    );
  }

  static int? _parseInt(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString());
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
    int? imageWidth,
    int? imageHeight,
    String? fileUrl,
    String? fileName,
    MediaReference? imageMedia,
    MediaReference? fileMedia,
    DateTime? createdAt,
    String? senderId,
    bool? isMe,
    DateTime? editedAt,
    DateTime? deletedAt,
    DateTime? readAt,
    String? clientMessageId,
    String? venueId,
    Venue? venue,
    String? replyToId,
    List<MessageReaction>? reactions,
    bool? sendFailed,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      messageType: messageType ?? this.messageType,
      text: text ?? this.text,
      imageUrl: imageUrl ?? this.imageUrl,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      fileUrl: fileUrl ?? this.fileUrl,
      fileName: fileName ?? this.fileName,
      imageMedia: imageMedia ?? this.imageMedia,
      fileMedia: fileMedia ?? this.fileMedia,
      createdAt: createdAt ?? this.createdAt,
      senderId: senderId ?? this.senderId,
      isMe: isMe ?? this.isMe,
      editedAt: editedAt ?? this.editedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      readAt: readAt ?? this.readAt,
      clientMessageId: clientMessageId ?? this.clientMessageId,
      venueId: venueId ?? this.venueId,
      venue: venue ?? this.venue,
      replyToId: replyToId ?? this.replyToId,
      reactions: reactions ?? this.reactions,
      sendFailed: sendFailed ?? this.sendFailed,
    );
  }
}
