import 'package:kmstry_frontend/core/network/api_client.dart';
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
          data['items'] ??
          data['chats'] ??
          data['data'] ??
          data['results'];
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

  /// POST /chats/:id/messages — send text or image message.
  Future<ChatMessage> sendMessage(
    String chatId, {
    required String messageType,
    String? text,
    String? imageUrl,
  }) async {
    final token = await _token();
    if (token == null) throw Exception('Not authenticated');

    final body = <String, dynamic>{
      'message_type': messageType,
    };
    if (messageType == 'text' && text != null) {
      body['text'] = text;
    }
    if (messageType == 'image' && imageUrl != null) {
      body['image_url'] = imageUrl;
    }

    final data = await _api.post(
      '/chats/$chatId/messages',
      headers: {'Authorization': 'Bearer $token'},
      body: body,
    );

    return ChatMessage.fromJson(data as Map<String, dynamic>);
  }

  /// PATCH /chats/:id/messages/:messageId — edit own message (optional).
  Future<void> editMessage(
    String chatId,
    String messageId, {
    String? text,
    String? imageUrl,
  }) async {
    final token = await _token();
    if (token == null) throw Exception('Not authenticated');

    final body = <String, dynamic>{};
    if (text != null) body['text'] = text;
    if (imageUrl != null) body['image_url'] = imageUrl;

    await _api.patch(
      '/chats/$chatId/messages/$messageId',
      headers: {'Authorization': 'Bearer $token'},
      body: body,
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
