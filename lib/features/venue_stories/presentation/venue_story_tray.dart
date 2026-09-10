import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/features/stories/data/story_model.dart';
import 'package:kmstry_frontend/features/stories/presentation/story_viewer_page.dart';
import '../data/venue_story_model.dart';
import '../data/venue_story_repository.dart';
import '../data/venue_story_viewed_cache.dart';

/// Venue adının yanında gösterilen tek story balonu.
/// Story yükleme, izleme ve "+" ekleme işlemlerini kendi içinde yönetir.
class VenueStoryBubble extends StatefulWidget {
  final String venueId;
  final String venueName;
  final String? venuePhotoUrl;
  final VoidCallback? onAddStory;
  final bool isUploading;

  const VenueStoryBubble({
    super.key,
    required this.venueId,
    required this.venueName,
    this.venuePhotoUrl,
    this.onAddStory,
    this.isUploading = false,
  });

  @override
  State<VenueStoryBubble> createState() => _VenueStoryBubbleState();
}

class _VenueStoryBubbleState extends State<VenueStoryBubble> {
  final _repo = VenueStoryRepository();

  List<VenueStoryItem> _stories = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant VenueStoryBubble old) {
    super.didUpdateWidget(old);
    if (old.isUploading && !widget.isUploading) _load();
  }

  Future<void> _load() async {
    try {
      final stories = await _repo.getVenueStories(widget.venueId);
      if (!mounted) return;
      setState(() {
        _stories = stories;
      });
    } catch (_) {}
  }

  void _openViewer() {
    if (_stories.isEmpty && !widget.isUploading) return;
    final venueId = widget.venueId;

    // Kaldığı yerden devam: ilk izlenmemiş story'den başla
    final startIndex = _stories.indexWhere((s) => !s.viewedByMe);
    final initialIndex = startIndex == -1 ? 0 : startIndex;

    final storyItems = _stories.map((s) => StoryItem(
          id: s.id,
          mediaUrl: s.mediaUrl,
          mediaType: s.mediaType,
          thumbnailUrl: s.thumbnailUrl,
          durationSecs: s.durationSecs,
          expiresAt: s.expiresAt,
          createdAt: s.createdAt,
          viewCount: s.viewCount,
        )).toList();

    if (widget.isUploading) storyItems.add(StoryItem.uploadingPlaceholder());

    final group = StoryGroup(
      user: StoryUser(
        id: 'venue_$venueId',
        fullName: widget.venueName,
        photo: widget.venuePhotoUrl,
      ),
      stories: storyItems,
    );

    Navigator.push<StoryViewerResult>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StoryViewerPage(
          groups: [group],
          venueId: venueId,
          initialStoryIndex: initialIndex,
          onClose: (lastIndex, allFinished) {
            final justViewed = allFinished
                ? _stories.map((s) => s.id).toSet()
                : { for (int i = 0; i <= lastIndex && i < _stories.length; i++) _stories[i].id };
            final cache = VenueStoryViewedCache.instance;
            justViewed.forEach(cache.mark);
            if (mounted) {
              setState(() {
                _stories = [
                  for (final s in _stories)
                    (s.viewedByMe || justViewed.contains(s.id)) ? s.copyWith(viewedByMe: true) : s,
                ];
              });
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasStories = _stories.isNotEmpty;
    final canAdd = widget.onAddStory != null;

    if (!hasStories && !canAdd && !widget.isUploading) {
      return const SizedBox.shrink();
    }

    final allSeen = _stories.isNotEmpty && _stories.every((s) => s.viewedByMe);

    return _VenueBubble(
      venuePhotoUrl: widget.venuePhotoUrl,
      venueName: widget.venueName,
      hasStories: hasStories,
      allSeen: allSeen,
      isUploading: widget.isUploading,
      onAddStory: canAdd ? widget.onAddStory! : null,
      onViewStories: hasStories || widget.isUploading ? _openViewer : null,
    );
  }
}

// ── Venue balonu ──────────────────────────────────────────────────────────────

class _VenueBubble extends StatefulWidget {
  final String venueName;
  final String? venuePhotoUrl;
  final bool hasStories;
  final bool allSeen;
  final bool isUploading;
  final VoidCallback? onAddStory;
  final VoidCallback? onViewStories;

  const _VenueBubble({
    required this.venueName,
    this.venuePhotoUrl,
    required this.hasStories,
    required this.allSeen,
    this.isUploading = false,
    this.onAddStory,
    this.onViewStories,
  });

  @override
  State<_VenueBubble> createState() => _VenueBubbleState();
}

class _VenueBubbleState extends State<_VenueBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.isUploading) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant _VenueBubble old) {
    super.didUpdateWidget(old);
    if (widget.isUploading && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.isUploading && _spin.isAnimating) {
      _spin.stop();
      _spin.value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Widget _ring(Widget child) {
    final color = Theme.of(context).colorScheme.primary;

    if (widget.isUploading) {
      return Stack(
        alignment: Alignment.center,
        children: [
          Container(padding: const EdgeInsets.all(2.5), child: child),
          Positioned.fill(
            child: RotationTransition(
              turns: _spin,
              child: CustomPaint(painter: _LoadingArcPainter()),
            ),
          ),
        ],
      );
    }

    final showGradient = widget.hasStories && !widget.allSeen;
    final showGray = widget.hasStories && widget.allSeen;

    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: showGradient
            ? const SweepGradient(
                colors: [
                  AppColors.magenta,
                  AppColors.teal,
                  AppColors.blue,
                  AppColors.orange,
                  AppColors.brand,
                  AppColors.magenta,
                ],
                startAngle: -1.5708,
                endAngle: 4.7124,
              )
            : null,
        color: showGray
            ? Colors.grey.shade400
            : (!widget.hasStories ? color.withValues(alpha: 0.3) : null),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final canAdd = widget.onAddStory != null;
    final uploading = widget.isUploading;
    final color = Theme.of(context).colorScheme.primary;
    final photo = widget.venuePhotoUrl;

    return GestureDetector(
      onTap: uploading ? widget.onViewStories : widget.onViewStories,
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                _ring(
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).scaffoldBackgroundColor,
                    ),
                    child: CircleAvatar(
                      radius: 27,
                      backgroundColor: color.withValues(alpha: 0.12),
                      backgroundImage: photo != null && photo.isNotEmpty
                          ? NetworkImage(photo)
                          : null,
                      child: photo == null || photo.isEmpty
                          ? Icon(Icons.storefront, color: color, size: 26)
                          : null,
                    ),
                  ),
                ),
                if (canAdd && !uploading)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: widget.onAddStory,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            width: 1.5,
                          ),
                        ),
                        child:
                            const Icon(Icons.add, color: Colors.white, size: 13),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Yükleniyor yayı ───────────────────────────────────────────────────────────

class _LoadingArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.8;
    final rect = Offset.zero & size;
    final inset = rect.deflate(stroke / 2);

    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppColors.magenta.withValues(alpha: 0.15)
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(inset, 0, 6.28318, false, basePaint);

    final shader = const SweepGradient(
      colors: [
        Color(0x00E020D8), // magenta transparent tail
        AppColors.magenta,
        AppColors.teal,
        AppColors.blue,
        AppColors.orange,
        AppColors.brand,
      ],
      stops: [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
    ).createShader(rect);

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = shader;
    canvas.drawArc(inset, -1.5708, 4.9, false, arcPaint);
  }

  @override
  bool shouldRepaint(covariant _LoadingArcPainter oldDelegate) => false;
}
