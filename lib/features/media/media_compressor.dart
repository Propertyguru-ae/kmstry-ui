import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';
import 'video_work_queue.dart';

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
  static final _videoWork = VideoWorkQueue(
    cleanup: VideoCompress.deleteAllCache,
  );

  /// Call before preparing a video and release after its transfer completes.
  static void Function() retainVideoFiles() => _videoWork.retainFiles();

  /// Videoyu sıkıştırır ve sıkıştırılmış dosyayı döndürür. Sıkıştırma
  /// başarısız olursa orijinali döndürür. Geçerli dönüşüm daha büyük olsa bile
  /// korunur: küçük bir HEVC orijinale geri dönmek AWS uyumluluğunu bozabilir.
  /// Backend yine her public videonun gerçek codec'ini doğrular.
  static Future<File> compressVideo(
    File input, {
    VideoQuality quality = VideoQuality.MediumQuality,
  }) => _videoWork.run(() => _compressVideo(input, quality: quality));

  static Future<File> _compressVideo(
    File input, {
    required VideoQuality quality,
  }) async {
    try {
      final originalSize = await input.length();
      final info = await VideoCompress.compressVideo(
        input.path,
        quality: quality,
        deleteOrigin: false,
        includeAudio: true,
      );

      final compressed = await selectPreparedVideo(input, info?.path);
      if (compressed.path == input.path) return input;

      final compressedSize = await compressed.length();

      if (kDebugMode) {
        final pct = (100 * (1 - compressedSize / originalSize)).toStringAsFixed(
          0,
        );
        debugPrint(
          '🎬 Video prepared: ${_mb(originalSize)} → ${_mb(compressedSize)} (size change: $pct%)',
        );
      }
      return compressed;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Video compression failed, using original: $e');
      }
      return input;
    }
  }

  /// Keep a valid encoder result even when codec conversion increases size.
  /// Invalid/missing output may fall back; the backend compatibility boundary
  /// will normalize that original before AWS can approve publication.
  @visibleForTesting
  static Future<File> selectPreparedVideo(
    File input,
    String? outputPath,
  ) async {
    if (outputPath == null || outputPath.isEmpty) return input;
    final output = File(outputPath);
    if (!await output.exists() || await output.length() == 0) return input;
    return output;
  }

  /// Venue story/gallery videoları için 720p sıkıştırma. 60 saniyelik medya
  /// mobil ağda güvenilir biçimde yüklenirken görüntü kalitesi korunur.
  static Future<File> compressVenueVideo(File input) =>
      compressVideo(input, quality: VideoQuality.Res1280x720Quality);

  /// Venue gallery videos are primarily viewed on a phone-sized surface.
  /// 540p keeps them clear while materially reducing encode/upload time for
  /// long gallery clips. Stories stay at 720p above.
  static Future<File> compressGalleryVideo(File input) =>
      compressVideo(input, quality: VideoQuality.Res960x540Quality);

  /// Fotoğrafı yüklemeden önce en uzun kenarı ~[maxDimension]px olacak şekilde
  /// küçültüp JPEG'e (kalite [quality]) çevirir. Native codec kullanır → iOS
  /// HEIC'i de JPEG'e dönüştürür ve hızlıdır. Sıkıştırma başarısız olursa veya
  /// sonuç orijinalden büyükse orijinali döndürür (yüklemeyi asla bozmaz).
  static Future<File> compressImage(
    File input, {
    int maxDimension = 1600,
    int quality = 85,
    int? sourceWidth,
    int? sourceHeight,
  }) async {
    try {
      final originalSize = await input.length();
      final dir = await getTemporaryDirectory();
      final target =
          '${dir.path}/img_${DateTime.now().microsecondsSinceEpoch}.jpg';

      final (targetWidth, targetHeight) = imageTargetSize(
        maxDimension,
        sourceWidth,
        sourceHeight,
      );
      final result = await FlutterImageCompress.compressAndGetFile(
        input.absolute.path,
        target,
        minWidth: targetWidth,
        minHeight: targetHeight,
        quality: quality,
        format: CompressFormat.jpeg,
        keepExif: false,
      );
      if (result == null) return input;

      final compressed = File(result.path);
      if (!await compressed.exists()) return input;

      final compressedSize = await compressed.length();
      if (compressedSize >= originalSize) return input;

      if (kDebugMode) {
        final pct = (100 * (1 - compressedSize / originalSize)).toStringAsFixed(
          0,
        );
        debugPrint(
          '🖼️ Image compressed: ${_mb(originalSize)} → ${_mb(compressedSize)} ($pct% smaller)',
        );
      }
      return compressed;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Image compression failed, using original: $e');
      }
      return input;
    }
  }

  /// Native compression scales against BOTH minimum dimensions. A square
  /// target otherwise keeps the short edge at 1280 and the long edge larger.
  static (int, int) imageTargetSize(int limit, int? width, int? height) {
    if (width == null || height == null || width <= 0 || height <= 0) {
      return (limit, limit);
    }
    final longest = width > height ? width : height;
    if (longest <= limit) return (width, height);
    final scale = limit / longest;
    return (
      (width * scale).round().clamp(1, limit),
      (height * scale).round().clamp(1, limit),
    );
  }

  /// İşi biten sıkıştırma geçici dosyalarını temizler. Uygulama arka plana
  /// alındığında veya check-in tamamlandığında çağrılabilir.
  static Future<void> cleanup() => _videoWork.cleanup();

  static String _mb(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
}
