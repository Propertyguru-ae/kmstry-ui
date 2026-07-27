import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_compress/video_compress.dart';

/// Yükleme öncesi medyayı sıkıştıran yardımcı.
///
/// Videolar ham hâlde (60 sn'lik bir video ~30-60MB olabilir) hem kullanıcının
/// mobil verisini yer hem de 8MB upload limitini aşardı. Burada yüklemeden önce
/// makul kaliteyle sıkıştırıp hem boyutu hem yükleme süresini ciddi düşürürüz.
///
/// Fotoğraflar zaten çekim akışında 720px'e küçültülüp JPEG kalitesi 92'ye
/// ayarlanıyor — ek sıkıştırma gerekmez.
class MediaCompressor {
  MediaCompressor._();

  /// Videoyu sıkıştırır ve sıkıştırılmış dosyayı döndürür. Sıkıştırma
  /// başarısız olursa (veya sonuç orijinalden büyükse) orijinali döndürür —
  /// yani bu çağrı yüklemeyi asla bozmaz.
  static Future<File> compressVideo(File input) async {
    try {
      final originalSize = await input.length();
      final info = await VideoCompress.compressVideo(
        input.path,
        quality: VideoQuality.MediumQuality, // 720p'ye yakın, iyi denge
        deleteOrigin: false,
        includeAudio: true,
      );

      final compressedPath = info?.path;
      if (compressedPath == null) return input;

      final compressed = File(compressedPath);
      if (!await compressed.exists()) return input;

      final compressedSize = await compressed.length();
      // Sıkıştırma ters teperse (nadiren küçük dosyalarda olur) orijinali kullan.
      if (compressedSize >= originalSize) return input;

      if (kDebugMode) {
        final pct = (100 * (1 - compressedSize / originalSize)).toStringAsFixed(0);
        debugPrint(
          '🎬 Video compressed: ${_mb(originalSize)} → ${_mb(compressedSize)} ($pct% smaller)',
        );
      }
      return compressed;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Video compression failed, using original: $e');
      return input;
    }
  }

  /// İşi biten sıkıştırma geçici dosyalarını temizler. Uygulama arka plana
  /// alındığında veya check-in tamamlandığında çağrılabilir.
  static Future<void> cleanup() async {
    try {
      await VideoCompress.deleteAllCache();
    } catch (_) {}
  }

  static String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
}
