import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import '../../checkin/data/checkin_repository.dart';
import '../../checkin/data/checkin_profile_model.dart';
import 'package:video_player/video_player.dart';

class MomentsViewerPage extends StatefulWidget {
  final List<CheckinProfileMedia> media;
  final int initialIndex;
  final bool allowFeature;

  const MomentsViewerPage({
    super.key,
    required this.media,
    required this.initialIndex,
    this.allowFeature = false,
  });

  @override
  State<MomentsViewerPage> createState() => _MomentsViewerPageState();
}

class _MomentsViewerPageState extends State<MomentsViewerPage> {
  late PageController _controller;
  late int _currentIndex;
  final CheckinRepository _repo = CheckinRepository();
  bool _loading = false;
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

    setState(() => _loading = true);

    try {
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
      await showPremiumErrorDialog(
        context,
        message: 'Failed to set featured media',
      );
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _deleteMedia(CheckinProfileMedia media) async {
    final shouldDelete = await _confirmDelete(media);
    if (!shouldDelete) return;
    if (!mounted) return;

    setState(() => _loading = true);

    try {
      await _repo.deletePhoto(media.id);

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      log("Delete error: $e");
      await showPremiumErrorDialog(context, message: 'Failed to delete media');
    }

    if (mounted) setState(() => _loading = false);
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
                  child: Image.network(
                    item.url,
                    fit: BoxFit.cover,
                  ),
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
              icon: const Icon(Icons.close,
                  color: Colors.white, size: 28),
              onPressed: () =>
                  Navigator.pop(context, _hasChanged),
            ),
          ),

          // ⭐ FEATURE + 🗑 DELETE
          if (widget.allowFeature)
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                children: [
                  // FEATURE
                  GestureDetector(
                    onTap: !canFeaturePhoto || _loading
                        ? null
                        : _setFeatured,
                    child: CircleAvatar(
                      backgroundColor:
                          Colors.black.withValues(alpha: 0.6),
                      radius: 28,
                      child: _loading
                          ? const CircularProgressIndicator(
                              color: Colors.white,
                            )
                          : Icon(
                              Icons.star,
                              color: currentMedia.isFeatured
                                  ? Colors.amber
                                  : canFeaturePhoto
                                  ? Colors.white
                                  : Colors.white38,
                              size: 26,
                            ),
                    ),
                  ),

                  // DELETE
                  GestureDetector(
                    onTap: _loading
                        ? null
                        : () => _deleteMedia(currentMedia),
                    child: CircleAvatar(
                      backgroundColor:
                          Colors.black.withValues(alpha: 0.6),
                      radius: 28,
                      child: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                        size: 26,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
