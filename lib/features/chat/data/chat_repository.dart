import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:mime/mime.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/chat/data/chat_detail_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_list_item_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_message_model.dart';

class ChatRepository {
  final ApiClient _api = ApiClient();

  Future<String?> _token() => SecureStorage.getAccessToken();

  /// GET /chats — list of active chats with last_message_at, sorted by last_message_at.
  Future<List<ChatListItem>> getChats() async {
    final token = await _token();
    if (token == null) throw Exception('Not authenticated');

    final data = await _api.get(
      '/chats',
      headers: {'Authorization': 'Bearer $token'},
    );
    return _parseChatList(data);
  }

  /// GET /chats/search?query=... — chat list filtered by participant name.
  Future<List<ChatListItem>> searchChatsByParticipantName(String query) async {
    final token = await _token();
    if (token == null) throw Exception('Not authenticated');
    final trimmed = query.trim();
    if (trimmed.isEmpty) return getChats();
    final encoded = Uri.encodeQueryComponent(trimmed);
    final data = await _api.get(
      '/chats/search?query=$encoded',
      headers: {'Authorization': 'Bearer $token'},
    );
    return _parseChatList(data);
  }

  List<ChatListItem> _parseChatList(dynamic data) {
    final list = _extractChatList(data);
    return list
        .map((e) => ChatListItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  List<dynamic> _extractChatList(dynamic data) {
    if (data is List) return data;
    if (data is Map<String, dynamic>) {
      final nested =
          data['items'] ?? data['chats'] ?? data['data'] ?? data['results'];
      if (nested is List) return nested;
      if (nested is Map<String, dynamic> && nested['items'] is List) {
        return nested['items'] as List;
      }
    }
    return const [];
  }

  /// POST /chats — create or get existing chat with [otherUserId]. Returns chat id.
  /// Backend may use body: { other_user_id } or { participant_id }.
  Future<String> createChat(String otherUserId) async {
    final token = await _token();
    if (token == null) throw Exception('Not authenticated');

    final data = await _api.post(
      '/chats',
      headers: {'Authorization': 'Bearer $token'},
      body: {'other_user_id': otherUserId},
    );

    final map = data as Map<String, dynamic>;
    String? id = map['id'] as String? ?? map['chat_id'] as String?;
    if (id == null || id.isEmpty) {
      final nested = map['chat'];
      if (nested is Map<String, dynamic>) {
        id = nested['id'] as String? ?? nested['chat_id'] as String?;
      }
    }
    if (id == null || id.isEmpty) {
      throw Exception('Create chat response missing id');
    }
    return id;
  }

  /// GET /chats/:id?markRead=true — chat detail + messages.
  /// Optional [beforeId] and [take] for pagination (load older messages).
  Future<ChatDetail> getChat(
    String chatId, {
    bool markRead = true,
    String? beforeId,
    int? take,
  }) async {
    final token = await _token();
    if (token == null) throw Exception('Not authenticated');

    final query = <String>[];
    if (markRead) query.add('markRead=true');
    if (beforeId != null) query.add('before_id=$beforeId');
    if (take != null) query.add('take=$take');
    final path = query.isEmpty
        ? '/chats/$chatId'
        : '/chats/$chatId?${query.join('&')}';
    final data = await _api.get(
      path,
      headers: {'Authorization': 'Bearer $token'},
    );

    return ChatDetail.fromJson(data as Map<String, dynamic>);
  }

  /// PATCH /chats/:id/read — mark chat as read (optional if using markRead=true on GET).
  Future<void> markChatRead(String chatId) async {
    final token = await _token();
    if (token == null) throw Exception('Not authenticated');

    await _api.patch(
      '/chats/$chatId/read',
      headers: {'Authorization': 'Bearer $token'},
      body: {},
    );
  }

  /// POST /chats/upload-image — chat fotoğrafını yükler, kalıcı URL döner.
  Future<String> uploadChatImage(File file) async {
    final token = await _token();
    if (token == null) throw Exception('Not authenticated');

    final uri = Uri.parse('${AppConfig.baseUrl}/chats/upload-image');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $token';

    final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
    final mimeSplit = mimeType.split('/');
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: http_parser.MediaType(mimeSplit[0], mimeSplit[1]),
      ),
    );

    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode >= 400) {
      throw Exception('Image upload failed (${streamed.statusCode}): $body');
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    final url = (json['url'] ?? '').toString();
    if (url.isEmpty) throw Exception('Upload response missing url');
    return url;
  }

  /// POST /chats/upload-file — chat belgesini yükler, {url, file_name} döner.
  Future<({String url, String fileName})> uploadChatFile(File file) async {
    final token = await _token();
    if (token == null) throw Exception('Not authenticated');

    final uri = Uri.parse('${AppConfig.baseUrl}/chats/upload-file');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $token';

    final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
    final mimeSplit = mimeType.split('/');
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: http_parser.MediaType(mimeSplit[0], mimeSplit[1]),
      ),
    );

    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode >= 400) {
      throw Exception('File upload failed (${streamed.statusCode}): $body');
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    final url = (json['url'] ?? '').toString();
    if (url.isEmpty) throw Exception('Upload response missing url');
    final fileName = (json['file_name'] ?? '').toString();
    return (url: url, fileName: fileName);
  }

  /// POST /chats/:id/messages — send text, image or file message.
  Future<ChatMessage> sendMessage(
    String chatId, {
    required String messageType,
    String? text,
    String? imageUrl,
    String? fileUrl,
    String? fileName,
    String? clientMessageId,
  }) async {
    final token = await _token();
    if (token == null) throw Exception('Not authenticated');

    final body = <String, dynamic>{'message_type': messageType};
    if (messageType == 'text' && text != null) {
      body['text'] = text;
    }
    if (messageType == 'image' && imageUrl != null) {
      body['image_url'] = imageUrl;
    }
    if (messageType == 'file' && fileUrl != null) {
      body['file_url'] = fileUrl;
      if (fileName != null && fileName.trim().isNotEmpty) {
        body['file_name'] = fileName.trim();
      }
    }
    if (clientMessageId != null && clientMessageId.trim().isNotEmpty) {
      body['client_message_id'] = clientMessageId.trim();
    }

    try {
      final data = await _api.post(
        '/chats/$chatId/messages',
        headers: {'Authorization': 'Bearer $token'},
        body: body,
      );
      return ChatMessage.fromJson(data as Map<String, dynamic>);
    } on ApiException catch (e) {
      // Backward compatibility: some backend versions still reject client_message_id.
      final hasClientMessageId =
          clientMessageId != null && clientMessageId.trim().isNotEmpty;
      final shouldRetryWithoutClientMessageId =
          hasClientMessageId &&
          e.toString().toLowerCase().contains('client_message_id');
      if (!shouldRetryWithoutClientMessageId) rethrow;

      final fallbackBody = Map<String, dynamic>.from(body)
        ..remove('client_message_id');
      final fallbackData = await _api.post(
        '/chats/$chatId/messages',
        headers: {'Authorization': 'Bearer $token'},
        body: fallbackBody,
      );
      return ChatMessage.fromJson(fallbackData as Map<String, dynamic>);
    }
  }

  /// GET `/chats/:id/messages?cursor=ISO_DATE&limit=1-100`
  Future<ChatMessagesPage> getMessagesSince(
    String chatId, {
    String? cursor,
    int limit = 50,
  }) async {
    final token = await _token();
    if (token == null) throw Exception('Not authenticated');

    final safeLimit = limit.clamp(1, 100);
    final query = <String>['limit=$safeLimit'];
    if (cursor != null && cursor.trim().isNotEmpty) {
      query.add('cursor=${Uri.encodeQueryComponent(cursor.trim())}');
    }
    final path = '/chats/$chatId/messages?${query.join('&')}';

    final data = await _api.get(
      path,
      headers: {'Authorization': 'Bearer $token'},
    );
    if (data is! Map<String, dynamic>) {
      return const ChatMessagesPage(items: <ChatMessage>[], nextCursor: null);
    }

    final itemsRaw = data['items'];
    final items = itemsRaw is List
        ? itemsRaw
              .whereType<Map>()
              .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
              .toList()
        : <ChatMessage>[];

    final nextCursor = data['nextCursor']?.toString();
    return ChatMessagesPage(items: items, nextCursor: nextCursor);
  }

  /// POST /chats/:id/messages/:messageId/reactions — reaction toggle.
  /// Sunucudan mesajın güncel reaction listesi döner.
  Future<List<MessageReaction>> toggleReaction(
    String chatId,
    String messageId,
    String emoji,
  ) async {
    final token = await _token();
    if (token == null) throw Exception('Not authenticated');

    final data = await _api.post(
      '/chats/$chatId/messages/$messageId/reactions',
      headers: {'Authorization': 'Bearer $token'},
      body: {'emoji': emoji},
    );
    final raw = data is Map<String, dynamic> ? data['reactions'] : null;
    if (raw is! List) return const <MessageReaction>[];
    return raw
        .whereType<Map>()
        .map((e) => MessageReaction.fromJson(Map<String, dynamic>.from(e)))
        .where((r) => r.emoji.isNotEmpty)
        .toList();
  }

  /// PATCH /chats/:id/messages/:messageId — edit own text message.
  Future<void> editMessage(
    String chatId,
    String messageId, {
    required String text,
  }) async {
    final token = await _token();
    if (token == null) throw Exception('Not authenticated');

    await _api.patch(
      '/chats/$chatId/messages/$messageId',
      headers: {'Authorization': 'Bearer $token'},
      body: {'text': text},
    );
  }

  /// DELETE /chats/:id/messages/:messageId — soft delete own message (optional).
  Future<void> deleteMessage(String chatId, String messageId) async {
    final token = await _token();
    if (token == null) throw Exception('Not authenticated');

    await _api.delete(
      '/chats/$chatId/messages/$messageId',
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  /// DELETE /chats/:id — soft delete chat for current user.
  Future<void> deleteChat(String chatId) async {
    final token = await _token();
    if (token == null) throw Exception('Not authenticated');
    await _api.delete(
      '/chats/$chatId',
      headers: {'Authorization': 'Bearer $token'},
    );
  }
}

class ChatMessagesPage {
  final List<ChatMessage> items;
  final String? nextCursor;

  const ChatMessagesPage({required this.items, required this.nextCursor});
}
