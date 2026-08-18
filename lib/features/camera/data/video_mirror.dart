import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Ön kamera videosunu çekerkenki ayna haline çevirir.
///
/// Her iki platformda da NATIVE, donanım hızlandırmalı yöntem kullanılır
/// (ffmpeg yok):
/// - **iOS**: AVFoundation passthrough (preferredTransform flip) → yeniden
///   kodlama yok, ~anlık, kalite kaybı yok.
/// - **Android**: Media3 Transformer (GPU üzerinde X-ekseni flip).
///
/// Başarısız olursa orijinal dosyayı döner.
class VideoMirror {
  static const _channel = MethodChannel('app/video_mirror');

  static Future<File> mirrorFront(File input) async {
    if (!Platform.isIOS && !Platform.isAndroid) {
      return input;
    }
    try {
      final outPath = await _channel.invokeMethod<String>(
        'mirror',
        {'path': input.path},
      );
      if (outPath != null) {
        final out = File(outPath);
        if (await out.exists()) return out;
      }
    } catch (e) {
      debugPrint('❌ VideoMirror native error: $e');
    }
    return input;
  }
}
