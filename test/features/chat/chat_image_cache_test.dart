import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/chat/data/chat_image_cache.dart';
import 'package:kmstry_frontend/features/chat/data/chat_message_model.dart';
import 'package:kmstry_frontend/features/media/media_compressor.dart';

class RecordingCache {
  String? receivedKey;
  Uint8List? bytes;
  bool fail = false;
  Future<void> putFile(
    String url,
    Uint8List fileBytes,
    String key,
    String fileExtension,
    Duration maxAge,
  ) async {
    if (fail) throw const FileSystemException('cache unavailable');
    receivedKey = key;
    bytes = fileBytes;
  }
}

void main() {
  test(
    'chat compression bounds the long edge without changing aspect ratio',
    () {
      expect(MediaCompressor.imageTargetSize(1280, 4000, 3000), (1280, 960));
      expect(MediaCompressor.imageTargetSize(1280, 3000, 4000), (960, 1280));
      expect(MediaCompressor.imageTargetSize(1280, 4000, 1000), (1280, 320));
      expect(MediaCompressor.imageTargetSize(1280, 640, 480), (640, 480));
      expect(MediaCompressor.imageTargetSize(1280, null, null), (1280, 1280));
    },
  );

  late Directory directory;
  late File uploaded;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'kmstry-image-cache-test-',
    );
    uploaded = await File(
      '${directory.path}/upload.jpg',
    ).writeAsBytes([1, 2, 3]);
  });
  tearDown(() async => directory.delete(recursive: true));

  ChatMessage confirmed() => ChatMessage.fromJson({
    'id': 'message-1',
    'message_type': 'image',
    'image_media_id': 'message-1:image',
    'image_temporary_url': 'https://media.example.com/photo?signature=test',
    'image_refresh_path': '/chats/messages/message-1/media/image',
    'created_at': '2026-09-09T10:00:00Z',
  });

  test(
    'seeds exact uploaded bytes under the stable signed media cache key',
    () async {
      final cache = RecordingCache();
      await cacheUploadedChatImage(confirmed(), uploaded, write: cache.putFile);
      expect(cache.receivedKey, 'message-1:image');
      expect(cache.bytes, [1, 2, 3]);
    },
  );

  test('cache write failure never rejects an already confirmed send', () async {
    final cache = RecordingCache()..fail = true;
    await expectLater(
      cacheUploadedChatImage(confirmed(), uploaded, write: cache.putFile),
      completes,
    );
  });

  test(
    'missing or expired signed URLs do not enable a public fallback',
    () async {
      final cache = RecordingCache();
      final expired = ChatMessage.fromJson({
        'id': 'message-1',
        'message_type': 'image',
        'image_temporary_url': 'https://media.example.com/photo?signature=test',
        'image_url_expires_at': '2000-01-01T00:00:00Z',
        'created_at': '2026-09-09T10:00:00Z',
      });
      await cacheUploadedChatImage(expired, uploaded, write: cache.putFile);
      expect(cache.receivedKey, isNull);
    },
  );
}
