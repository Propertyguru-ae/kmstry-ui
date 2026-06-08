import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../data/story_model.dart';
import '../data/story_repository.dart';
import '../data/story_viewed_cache.dart';
import '../../venue/data/venue_repository.dart';
import '../../venue/presentation/venue_detail_page.dart';

class StoryViewerPage extends StatefulWidget {
  final List<StoryGroup> groups;
  final int initialGroupIndex;
  final int initialStoryIndex;

  const StoryViewerPage({
    super.key,
    required this.groups,
    this.initialGroupIndex = 0,
    this.initialStoryIndex = 0,
  });

  @override
  State<StoryViewerPage> createState() => _StoryViewerPageState();
}

class _StoryViewerPageState extends State<StoryViewerPage>
    with TickerProviderStateMixin {
  final _repo = StoryRepository();

  late int _groupIndex;
  int _storyIndex = 0;
  late List<StoryGroup> _groups;
  int _pollToken = 0; // her placeholder yüklemesinde artar → eski polling iptal

  AnimationController? _progressController;
  VideoPlayerController? _videoController;
  bool _videoReady = false;
  bool _advancing = false;
  bool _loadingStory = false;
  int _progressKey = 0; // her story yüklenince artar → progress bar sıfırdan oluşturulur

  static const Duration _photoDuration = Duration(seconds: 5);

  StoryGroup get _currentGroup => _groups[_groupIndex];
  StoryItem get _currentStory => _currentGroup.stories[_storyIndex];

  @override
  void initState() {
    super.initState();
    _groups = List<StoryGroup>.from(widget.groups);
    _groupIndex = widget.initialGroupIndex;
    _storyIndex = widget.initialStoryIndex;
    _loadStory();
  }

  @override
  void dispose() {
    _progressController?.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _loadStory() async {
    _advancing = false;
    _loadingStory = true;
    _progressKey++;
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

    _repo.recordView(story.id).ignore();
    StoryViewedCache.markViewed(story.id).ignore();

    if (story.isVideo) {
      final vc = VideoPlayerController.networkUrl(Uri.parse(story.mediaUrl));
      _videoController = vc;
      try {
        await vc.initialize();
      } catch (e) {
        debugPrint('❌ Video initialize error: $e');
        if (!mounted) return;
        _loadingStory = false;
        final fallback = AnimationController(vsync: this, duration: _photoDuration)
          ..addStatusListener((s) { if (s == AnimationStatus.completed) _advance(); });
        setState(() => _progressController = fallback);
        fallback.forward();
        return;
      }
      if (!mounted) return;
      await vc.setLooping(false);
      // Bitiş tespiti: video pozisyonu sona ulaşınca _advance()
      vc.addListener(() {
        if (_videoController != vc) return; // bu vc artık aktif değil
        final val = vc.value;
        if (!val.isPlaying && !val.isBuffering &&
            val.duration.inMilliseconds > 0 &&
            val.position >= val.duration) {
          vc.removeListener(() {});
          _advance();
        }
      });
      _loadingStory = false;
      setState(() => _videoReady = true);
      await vc.play();
    } else {
      _loadingStory = false;
      final progress = AnimationController(vsync: this, duration: _photoDuration)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _advance();
        });
      setState(() => _progressController = progress);
      progress.forward();
    }
  }

  Future<void> _pollForUploadedStory() async {
    final token = ++_pollToken;
    final group = _currentGroup;
    final groupIdx = _groupIndex;
    final placeholderIdx = _storyIndex;
    final realCount =
        group.stories.where((s) => !s.isUploadingPlaceholder).length;

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

  void _advance() {
    if (!mounted || _advancing || _loadingStory) return;
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
      Navigator.pop(context);
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

void _pauseProgress() {
    if (_loadingStory) return;
    _progressController?.stop();
    _videoController?.pause();
  }

  void _resumeProgress() {
    if (_loadingStory) return;
    _progressController?.forward();
    _videoController?.play();
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
                  : story.isVideo
                  ? _videoReady && _videoController != null
                      ? FittedBox(
                          fit: BoxFit.cover,
                          clipBehavior: Clip.hardEdge,
                          child: SizedBox(
                            width: _videoController!.value.size.width,
                            height: _videoController!.value.size.height,
                            child: VideoPlayer(_videoController!),
                          ),
                        )
                      : const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                  : Image.network(
                      story.mediaUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
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
                          controller: (i == _storyIndex && !story.isVideo)
                              ? _progressController
                              : null,
                          videoController: (i == _storyIndex && story.isVideo && _videoReady)
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
            // Long press on full screen → pause/resume
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPressStart: (_) => _pauseProgress(),
                onLongPressEnd: (_) => _resumeProgress(),
              ),
            ),
            // Left 35% → go back
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              width: screenSize.width * 0.35,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _goBack,
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
                onTap: _advance,
              ),
            ),

            // ── VENUE LABEL (bottom-right) — tap zone'lardan sonra gelir ───
            if (story.venueId != null && story.venueName != null)
              Positioned(
                left: 16,
                bottom: 32,
                child: GestureDetector(
                  onTap: () => _openVenueDetail(story.venueId!, story.venueName!),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                          const Icon(Icons.location_on, color: Colors.white, size: 13),
                        const SizedBox(width: 4),
                        Text(
                          'at ${story.venueName}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            shadows: [Shadow(blurRadius: 3, color: Colors.black54)],
                          ),
                        ),
                      ],
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
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
            ),
          ],
          ),   // Stack
        ),     // SizedBox
    );
  }

  bool _venueLoading = false;

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
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  );
                },
              )
            : active && controller != null
                // Foto: AnimationController ile ilerler
                ? AnimatedBuilder(
                    animation: controller!,
                    builder: (ctx, child) => LinearProgressIndicator(
                      value: controller!.value,
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
