import 'package:flutter/material.dart';
import '../data/story_model.dart';
import '../data/story_repository.dart';
import '../data/story_viewed_cache.dart';
import 'story_viewer_page.dart';

/// Venue profil sayfasında gösterilen story tray.
/// "Venue" balonu: venue'nun kendi paylaştığı story'ler (checkin bağımsız).
class VenueStoryTray extends StatefulWidget {
  final String venueId;
  final String venueName;
  final String? venuePhotoUrl;

  /// Story yükleniyorsa dönen animasyon gösterilir.
  final bool isUploading;

  /// Yeni story eklemek için callback (kamera açar).
  final VoidCallback? onAddStory;

  const VenueStoryTray({
    super.key,
    required this.venueId,
    required this.venueName,
    this.venuePhotoUrl,
    this.isUploading = false,
    this.onAddStory,
  });

  @override
  State<VenueStoryTray> createState() => _VenueStoryTrayState();
}

class _VenueStoryTrayState extends State<VenueStoryTray> {
  final _repo = StoryRepository();

  List<StoryItem> _venueStories = [];
  bool _loading = true;
  Set<String> _viewedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant VenueStoryTray old) {
    super.didUpdateWidget(old);
    // Yükleme bitti (isUploading false → true → false): yenile
    if (old.isUploading && !widget.isUploading) {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _repo.getVenueOwnStories(widget.venueId),
        StoryViewedCache.loadAll(),
      ]);
      if (!mounted) return;
      setState(() {
        _venueStories = results[0] as List<StoryItem>;
        _viewedIds = results[1] as Set<String>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _refreshViewed() async {
    final ids = await StoryViewedCache.loadAll();
    if (!mounted) return;
    setState(() => _viewedIds = ids);
  }

  void _openViewer() {
    if (_venueStories.isEmpty && !widget.isUploading) return;

    final stories = widget.isUploading
        ? [..._venueStories, StoryItem.uploadingPlaceholder()]
        : _venueStories;

    final venueUser = StoryUser(
      id: 'venue_${widget.venueId}',
      fullName: widget.venueName,
      photo: widget.venuePhotoUrl,
    );
    final group = StoryGroup(user: venueUser, stories: stories);

    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StoryViewerPage(groups: [group]),
      ),
    ).then((_) => _refreshViewed());
  }

  @override
  Widget build(BuildContext context) {
    final hasStories = _venueStories.isNotEmpty;
    final canAdd = widget.onAddStory != null;

    if (_loading) {
      return const SizedBox(
        height: 90,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    // Hiç story yok ve add butonu da yoksa gösterme
    if (!hasStories && !canAdd && !widget.isUploading) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 90,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _VenueBubble(
            venueName: widget.venueName,
            venuePhotoUrl: widget.venuePhotoUrl,
            stories: _venueStories,
            viewedIds: _viewedIds,
            isUploading: widget.isUploading,
            onAddStory: canAdd ? widget.onAddStory! : null,
            onViewStories: hasStories || widget.isUploading ? _openViewer : null,
          ),
        ],
      ),
    );
  }
}

// ── Venue balonu ──────────────────────────────────────────────────────────────

class _VenueBubble extends StatefulWidget {
  final String venueName;
  final String? venuePhotoUrl;
  final List<StoryItem> stories;
  final Set<String> viewedIds;
  final bool isUploading;
  final VoidCallback? onAddStory;
  final VoidCallback? onViewStories;

  const _VenueBubble({
    required this.venueName,
    this.venuePhotoUrl,
    required this.stories,
    required this.viewedIds,
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

  bool get _allSeen {
    final ids = widget.stories
        .where((s) => !s.isUploadingPlaceholder)
        .map((s) => s.id)
        .toList();
    return StoryViewedCache.allViewedSync(ids, widget.viewedIds);
  }

  Widget _ring(Widget child) {
    final hasStories = widget.stories.isNotEmpty;
    final allSeen = _allSeen;
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

    final showGradient = hasStories && !allSeen;
    final showGray = hasStories && allSeen;

    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: showGradient
            ? const LinearGradient(
                colors: [Color(0xFFf09433), Color(0xFFbc2a8d)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: showGray
            ? Colors.grey.shade400
            : (!hasStories ? color.withValues(alpha: 0.3) : null),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasStories = widget.stories.isNotEmpty;
    final canAdd = widget.onAddStory != null;
    final uploading = widget.isUploading;
    final color = Theme.of(context).colorScheme.primary;
    final photo = widget.venuePhotoUrl;

    final label = widget.venueName.length > 10
        ? '${widget.venueName.substring(0, 10)}…'
        : widget.venueName;

    return GestureDetector(
      onTap: uploading
          ? widget.onViewStories
          : (hasStories ? widget.onViewStories : null),
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
                      backgroundImage:
                          photo != null && photo.isNotEmpty
                              ? NetworkImage(photo)
                              : null,
                      child: photo == null || photo.isEmpty
                          ? Icon(Icons.storefront,
                              color: color, size: 26)
                          : null,
                    ),
                  ),
                ),

                // "+" rozeti — yüklenirken gizli
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
                        child: const Icon(Icons.add,
                            color: Colors.white, size: 13),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            SizedBox(
              width: 64,
              child: Text(
                uploading ? 'Uploading…' : label,
                style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
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
      ..color = const Color(0x22000000)
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(inset, 0, 6.28318, false, basePaint);

    final sweep = 4.9;
    final shader = const SweepGradient(
      colors: [
        Color(0x00f09433),
        Color(0xFFf09433),
        Color(0xFFbc2a8d),
      ],
      stops: [0.0, 0.5, 1.0],
    ).createShader(rect);

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = shader;
    canvas.drawArc(inset, -1.5708, sweep, false, arcPaint);
  }

  @override
  bool shouldRepaint(covariant _LoadingArcPainter oldDelegate) => false;
}
