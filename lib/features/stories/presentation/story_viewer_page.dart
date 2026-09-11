import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../data/story_model.dart';
import 'story_display_timer.dart';
import '../../../core/ui/cached_image.dart';
import '../../../core/ui/destructive_confirmation_dialog.dart';
import '../../../core/media/signed_media_resolver.dart';
import '../../media/media_text_overlay.dart';
import '../data/story_repository.dart';
import '../data/story_viewed_cache.dart';
import '../../venue/data/venue_repository.dart';
import '../../venue/presentation/venue_detail_page.dart';
import '../../venue_stories/data/venue_story_repository.dart';
import '../../reports/presentation/report_user_sheet.dart';
import '../../auth/data/auth_repository.dart';

class StoryViewerResult {
  final int lastStoryIndex;
  final bool allFinished;
  const StoryViewerResult({
    required this.lastStoryIndex,
    required this.allFinished,
  });
}

class StoryViewerPage extends StatefulWidget {
  final List<StoryGroup> groups;
  final int initialGroupIndex;
  final int initialStoryIndex;

  /// Set when viewing venue stories — enables Instagram-style viewer count overlay (owner only)
  final String? venueId;
  final bool showViewers;

  /// Called just before pop — index of last shown story, allFinished=true if all stories played through
  final void Function(int lastIndex, bool allFinished)? onClose;

  /// Called when a story is deleted — passes the deleted storyId
  final void Function(String storyId)? onStoryDeleted;
  final bool canDelete;

  const StoryViewerPage({
    super.key,
    required this.groups,
    this.initialGroupIndex = 0,
    this.initialStoryIndex = 0,
    this.venueId,
    this.showViewers = false,
    this.canDelete = false,
    this.onClose,
    this.onStoryDeleted,
  });

  @override
  State<StoryViewerPage> createState() => _StoryViewerPageState();
}

class _StoryViewerPageState extends State<StoryViewerPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _repo = StoryRepository();

  late int _groupIndex;
  int _storyIndex = 0;
  late List<StoryGroup> _groups;
  int _pollToken = 0; // her placeholder yüklemesinde artar → eski polling iptal

  AnimationController? _progressController;
  StoryDisplayTimer? _displayTimer;
  VideoPlayerController? _videoController;
  bool _videoReady = false;
  bool _advancing = false;
  bool _loadingStory = false;
  bool _interactionPaused = false;
  bool _appPaused = false;
  DateTime? _storyPressStartedAt;
  double _storyVerticalDragOffset = 0;
  bool _closingStory = false;
  int _progressKey =
      0; // her story yüklenince artar → progress bar sıfırdan oluşturulur
  final Map<int, int> _liveViewCounts =
      {}; // storyIndex → fresh count from sheet

  static const Duration _photoDuration = Duration(seconds: 5);
  static const Duration _tapNavigationThreshold = Duration(milliseconds: 260);
  static const double _dismissDragDistance = 90;
  static const double _dismissDragVelocity = 650;

  StoryGroup get _currentGroup => _groups[_groupIndex];
  StoryItem get _currentStory => _currentGroup.stories[_storyIndex];

  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _groups = List<StoryGroup>.from(widget.groups);
    _groupIndex = widget.initialGroupIndex;
    _storyIndex = widget.initialStoryIndex;
    _loadStory();
    _loadCurrentUserId();
    if (widget.showViewers && widget.venueId != null) {
      _prefetchViewCounts();
    }
  }

  Future<void> _loadCurrentUserId() async {
    try {
      final me = await AuthRepository().getMe();
      if (mounted) setState(() => _currentUserId = me['id']?.toString());
    } catch (_) {}
  }

  bool _isCurrentUserStory(StoryGroup group) {
    if (group.isCurrentUserOwner) return true;
    final currentId = _currentUserId?.trim();
    final ownerId = group.user.id.trim();
    return currentId != null && currentId.isNotEmpty && ownerId == currentId;
  }

  bool _canReportStoryOwner(StoryGroup group, StoryItem story) {
    if (story.isUploadingPlaceholder) return false;
    // NOT: _currentUserId async yüklenir; ilk açılışta null olabilir. Üç noktayı
    // ona bağlı erken-dönüşle GİZLEME — kişisel story'de group.isCurrentUserOwner
    // "başkasının story'si mi"yi zaten anında bilir; venue story'de de id
    // yüklenene kadar göster (kendi id'mizle eşleşmedikçe).
    if (!story.isVenueStory) return !_isCurrentUserStory(group);
    final targetUserId = story.user?.id?.trim();
    if (targetUserId == null || targetUserId.isEmpty) return false;
    final me = _currentUserId?.trim();
    return me == null || me.isEmpty || targetUserId != me;
  }

  Future<void> _openReportSheet(String targetUserId, StoryItem story) async {
    if (targetUserId.trim() == _currentUserId?.trim()) return;
    _pauseProgress();
    final ok = await showReportUserSheet(
      context,
      targetUserId: targetUserId,
      storyId: story.isVenueStory ? null : story.id,
      venueStoryId: story.isVenueStory ? story.id : null,
    );
    if (ok && mounted) {
      widget.onClose?.call(_storyIndex, false);
      Navigator.pop(
        context,
        StoryViewerResult(lastStoryIndex: _storyIndex, allFinished: false),
      );
      return;
    }
    if (mounted) _resumeProgress();
  }

  Future<void> _prefetchViewCounts() async {
    try {
      final all = await VenueStoryRepository().getViewers(widget.venueId!);
      if (!mounted) return;
      final stories = _currentGroup.stories;
      final countById = <String, int>{
        for (final s in all)
          s['story_id'] as String: (s['view_count'] as num?)?.toInt() ?? 0,
      };
      setState(() {
        for (var i = 0; i < stories.length; i++) {
          final c = countById[stories[i].id];
          if (c != null) _liveViewCounts[i] = c;
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _displayTimer?.dispose();
    _progressController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _loadStory() async {
    _advancing = false;
    _interactionPaused = false;
    _loadingStory = true;
    _progressKey++;
    final loadKey = _progressKey;
    _displayTimer?.dispose();
    _displayTimer = null;
    _pollToken++; // navigasyon/yeni story → eski polling iptal
    _progressController?.dispose();
    _progressController = null;
    _videoController?.dispose();
    _videoController = null;
    _videoReady = false;

    final story = _currentStory;

    // Yüklenmekte olan placeholder: zamanlayıcı/video yok, sadece "Loading…".
    // Upload bitince getMyStories ile gerçek story'yi çekip yerine koy.
    if (story.isUploadingPlaceholder) {
      _loadingStory = false;
      if (mounted) setState(() {});
      _pollForUploadedStory();
      return;
    }

    StoryViewedCache.markViewed(story.id).ignore();
    if (story.isVenueStory && story.venueId != null) {
      // Home feed'deki takip edilen venue'nün kendi story'si → yalnızca venue
      // endpoint'ine kaydet (kişisel /stories/:id/view'a gönderme, o id orada yok).
      VenueStoryRepository().recordView(story.venueId!, story.id).ignore();
    } else {
      _repo.recordView(story.id).ignore();
      // Venue tray'inden açıldıysa (widget.venueId) izlenme venue'ye de yazılır —
      // operatör dahil kalıcı gri halka için.
      if (widget.venueId != null) {
        VenueStoryRepository().recordView(widget.venueId!, story.id).ignore();
      }
    }

    // Sonraki story'nin görselini/thumbnail'ını önden cache'e al (siyah ekran
    // olmadan geçiş). Video preload'u aşağıda, mevcut video reuse edildikten
    // SONRA yapılır (yoksa reuse edeceğimiz controller'ı yanlışlıkla silerdi).
    _precacheNextStory();

    if (story.isVideo) {
      // Signed URL süresi (neredeyse) dolmuşsa, controller'ı oluşturmadan önce
      // tek-seferlik yeniden imzala — aksi halde expired URL ile video açılmaz.
      var videoUrl = story.mediaUrl;
      final ref = story.mediaReference;
      if (ref != null &&
          ref.canRefresh &&
          (videoUrl.isEmpty ||
              (ref.expiresAt != null &&
                  ref.expiresAt!.isBefore(
                    DateTime.now().add(const Duration(seconds: 10)),
                  )))) {
        final refreshed = await SignedMediaResolver.instance.refreshOnce(ref);
        if (refreshed != null && refreshed.url.isNotEmpty) {
          videoUrl = refreshed.url;
        }
      }
      if (videoUrl.isEmpty) {
        if (!mounted || loadKey != _progressKey || _closingStory) return;
        _loadingStory = false;
        _startTimedStory();
        return;
      }
      if (!mounted || loadKey != _progressKey || _closingStory) return;
      final vc = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      _videoController = vc;
      try {
        await vc.initialize();
      } catch (e) {
        debugPrint('❌ Video initialize error: $e');
        if (!mounted || loadKey != _progressKey || _closingStory) return;
        _loadingStory = false;
        _startTimedStory();
        return;
      }
      if (!mounted || loadKey != _progressKey || _closingStory) return;
      await vc.setLooping(false);
      if (!mounted || loadKey != _progressKey || _closingStory) return;
      // Bitiş tespiti: video pozisyonu sona ulaşınca _advance()
      vc.addListener(() {
        if (_videoController != vc) return; // bu vc artık aktif değil
        final val = vc.value;
        if (!val.isPlaying &&
            !val.isBuffering &&
            val.duration.inMilliseconds > 0 &&
            val.position >= val.duration) {
          vc.removeListener(() {});
          _advance();
        }
      });
      _loadingStory = false;
      setState(() => _videoReady = true);
      if (!_interactionPaused && !_appPaused) await vc.play();
    } else {
      _loadingStory = false;
      _startTimedStory();
    }
  }

  void _startTimedStory() {
    final loadKey = _progressKey;
    final progress = AnimationController(
      vsync: this,
      duration: _photoDuration,
      // Visual only. The independent timer below owns auto-advance.
      // Preserve its time scale; reduced-motion rendering is stepped below.
      animationBehavior: AnimationBehavior.preserve,
    );
    _displayTimer = StoryDisplayTimer(
      duration: _photoDuration,
      onComplete: () {
        if (mounted && !_closingStory && loadKey == _progressKey) _advance();
      },
    );
    setState(() => _progressController = progress);
    _resumePlaybackIfAllowed();
  }

  Future<void> _pollForUploadedStory() async {
    final token = ++_pollToken;
    final group = _currentGroup;
    final groupIdx = _groupIndex;
    final placeholderIdx = _storyIndex;
    final realCount = group.stories
        .where((s) => !s.isUploadingPlaceholder)
        .length;

    for (int i = 0; i < 60; i++) {
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted || token != _pollToken) return; // iptal / başka story

      List<StoryItem> mine;
      try {
        mine = await _repo.getMyStories();
      } catch (_) {
        continue;
      }
      if (!mounted || token != _pollToken) return;

      if (mine.length > realCount) {
        // En yeni story (asc sıralama → sonuncu) placeholder yerine geçer.
        final newStory = mine.last;
        final updatedStories = [
          ...group.stories.where((s) => !s.isUploadingPlaceholder),
          newStory,
        ];
        setState(() {
          _groups[groupIdx] = StoryGroup(
            user: group.user,
            stories: updatedStories,
            featuredPhotoUrl: group.featuredPhotoUrl,
          );
        });
        // Hâlâ o slotta isek gerçek story'yi oynat.
        if (_groupIndex == groupIdx && _storyIndex == placeholderIdx) {
          _loadStory();
        }
        return;
      }
    }
  }

  /// Bir sonraki story'yi (grup içindeki veya sonraki grubun ilk) döndürür.
  StoryItem? _nextStoryItem() {
    if (_storyIndex < _currentGroup.stories.length - 1) {
      return _currentGroup.stories[_storyIndex + 1];
    }
    if (_groupIndex < _groups.length - 1) {
      final next = _groups[_groupIndex + 1].stories;
      return next.isNotEmpty ? next.first : null;
    }
    return null;
  }

  /// Sonraki story'nin görselini önden cache'e alır (fotoğrafta tam medya,
  /// videoda thumbnail). ASLA _loadStory'yi bozmamalı — bütün gövde try/catch
  /// içinde ve bir frame sonrasına ertelendi (context image-config için hazır
  /// olsun). Hata sessizce yutulur, kritik değil.
  void _precacheNextStory() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final next = _nextStoryItem();
        if (next == null || next.isUploadingPlaceholder) return;
        final url = next.isVideo ? next.thumbnailUrl : next.mediaUrl;
        if (url == null || url.isEmpty) return;
        precacheImage(NetworkImage(url), context).ignore();
        if (next.isVideo &&
            next.thumbnailUrl != null &&
            next.thumbnailUrl!.isNotEmpty) {
          precacheImage(NetworkImage(next.thumbnailUrl!), context).ignore();
        }
      } catch (_) {
        // preload kritik değil; sessizce geç.
      }
    });
  }

  void _advance() {
    if (!mounted ||
        _closingStory ||
        _advancing ||
        _loadingStory ||
        _appPaused ||
        _interactionPaused) {
      return;
    }
    _advancing = true;
    if (_storyIndex < _currentGroup.stories.length - 1) {
      setState(() => _storyIndex++);
      _loadStory();
    } else if (_groupIndex < _groups.length - 1) {
      setState(() {
        _groupIndex++;
        _storyIndex = 0;
      });
      _loadStory();
    } else {
      _closeStory(allFinished: true);
    }
  }

  void _goBack() {
    if (!mounted || _loadingStory) return;
    if (_storyIndex > 0) {
      setState(() => _storyIndex--);
      _loadStory();
    } else if (_groupIndex > 0) {
      setState(() {
        _groupIndex--;
        _storyIndex = _groups[_groupIndex].stories.length - 1;
      });
      _loadStory();
    }
  }

  /// Bu story silinebilir mi? Venue story'de owner yetkisi (canDelete) veya
  /// kişisel story'de kendi story'n (isCurrentUserOwner).
  bool get _canDeleteCurrentStory {
    if (_currentStory.isUploadingPlaceholder) return false;
    if (widget.venueId != null) return widget.canDelete;
    return _currentGroup.isCurrentUserOwner;
  }

  Future<void> _deleteCurrentStory() async {
    if (!_canDeleteCurrentStory) return;
    final story = _currentStory;
    _pauseProgress();
    final confirmed = await showDestructiveConfirmationDialog(
      context,
      title: 'Delete story?',
      message: 'This story will be permanently deleted and can’t be undone.',
      confirmLabel: 'Delete story',
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed) {
      _resumeProgress();
      return;
    }
    try {
      // Venue story → VenueStoryRepository; kişisel story → StoryRepository.
      if (widget.venueId != null) {
        await VenueStoryRepository().deleteStory(widget.venueId!, story.id);
      } else {
        await _repo.deleteStory(story.id);
      }
      widget.onStoryDeleted?.call(story.id);
      if (!mounted) return;
      final group = _currentGroup;
      final newStories = List<StoryItem>.from(group.stories)
        ..removeAt(_storyIndex);
      if (newStories.isEmpty) {
        widget.onClose?.call(_storyIndex, true);
        Navigator.pop(
          context,
          StoryViewerResult(lastStoryIndex: 0, allFinished: true),
        );
        return;
      }
      setState(() {
        _groups[_groupIndex] = StoryGroup(
          user: group.user,
          stories: newStories,
          isCurrentUserOwner: group.isCurrentUserOwner,
          featuredPhotoUrl: group.featuredPhotoUrl,
        );
        if (_storyIndex >= newStories.length)
          _storyIndex = newStories.length - 1;
      });
      _loadStory();
    } catch (e) {
      if (!mounted) return;
      _resumeProgress();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Silinemedi: $e')));
    }
  }

  void _pauseProgress() {
    _interactionPaused = true;
    _stopPlayback();
  }

  void _stopPlayback() {
    _displayTimer?.pause();
    _progressController?.stop();
    _videoController?.pause();
  }

  void _resumeProgress() {
    _interactionPaused = false;
    _resumePlaybackIfAllowed();
  }

  void _resumePlaybackIfAllowed() {
    if (_loadingStory || _closingStory || _appPaused || _interactionPaused)
      return;
    _displayTimer?.resume();
    _progressController?.forward();
    _videoController?.play();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appPaused = state != AppLifecycleState.resumed;
    if (_appPaused) {
      _stopPlayback();
    } else {
      _resumePlaybackIfAllowed();
    }
  }

  void _handleStoryPressStart(TapDownDetails _) {
    _storyPressStartedAt = DateTime.now();
    _pauseProgress();
  }

  void _handleStoryPressEnd(VoidCallback onShortTap) {
    final startedAt = _storyPressStartedAt;
    _storyPressStartedAt = null;
    _resumeProgress();

    if (startedAt == null) return;
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed <= _tapNavigationThreshold) {
      onShortTap();
    }
  }

  void _handleStoryPressCancel() {
    _storyPressStartedAt = null;
    _resumeProgress();
  }

  void _closeStory({bool allFinished = false}) {
    if (!mounted || _closingStory) return;
    _closingStory = true;
    _displayTimer?.dispose();
    _progressController?.stop();
    _videoController?.pause();
    widget.onClose?.call(_storyIndex, allFinished);
    Navigator.pop(
      context,
      StoryViewerResult(lastStoryIndex: _storyIndex, allFinished: allFinished),
    );
  }

  void _handleStoryVerticalDragStart(DragStartDetails _) {
    _storyPressStartedAt = null;
    _storyVerticalDragOffset = 0;
    _pauseProgress();
  }

  void _handleStoryVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity > _dismissDragVelocity) {
      _closeStory();
      return;
    }
    _storyVerticalDragOffset = 0;
    _resumeProgress();
  }

  void _handleStoryVerticalDragUpdate(DragUpdateDetails details) {
    _storyVerticalDragOffset += details.primaryDelta ?? 0;
    if (_storyVerticalDragOffset > _dismissDragDistance) {
      _closeStory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = _currentGroup;
    final story = _currentStory;

    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: SizedBox(
        width: screenSize.width,
        height: screenSize.height,
        child: Stack(
          children: [
            // ── MEDIA ──────────────────────────────────────────────────────
            Positioned.fill(
              child: story.isUploadingPlaceholder
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            'Loading…',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        // Thumbnail placeholder — anında görünür (düşük çözünürlük,
                        // story tray'den zaten cache'te olabilir). Siyah ekran yerine
                        // bu görünür, asıl medya yüklenince üstüne biner.
                        if (story.thumbnailUrl != null &&
                            story.thumbnailUrl!.isNotEmpty)
                          Image.network(
                            story.thumbnailUrl!,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                        if (story.isVideo)
                          if (_videoReady && _videoController != null)
                            FittedBox(
                              fit: BoxFit.cover,
                              clipBehavior: Clip.hardEdge,
                              child: SizedBox(
                                width: _videoController!.value.size.width,
                                height: _videoController!.value.size.height,
                                child: VideoPlayer(_videoController!),
                              ),
                            )
                          else if (story.thumbnailUrl == null ||
                              story.thumbnailUrl!.isEmpty)
                            // Poster yoksa düz siyah yerine ince bir yükleniyor
                            // göstergesi — daha profesyonel.
                            const Center(
                              child: SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white70,
                                ),
                              ),
                            )
                          else
                            const SizedBox.shrink()
                        else
                          // Signed URL: CachedImage, mediaReference ile URL
                          // expire olursa tek-seferlik yeniden imzalar. Arkadaki
                          // thumbnail placeholder olarak kalsın diye şeffaf.
                          CachedImage(
                            story.mediaUrl,
                            mediaReference: story.mediaReference,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            placeholder: (_) => const SizedBox.shrink(),
                          ),
                      ],
                    ),
            ),

            // ── TEXT OVERLAY (medyaya eklenen yazı — client render) ────────
            // Video için yazıyı yalnızca video HAZIR olunca göster; aksi halde
            // buffer sırasında siyah zeminde yazı görünüp sonra video geliyordu.
            // Video ve yazı birlikte belirsin (profesyonel his). Fotoğrafta
            // medya zaten hızlı geldiği için beklenmez.
            if (story.textOverlay != null &&
                !story.isUploadingPlaceholder &&
                (!story.isVideo || _videoReady))
              Positioned.fill(
                child: MediaTextOverlayView(overlay: story.textOverlay!),
              ),

            // ── GRADIENT TOP ───────────────────────────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 120,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // ── PROGRESS BARS ──────────────────────────────────────────────
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  key: ValueKey(_progressKey),
                  children: List.generate(
                    group.stories.length,
                    (i) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: _ProgressBar(
                          completed: i < _storyIndex,
                          active: i == _storyIndex,
                          controller: (i == _storyIndex)
                              ? _progressController
                              : null,
                          videoController:
                              (i == _storyIndex && story.isVideo && _videoReady)
                              ? _videoController
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── TAP ZONES (left: back, right: advance) ────────────────────
            // Press-and-hold pauses immediately; a quick tap still navigates.
            // Left 35% → go back
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              width: screenSize.width * 0.35,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: _handleStoryPressStart,
                onTapUp: (_) => _handleStoryPressEnd(_goBack),
                onTapCancel: _handleStoryPressCancel,
                onVerticalDragStart: _handleStoryVerticalDragStart,
                onVerticalDragUpdate: _handleStoryVerticalDragUpdate,
                onVerticalDragEnd: _handleStoryVerticalDragEnd,
              ),
            ),
            // Right 65% → advance
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: screenSize.width * 0.65,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: _handleStoryPressStart,
                onTapUp: (_) => _handleStoryPressEnd(_advance),
                onTapCancel: _handleStoryPressCancel,
                onVerticalDragStart: _handleStoryVerticalDragStart,
                onVerticalDragUpdate: _handleStoryVerticalDragUpdate,
                onVerticalDragEnd: _handleStoryVerticalDragEnd,
              ),
            ),

            // ── VENUE STORY: viewers count bar (Instagram-style) ──────────
            if (widget.venueId != null &&
                widget.showViewers &&
                !story.isUploadingPlaceholder)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  onTap: () => _openViewersList(story),
                  onVerticalDragEnd: (d) {
                    if (d.primaryVelocity != null &&
                        d.primaryVelocity! < -100) {
                      _openViewersList(story);
                    }
                  },
                  child: Container(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      16,
                      20,
                      MediaQuery.of(context).padding.bottom + 20,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.65),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.remove_red_eye_outlined,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_liveViewCounts[_storyIndex] ?? story.viewCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.keyboard_arrow_up_rounded,
                          color: Colors.white60,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // ── VENUE LABEL (bottom-right) — tap zone'lardan sonra gelir ───
            if (story.venueId != null && story.venueName != null)
              Positioned(
                left: 16,
                bottom: 32,
                child: GestureDetector(
                  onTap: () =>
                      _openVenueDetail(story.venueId!, story.venueName!),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_venueLoading)
                          const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 1.5,
                            ),
                          )
                        else
                          const Icon(
                            Icons.location_on,
                            color: Colors.white,
                            size: 13,
                          ),
                        const SizedBox(width: 4),
                        Text(
                          'at ${story.venueName}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            shadows: [
                              Shadow(blurRadius: 3, color: Colors.black54),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            // ── DELETE (bottom-right) — kendi story'n / venue owner ───────────
            if (_canDeleteCurrentStory)
              Positioned(
                right: 16,
                bottom:
                    MediaQuery.of(context).padding.bottom +
                    ((widget.venueId != null &&
                            widget.showViewers &&
                            !story.isUploadingPlaceholder)
                        ? 76
                        : 28),
                child: GestureDetector(
                  onTap: _deleteCurrentStory,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ),

            // ── USER ROW — tap zone'lardan sonra: çarpı butonu tıklanabilir ──
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 38, 12, 0),
                child: Row(
                  children: [
                    _Avatar(url: group.user.photo, radius: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.user.displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              shadows: [
                                Shadow(blurRadius: 4, color: Colors.black54),
                              ],
                            ),
                          ),
                          Text(
                            _timeAgo(story.createdAt),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_canReportStoryOwner(group, story))
                      IconButton(
                        tooltip: 'Report',
                        icon: const Icon(
                          Icons.flag_outlined,
                          color: Colors.white,
                        ),
                        onPressed: () => _openReportSheet(
                          story.isVenueStory ? story.user!.id : group.user.id,
                          story,
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: _closeStory,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ), // Stack
      ), // SizedBox
    );
  }

  bool _venueLoading = false;

  Future<void> _openViewersList(StoryItem story) async {
    if (widget.venueId == null) return;
    _pauseProgress();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ViewersSheet(
        venueId: widget.venueId!,
        storyId: story.id,
        onFreshCount: (count) {
          if (mounted) setState(() => _liveViewCounts[_storyIndex] = count);
        },
      ),
    );
    if (mounted) _resumeProgress();
  }

  Future<void> _openVenueDetail(String venueId, String venueName) async {
    if (_venueLoading) return;
    _pauseProgress();
    setState(() => _venueLoading = true);
    try {
      final venue = await VenueRepository().getVenueById(venueId);
      if (!mounted) return;
      setState(() => _venueLoading = false);
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VenueDetailPage(venue: venue)),
      );
    } catch (e) {
      debugPrint('❌ _openVenueDetail error: $e');
      if (!mounted) return;
      setState(() => _venueLoading = false);
    } finally {
      if (mounted) {
        _venueLoading = false;
        _resumeProgress();
      }
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _ProgressBar extends StatelessWidget {
  final bool completed;
  final bool active;
  final AnimationController? controller;
  final VideoPlayerController? videoController;

  const _ProgressBar({
    required this.completed,
    required this.active,
    this.controller,
    this.videoController,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: active && videoController != null
            // Video: gerçek pozisyona göre ilerler
            ? AnimatedBuilder(
                animation: videoController!,
                builder: (ctx, child) {
                  final dur = videoController!.value.duration.inMilliseconds;
                  final pos = videoController!.value.position.inMilliseconds;
                  final val = dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0.0;
                  return LinearProgressIndicator(
                    value: val,
                    backgroundColor: Colors.white30,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white,
                    ),
                  );
                },
              )
            : active && controller != null
            // Visual progress only; never controls the story lifetime.
            ? AnimatedBuilder(
                animation: controller!,
                builder: (ctx, child) => LinearProgressIndicator(
                  value: MediaQuery.disableAnimationsOf(ctx)
                      ? (controller!.value * 5).floor() / 5
                      : controller!.value,
                  backgroundColor: Colors.white30,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : LinearProgressIndicator(
                value: completed ? 1.0 : 0.0,
                backgroundColor: Colors.white30,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
      ),
    );
  }
}

// ─── Instagram-style viewers bottom sheet ─────────────────────────────────────

class _ViewersSheet extends StatefulWidget {
  final String venueId;
  final String storyId;
  final void Function(int count)? onFreshCount;

  const _ViewersSheet({
    required this.venueId,
    required this.storyId,
    this.onFreshCount,
  });

  @override
  State<_ViewersSheet> createState() => _ViewersSheetState();
}

class _ViewersSheetState extends State<_ViewersSheet> {
  final _repo = VenueStoryRepository();
  List<Map<String, dynamic>> _viewers = [];
  int _viewCount = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      debugPrint(
        '🔍 ViewersSheet: loading venueId=${widget.venueId} storyId=${widget.storyId}',
      );
      final all = await _repo.getViewers(widget.venueId);
      debugPrint(
        '🔍 ViewersSheet: got ${all.length} stories, ids=${all.map((s) => s['story_id']).toList()}',
      );
      final story = all.firstWhere(
        (s) => s['story_id'] == widget.storyId,
        orElse: () => <String, dynamic>{},
      );
      debugPrint('🔍 ViewersSheet: matched story=$story');
      if (mounted) {
        final freshCount = (story['view_count'] as num?)?.toInt() ?? 0;
        widget.onFreshCount?.call(freshCount);
        setState(() {
          _viewers = List<Map<String, dynamic>>.from(
            story['viewers'] as List? ?? [],
          );
          _viewCount = freshCount;
          _loading = false;
        });
      }
    } catch (e, st) {
      debugPrint('❌ ViewersSheet load error: $e\n$st');
      if (mounted)
        setState(() {
          _loading = false;
          _error = e.toString();
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.25,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF121212),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(
                      Icons.remove_red_eye_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _loading
                          ? 'Viewers'
                          : '$_viewCount ${_viewCount == 1 ? 'viewer' : 'viewers'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),

              // List
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white30,
                          strokeWidth: 2,
                        ),
                      )
                    : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : _viewers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.remove_red_eye_outlined,
                              color: Colors.white.withValues(alpha: 0.2),
                              size: 40,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No views yet',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: controller,
                        padding: EdgeInsets.fromLTRB(0, 4, 0, bottom + 16),
                        itemCount: _viewers.length,
                        itemBuilder: (_, i) {
                          final v = _viewers[i];
                          final user = v['user'] as Map<String, dynamic>;
                          final photo = user['photo'] as String?;
                          final name =
                              (user['full_name'] ?? user['username'] ?? 'User')
                                  as String;
                          final username = user['username'] as String?;
                          final venueRole = v['venue_role'] as String?;
                          final viewedAt = v['viewed_at'] as String?;
                          final dt = viewedAt != null
                              ? DateTime.tryParse(viewedAt)?.toLocal()
                              : null;
                          final timeLabel = _timeLabel(dt);

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 2,
                            ),
                            leading: CircleAvatar(
                              radius: 22,
                              backgroundColor: Colors.white12,
                              backgroundImage: photo != null && photo.isNotEmpty
                                  ? NetworkImage(photo)
                                  : null,
                              child: photo == null || photo.isEmpty
                                  ? Text(
                                      name.isNotEmpty
                                          ? name[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    )
                                  : null,
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (venueRole != null &&
                                    (venueRole == 'OWNER' ||
                                        venueRole == 'ADMIN')) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: venueRole == 'OWNER'
                                          ? const Color(
                                              0xFF1A9FE8,
                                            ).withValues(alpha: 0.2)
                                          : const Color(
                                              0xFF1FD9A8,
                                            ).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: venueRole == 'OWNER'
                                            ? const Color(
                                                0xFF1A9FE8,
                                              ).withValues(alpha: 0.5)
                                            : const Color(
                                                0xFF1FD9A8,
                                              ).withValues(alpha: 0.5),
                                      ),
                                    ),
                                    child: Text(
                                      venueRole == 'OWNER' ? 'Owner' : 'Admin',
                                      style: TextStyle(
                                        color: venueRole == 'OWNER'
                                            ? const Color(0xFF1A9FE8)
                                            : const Color(0xFF1FD9A8),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: username != null
                                ? Text(
                                    '@$username',
                                    style: TextStyle(
                                      color: Colors.white.withValues(
                                        alpha: 0.4,
                                      ),
                                      fontSize: 12,
                                    ),
                                  )
                                : null,
                            trailing: Text(
                              timeLabel,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 12,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _timeLabel(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _Avatar extends StatelessWidget {
  final String? url;
  final double radius;

  const _Avatar({this.url, required this.radius});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundImage: url != null && url!.isNotEmpty
          ? NetworkImage(url!)
          : null,
      backgroundColor: Colors.grey.shade700,
      child: url == null || url!.isEmpty
          ? Icon(Icons.person, color: Colors.white70, size: radius)
          : null,
    );
  }
}
