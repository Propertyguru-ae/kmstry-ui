import 'dart:developer';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/features/checkin/services/avatar_crop_helper.dart';
import '../../checkin/data/checkin_repository.dart';
import '../../checkin/data/checkin_profile_model.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

class MomentsViewerPage extends StatefulWidget {
  final List<CheckinProfileMedia> media;
  final int initialIndex;
  final bool allowFeature;
  final String? checkinId;

  const MomentsViewerPage({
    super.key,
    required this.media,
    required this.initialIndex,
    this.allowFeature = false,
    this.checkinId,
  });

  @override
  State<MomentsViewerPage> createState() => _MomentsViewerPageState();
}

class _MomentsViewerPageState extends State<MomentsViewerPage> {
  late PageController _controller;
  late int _currentIndex;
  final CheckinRepository _repo = CheckinRepository();
  bool _loading = false; // sadece "featured yap" işlemi (yıldız spinner'ı)
  bool _deleting = false;
  late List<CheckinProfileMedia> _media;
  bool _hasChanged = false;
  VideoPlayerController? _videoController;
  int _setupSeq = 0;

  int _safeInitialIndex(List<CheckinProfileMedia> media, int requestedIndex) {
    if (media.isEmpty) return 0;
    if (requestedIndex < 0) return 0;
    if (requestedIndex >= media.length) return media.length - 1;
    return requestedIndex;
  }

  @override
  void initState() {
    super.initState();

    // 🔥 HATA BURADAYDI
    _media = List.from(widget.media);

    _currentIndex = _safeInitialIndex(_media, widget.initialIndex);
    _controller = PageController(initialPage: _currentIndex);

    // İlk item video ise başlat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupVideoIfNeeded(_currentIndex);
    });
  }

  Future<void> _setupVideoIfNeeded(int index) async {
    if (_media.isEmpty) return;
    if (index < 0 || index >= _media.length) return;
    final item = _media[index];

    final seq = ++_setupSeq;

    _videoController?.dispose();
    _videoController = null;

    if (item.mediaType != MediaType.video) return;

    final controller = VideoPlayerController.networkUrl(Uri.parse(item.url));

    await controller.initialize();

    // Eğer bu arada yeni bir setup çağrısı geldiyse bu sonucu kullanma
    if (seq != _setupSeq) {
      controller.dispose();
      return;
    }

    await controller.setLooping(true);
    await controller.play();

    _videoController = controller;

    if (mounted) setState(() {});
  }

  Future<void> _setFeatured() async {
    final selected = _media[_currentIndex];
    if (selected.mediaType != MediaType.photo) {
      await showPremiumErrorDialog(
        context,
        message: 'Only photos can be featured.',
      );
      return;
    }

    try {
      setState(() => _loading = true);
      await _repo.setFeaturedPhoto(selected.id);
      if (!mounted) return;

      setState(() {
        _media = _media.map((m) {
          return m.copyWith(isFeatured: m.id == selected.id);
        }).toList();
        _hasChanged = true;
      });
    } catch (e) {
      log("Feature error: $e");
      if (!mounted) return;
      await showPremiumErrorDialog(
        context,
        message: 'Failed to set featured media',
      );
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      if (mounted) {
        await _showFeaturedCropPrompt(selected);
      }
    } catch (e) {
      log("Featured avatar crop/upload error: $e");
      if (mounted) {
        await showPremiumErrorDialog(
          context,
          message: 'Featured updated, but avatar crop could not be saved.',
        );
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _showFeaturedCropPrompt(CheckinProfileMedia selected) async {
    final checkinId = widget.checkinId;
    if (checkinId == null || checkinId.isEmpty) return;

    final colors = Theme.of(context).colorScheme;
    final shouldCrop = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.onSurface.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Use as your check-in avatar?',
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Adjust how this featured photo appears on your profile while this check-in is active.',
                  style: TextStyle(
                    color: colors.onSurface.withValues(alpha: 0.62),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.crop_rounded),
                  title: const Text('Adjust crop'),
                  onTap: () => Navigator.pop(ctx, true),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.check_circle_outline_rounded),
                  title: const Text('Use as is'),
                  onTap: () => Navigator.pop(ctx, false),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (shouldCrop != true || !mounted) return;

    final localFile = await _downloadMediaToTemp(selected.url);
    if (!mounted) return;
    if (localFile == null) {
      throw Exception('Could not download selected featured photo for crop');
    }

    final cropped = await cropSquareAvatar(context, localFile);
    if (!mounted || cropped == null) return;

    await _repo.uploadCheckinAvatar(checkinId: checkinId, file: cropped);
    _hasChanged = true;
  }

  Future<File?> _downloadMediaToTemp(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode >= 400) return null;
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/kmstry-featured-avatar-${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(response.bodyBytes, flush: true);
      return file;
    } catch (e) {
      log('Featured avatar download error: $e');
      return null;
    }
  }

  Future<void> _deleteMedia(CheckinProfileMedia media) async {
    final shouldDelete = await _confirmDelete(media);
    if (!shouldDelete) return;
    if (!mounted) return;

    setState(() => _deleting = true);

    try {
      await _repo.deletePhoto(media.id);

      if (!mounted) return;

      // Story mantığı: silinince listeden çıkar. Başka post varsa bir sonrakini
      // göster; hiç kalmadıysa kapanıp profile dön.
      _media.removeWhere((m) => m.id == media.id);
      _hasChanged = true;

      if (_media.isEmpty) {
        Navigator.pop(context, true);
        return;
      }

      // Silinen item mevcut index'teydi; liste kaydığı için aynı index artık
      // bir sonraki postu gösterir. Son item silindiyse bir geri git.
      final newIndex = _currentIndex >= _media.length
          ? _media.length - 1
          : _currentIndex;

      setState(() {
        _currentIndex = newIndex;
        _deleting = false;
      });
      _controller.jumpToPage(newIndex);
      await _setupVideoIfNeeded(newIndex);
      return;
    } catch (e) {
      log("Delete error: $e");
      if (!mounted) return;
      await showPremiumErrorDialog(context, message: 'Failed to delete media');
    }

    if (mounted) setState(() => _deleting = false);
  }

  Future<bool> _confirmDelete(CheckinProfileMedia media) async {
    final typeLabel = media.mediaType == MediaType.video ? 'video' : 'photo';
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete media'),
        content: Text(
          'Are you sure you want to delete this $typeLabel? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return result == true;
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_media.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              const Center(
                child: Text(
                  'No moments available',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.pop(context, _hasChanged),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final currentMedia = _media[_currentIndex];
    final canFeaturePhoto =
        currentMedia.mediaType == MediaType.photo && !currentMedia.isFeatured;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: _media.length,
            onPageChanged: (index) async {
              setState(() => _currentIndex = index);
              await _setupVideoIfNeeded(index);
            },
            itemBuilder: (context, index) {
              final item = _media[index];

              // 🖼 PHOTO
              if (item.mediaType == MediaType.photo) {
                return SizedBox.expand(
                  child: CachedImage(item.url, fit: BoxFit.cover),
                );
              }

              // 🎬 VIDEO
              if (_videoController != null &&
                  _videoController!.value.isInitialized &&
                  _currentIndex == index) {
                return SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: _videoController!.value.size.width,
                      height: _videoController!.value.size.height,
                      child: VideoPlayer(_videoController!),
                    ),
                  ),
                );
              }
              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            },
          ),

          // ❌ CLOSE
          Positioned(
            top: 40,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context, _hasChanged),
            ),
          ),

          // ⭐ FEATURE + 🗑 DELETE
          if (widget.allowFeature)
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // FEATURE — glass buton, featured'da teal accent.
                  _GlassCircleButton(
                    onTap: !canFeaturePhoto || _loading || _deleting
                        ? null
                        : _setFeatured,
                    busy: _loading,
                    icon: currentMedia.isFeatured
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    iconColor: currentMedia.isFeatured
                        ? AppColors.tealDark
                        : canFeaturePhoto
                        ? Colors.white
                        : Colors.white38,
                    spinnerColor: AppColors.tealDark,
                  ),

                  // DELETE — glass buton, magenta accent.
                  _GlassCircleButton(
                    onTap: _loading || _deleting
                        ? null
                        : () => _deleteMedia(currentMedia),
                    busy: _deleting,
                    icon: Icons.delete_outline_rounded,
                    iconColor: AppColors.magentaDark,
                    spinnerColor: AppColors.magentaDark,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Uygulama geneli glassmorphism buton — buzlu cam daire, ince kenarlık.
/// Moments viewer'daki featured/delete aksiyonları için kullanılır.
class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({
    required this.onTap,
    required this.icon,
    required this.iconColor,
    this.busy = false,
    this.spinnerColor = Colors.white,
  });

  final VoidCallback? onTap;
  final IconData icon;
  final Color iconColor;
  final bool busy;
  final Color spinnerColor;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Material(
          color: Colors.white.withValues(alpha: 0.12),
          child: InkWell(
            onTap: onTap,
            child: Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
              ),
              child: busy
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: spinnerColor,
                      ),
                    )
                  : Icon(icon, color: iconColor, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}
