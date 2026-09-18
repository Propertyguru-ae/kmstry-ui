import 'dart:io';
import 'package:kmstry_frontend/features/media/text_overlay_composer.dart';
import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/media_upload_progress_dialog.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/features/camera/presentation/camera_screen.dart';
import 'package:kmstry_frontend/features/media/media_compressor.dart';
import '../data/venue_story_repository.dart';

const _maxVenueStoryUploadBytes = 50 * 1024 * 1024;

class AddVenueStoryPage extends StatefulWidget {
  final String venueId;
  const AddVenueStoryPage({super.key, required this.venueId});

  /// Saydam route: sayfanın kendisi görsel bir zemin çizmez (kamera + yükleme
  /// dialog'u yönetir). opaque:false ile arkadaki uygulama görünür kalır.
  static Route<bool> route(String venueId) {
    return PageRouteBuilder<bool>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      // Saydam sayfa: slide/döndürme yerine yumuşak fade (sayfa zaten görünmez,
      // arkada uygulama kalır). Varsayılan geçişin "dönerek sola" görünmesini
      // engeller.
      transitionsBuilder: (_, animation, __, child) =>
          FadeTransition(opacity: animation, child: child),
      pageBuilder: (_, __, ___) => AddVenueStoryPage(venueId: venueId),
    );
  }

  @override
  State<AddVenueStoryPage> createState() => _AddVenueStoryPageState();
}

class _AddVenueStoryPageState extends State<AddVenueStoryPage> {
  final _repo = VenueStoryRepository();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openCamera());
  }

  Future<void> _openCamera() async {
    if (!mounted) return;

    // Video akışı CapturedMedia (dosya + text overlay) dönebilir — dosyayı
    // çıkar (venue story'de overlay şimdilik desteklenmiyor).
    final dynamic captureResult = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const CameraScreen(useFrontCamera: false, optimizeForUpload: true),
      ),
    );

    if (!mounted) return;
    final File? captured = captureResult is CapturedMedia
        ? captureResult.file
        : captureResult as File?;
    if (captured == null) {
      Navigator.pop(context);
      return;
    }

    await _upload(captured);
  }

  Future<void> _upload(File file) async {
    if (!mounted) return;

    final ext = file.path.toLowerCase();
    final isVideo =
        ext.endsWith('.mp4') || ext.endsWith('.mov') || ext.endsWith('.avi');

    // Uygulama geneli yükleme dialog'u (premium kart + progress) — eski tam
    // ekran siyah "Uploading..." yerine.
    final progress = MediaUploadProgressController(
      title: isVideo ? 'Uploading video story' : 'Uploading story',
      message: isVideo
          ? 'Optimizing your video for a faster upload…'
          : 'Sharing your story…',
    );
    await progress.show(context);

    bool success = false;
    Object? err;
    try {
      final uploadFile = isVideo
          ? await MediaCompressor.compressVenueVideo(file)
          : file;
      if (isVideo && await uploadFile.length() > _maxVenueStoryUploadBytes) {
        throw Exception('VIDEO_TOO_LARGE');
      }
      if (isVideo) {
        progress.update(
          message: 'Your optimized video is being uploaded…',
          progress: 0,
        );
      }
      await _repo.createVenueStory(
        venueId: widget.venueId,
        file: uploadFile,
        mediaType: isVideo ? 'video' : 'photo',
        onProgress: (sent, total) {
          if (total <= 0) return;
          progress.update(progress: sent / total);
        },
      );
      success = true;
    } catch (e) {
      err = e;
    } finally {
      await progress.close();
      progress.dispose();
    }

    if (!mounted) return;
    if (success) {
      try {
        showSuccessSnackBar(context, message: 'Story shared!');
      } catch (_) {}
      Navigator.pop(context, true);
      return;
    }

    // Backend STORIES'i SOCIAL+ plana kilitliyor. Plan hatası düşerse generic
    // "could not upload" yerine gerçek nedeni göster.
    final s = err.toString();
    final isPlanLocked = s.contains('PLAN_UPGRADE_REQUIRED');
    final isTooLong = s.contains('60 seconds or shorter');
    final isTooLarge =
        s.contains('VIDEO_TOO_LARGE') ||
        s.contains('413') ||
        s.contains('File too large');
    await showPremiumErrorDialog(
      context,
      message: isPlanLocked
          ? 'Venue stories are part of the Social plan. Upgrade your venue to post stories.'
          : isTooLong
          ? 'Video must be 60 seconds or shorter.'
          : isTooLarge
          ? 'Video is too large. Please choose a smaller file.'
          : 'Could not upload story. Please try again.',
    );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    // Sayfa SAYDAM: kamera ayrı route'ta açılır, yükleme dialog'u root
    // navigator'da gösterilir. Böylece dialog görünürken arkada beyaz boş bir
    // zemin değil, normal uygulama (venue profil) görünür. (Route opaque:false
    // ile açılır — aşağıdaki AddVenueStoryPage.route.)
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: SizedBox.shrink(),
    );
  }
}
