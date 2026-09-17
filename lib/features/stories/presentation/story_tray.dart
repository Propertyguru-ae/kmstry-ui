import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'package:kmstry_frontend/core/media/media_reference.dart';
import '../data/story_model.dart';
import '../data/story_repository.dart';
import '../data/story_viewed_cache.dart';
import '../data/story_visibility.dart';
import 'story_viewer_page.dart';

class StoryTray extends StatefulWidget {
  final String venueId;

  /// Aktif checkin varsa Add Story butonu gösterilir.
  final VoidCallback? onAddStory;

  /// Story yükleniyorsa "Me" balonu çevresinde loading çemberi döner.
  final bool isUploading;

  /// Anonymous Mode açıksa "+" balonu soluk/inactive görünür; basınca ekleme
  /// yerine [onAddStory] bilgilendirme popup'ı gösterir.
  final bool anonymousLocked;

  /// Kendi story'si yokken "Me" balonunda gösterilecek profil/check-in resmi.
  final String? myPhotoUrl;

  /// Kullanıcının BU venue'da kendi story'si olup olmadığını üst widget'a bildirir
  /// (ör. venue detail'de "story paylaş" teşvik metnini göstermek için).
  final ValueChanged<bool>? onMyStoryStateChanged;

  /// Bu venue'da HİÇ story olup olmadığını (kimsenin paylaşmadığını) üst
  /// widget'a bildirir — venue detail'de "ilk story'yi sen paylaş" CTA'sı için.
  final ValueChanged<bool>? onStoriesEmptyChanged;

  const StoryTray({
    super.key,
    required this.venueId,
    this.onAddStory,
    this.isUploading = false,
    this.anonymousLocked = false,
    this.myPhotoUrl,
    this.onMyStoryStateChanged,
    this.onStoriesEmptyChanged,
  });

  @override
  State<StoryTray> createState() => _StoryTrayState();
}

class _StoryTrayState extends State<StoryTray> {
  final _repo = StoryRepository();

  List<StoryItem> _myStories = [];
  List<StoryGroup> _groups = [];
  bool _loading = true;
  bool _initialLoaded = false;
  int _loadRequest = 0;
  // Local session-only viewed IDs — populated from backend on load, updated after viewer closes.
  // NOT persisted to SharedPreferences to avoid cross-user contamination.
  Set<String> _viewedIds = {};

  @override
  void initState() {
    super.initState();
    StoryVisibility.changes.addListener(_onVisibilityChanged);
    _load();
  }

  @override
  void dispose() {
    StoryVisibility.changes.removeListener(_onVisibilityChanged);
    super.dispose();
  }

  void _onVisibilityChanged() {
    if (!mounted) return;
    final change = StoryVisibility.changes.value;
    if (change == null) return;
    setState(() => _groups = change.apply(_groups));
    _load();
  }

  Future<void> _load() async {
    final request = ++_loadRequest;
    _loadMyStories();
    try {
      final freshGroups = await _repo.getVenueStories(widget.venueId);
      if (!mounted || request != _loadRequest) return;

      // İlk yüklemede backend'in shuffle'lı sırasını kullan.
      // Sonraki yüklemelerde (viewer kapandıktan sonra) mevcut sırayı koru —
      // sadece viewed_by_me bilgisini güncelle, kullanıcı şaşırmasın.
      final List<StoryGroup> orderedGroups;
      if (!_initialLoaded) {
        orderedGroups = freshGroups;
      } else {
        final freshMap = {for (final g in freshGroups) g.user.id: g};
        orderedGroups = [
          for (final g in _groups)
            if (freshMap.containsKey(g.user.id)) freshMap[g.user.id]!,
          for (final g in freshGroups)
            if (!_groups.any((e) => e.user.id == g.user.id)) g,
        ];
      }

      final backendViewed = <String>{};
      for (final g in orderedGroups) {
        for (final s in g.stories) {
          if (s.viewedByMe) backendViewed.add(s.id);
        }
      }
      // İzlenme durumunu kalıcı cache ile birleştir — özellikle kendi ("Me")
      // story'lerinde backend viewed_by_me false döndüğü için, sayfa yeniden
      // yaratılınca halka tekrar renkli görünüyordu. Cache logout'ta temizlendiği
      // için cross-user contamination riski yok.
      final persistedViewed = await StoryViewedCache.loadAll();
      if (!mounted || request != _loadRequest) return;
      setState(() {
        _groups = orderedGroups;
        _viewedIds = {...backendViewed, ...persistedViewed};
        _loading = false;
        _initialLoaded = true;
      });
      _notifyEmptiness();
    } catch (_) {
      if (!mounted || request != _loadRequest) return;
      setState(() => _loading = false);
    }
  }

  void _notifyEmptiness() {
    widget.onStoriesEmptyChanged?.call(_groups.isEmpty && _myStories.isEmpty);
  }

  Future<void> _loadMyStories() async {
    try {
      final stories = await _repo.getMyStories();
      if (!mounted) return;
      // getMyStories tüm venue'lardaki kendi story'lerini döndürür; bu tray
      // venue'ya özel olduğu için yalnızca BU venue'nunkileri göster. Aksi
      // halde Alpha'da paylaşılan story Beta detay sayfasında da görünüyordu.
      final venueStories = stories
          .where((s) => s.venueId == widget.venueId)
          .toList();
      setState(() => _myStories = venueStories);
      widget.onMyStoryStateChanged?.call(venueStories.isNotEmpty);
      _notifyEmptiness();
    } catch (_) {}
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
    final realStories = _myStories
        .where((s) => !s.isUploadingPlaceholder)
        .toList();
    final meGroup = StoryGroup(
      user: StoryUser(id: 'me', fullName: 'Me'),
      stories: _myStories,
      isCurrentUserOwner: true,
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
    ).then((result) {
      if (!mounted) return;
      if (result is StoryViewerResult) {
        _markMyStoriesViewed(result.lastStoryIndex, result.allFinished);
      }
      _load();
    });
  }

  void _openViewer(int groupIndex) {
    final meGroup = _myStories.isNotEmpty
        ? StoryGroup(
            user: StoryUser(id: 'me', fullName: 'Me'),
            stories: _myStories,
            isCurrentUserOwner: true,
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
    ).then((result) {
      if (!mounted) return;
      if (result is StoryViewerResult && result.lastStoryIndex >= 0) {
        _markViewedForGroup(allGroups[offsetIndex], result);
      }
      _load();
    });
  }

  void _markMyStoriesViewed(int lastIndex, bool allFinished) {
    if (_myStories.isEmpty) return;
    final ids = allFinished
        ? _myStories.map((s) => s.id)
        : [
            for (int i = 0; i <= lastIndex && i < _myStories.length; i++)
              _myStories[i].id,
          ];
    setState(() => _viewedIds = {..._viewedIds, ...ids});
  }

  void _markViewedForGroup(StoryGroup group, StoryViewerResult result) {
    if (group.isCurrentUserOwner) {
      _markMyStoriesViewed(result.lastStoryIndex, result.allFinished);
      return;
    }
    final ids = result.allFinished
        ? group.stories.map((s) => s.id)
        : [
            for (
              int i = 0;
              i <= result.lastStoryIndex && i < group.stories.length;
              i++
            )
              group.stories[i].id,
          ];
    setState(() => _viewedIds = {..._viewedIds, ...ids});
  }

  @override
  Widget build(BuildContext context) {
    final hasAdd = widget.onAddStory != null;
    final hasMe = _myStories.isNotEmpty;

    if (_loading && !hasAdd && !hasMe) {
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
            final meSeen =
                myIds.isNotEmpty &&
                myIds.every((id) => _viewedIds.contains(id));
            return _MeBubble(
              myStories: _myStories,
              isUploading: widget.isUploading,
              allSeen: meSeen,
              onAddStory: hasAdd ? widget.onAddStory! : null,
              onViewStories: hasMe ? _openMyStories : null,
              anonymousLocked: widget.anonymousLocked,
              fallbackImageUrl: widget.myPhotoUrl,
            );
          }

          final groupIndex = index - 1;
          final group = _groups[groupIndex];
          final ids = group.stories.map((s) => s.id).toList();
          final seen =
              ids.isNotEmpty && ids.every((id) => _viewedIds.contains(id));
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

// ── Logo brand ring colors ─────────────────────────────────────────────────────

const _kBrandRingColors = [
  AppColors.magenta,
  AppColors.teal,
  AppColors.blue,
  AppColors.orange,
  AppColors.brand,
];

// ── Shared square ring painter (static gradient — full ring) ──────────────────

class _SquareRingPainter extends CustomPainter {
  final List<Color> colors;
  final double pad;
  final double strokeWidth;
  final double radius;

  const _SquareRingPainter({
    required this.colors,
    required this.pad,
    required this.strokeWidth,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect =
        Offset(strokeWidth / 2, strokeWidth / 2) &
        Size(size.width - strokeWidth, size.height - strokeWidth);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final shader = SweepGradient(
      colors: [...colors, colors.first],
    ).createShader(rect);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..shader = shader
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SquareRingPainter old) => old.colors != colors;
}

// ── Square spinner painter (fade-tail, rotated by RotationTransition) ──────────

class _SquareSpinnerPainter extends CustomPainter {
  final double strokeWidth;
  final double radius;

  const _SquareSpinnerPainter({
    required this.strokeWidth,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect =
        Offset(strokeWidth / 2, strokeWidth / 2) &
        Size(size.width - strokeWidth, size.height - strokeWidth);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // Soluk arka plan halkası
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = AppColors.magenta.withValues(alpha: 0.15)
        ..strokeCap = StrokeCap.round,
    );

    // Soluktan başlayıp parlayan tail — gradient sweep
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
      startAngle: -1.5708,
      endAngle: 4.7124,
    ).createShader(rect);

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..shader = shader
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SquareSpinnerPainter old) =>
      old.strokeWidth != strokeWidth || old.radius != radius;
}

// ── Shared square avatar ───────────────────────────────────────────────────────

const _kAvatarSize = 54.0;
const _kRingPad = 3.0;
const _kRingStroke = 2.2;
const _kAvatarRadius = 11.0;

Widget _squareAvatar({
  required BuildContext context,
  required String? imageUrl,
  MediaReference? mediaReference,
  required Widget placeholder,
}) {
  return Container(
    width: _kAvatarSize,
    height: _kAvatarSize,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(_kAvatarRadius),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(_kAvatarRadius),
      child: imageUrl != null && imageUrl.isNotEmpty
          ? CachedImage(
              imageUrl,
              fit: BoxFit.cover,
              mediaReference: mediaReference,
            )
          : placeholder,
    ),
  );
}

// ── Me bubble ─────────────────────────────────────────────────────────────────

class _MeBubble extends StatefulWidget {
  final List<StoryItem> myStories;
  final bool isUploading;
  final bool allSeen;
  final VoidCallback? onAddStory;
  final VoidCallback? onViewStories;
  final bool anonymousLocked;
  final String? fallbackImageUrl;

  const _MeBubble({
    required this.myStories,
    this.isUploading = false,
    this.allSeen = false,
    this.onAddStory,
    this.onViewStories,
    this.anonymousLocked = false,
    this.fallbackImageUrl,
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
    // Home'daki "Your story" balonuyla aynı kaynağı kullan. Fotoğraf üzerine
    // yazılan metin görsele işlendiği için story medyası, eski check-in
    // featured görselinden önce gelmeli.
    for (final s in stories) {
      final thumbnail = s.thumbnailUrl;
      if (thumbnail != null && thumbnail.isNotEmpty) return thumbnail;
      if (!s.isVideo && s.mediaUrl.isNotEmpty) return s.mediaUrl;
    }
    for (final s in stories) {
      final f = s.checkinFeaturedPhotoUrl;
      if (f != null && f.isNotEmpty) return f;
    }
    return null;
  }

  void _openUploadingViewer() {
    final stories = [...widget.myStories, StoryItem.uploadingPlaceholder()];
    final meGroup = StoryGroup(
      user: StoryUser(id: 'me', fullName: 'Me'),
      stories: stories,
      isCurrentUserOwner: true,
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
    final color = Theme.of(context).colorScheme.primary;
    final bubbleImg = _bubbleImage(widget.myStories) ?? widget.fallbackImageUrl;

    if (!hasStories && !canAdd) return const SizedBox.shrink();

    final avatar = _squareAvatar(
      context: context,
      imageUrl: bubbleImg,
      placeholder: Center(
        child: Icon(
          hasStories ? Icons.videocam : Icons.person,
          color: color,
          size: 24,
        ),
      ),
    );

    final ringColors = hasStories && !widget.allSeen
        ? _kBrandRingColors
        : [Colors.grey.shade400, Colors.grey.shade400];

    Widget content;
    if (uploading) {
      final totalSize = _kAvatarSize + (_kRingPad + _kRingStroke) * 2;
      content = SizedBox(
        width: totalSize,
        height: totalSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(_kRingPad + _kRingStroke),
              child: avatar,
            ),
            Positioned.fill(
              child: RotationTransition(
                turns: _spin,
                child: CustomPaint(
                  painter: _SquareSpinnerPainter(
                    strokeWidth: _kRingStroke,
                    radius: _kAvatarRadius + _kRingPad + _kRingStroke,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    } else if (hasStories) {
      content = CustomPaint(
        painter: _SquareRingPainter(
          colors: ringColors,
          pad: _kRingPad,
          strokeWidth: _kRingStroke,
          radius: _kAvatarRadius + _kRingPad + _kRingStroke,
        ),
        child: Padding(
          padding: const EdgeInsets.all(_kRingPad + _kRingStroke),
          child: avatar,
        ),
      );
    } else if (canAdd) {
      // Story yokken baloncuk belirgin dursun ama DÜZ renk olsun (gradient
      // yalnızca bakılmamış story varken). "Story ekle" affordance'ı için
      // marka mavisi tek renk halka.
      content = CustomPaint(
        painter: _SquareRingPainter(
          colors: const [AppColors.blue, AppColors.blue],
          pad: _kRingPad,
          strokeWidth: _kRingStroke,
          radius: _kAvatarRadius + _kRingPad + _kRingStroke,
        ),
        child: Padding(
          padding: const EdgeInsets.all(_kRingPad + _kRingStroke),
          child: avatar,
        ),
      );
    } else {
      content = avatar;
    }

    return GestureDetector(
      onTap: uploading
          ? _openUploadingViewer
          : (hasStories ? widget.onViewStories : widget.onAddStory),
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                content,
                if (canAdd && !uploading)
                  Positioned(
                    right: hasStories ? 0 : -2,
                    bottom: hasStories ? 0 : -2,
                    child: GestureDetector(
                      onTap: widget.onAddStory,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          // Anonymous: dim the "+" so it reads as inactive.
                          color: widget.anonymousLocked
                              ? Colors.grey.shade500
                              : color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          widget.anonymousLocked
                              ? Icons.lock_outline_rounded
                              : Icons.add,
                          color: Colors.white,
                          size: 13,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            SizedBox(
              width: _kAvatarSize + (_kRingPad + _kRingStroke) * 2,
              child: Text(
                uploading
                    ? 'Uploading…'
                    : (!hasStories && canAdd ? 'Your story' : 'Me'),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
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
    final ringColors = allSeen
        ? [Colors.grey.shade400, Colors.grey.shade400]
        : _kBrandRingColors;

    final avatar = _squareAvatar(
      context: context,
      imageUrl: group.bubbleImageUrl,
      mediaReference: group.bubbleMediaReference,
      placeholder: const Center(
        child: Icon(Icons.person, color: Colors.white70, size: 24),
      ),
    );

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(
              painter: _SquareRingPainter(
                colors: ringColors,
                pad: _kRingPad,
                strokeWidth: _kRingStroke,
                radius: _kAvatarRadius + _kRingPad + _kRingStroke,
              ),
              child: Padding(
                padding: const EdgeInsets.all(_kRingPad + _kRingStroke),
                child: avatar,
              ),
            ),
            const SizedBox(height: 5),
            SizedBox(
              width: _kAvatarSize + (_kRingPad + _kRingStroke) * 2,
              child: Text(
                group.user.displayName,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
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
