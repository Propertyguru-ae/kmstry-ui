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

    if (data is! List) return [];
    return (data as List)
        .map((e) => ChatListItem.fromJson(e as Map<String, dynamic>))
        .toList();
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
    final id = map['id'] as String? ?? map['chat_id'] as String?;
    if (id == null) throw Exception('Create chat response missing id');
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
}
