import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/chat/data/chat_message_model.dart';

void main() {
  test('retains a refreshable private image reference without an initial URL', () {
    final message = ChatMessage.fromJson({
      'id': 'message-1',
      'message_type': 'image',
      'image_media_id': 'message-1:image',
      'image_temporary_url': null,
      'image_refresh_path': '/chats/chat-1/messages/message-1/media/image',
      'image_url_expires_at': null,
      'created_at': '2026-09-09T08:00:00.000Z',
    });

    expect(message.imageUrl, isNull);
    expect(message.imageMedia, isNotNull);
    expect(message.imageMedia?.canRefresh, isTrue);
  });

  test('does not invent a media reference for an empty text message', () {
    final message = ChatMessage.fromJson({
      'id': 'message-2',
      'message_type': 'text',
      'text': 'hello',
      'created_at': '2026-09-09T08:00:00.000Z',
    });

    expect(message.imageMedia, isNull);
    expect(message.fileMedia, isNull);
  });
}
