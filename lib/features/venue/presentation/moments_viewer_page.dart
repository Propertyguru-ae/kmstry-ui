import 'dart:developer';
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();

    // 🔥 HATA BURADAYDI
    _media = List.from(widget.media);

    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);

    // İlk item video ise başlat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupVideoIfNeeded(_currentIndex);
    });
  }

  Future<void> _setupVideoIfNeeded(int index) async {
    final item = _media[index];

    _videoController?.dispose();
    _videoController = null;

    if (item.mediaType == MediaType.video) {
      _videoController =
          VideoPlayerController.networkUrl(Uri.parse(item.url));

      await _videoController!.initialize();
      await _videoController!.setLooping(true);
      await _videoController!.play();

      if (mounted) setState(() {});
    }
  }

  Future<void> _setFeatured() async {
    setState(() => _loading = true);

    try {
      final selected = _media[_currentIndex];

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to set featured media")),
      );
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _deleteMedia(CheckinProfileMedia media) async {
    setState(() => _loading = true);

    try {
      await _repo.deletePhoto(media.id);

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      log("Delete error: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to delete media")),
      );
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentMedia = _media[_currentIndex];

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
                return Center(
                  child: InteractiveViewer(
                    child: Image.network(
                      item.url,
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              }

              // 🎬 VIDEO
              return Center(
                child: _videoController != null &&
                        _videoController!.value.isInitialized &&
                        _currentIndex == index
                    ? AspectRatio(
                        aspectRatio:
                            _videoController!.value.aspectRatio,
                        child: VideoPlayer(_videoController!),
                      )
                    : const CircularProgressIndicator(
                        color: Colors.white,
                      ),
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
                    onTap: currentMedia.isFeatured || _loading
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
                                  : Colors.white,
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
