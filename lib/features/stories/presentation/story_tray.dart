import 'package:flutter/material.dart';
import '../data/story_model.dart';
import '../data/story_repository.dart';
import '../data/story_viewed_cache.dart';
import 'story_viewer_page.dart';

class StoryTray extends StatefulWidget {
  final String venueId;

  /// Aktif checkin varsa Add Story butonu gösterilir.
  final VoidCallback? onAddStory;

  /// Story yükleniyorsa "Me" balonu çevresinde loading çemberi döner.
  final bool isUploading;

  const StoryTray({
    super.key,
    required this.venueId,
    this.onAddStory,
    this.isUploading = false,
  });

  @override
  State<StoryTray> createState() => _StoryTrayState();
}

class _StoryTrayState extends State<StoryTray> {
  final _repo = StoryRepository();

  List<StoryItem> _myStories = [];
  List<StoryGroup> _groups = [];
  bool _loading = true;
  Set<String> _viewedIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _repo.getMyStories(),
        _repo.getVenueStories(widget.venueId),
        StoryViewedCache.loadAll(),
      ]);
      if (!mounted) return;
      setState(() {
        _myStories = results[0] as List<StoryItem>;
        _groups = results[1] as List<StoryGroup>;
        _viewedIds = results[2] as Set<String>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// Viewer kapandıktan sonra viewed cache'i yenile → halkalar güncellenir.
  Future<void> _refreshViewed() async {
    final ids = await StoryViewedCache.loadAll();
    if (!mounted) return;
    setState(() => _viewedIds = ids);
  }

  /// Verilen story listesinde ilk görülmemiş story'nin indexini döner.
  /// Hepsi görüldüyse 0 döner (baştan başlar).
  int _firstUnseenIndex(List<StoryItem> stories) {
    for (int i = 0; i < stories.length; i++) {
      if (!_viewedIds.contains(stories[i].id)) return i;
    }
    return 0;
  }

  void _openMyStories() {
    if (_myStories.isEmpty) return;
    final realStories =
        _myStories.where((s) => !s.isUploadingPlaceholder).toList();
    final meGroup = StoryGroup(
      user: StoryUser(id: 'me', fullName: 'Me'),
      stories: _myStories,
    );
    final startIndex = _firstUnseenIndex(realStories);
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StoryViewerPage(
          groups: [meGroup, ..._groups],
          initialGroupIndex: 0,
          initialStoryIndex: startIndex,
        ),
      ),
    ).then((_) => _refreshViewed());
  }

  void _openViewer(int groupIndex) {
    final meGroup = _myStories.isNotEmpty
        ? StoryGroup(
            user: StoryUser(id: 'me', fullName: 'Me'),
            stories: _myStories,
          )
        : null;

    final allGroups = [if (meGroup != null) meGroup, ..._groups];
    final offsetIndex = meGroup != null ? groupIndex + 1 : groupIndex;
    final group = _groups[groupIndex];
    final startIndex = _firstUnseenIndex(group.stories);

    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StoryViewerPage(
          groups: allGroups,
          initialGroupIndex: offsetIndex,
          initialStoryIndex: startIndex,
        ),
      ),
    ).then((_) => _refreshViewed());
  }

  @override
  Widget build(BuildContext context) {
    final hasAdd = widget.onAddStory != null;
    final hasMe = _myStories.isNotEmpty;

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

    // Hiç içerik yoksa tray'i gösterme
    if (!hasAdd && !hasMe && _groups.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 90,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: 1 + _groups.length, // "Me" her zaman ilk slot
        itemBuilder: (context, index) {
          if (index == 0) {
            final myIds = _myStories
                .where((s) => !s.isUploadingPlaceholder)
                .map((s) => s.id)
                .toList();
            final meSeen = StoryViewedCache.allViewedSync(myIds, _viewedIds);
            return _MeBubble(
              myStories: _myStories,
              isUploading: widget.isUploading,
              allSeen: meSeen,
              onAddStory: hasAdd ? widget.onAddStory! : null,
              onViewStories: hasMe ? _openMyStories : null,
            );
          }

          final groupIndex = index - 1;
          final group = _groups[groupIndex];
          final ids = group.stories.map((s) => s.id).toList();
          final seen = StoryViewedCache.allViewedSync(ids, _viewedIds);
          return _StoryBubble(
            group: group,
            allSeen: seen,
            onTap: () => _openViewer(groupIndex),
          );
        },
      ),
    );
  }
}

// ── Me bubble ─────────────────────────────────────────────────────────────────

class _MeBubble extends StatefulWidget {
  final List<StoryItem> myStories;
  final bool isUploading;
  final bool allSeen;
  final VoidCallback? onAddStory;
  final VoidCallback? onViewStories;

  const _MeBubble({
    required this.myStories,
    this.isUploading = false,
    this.allSeen = false,
    this.onAddStory,
    this.onViewStories,
  });

  @override
  State<_MeBubble> createState() => _MeBubbleState();
}

class _MeBubbleState extends State<_MeBubble>
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
  void didUpdateWidget(covariant _MeBubble old) {
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

  static String? _bubbleImage(List<StoryItem> stories) {
    if (stories.isEmpty) return null;
    // Featured checkin fotosu öncelikli
    for (final s in stories) {
      final f = s.checkinFeaturedPhotoUrl;
      if (f != null && f.isNotEmpty) return f;
    }
    return null;
  }

  void _openUploadingViewer() {
    // Mevcut storyler + en sona yüklenmekte olan placeholder.
    final stories = [
      ...widget.myStories,
      StoryItem.uploadingPlaceholder(),
    ];
    final meGroup = StoryGroup(
      user: StoryUser(id: 'me', fullName: 'Me'),
      stories: stories,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StoryViewerPage(groups: [meGroup]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasStories = widget.myStories.isNotEmpty;
    final canAdd = widget.onAddStory != null;
    final uploading = widget.isUploading;
    final allSeen = widget.allSeen;
    final color = Theme.of(context).colorScheme.primary;
    final bubbleImage = _bubbleImage(widget.myStories);

    // Hiç story yok ve add butonu da yoksa balonu gizle
    if (!hasStories && !canAdd) return const SizedBox.shrink();

    // Çember:
    //  - Yüklenirken: avatar SABİT kalır, sadece çevresinde dönen bir yay döner.
    //  - Story varsa: sabit Instagram gradyan çemberi.
    //  - Yoksa: soluk düz çember.
    Widget ring(Widget child) {
      if (uploading) {
        // İçteki avatar + beyaz boşluk sabit; üstüne dönen gradyan yay.
        final inner = Container(
          padding: const EdgeInsets.all(2.5),
          child: child,
        );
        return Stack(
          alignment: Alignment.center,
          children: [
            inner,
            Positioned.fill(
              child: RotationTransition(
                turns: _spin,
                child: CustomPaint(
                  painter: _LoadingArcPainter(),
                ),
              ),
            ),
          ],
        );
      }
      // Renk mantığı:
      //   - Story yok: soluk düz çember
      //   - Story var + hepsi görüldü (allSeen): gri çember
      //   - Story var + görülmemiş var: Instagram gradyan çember
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

    return GestureDetector(
      // Yüklenirken basılırsa loading ekranı; aksi halde story viewer.
      onTap: uploading
          ? _openUploadingViewer
          : (hasStories ? widget.onViewStories : null),
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                ring(
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).scaffoldBackgroundColor,
                    ),
                    child: CircleAvatar(
                      radius: 27,
                      backgroundColor: color.withValues(alpha: 0.12),
                      backgroundImage: bubbleImage != null
                          ? NetworkImage(bubbleImage)
                          : null,
                      child: bubbleImage == null
                          ? Icon(
                              hasStories ? Icons.videocam : Icons.person,
                              color: color,
                              size: 26,
                            )
                          : null,
                    ),
                  ),
                ),

                // "+" rozeti — yüklenirken gizli, ayrı tap target, kamera açar
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
            Text(
              uploading ? 'Uploading…' : 'Me',
              style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Yükleniyor yayı: avatar çevresinde dönen gradyan arc ───────────────────────

class _LoadingArcPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.8;
    final rect = Offset.zero & size;
    final inset = rect.deflate(stroke / 2);

    // Soluk taban halkası
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = const Color(0x22000000)
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(inset, 0, 6.28318, false, basePaint);

    // Dönen gradyan yay (~280°)
    final sweep = 4.9; // radyan
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


// ── Story bubble ──────────────────────────────────────────────────────────────

class _StoryBubble extends StatelessWidget {
  final StoryGroup group;
  final bool allSeen;
  final VoidCallback onTap;

  const _StoryBubble({
    required this.group,
    required this.onTap,
    this.allSeen = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: allSeen
                    ? null
                    : const LinearGradient(
                        colors: [Color(0xFFf09433), Color(0xFFbc2a8d)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                color: allSeen ? Colors.grey.shade400 : null,
              ),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).scaffoldBackgroundColor,
                ),
                child: CircleAvatar(
                  radius: 27,
                  backgroundImage: group.bubbleImageUrl != null &&
                          group.bubbleImageUrl!.isNotEmpty
                      ? NetworkImage(group.bubbleImageUrl!)
                      : null,
                  backgroundColor: Colors.grey.shade700,
                  child: group.bubbleImageUrl == null ||
                          group.bubbleImageUrl!.isEmpty
                      ? const Icon(Icons.person,
                          color: Colors.white70, size: 24)
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 5),
            SizedBox(
              width: 64,
              child: Text(
                group.user.displayName,
                style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w500),
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
