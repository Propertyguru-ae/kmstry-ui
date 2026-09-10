import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:mime/mime.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/network/app_request_headers.dart';
import 'package:kmstry_frontend/core/network/multipart_upload.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/chat/data/chat_detail_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_list_item_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_message_model.dart';
import 'chat_memory_cache.dart';
import 'chat_image_cache.dart';

class ChatRepository {
  ChatRepository({
    ApiClient? api,
    ChatMemoryCache? cache,
    Future<String?> Function()? tokenProvider,
  }) : _api = api ?? ApiClient(),
       _cache = cache ?? ChatMemoryCache.shared,
       _tokenProvider = tokenProvider ?? SecureStorage.getAccessToken;
  final ApiClient _api;
  final ChatMemoryCache _cache;
  final Future<String?> Function() _tokenProvider;
  Stream<String> get cacheChanges => _cache.changes;
  void rememberChat(ChatDetail detail) => _cache.remember(detail);

  Future<String?> _token() => _tokenProvider();

  List<ChatListItem>? get cachedChats {
    final chats = _cache.chats;
    if (chats == null || chats.isEmpty) return null;
    return List<ChatListItem>.from(chats);
  }

  ChatDetail? cachedChat(String chatId) => _cache.detail(chatId);

  /// GET /chats — list of active chats with last_message_at, sorted by last_message_at.
  Future<List<ChatListItem>> getChats() async {
    final generation = _cache.generation;
    final snapshot = _cache.chats;
    final token = await _token();
    if (token == null) throw Exception('Not authenticated');

    final data = await _api.get(
      '/chats',
      headers: {'Authorization': 'Bearer $token'},
    );
    final chats = _parseChatList(data);
    return generation == _cache.generation
        ? _cache.acceptRows(chats, snapshot: snapshot)
        : chats;
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
    final generation = _cache.generation;
    final snapshot = _cache.detail(chatId);
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

    final detail = ChatDetail.fromJson(data as Map<String, dynamic>);
    // History pages are not the latest page: never replace its warm snapshot.
    if (beforeId != null || generation != _cache.generation) return detail;
    return _cache.acceptDetail(detail, snapshot);
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

  /// POST /chats/upload-image — private chat fotoğrafını yükler.
  Future<({String url, String objectKey})> uploadChatImage(File file) async {
    final token = await _token();
    if (token == null) throw Exception('Not authenticated');

    final uri = Uri.parse('${AppConfig.baseUrl}/chats/upload-image');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(await AppRequestHeaders.build(accessToken: token));

    final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
    final mimeSplit = mimeType.split('/');
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: http_parser.MediaType(mimeSplit[0], mimeSplit[1]),
      ),
    );

    final streamed = await sendMultipartRequest(request);
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode >= 400) {
      throw Exception('Image upload failed (${streamed.statusCode}): $body');
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    final url = (json['url'] ?? '').toString();
    if (url.isEmpty) throw Exception('Upload response missing url');
    final objectKey = (json['object_key'] ?? '').toString();
    if (objectKey.isEmpty) {
      throw Exception('Upload response missing object key');
    }
    return (url: url, objectKey: objectKey);
  }

  /// POST /chats/upload-file — chat belgesini yükler, {url, file_name} döner.
  Future<({String url, String objectKey, String fileName})> uploadChatFile(
    File file,
  ) async {
    final token = await _token();
    if (token == null) throw Exception('Not authenticated');

    final uri = Uri.parse('${AppConfig.baseUrl}/chats/upload-file');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(await AppRequestHeaders.build(accessToken: token));

    final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
    final mimeSplit = mimeType.split('/');
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: http_parser.MediaType(mimeSplit[0], mimeSplit[1]),
      ),
    );

    final streamed = await sendMultipartRequest(request);
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode >= 400) {
      throw Exception('File upload failed (${streamed.statusCode}): $body');
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    final url = (json['url'] ?? '').toString();
    if (url.isEmpty) throw Exception('Upload response missing url');
    final objectKey = (json['object_key'] ?? '').toString();
    if (objectKey.isEmpty) {
      throw Exception('Upload response missing object key');
    }
    final fileName = (json['file_name'] ?? '').toString();
    return (url: url, objectKey: objectKey, fileName: fileName);
  }

  /// POST /chats/:id/messages — send text, image, file or venue card.
  Future<ChatMessage> sendMessage(
    String chatId, {
    required String messageType,
    String? text,
    String? imageUrl,
    String? imageObjectKey,
    int? imageWidth,
    int? imageHeight,
    String? fileUrl,
    String? fileObjectKey,
    String? fileName,
    String? clientMessageId,
    String? replyToId,
    String? venueId,
    File? localUploadedImage,
  }) async {
    final generation = _cache.generation;
    Future<ChatMessage> confirmed(dynamic data) async {
      final message = ChatMessage.fromJson(data as Map<String, dynamic>);
      if (localUploadedImage != null && generation == _cache.generation) {
        await cacheUploadedChatImage(message, localUploadedImage);
      }
      if (generation == _cache.generation) {
        _cache.confirmedMessage(chatId, message);
      }
      return message;
    }

    final token = await _token();
    if (token == null) throw Exception('Not authenticated');

    final body = <String, dynamic>{'message_type': messageType};
    if (messageType == 'text' && text != null) {
      body['text'] = text;
    }
    if (messageType == 'image' && imageUrl != null) {
      body['image_url'] = imageUrl;
      if (imageObjectKey != null && imageObjectKey.trim().isNotEmpty) {
        body['image_object_key'] = imageObjectKey.trim();
      }
      if (imageWidth != null && imageWidth > 0) {
        body['image_width'] = imageWidth;
      }
      if (imageHeight != null && imageHeight > 0) {
        body['image_height'] = imageHeight;
      }
    }
    if (messageType == 'file' && fileUrl != null) {
      body['file_url'] = fileUrl;
      if (fileObjectKey != null && fileObjectKey.trim().isNotEmpty) {
        body['file_object_key'] = fileObjectKey.trim();
      }
      if (fileName != null && fileName.trim().isNotEmpty) {
        body['file_name'] = fileName.trim();
      }
    }
    if (messageType == 'venue' && venueId != null) {
      body['venue_id'] = venueId;
    }
    if (clientMessageId != null && clientMessageId.trim().isNotEmpty) {
      body['client_message_id'] = clientMessageId.trim();
    }
    if (replyToId != null && replyToId.trim().isNotEmpty) {
      body['reply_to_id'] = replyToId.trim();
    }

    Future<dynamic> postMessage(Map<String, dynamic> payload) {
      return _api.post(
        '/chats/$chatId/messages',
        headers: {'Authorization': 'Bearer $token'},
        body: payload,
      );
    }

    try {
      final data = await postMessage(body);
      return confirmed(data);
    } on ApiException catch (e) {
      if (e.statusCode == 429) {
        await Future.delayed(const Duration(milliseconds: 900));
        final retryData = await postMessage(body);
        return confirmed(retryData);
      }

      // Backward compatibility: some backend versions still reject client_message_id.
      final hasClientMessageId =
          clientMessageId != null && clientMessageId.trim().isNotEmpty;
      final shouldRetryWithoutClientMessageId =
          hasClientMessageId &&
          e.toString().toLowerCase().contains('client_message_id');
      if (!shouldRetryWithoutClientMessageId) rethrow;

      final fallbackBody = Map<String, dynamic>.from(body)
        ..remove('client_message_id');
      final fallbackData = await postMessage(fallbackBody);
      return confirmed(fallbackData);
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
    _cache.removeMessage(chatId, messageId);
  }

  /// DELETE /chats/:id — soft delete chat for current user.
  Future<void> deleteChat(String chatId) async {
    final token = await _token();
    if (token == null) throw Exception('Not authenticated');
    await _api.delete(
      '/chats/$chatId',
      headers: {'Authorization': 'Bearer $token'},
    );
    _cache.removeChat(chatId);
  }
}

class ChatMessagesPage {
  final List<ChatMessage> items;
  final String? nextCursor;

  const ChatMessagesPage({required this.items, required this.nextCursor});
}
