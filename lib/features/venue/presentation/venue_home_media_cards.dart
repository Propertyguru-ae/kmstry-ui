import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/content_moderation/presentation/sharing_permission_hint.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'package:kmstry_frontend/core/venue/plan_gate.dart';
import 'package:kmstry_frontend/core/venue/venue_plan.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_upload_coordinator.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_picker.dart';
import 'package:kmstry_frontend/features/stories/data/story_model.dart';
import 'package:kmstry_frontend/features/stories/presentation/story_viewer_page.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_gallery_section.dart';
import 'package:kmstry_frontend/features/venue_stories/data/venue_story_model.dart';
import 'package:kmstry_frontend/features/venue_stories/data/venue_story_repository.dart';
import 'package:kmstry_frontend/features/venue_stories/presentation/add_venue_story_page.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/content_moderation/presentation/pending_public_media_preview.dart';
import 'package:kmstry_frontend/core/venue/visible_venue_read.dart';

/// Venue home sayfasının en üstündeki iki karesel medya kartı:
///   • "Story"  — boşken `+`, story varsa son story'nin önizlemesi (sağ altta `+`).
///   • "Gallery"— boşken `+`, galeri varsa iskambil gibi yelpazelenmiş kartlar.
/// Story kartına basınca story viewer, galeri kartına basınca galeri viewer açılır.
class VenueHomeMediaCards extends StatefulWidget {
  final String venueId;
  final String venueName;
  final String? venuePhotoUrl;
  final bool canEditStory;
  final bool canViewStoryStats;
  final bool canEditGallery;
  final bool isActive;
  final VenueStoryRepository? storyRepository;
  final VenueGalleryRepository? galleryRepository;

  const VenueHomeMediaCards({
    super.key,
    required this.venueId,
    required this.venueName,
    this.venuePhotoUrl,
    required this.canEditStory,
    this.canViewStoryStats = false,
    required this.canEditGallery,
    this.isActive = true,
    this.storyRepository,
    this.galleryRepository,
  });

  @override
  State<VenueHomeMediaCards> createState() => _VenueHomeMediaCardsState();
}

class _VenueHomeMediaCardsState extends State<VenueHomeMediaCards>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  late final _storyRepo = widget.storyRepository ?? VenueStoryRepository();
  late final _galleryRepo =
      widget.galleryRepository ?? VenueGalleryRepository();
  late final _storiesRead = VisibleVenueRead(
    read: _readStories,
    isVisible: () => mounted && widget.isActive,
  );
  late final _galleryRead = VisibleVenueRead(
    read: _readGallery,
    isVisible: () => mounted && widget.isActive,
  );

  // ListView aşağı kaydırılıp bu kart görüş alanından çıkınca dispose edilmesin;
  // geri gelince initState + ağ çağrısı tekrar çalışıp "geç yükleniyor" gibi
  // görünmesin diye state'i canlı tut.
  @override
  bool get wantKeepAlive => true;

  List<VenueStoryItem> _stories = [];
  List<VenueGalleryItem> _gallery = [];
  final bool _uploadingStory = false;
  int _galleryLoadRequest = 0;
  int _storyLoadRequest = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStories();
    _loadGallery();
    // Profil sayfası gibi başka yerlerden yapılan ekleme/silmelerde de tazele.
    VenueGalleryRepository.changes.addListener(_loadGallery);
    VenueStoryRepository.changes.addListener(_loadStories);
    PendingPublicMediaService.instance.changes.addListener(_onPendingChanged);
  }

  @override
  void dispose() {
    _galleryPermission.dispose();
    _storiesRead.dispose();
    _galleryRead.dispose();
    WidgetsBinding.instance.removeObserver(this);
    VenueGalleryRepository.changes.removeListener(_loadGallery);
    VenueStoryRepository.changes.removeListener(_loadStories);
    PendingPublicMediaService.instance.changes.removeListener(
      _onPendingChanged,
    );
    super.dispose();
  }

  Future<void> _loadStories() => _storiesRead.invalidate();

  Future<bool> _readStories() async {
    final request = ++_storyLoadRequest;
    final venueId = widget.venueId;
    final uploads = PendingPublicMediaService.instance;
    final session = uploads.sessionGeneration;
    try {
      final s = await _storyRepo.getVenueStories(venueId);
      if (mounted &&
          request == _storyLoadRequest &&
          venueId == widget.venueId &&
          uploads.isCurrentSession(session)) {
        setState(() => _stories = s);
        return true;
      }
    } catch (_) {}
    return false;
  }

  void _onPendingChanged() {
    if (mounted && widget.isActive) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _storiesRead.activate();
      _galleryRead.activate();
    }
  }

  Future<void> _loadGallery() => _galleryRead.invalidate();

  Future<bool> _readGallery() async {
    final request = ++_galleryLoadRequest;
    final venueId = widget.venueId;
    final uploads = PendingPublicMediaService.instance;
    final session = uploads.sessionGeneration;
    try {
      final g = await _galleryRepo.getGallery(venueId);
      if (mounted &&
          request == _galleryLoadRequest &&
          venueId == widget.venueId &&
          uploads.isCurrentSession(session)) {
        setState(() => _gallery = g);
        return true;
      }
    } catch (_) {}
    return false;
  }

  @override
  void didUpdateWidget(covariant VenueHomeMediaCards oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.venueId != oldWidget.venueId) {
      _gallery = [];
      _stories = [];
      _galleryLoadRequest++;
      _storyLoadRequest++;
      _storiesRead.reset();
      _galleryRead.reset();
      _loadGallery();
      _loadStories();
    } else if (widget.isActive && !oldWidget.isActive) {
      _storiesRead.activate();
      _galleryRead.activate();
    }
  }

  // ── Story ──────────────────────────────────────────────────────────────────

  Future<void> _addStory() async {
    // Plan kilidi: Free venue story paylaşamaz (backend STORIES → SOCIAL+).
    // Kamerayı hiç açmadan baştan upsell göster — aksi halde upload 403 dönüp
    // "could not upload" gibi anlamsız bir hata çıkıyordu.
    if (!PlanGate.allows(VenueFeature.stories)) {
      await PlanGate.ensureWithUpsell(
        context,
        VenueFeature.stories,
        icon: Icons.amp_stories_rounded,
        title: 'Share Stories with your guests',
        message:
            'Post 24-hour photo moments that pull people in and drive '
            'foot traffic. Stories are part of the Social plan — upgrade to '
            'start engaging your audience.',
        onAllowed: () {},
      );
      return;
    }

    await Navigator.push<bool>(
      context,
      AddVenueStoryPage.route(widget.venueId),
    );
  }

  void _openStoryViewer() {
    if (_stories.isEmpty &&
        PendingPublicMediaService.instance.latest(
              PendingPublicMediaKind.venueStory,
              venueId: widget.venueId,
            ) ==
            null) {
      return;
    }
    final startIndex = _stories.indexWhere((s) => !s.viewedByMe);
    final initialIndex = startIndex == -1 ? 0 : startIndex;

    final storyItems = _stories
        .map(
          (s) => StoryItem(
            id: s.id,
            mediaUrl: s.mediaUrl,
            mediaType: s.mediaType,
            thumbnailUrl: s.thumbnailUrl,
            durationSecs: s.durationSecs,
            textOverlay: s.textOverlay,
            expiresAt: s.expiresAt,
            createdAt: s.createdAt,
            viewCount: s.viewCount,
            canViewStats: s.canViewStats,
            user: s.posterUserId == null
                ? null
                : StoryUser(id: s.posterUserId!),
            isVenueStory: true,
            venueId: widget.venueId,
            venueName: widget.venueName,
          ),
        )
        .toList();

    final group = StoryGroup(
      user: StoryUser(
        id: 'venue_${widget.venueId}',
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
          venueId: widget.venueId,
          ownerUploadKind: PendingPublicMediaKind.venueStory,
          onCreateStory: widget.canEditStory ? _addStory : null,
          initialStoryIndex: initialIndex,
          showViewers: widget.canViewStoryStats,
          venueStoryRepository: _storyRepo,
          isManagedVenueContent: true,
          canDelete: widget.canEditStory,
          onStoryDeleted: (storyId) {
            if (mounted) {
              setState(
                () =>
                    _stories = _stories.where((s) => s.id != storyId).toList(),
              );
            }
          },
          onClose: (lastIndex, allFinished) {
            final justViewed = allFinished
                ? _stories.map((s) => s.id).toSet()
                : {
                    for (int i = 0; i <= lastIndex && i < _stories.length; i++)
                      _stories[i].id,
                  };
            if (mounted) {
              setState(() {
                _stories = [
                  for (final s in _stories)
                    (s.viewedByMe || justViewed.contains(s.id))
                        ? s.copyWith(viewedByMe: true)
                        : s,
                ];
              });
            }
          },
        ),
      ),
    );
  }

  // ── Gallery ────────────────────────────────────────────────────────────────

  bool _pickingMedia = false;
  final _galleryPermission = SharingPermissionController();

  Future<void> _addGalleryMedia() async {
    if (!widget.canEditGallery || _pickingMedia) return;
    final venueId = widget.venueId;
    final session = PendingPublicMediaService.instance.sessionGeneration;
    setState(() => _pickingMedia = true);
    try {
      if (!await _galleryPermission.check() ||
          !mounted ||
          venueId != widget.venueId ||
          !PendingPublicMediaService.instance.isCurrentSession(session)) {
        return;
      }
      final files = await pickVenueGalleryMedia();
      if (!mounted ||
          venueId != widget.venueId ||
          !PendingPublicMediaService.instance.isCurrentSession(session)) {
        return;
      }
      if (files.isEmpty) return;
      VenueGalleryUploadCoordinator.instance.share(
        venueId: venueId,
        files: files,
        expectedGeneration: session,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open your photos. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pickingMedia = false);
    }
  }

  /// Sahibine bekleyen yüklemeler de (en başta, durum kartıyla) gösterilir —
  /// popup yerine venue profilindeki galeriyle aynı büyük gösterim.
  void _openGalleryViewer() {
    final hasPending =
        widget.canEditGallery &&
        PendingPublicMediaService.instance
            .forKind(
              PendingPublicMediaKind.venueGallery,
              venueId: widget.venueId,
            )
            .isNotEmpty;
    if (_gallery.isEmpty && !hasPending) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => GalleryViewer(
          venueId: widget.venueId,
          items: List.of(_gallery),
          initialIndex: 0,
          pendingUploads: widget.canEditGallery
              ? PendingPublicMediaService.instance
              : null,
          onRetake: widget.canEditGallery ? _addGalleryMedia : null,
          onDelete: widget.canEditGallery
              ? (item) async {
                  await _galleryRepo.deleteItem(widget.venueId, item.id);
                  if (mounted) {
                    setState(
                      () => _gallery = _gallery
                          .where((i) => i.id != item.id)
                          .toList(),
                    );
                  }
                }
              : null,
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  static const double _cardsWidthFactor = 0.86;

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin gereği
    final hasStory = _stories.isNotEmpty || _uploadingStory;
    final hasGallery = _gallery.isNotEmpty;

    // Yetkisi yoksa ve içerik de yoksa kartı hiç gösterme.
    final showStory = hasStory || widget.canEditStory;
    final showGallery = hasGallery || widget.canEditGallery;
    if (!showStory && !showGallery) return const SizedBox.shrink();

    final bothShown = showStory && showGallery;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      // Kartlar bir tık küçük: satır genişliğinin %86'sı, ortalı.
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SharingPermissionHint(
            controller: _galleryPermission,
            isMedia: true,
            onReview: _pickingMedia ? null : _addGalleryMedia,
          ),
          bothShown
              ? Center(
                  child: FractionallySizedBox(
                    widthFactor: _cardsWidthFactor,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildStoryCard()),
                        const SizedBox(width: 12),
                        Expanded(child: _buildGalleryCard()),
                      ],
                    ),
                  ),
                )
              // Tek kart: iki kart durumundaki genişliği koru (yarım) ve ortala.
              : Align(
                  alignment: Alignment.center,
                  child: FractionallySizedBox(
                    widthFactor: 0.5 * _cardsWidthFactor,
                    child: showStory ? _buildStoryCard() : _buildGalleryCard(),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildStoryCard() {
    final hasStory = _stories.isNotEmpty;
    final pending = widget.canEditStory
        ? PendingPublicMediaService.instance.latest(
            PendingPublicMediaKind.venueStory,
            venueId: widget.venueId,
          )
        : null;
    final allSeen = hasStory && _stories.every((s) => s.viewedByMe);
    final firstStory = hasStory ? _stories.first : null;
    final preview = firstStory == null
        ? null
        : firstStory.thumbnailUrl?.isNotEmpty == true
        ? firstStory.thumbnailUrl
        : firstStory.isVideo
        ? null
        : firstStory.mediaUrl;

    return _PremiumMediaCard(
      variant: _MediaVariant.story,
      accent: AppColors.magenta,
      title: 'Story',
      subtitle: pending == null
          ? '${_stories.length} active'
          : pendingPublicMediaLabel(pending),
      emptyIcon: Icons.play_arrow_rounded,
      hasContent: hasStory,
      previewUrl: preview,
      showPlayOverlay: firstStory?.isVideo == true,
      unseen: hasStory && !allSeen,
      loading: _uploadingStory,
      pending: pending,
      showAddBadge: widget.canEditStory,
      onAdd: widget.canEditStory ? _addStory : null,
      onTap: pending != null || hasStory
          ? _openStoryViewer
          : (widget.canEditStory ? _addStory : null),
      galleryItems: const [],
    );
  }

  Widget _buildGalleryCard() {
    final hasGallery = _gallery.isNotEmpty;
    final pending = widget.canEditGallery
        ? PendingPublicMediaService.instance.latest(
            PendingPublicMediaKind.venueGallery,
            venueId: widget.venueId,
          )
        : null;
    final n = _gallery.length;
    return _PremiumMediaCard(
      variant: _MediaVariant.gallery,
      accent: AppColors.teal,
      title: 'Gallery',
      subtitle: pending == null
          ? '$n ${n == 1 ? 'item' : 'items'}'
          : pendingPublicMediaLabel(pending),
      emptyIcon: Icons.photo_library_rounded,
      hasContent: hasGallery,
      previewUrl: null,
      showPlayOverlay: false,
      unseen: false,
      loading: false,
      pending: pending,
      showAddBadge: widget.canEditGallery,
      onAdd: widget.canEditGallery ? _addGalleryMedia : null,
      onTap: pending != null
          ? _openGalleryViewer
          : hasGallery
          ? _openGalleryViewer
          : (widget.canEditGallery ? _addGalleryMedia : null),
      galleryItems: _gallery,
    );
  }
}

// ── Premium medya kartı (story / gallery) ───────────────────────────────────────

enum _MediaVariant { story, gallery }

class _PremiumMediaCard extends StatelessWidget {
  final _MediaVariant variant;
  final Color accent;
  final String title;
  final String subtitle;
  final IconData emptyIcon;
  final bool hasContent;
  final String? previewUrl; // story önizleme
  final bool showPlayOverlay;
  final List<VenueGalleryItem> galleryItems;
  final bool unseen;
  final bool loading;
  final PendingPublicMedia? pending;
  final bool showAddBadge;
  final VoidCallback? onAdd;
  final VoidCallback? onTap;

  const _PremiumMediaCard({
    required this.variant,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.emptyIcon,
    required this.hasContent,
    required this.previewUrl,
    required this.showPlayOverlay,
    required this.galleryItems,
    required this.unseen,
    required this.loading,
    this.pending,
    required this.showAddBadge,
    required this.onAdd,
    required this.onTap,
  });

  static const _radius = 20.0;

  List<Color> get _borderColors => variant == _MediaVariant.story
      ? const [
          AppColors.magenta,
          AppColors.teal,
          AppColors.blue,
          AppColors.orange,
          AppColors.magenta,
        ]
      : const [
          AppColors.teal,
          AppColors.blue,
          AppColors.orange,
          AppColors.magenta,
          AppColors.teal,
        ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final innerDecoration = variant == _MediaVariant.story
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(_radius - 2),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? const [Color(0xFF1A0828), Color(0xFF0A1030)]
                  : const [Color(0xFFFBEFFF), Color(0xFFEEF3FF)],
            ),
          )
        : BoxDecoration(
            borderRadius: BorderRadius.circular(_radius - 2),
            color: isDark ? const Color(0xFF0D1525) : const Color(0xFFF3F6FC),
          );

    // Radial marka parıltısı (üstte).
    final glow = Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_radius - 2),
            gradient: RadialGradient(
              center: const Alignment(0, -0.45),
              radius: 0.95,
              colors: [
                accent.withValues(alpha: isDark ? 0.22 : 0.13),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );

    final isGalleryFilled = variant == _MediaVariant.gallery && hasContent;
    final isStoryPreview =
        variant == _MediaVariant.story && hasContent && previewUrl != null;

    Widget content;
    if (pending != null) {
      content = PendingPublicMediaPreview(item: pending!);
    } else if (isStoryPreview) {
      content = CachedImage(
        previewUrl!,
        fit: BoxFit.cover,
        errorWidget: (_) => _emptyContent(context, isDark, onSurface),
      );
    } else if (isGalleryFilled) {
      content = _galleryContent(context, isDark, scaffoldBg, onSurface);
    } else {
      content = _emptyContent(context, isDark, onSurface);
    }

    // Gallery dolu → "+" overlay içinde; diğerlerinde sağ altta.
    final showBottomRightAdd =
        showAddBadge && (!isGalleryFilled || pending != null);

    final frame = AspectRatio(
      aspectRatio: 0.92,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: EdgeInsets.all(unseen ? 2.5 : 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_radius),
                gradient: SweepGradient(
                  colors: _borderColors,
                  startAngle: -1.5708,
                  endAngle: 4.7124,
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: isDark ? 0.28 : 0.16),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: DecoratedBox(
                decoration: innerDecoration,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_radius - 2),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      glow,
                      content,
                      if (showPlayOverlay && isStoryPreview && pending == null)
                        Center(
                          child: Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.48),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.72),
                              ),
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                          ),
                        ),
                      if (pending != null)
                        Positioned(
                          bottom: 8,
                          left: 8,
                          right: 8,
                          child: Center(
                            child: PublicMediaUploadStatus(
                              item: pending!,
                              overlay: true,
                            ),
                          ),
                        ),
                      if (loading)
                        Container(
                          color: Colors.black.withValues(alpha: 0.4),
                          child: const Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (showBottomRightAdd)
              Positioned(right: 9, bottom: 9, child: _addCircle(scaffoldBg)),
          ],
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        frame,
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _addCircle(Color borderColor) {
    // Gallery "+" marka mavisi; Story "+" kendi aksan rengi (magenta).
    final fill = variant == _MediaVariant.gallery ? AppColors.blue : accent;
    final circle = Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: fill.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Icon(Icons.add, color: Colors.white, size: 17),
    );
    if (onAdd == null) return circle;
    return GestureDetector(
      onTap: onAdd,
      behavior: HitTestBehavior.opaque,
      child: circle,
    );
  }

  Widget _emptyContent(BuildContext context, bool isDark, Color onSurface) {
    final titleColor = isDark
        ? const Color(0xFFC8D8F0)
        : const Color(0xFF24304A);
    final subColor = isDark ? const Color(0xFF3A5070) : const Color(0xFF8A9BB5);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.16 : 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(emptyIcon, color: accent, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 10, color: subColor)),
        ],
      ),
    );
  }

  Widget _galleryContent(
    BuildContext context,
    bool isDark,
    Color scaffoldBg,
    Color onSurface,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // İskambil gibi yelpazelenmiş fotoğraflar (en yeni önde).
        LayoutBuilder(
          builder: (context, c) {
            final shown = galleryItems.take(3).toList();
            final n = shown.length;
            final cardW = c.maxWidth * 0.5;
            final cardH = c.maxHeight * 0.55;
            // Arkadan öne: en eski arkada, en yeni (index 0) en önde/ortada.
            final order = [for (int i = n - 1; i >= 0; i--) i];
            return Stack(
              // Alt overlay (sayı + "+") ile dipdibe olmasın diye biraz yukarı.
              alignment: const Alignment(0, -0.32),
              clipBehavior: Clip.hardEdge,
              children: [
                for (final i in order)
                  Transform.rotate(
                    angle: _angleFor(i, n),
                    child: Transform.translate(
                      offset: _offsetFor(i, n, c),
                      child: _photoFrame(shown[i], cardW, cardH),
                    ),
                  ),
              ],
            );
          },
        ),
        // Alt overlay: sayı + "+".
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          // Arka plan karartması yok: sayı + "+" doğrudan kart zemininde.
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 10, 9),
            child: Row(
              children: [
                // Öğe sayısı marka mavisi.
                const Icon(
                  Icons.collections_rounded,
                  size: 13,
                  color: AppColors.blue,
                ),
                const SizedBox(width: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.blue,
                  ),
                ),
                const Spacer(),
                if (showAddBadge) _addCircle(scaffoldBg),
              ],
            ),
          ),
        ),
      ],
    );
  }

  double _angleFor(int i, int n) {
    if (n == 1) return 0;
    const spread = 0.16; // ~9°
    // i=0 (en yeni) düz, arkadakiler simetrik açılı.
    switch (i) {
      case 0:
        return -0.02;
      case 1:
        return spread;
      default:
        return -spread;
    }
  }

  Offset _offsetFor(int i, int n, BoxConstraints c) {
    if (n == 1) return Offset.zero;
    final dx = c.maxWidth * 0.13;
    final dy = c.maxHeight * 0.05;
    switch (i) {
      case 0:
        return Offset(0, dy * 0.3);
      case 1:
        return Offset(dx, -dy);
      default:
        return Offset(-dx, dy);
    }
  }

  Widget _photoFrame(VenueGalleryItem item, double w, double h) {
    final usesThumbnail = item.thumbnailUrl?.isNotEmpty == true;
    final url = usesThumbnail ? item.thumbnailUrl! : item.url;
    final mediaReference = usesThumbnail
        ? item.thumbnailReference
        : item.mediaReference;
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.black,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.9),
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedImage(
              url,
              mediaReference: mediaReference,
              fit: BoxFit.cover,
              errorWidget: (_) => Container(
                color: const Color(0xFF1A2233),
                child: const Icon(Icons.image, color: Colors.white24, size: 20),
              ),
            ),
            if (item.mediaType == 'video')
              const Center(
                child: Icon(
                  Icons.play_circle_fill,
                  color: Colors.white,
                  size: 22,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
