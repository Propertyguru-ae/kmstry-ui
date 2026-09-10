import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'chat_message_model.dart';

typedef ChatImageCacheWriter =
    Future<void> Function(
      String url,
      Uint8List bytes,
      String key,
      String extension,
      Duration maxAge,
    );

/// Reuse the exact uploaded bytes for the sender's preview instead of fetching
/// them from storage again. The server-confirmed signed reference stays intact.
Future<void> cacheUploadedChatImage(
  ChatMessage message,
  File file, {
  ChatImageCacheWriter? write,
}) async {
  final media = message.imageMedia;
  final url = media?.url ?? message.imageUrl ?? '';
  final uri = Uri.tryParse(url);
  if (message.messageType != 'image' ||
      uri?.scheme != 'https' ||
      uri!.host.isEmpty) {
    return;
  }
  final lifetime = media?.expiresAt?.difference(DateTime.now());
  if (lifetime != null && lifetime <= Duration.zero) return;
  try {
    final writer =
        write ??
        (url, bytes, key, extension, maxAge) async {
          await DefaultCacheManager().putFile(
            url,
            bytes,
            key: key,
            fileExtension: extension,
            maxAge: maxAge,
          );
        };
    await writer(
      url,
      await file.readAsBytes(),
      media?.mediaId ?? url,
      file.path.split('.').last.toLowerCase(),
      lifetime ?? const Duration(minutes: 5),
    );
  } catch (_) {
    // Disk-cache failure must never turn a successfully sent message into a
    // failed send. Normal signed download remains available as fallback.
  }
}
