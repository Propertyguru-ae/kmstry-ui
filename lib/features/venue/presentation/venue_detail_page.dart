import 'dart:async';
import 'package:kmstry_frontend/features/media/text_overlay_composer.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/app_back_button.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'package:flutter/foundation.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_stats_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_gallery_section.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_reporsitory.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/checkin/presentation/checkin_upload_page.dart';
import 'package:kmstry_frontend/features/checkin/services/active_checkin_service.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_people_page.dart';
import 'package:kmstry_frontend/features/camera/presentation/camera_screen.dart';
import 'package:kmstry_frontend/features/stories/data/story_model.dart';
import 'package:kmstry_frontend/features/stories/data/story_repository.dart';
import 'package:kmstry_frontend/features/stories/presentation/story_tray.dart';
import 'package:kmstry_frontend/features/stories/presentation/story_viewer_page.dart';
import 'package:kmstry_frontend/features/venue_stories/data/venue_story_model.dart';
import 'package:kmstry_frontend/features/venue_stories/data/venue_story_repository.dart';
import 'package:kmstry_frontend/features/venue_stories/data/venue_story_viewed_cache.dart';

import 'package:kmstry_frontend/features/venue/presentation/personal_event_detail_page.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';

// VenueUpcomingEvent, venue_model.dart'tan geliyor — ayrı import gerekmez

class VenueDetailPage extends StatefulWidget {
  final Venue venue;

  const VenueDetailPage({super.key, required this.venue});

  @override
  State<VenueDetailPage> createState() => _VenueDetailPageState();
}

class _VenueDetailPageState extends State<VenueDetailPage> {
  final _repo = VenueCheckinRepository();
  final _checkinRepo = CheckinRepository();
  final _venueContextRepo = VenueContextRepository();
  final _storyRepo = StoryRepository();
  final _venueStoryRepo = VenueStoryRepository();
  int _storyTrayRefreshCount = 0;
  bool _storyUploading = false;
  bool _hasMyStoryHere =
      false; // kullanıcının bu venue'da kendi story'si var mı
  bool _storyStateKnown =
      false; // StoryTray ilk yüklemesini bitirdi mi (banner flash'ını önler)
  bool _noStoriesHere = false; // bu venue'da hiç story paylaşılmamış mı
  List<VenueStoryItem> _headerStories = [];
  String? _activeCheckinId;
  String? _activeCheckinVenueId;
  String? _activeCheckinVenuePlaceId;
  bool _checkingOut = false;
  String? _resolvedVenueIdForCurrentDetail;
  bool _loadingActiveCheckin = true;
  bool _resolvingVenueForCheckin = false;
  Map<String, dynamic>? _venueDetails;
  Map<String, dynamic>? _enrichedVenueData;
  bool _loadingCheckinStats = false;
  int? _checkinCountActive;
  int? _checkinCountMale;
  int? _checkinCountFemale;
  bool _isFollowing = false;
  int _followerCount = 0;
  bool _followLoading = false;
  int _galleryCount = 0; // VenueGalleryStrip'ten gelen foto/video adedi
  bool _isAnonymous = false; // Anonymous Mode blocks story sharing

  // Backend'deki 200m check-in mesafe sınırıyla aynı değer (checkins.service.ts).
  static const double _kCheckinMaxDistanceMeters = 200;

  /// null = henüz doğrulanmadı → buton pasif kalır. Sadece kesin olarak
  /// venue'nün 200m içinde olduğu ölçülünce true olur ("fail-closed").
  bool? _isNearVenue;
  bool _checkingProximity = true;

  @override
  void initState() {
    super.initState();
    _checkinCountActive = widget.venue.checkinCountActive;
    _checkinCountMale = widget.venue.checkinCountMale;
    _checkinCountFemale = widget.venue.checkinCountFemale;
    _isFollowing = widget.venue.isFollowing;
    _followerCount = widget.venue.followerCount;
    _primeResolvedVenueId();
    _primeActiveCheckinFromMemory();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startDeferredInitialLoads();
    });
  }

  void _primeResolvedVenueId() {
    if (widget.venue.isInDb && widget.venue.id.isNotEmpty) {
      _resolvedVenueIdForCurrentDetail = widget.venue.id;
    }
  }

  void _primeActiveCheckinFromMemory() {
    final active = ActiveCheckinService();
    final activeId = active.activeCheckinId;
    if (activeId == null || activeId.isEmpty) return;
    _activeCheckinId = activeId;
    _activeCheckinVenueId = active.activeVenueId;
    _loadingActiveCheckin = false;
  }

  void _startDeferredInitialLoads() {
    unawaited(_loadVenueDetails());
    unawaited(_loadActiveCheckin());
    unawaited(_loadEnrichedVenueData());
    unawaited(_checkProximity(useFreshGps: false));

    if (_checkinCountActive == null &&
        (_checkinCountMale == null || _checkinCountFemale == null)) {
      unawaited(_refreshCheckinStats());
    }

    unawaited(_loadHeaderStories());
    Future.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      unawaited(_loadAnonymousStatus());
    });
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      unawaited(_checkProximity(useFreshGps: true));
    });
  }

  /// Gerçek venue'lerde kullanıcının fiziksel olarak mekânda olup olmadığını
  /// kontrol eder — check-in butonu SADECE bu doğrulandıktan sonra aktif olur.
  /// Alpha/Beta test venue'lerinde (isTestVenue) her zaman true döner, backend
  /// mesafe kontrolünü zaten atlıyor.
  ///
  /// Hız için önce cihazda önbelleğe alınmış son konum (getLastKnownPosition,
  /// neredeyse anında döner) kullanılıp buton hemen karar veriyor; ardından
  /// arka planda taze bir GPS okumasıyla (5sn sınırlı) sonuç sessizce doğrulanıyor.
  Future<void> _checkProximity({required bool useFreshGps}) async {
    if (_enrichedVenueData?['isTestVenue'] == true) return;
    if (!widget.venue.latitude.isFinite || !widget.venue.longitude.isFinite) {
      if (mounted) setState(() => _checkingProximity = false);
      return;
    }

    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) _applyProximityResult(lastKnown);
    } catch (_) {}

    if (!useFreshGps) {
      if (mounted && _checkingProximity) {
        setState(() => _checkingProximity = false);
      }
      return;
    }

    try {
      final fresh = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
      _applyProximityResult(fresh);
    } catch (_) {
      // Konum alınamadı/zaman aşımı — hâlâ "checking" ise pasif göster,
      // sunucu zaten check-in anında kesin kontrolü yapacak.
      if (mounted && _checkingProximity) {
        setState(() => _checkingProximity = false);
      }
    }
  }

  void _applyProximityResult(Position position) {
    if (!mounted) return;
    if (_enrichedVenueData?['isTestVenue'] == true) return;
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      widget.venue.latitude,
      widget.venue.longitude,
    );
    setState(() {
      _isNearVenue = distance <= _kCheckinMaxDistanceMeters;
      _checkingProximity = false;
    });
  }

  void _showAnonymousStoryBlockedDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.visibility_off_rounded, size: 28),
        title: const Text("You're in Anonymous Mode"),
        content: const Text(
          "While Anonymous Mode is on, you're invisible — so you can't share "
          "stories (no one would see them).\n\n"
          "To share a story, turn it off from:\n"
          "Settings › Account Center › Manage Accounts › your account.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadAnonymousStatus() async {
    try {
      final me = await AuthRepository().getMe();
      if (!mounted) return;
      setState(() => _isAnonymous = me['isAnonymous'] == true);
    } catch (_) {}
  }

  Future<void> _loadHeaderStories() async {
    try {
      final stories = await _venueStoryRepo.getVenueStories(widget.venue.id);
      if (!mounted) return;
      setState(() {
        _headerStories = stories;
      });
    } catch (_) {}
  }

  void _openStoryViewer() {
    if (_headerStories.isEmpty) return;
    final venueId = widget.venue.id;
    final startIndex = _headerStories.indexWhere((s) => !s.viewedByMe);
    final initialIndex = startIndex == -1 ? 0 : startIndex;
    final group = StoryGroup(
      user: StoryUser(
        id: 'venue_$venueId',
        fullName: widget.venue.name,
        photo: widget.venue.photoUrl.isNotEmpty ? widget.venue.photoUrl : null,
      ),
      stories: _headerStories
          .map(
            (s) => StoryItem(
              id: s.id,
              mediaUrl: s.mediaUrl,
              mediaType: s.mediaType,
              thumbnailUrl: s.thumbnailUrl,
              durationSecs: s.durationSecs,
              expiresAt: s.expiresAt,
              createdAt: s.createdAt,
              viewCount: s.viewCount,
            ),
          )
          .toList(),
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
                ? _headerStories.map((s) => s.id).toSet()
                : {
                    for (
                      int i = 0;
                      i <= lastIndex && i < _headerStories.length;
                      i++
                    )
                      _headerStories[i].id,
                  };
            final cache = VenueStoryViewedCache.instance;
            justViewed.forEach(cache.mark);
            if (!mounted) return;
            setState(() {
              _headerStories = [
                for (final s in _headerStories)
                  (s.viewedByMe || justViewed.contains(s.id))
                      ? s.copyWith(viewedByMe: true)
                      : s,
              ];
            });
          },
        ),
      ),
    );
  }

  /// For Google-backed detail, [Venue.id] may be a Places id while active check-in uses DB UUID.
  /// We need a stable key to resolve/compare without flashing the wrong CTA.
  String? _effectivePlaceKeyForActiveCheckinCorrelation() {
    final p = widget.venue.placeId;
    if (p != null && p.isNotEmpty) return p;
    if (widget.venue.source != 'google') return null;
    if (widget.venue.id.isEmpty) return null;
    // Real DB uuid as id — matching is done via id == activeVenueId.
    if (widget.venue.isInDb && widget.venue.canCheckin) return null;
    return widget.venue.id;
  }

  Future<void> _loadEnrichedVenueData() async {
    if (!widget.venue.isInDb || widget.venue.id.isEmpty) return;
    try {
      final data = await _venueContextRepo.getVenueById(widget.venue.id);
      if (!mounted) return;
      setState(() {
        _enrichedVenueData = data;
        _isFollowing = (data['isFollowing'] ?? data['is_following']) == true;
        _followerCount =
            _parseOptionalInt(
              data['followerCount'] ?? data['follower_count'],
            ) ??
            _followerCount;
        if (data['isTestVenue'] == true) {
          _isNearVenue = true;
          _checkingProximity = false;
        }
      });
    } catch (e) {
      debugPrint('⚠️ Could not load enriched venue data: $e');
    }
  }

  Future<void> _loadVenueDetails() async {
    try {
      final placeId = widget.venue.placeId;

      if (placeId == null || placeId.isEmpty) {
        return;
      }

      final data = await _venueContextRepo.getVenueDetails(placeId);

      if (!mounted) return;

      setState(() {
        _venueDetails = data;
      });
    } catch (e) {
      debugPrint('❌ Error loading venue details: $e');
    }
  }

  int? _parseOptionalInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Future<void> _toggleFollow() async {
    if (_followLoading || !widget.venue.isInDb || widget.venue.id.isEmpty) {
      return;
    }
    final previousFollowing = _isFollowing;
    final previousCount = _followerCount;
    final nextFollowing = !previousFollowing;

    setState(() {
      _followLoading = true;
      _isFollowing = nextFollowing;
      _followerCount = nextFollowing
          ? previousCount + 1
          : (previousCount > 0 ? previousCount - 1 : 0);
    });

    try {
      final result = nextFollowing
          ? await _venueContextRepo.followVenue(widget.venue.id)
          : await _venueContextRepo.unfollowVenue(widget.venue.id);
      final count = _parseOptionalInt(result['followerCount']);
      if (mounted && count != null) {
        setState(() => _followerCount = count);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFollowing = previousFollowing;
        _followerCount = previousCount;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextFollowing
                ? 'Could not follow this venue.'
                : 'Could not unfollow this venue.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _followLoading = false);
      }
    }
  }

  // ── Logo-renkli tema paleti (light/dark uyumlu) ───────────────────────────
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _pageBg => _isDark ? AppColors.darkBg : Colors.white;
  Color get _cardSurface =>
      _isDark ? const Color(0xFF0D1525) : const Color(0xFFF4F7FB);
  Color get _cardBorder =>
      _isDark ? const Color(0xFF162040) : Colors.black.withValues(alpha: 0.08);
  Color get _textPrimary => _isDark ? Colors.white : const Color(0xFF0F172A);
  // Daha okunaklı: eski muted/faint tonları çok soluktu.
  Color get _textMuted =>
      _isDark ? const Color(0xFFA6BAD6) : const Color(0xFF4B5563);
  Color get _textFaint =>
      _isDark ? const Color(0xFF7E93B4) : const Color(0xFF6B7684);

  /// Bölüm başlığı: renkli logo noktası + başlık + opsiyonel sağ aksiyon.
  Widget _sectionTitle(Color dotColor, String title, {Widget? trailing}) {
    final left = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: _isDark ? const Color(0xFFC8D8F0) : _textPrimary,
          ),
        ),
      ],
    );
    if (trailing == null) return left;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [left, trailing],
    );
  }

  /// Check-in yapmış ama henüz story paylaşmamış kullanıcıya, "Your story"
  /// baloncuğunun ne olduğunu açıklayan ve paylaşmaya teşvik eden bilgi kartı.
  Widget _buildShareStoryHint() {
    return GestureDetector(
      onTap: _openAddStory,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: [
              AppColors.magenta.withValues(alpha: _isDark ? 0.16 : 0.10),
              AppColors.blue.withValues(alpha: _isDark ? 0.14 : 0.08),
            ],
          ),
          border: Border.all(color: AppColors.magenta.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.magenta.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.add_a_photo_rounded,
                size: 18,
                color: AppColors.magenta,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "You're checked in — share a story",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Show everyone the vibe here. Your story stays for 24h.',
                    style: TextStyle(fontSize: 11.5, color: _textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 20, color: _textMuted),
          ],
        ),
      ),
    );
  }

  /// Bu venue'da henüz hiç story yokken, check-in yapmamış kullanıcıyı ilk
  /// story'yi paylaşmaya teşvik eden boş-durum kartı. Basınca check-in akışı.
  Widget _buildFirstStoryCta() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: _openCheckinFlow,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                AppColors.blue.withValues(alpha: _isDark ? 0.16 : 0.10),
                AppColors.teal.withValues(alpha: _isDark ? 0.14 : 0.08),
              ],
            ),
            border: Border.all(color: AppColors.blue.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.blue, AppColors.teal],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      size: 20,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Be the first to share a story!',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'No stories here yet. Check in and show everyone the vibe.',
                          style: TextStyle(fontSize: 11.5, color: _textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // "Check in" — check-in butonuyla aynı blue→teal gradient.
              _actionButton(
                height: 44,
                onTap: _openCheckinFlow,
                gradient: const LinearGradient(
                  colors: [AppColors.blue, AppColors.teal],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.blue.withValues(alpha: 0.34),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_location_alt_rounded,
                      size: 17,
                      color: Colors.white,
                    ),
                    SizedBox(width: 7),
                    Text(
                      'Check in',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Aksiyon butonları için ortak kap — gradient/solid + opsiyonel kenarlık/gölge.
  Widget _actionButton({
    required VoidCallback? onTap,
    required Widget child,
    Color? background,
    Gradient? gradient,
    Color? borderColor,
    List<BoxShadow>? boxShadow,
    double height = 46,
  }) {
    return SizedBox(
      height: height,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: gradient == null ? background : null,
              gradient: gradient,
              borderRadius: BorderRadius.circular(14),
              border: borderColor != null
                  ? Border.all(color: borderColor, width: 1.4)
                  : null,
              boxShadow: boxShadow,
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  Widget _buildFollowButton() {
    if (!widget.venue.isInDb || widget.venue.id.isEmpty) {
      return const SizedBox.shrink();
    }
    final following = _isFollowing;
    return _actionButton(
      onTap: _followLoading ? null : _toggleFollow,
      background: following
          ? AppColors.teal.withValues(alpha: 0.12)
          : AppColors.teal,
      borderColor: following ? AppColors.teal.withValues(alpha: 0.34) : null,
      child: _followLoading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: following ? AppColors.teal : Colors.white,
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  following ? Icons.check_rounded : Icons.add_rounded,
                  size: 16,
                  color: following ? AppColors.teal : Colors.white,
                ),
                const SizedBox(width: 6),
                Text(
                  following ? 'Following' : 'Follow',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: following ? AppColors.teal : Colors.white,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildDirectionsButton() {
    final enabled = _canOpenDirections;
    return _actionButton(
      onTap: enabled ? () => _openDirections() : null,
      background: _cardSurface,
      borderColor: _cardBorder,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.directions_outlined,
            size: 16,
            color: enabled ? AppColors.blue : _textFaint,
          ),
          const SizedBox(width: 6),
          Text(
            'Directions',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: enabled ? _textMuted : _textFaint,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadActiveCheckin() async {
    try {
      final activeCheckin = await _repo.getActiveCheckin();
      final activeVenueId = activeCheckin?.venueId;

      if (!mounted) return;

      if (activeVenueId == null || activeVenueId.isEmpty) {
        setState(() {
          _activeCheckinId = null;
          _activeCheckinVenueId = null;
          _activeCheckinVenuePlaceId = null;
          _loadingActiveCheckin = false;
        });
        return;
      }

      setState(() {
        _activeCheckinId = activeCheckin?.id;
        _activeCheckinVenueId = activeVenueId;
        _activeCheckinVenuePlaceId = null;
        // Stay loading until we can decide "here" vs elsewhere (avoid wrong "Check in first").
      });

      final matchedById =
          widget.venue.id.isNotEmpty && widget.venue.id == activeVenueId;
      if (matchedById) {
        if (mounted) {
          setState(() => _loadingActiveCheckin = false);
        }
        return;
      }

      final placeKey = _effectivePlaceKeyForActiveCheckinCorrelation();
      if (placeKey != null && placeKey.isNotEmpty) {
        try {
          final resolvedResponse = await _venueContextRepo
              .resolveVenueFromPlace(placeKey);
          final resolved = _extractVenueIdFromResponse(resolvedResponse);
          if (!mounted) return;
          if (resolved != null &&
              resolved.isNotEmpty &&
              resolved == activeVenueId) {
            setState(() {
              _resolvedVenueIdForCurrentDetail = resolved;
              _loadingActiveCheckin = false;
            });
            return;
          }
        } catch (e) {
          debugPrint('⚠️ resolve for active check-in correlation: $e');
        }
      }

      try {
        final venueData = await _venueContextRepo.getVenueById(activeVenueId);
        final placeId =
            (venueData['placeId'] ??
                    venueData['place_id'] ??
                    venueData['googlePlaceId'] ??
                    venueData['google_place_id'])
                ?.toString();
        if (!mounted) return;
        setState(() {
          if (placeId != null && placeId.isNotEmpty) {
            _activeCheckinVenuePlaceId = placeId;
          }
          _loadingActiveCheckin = false;
        });
      } catch (e) {
        debugPrint('⚠️ Could not load active check-in venue details: $e');
        if (!mounted) return;
        setState(() => _loadingActiveCheckin = false);
      }
    } catch (e) {
      debugPrint('⚠️ Error loading active check-in: $e');
      if (!mounted) return;
      setState(() {
        _activeCheckinId = null;
        _activeCheckinVenueId = null;
        _loadingActiveCheckin = false;
      });
    }
  }

  String? _extractVenueIdFromResponse(Map<String, dynamic> response) {
    final direct =
        response['venueId'] ?? response['venue_id'] ?? response['id'];
    if (direct is String && direct.isNotEmpty) return direct;

    final venue = response['venue'];
    if (venue is Map) {
      final nestedId = venue['id'] ?? venue['venueId'] ?? venue['venue_id'];
      if (nestedId is String && nestedId.isNotEmpty) return nestedId;
    }
    return null;
  }

  Future<String> _resolveVenueIdForCheckin() async {
    if (widget.venue.id.isNotEmpty && widget.venue.canCheckin) {
      return widget.venue.id;
    }

    final placeId = widget.venue.placeId;
    if (placeId == null || placeId.isEmpty) {
      if (widget.venue.id.isNotEmpty) return widget.venue.id;
      throw Exception('Venue reference is missing');
    }

    // Check-in flow must resolve a usable venue id without claim/account side effects.
    final resolvedResponse = await _venueContextRepo.resolveVenueFromPlace(
      placeId,
    );
    final resolved = _extractVenueIdFromResponse(resolvedResponse);
    if (resolved == null || resolved.isEmpty) {
      throw Exception('Could not resolve venue id from place');
    }
    return resolved;
  }

  Future<void> _openCheckinFlow() async {
    setState(() => _resolvingVenueForCheckin = true);
    try {
      final resolvedVenueId = await _resolveVenueIdForCheckin();
      if (!mounted) return;
      setState(() {
        _resolvedVenueIdForCurrentDetail = resolvedVenueId;
      });
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CheckInPage(
            venueId: resolvedVenueId,
            venueLatitude: widget.venue.latitude,
            venueLongitude: widget.venue.longitude,
          ),
        ),
      );

      // Check-in tamamlandıysa → who's here sayfasına direkt geç.
      final active = ActiveCheckinService();
      if (mounted && active.isCheckedInAt(resolvedVenueId)) {
        // Buton durumunu re-fetch yarışına bırakmadan hemen "Who's here?"e
        // çevir — who's-here'den geri dönünce "Check in" gösterme bug'ını önler.
        if (mounted) {
          setState(() {
            _activeCheckinId = active.activeCheckinId;
            _activeCheckinVenueId = active.activeVenueId ?? resolvedVenueId;
            _resolvedVenueIdForCurrentDetail = resolvedVenueId;
            _loadingActiveCheckin = false;
          });
        }
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VenuePeoplePage(
              venue: widget.venue,
              listVenueId: resolvedVenueId,
            ),
          ),
        );
      }

      _loadActiveCheckin();
      await _refreshCheckinStats(forcedVenueId: resolvedVenueId);
      Future.delayed(const Duration(seconds: 1), () {
        if (!mounted) return;
        _refreshCheckinStats(forcedVenueId: resolvedVenueId);
      });
    } catch (e) {
      if (!mounted) return;
      await showPremiumErrorDialog(
        context,
        message: 'Could not prepare venue for check-in',
      );
      debugPrint('❌ Check-in venue resolve error: $e');
    } finally {
      if (mounted) {
        setState(() => _resolvingVenueForCheckin = false);
      }
    }
  }

  /// Zaten bu venue'da aktif check-in varsa mesafe kontrolü uygulanmaz
  /// (kullanıcı zaten orada, sadece "Who's here?"e gidiyor). Yeni check-in
  /// için buton SADECE konum doğrulanıp venue'nün 200m içinde olduğu
  /// kesinleşince aktif olur — doğrulanana kadar ve venue dışındaysa pasif
  /// kalır, "You're not at this venue" yazar.
  Widget _buildCheckinButton(bool hasActiveCheckinHere) {
    final notVerifiedYet = !hasActiveCheckinHere && _isNearVenue != true;
    final disabled =
        _loadingActiveCheckin || _resolvingVenueForCheckin || notVerifiedYet;

    String? label;
    if (_resolvingVenueForCheckin) {
      label = null; // spinner gösterilir, metin yok
    } else if (hasActiveCheckinHere) {
      label = "Who's here?";
    } else if (_checkingProximity) {
      label = 'Checking your location...';
    } else if (_isNearVenue != true) {
      label = "You're not at this venue";
    } else {
      label = 'Check in';
    }

    final enabled = !disabled;
    return SizedBox(
      width: double.infinity,
      child: _actionButton(
        height: 48,
        onTap: disabled
            ? null
            : () async {
                if (hasActiveCheckinHere) {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VenuePeoplePage(
                        venue: widget.venue,
                        listVenueId:
                            _activeCheckinVenueId ??
                            _resolvedVenueIdForCurrentDetail,
                      ),
                    ),
                  );
                  _refreshCheckinStats();
                  return;
                }
                await _openCheckinFlow();
              },
        gradient: enabled
            ? const LinearGradient(
                colors: [AppColors.blue, AppColors.teal],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        background: enabled ? null : _cardSurface,
        borderColor: enabled ? null : _cardBorder,
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: AppColors.blue.withValues(alpha: 0.34),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
        child: _resolvingVenueForCheckin
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    hasActiveCheckinHere
                        ? Icons.groups_rounded
                        : Icons.add_location_alt_rounded,
                    size: 17,
                    color: enabled ? Colors.white : _textFaint,
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      label!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: enabled ? Colors.white : _textFaint,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  bool _openingStory = false;

  Future<void> _openAddStory() async {
    // Banner + baloncuk aynı akışı tetikliyor; üst üste basınca birden fazla
    // kamera açılmasın — açılış tamamlanana kadar tekrar girişi engelle.
    if (_openingStory) return;
    final checkinId = _activeCheckinId;
    if (checkinId == null) return;
    _openingStory = true;
    try {
      await _openAddStoryFlow(checkinId);
    } finally {
      if (mounted) _openingStory = false;
    }
  }

  Future<void> _openAddStoryFlow(String checkinId) async {
    // Anonymous Mode: önbellekteki durumla ANINDA geçit yap (kamera hemen
    // açılsın). Sayfa açılışında ve arka planda zaten güncelleniyor; ayrıca
    // backend upload'da da anon kontrolü yapıyor → güvenli.
    if (_isAnonymous) {
      _showAnonymousStoryBlockedDialog();
      return;
    }

    // Video akışı CapturedMedia (dosya + text overlay) dönebilir.
    final dynamic captureResult = await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const CameraScreen(useFrontCamera: true),
      ),
    );

    final File? file = captureResult is CapturedMedia
        ? captureResult.file
        : captureResult as File?;
    final storyOverlay = captureResult is CapturedMedia
        ? captureResult.overlay
        : null;
    if (file == null || !mounted) return;

    // Determine media type from extension.
    final filePath = file.path;
    final isVideo =
        filePath.endsWith('.mp4') ||
        filePath.endsWith('.mov') ||
        filePath.endsWith('.avi');
    final mediaType = isVideo ? 'video' : 'photo';

    // Overlay'i async gap'ten ÖNCE yakala — kullanıcı başka sayfaya geçse bile
    // kart root overlay üzerinde gösterilecek.
    final overlay = Overlay.maybeOf(context, rootOverlay: true);

    setState(() => _storyUploading = true);

    try {
      await _storyRepo.createStory(
        checkinId: checkinId,
        file: file,
        mediaType: mediaType,
        textOverlayJson: storyOverlay?.toJsonString(),
      );
      // Sayfa hâlâ açıksa tray'i yenile.
      if (mounted) {
        setState(() {
          _storyUploading = false;
          _storyTrayRefreshCount++;
        });
      }
      // Kutlama kartını göster — kullanıcı nerede olursa olsun.
      if (overlay != null) {
        showStorySharedCard(
          overlay,
          mediaFile: file,
          venueName: widget.venue.name,
          isVideo: isVideo,
        );
      }
    } catch (e, st) {
      debugPrint('❌ Story upload error: $e\n$st');
      if (!mounted) return;
      setState(() => _storyUploading = false);
      await showPremiumErrorDialog(context, message: 'Upload failed: $e');
    }
  }

  Future<void> _checkout() async {
    final checkinId = _activeCheckinId;
    if (checkinId == null) return;

    setState(() => _checkingOut = true);
    try {
      await _checkinRepo.checkout(checkinId);
      ActiveCheckinService().clear();
      if (!mounted) return;
      setState(() {
        _activeCheckinId = null;
        _activeCheckinVenueId = null;
        _activeCheckinVenuePlaceId = null;
        _checkingOut = false;
        // Checkout backend'de bu check-in'in story'sini de sildi; tray key'ini
        // değiştirip yeniden yükleterek "Me" balonunu anında kaldır.
        _storyTrayRefreshCount++;
      });
      await _refreshCheckinStats();
    } catch (e) {
      debugPrint('❌ Checkout error: $e');
      if (!mounted) return;
      setState(() => _checkingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not check out. Please try again.')),
      );
    }
  }

  Future<void> _refreshCheckinStats({String? forcedVenueId}) async {
    if (_loadingCheckinStats) return;
    setState(() => _loadingCheckinStats = true);
    try {
      String? venueId = forcedVenueId;
      if (venueId == null || venueId.isEmpty) {
        try {
          venueId = await _resolveVenueIdForCheckin();
        } catch (_) {
          venueId = null;
        }
      }
      if (venueId == null || venueId.isEmpty) {
        if (!mounted) return;
        setState(() => _loadingCheckinStats = false);
        return;
      }
      final VenueCheckinStats stats = await _venueContextRepo
          .getVenueCheckinStats(venueId);

      if (!mounted) return;
      setState(() {
        _resolvedVenueIdForCurrentDetail ??= venueId;
        _checkinCountActive = stats.checkinCountActive;
        _checkinCountMale = stats.male;
        _checkinCountFemale = stats.female;
        _loadingCheckinStats = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCheckinStats = false);
    }
  }

  int? get _displayCheckinTotal {
    if (_checkinCountActive != null) return _checkinCountActive;
    if (_checkinCountMale != null && _checkinCountFemale != null) {
      return _checkinCountMale! + _checkinCountFemale!;
    }
    return null;
  }

  Widget _buildDescriptionSection(String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(AppColors.magenta, 'About'),
        const SizedBox(height: 8),
        Text(
          description,
          style: TextStyle(fontSize: 13, height: 1.6, color: _textMuted),
        ),
      ],
    );
  }

  Widget _buildUpcomingEventsSection(List<VenueUpcomingEvent> events) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(AppColors.orange, 'Upcoming Events'),
        const SizedBox(height: 10),
        ...events.map((event) => _buildEventCard(event)),
      ],
    );
  }

  Widget _buildEventCard(VenueUpcomingEvent event) {
    final paid = event.priceAed != null;
    final accent = paid ? AppColors.orange : AppColors.teal;
    final imgUrl = event.photos.isNotEmpty ? event.photos.first : event.photo;
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PersonalEventDetailPage(
            event: event,
            venueId: widget.venue.id,
            venueName: widget.venue.name,
            venueAddress: (_venueDetails?['address'] ?? widget.venue.address)
                ?.toString(),
            venuePhotoUrl: widget.venue.photoUrl,
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(11, 11, 13, 11),
        decoration: BoxDecoration(
          color: _cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _cardBorder),
        ),
        child: Row(
          children: [
            // Sol renkli aksan çubuğu (free = teal, paid = orange)
            Container(
              width: 3,
              height: 34,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 11),
            if (imgUrl != null && imgUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: CachedImage(
                  imgUrl,
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                  errorWidget: (ctx) => _eventIconTile(accent, paid),
                ),
              )
            else
              _eventIconTile(accent, paid),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    event.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _isDark ? const Color(0xFFEEF2FF) : _textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule_rounded, size: 12, color: accent),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          event.formattedDate,
                          style: TextStyle(fontSize: 11, color: _textFaint),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accent.withValues(alpha: 0.24)),
              ),
              child: Text(
                paid ? '${event.priceAed} AED' : 'Free',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _eventIconTile(Color accent, bool paid) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(
        paid ? Icons.confirmation_number_outlined : Icons.event_outlined,
        color: accent,
        size: 17,
      ),
    );
  }

  /// Small icon + value pill used in the header line under the venue name.
  Widget _headerCount(IconData icon, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: _textFaint),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            color: _textFaint,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// Men/Women share as icon-only percentages, shown to the right of the total.
  List<Widget> _headerGenderPcts() {
    final male = _checkinCountMale;
    final female = _checkinCountFemale;
    final base = (male ?? 0) + (female ?? 0);
    if (base == 0) return const [];
    final malePct = ((male ?? 0) * 100 / base).round();
    final femalePct = 100 - malePct;
    return [
      const SizedBox(width: 10),
      _headerCount(Icons.man_rounded, '$malePct%'),
      const SizedBox(width: 8),
      _headerCount(Icons.woman_rounded, '$femalePct%'),
    ];
  }

  bool _hasValidLatLng(Venue v) {
    if (!v.latitude.isFinite || !v.longitude.isFinite) return false;
    if (v.latitude == 0 && v.longitude == 0) return false;
    return true;
  }

  bool get _canOpenDirections {
    final v = widget.venue;
    final pid = v.placeId?.trim();
    if (pid != null && pid.isNotEmpty) return true;
    if (_hasValidLatLng(v)) return true;
    return '${v.address} ${v.city}'.trim().isNotEmpty;
  }

  String _safeDisplayPhotoUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4';
    }
    return trimmed;
  }

  Future<void> _openDirections() async {
    final v = widget.venue;
    final hasLatLng = _hasValidLatLng(v);
    final placeId = v.placeId?.trim();
    final labelQuery = '${v.name} ${v.address} ${v.city}'
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final latLng = hasLatLng ? '${v.latitude},${v.longitude}' : '';
    final destinationForUrl = labelQuery.isNotEmpty ? labelQuery : latLng;
    final destinationForApp = labelQuery.isNotEmpty ? labelQuery : latLng;

    if (destinationForUrl.isEmpty) {
      if (!mounted) return;
      await showPremiumErrorDialog(
        context,
        message: 'No location available for directions',
      );
      return;
    }

    // Google Maps universal URL: opens directions preview (ETA + Start button).
    final browserParams = <String, String>{
      'api': '1',
      'destination': destinationForUrl,
      'travelmode': 'driving',
    };
    if (placeId != null && placeId.isNotEmpty) {
      browserParams['destination_place_id'] = placeId;
    }
    final browserUri = Uri.https('www.google.com', '/maps/dir/', browserParams);

    // Platform-preferred deep links to open maps app directly when available.
    final List<Uri> launchOrder = [];
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // Google Maps app scheme (iOS) in route-preview mode (not auto-start).
      final iosDaddr = placeId != null && placeId.isNotEmpty
          ? 'place_id:$placeId'
          : destinationForApp;
      launchOrder.add(
        Uri(
          scheme: 'comgooglemaps',
          queryParameters: {
            'daddr': iosDaddr,
            'directionsmode': 'driving',
            'views': 'traffic',
          },
        ),
      );
    }
    // Cross-platform fallback that keeps route preview visible.
    launchOrder.add(browserUri);

    for (final uri in launchOrder) {
      try {
        if (!await canLaunchUrl(uri)) continue;
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      } catch (_) {
        // Try next fallback uri.
      }
    }

    if (!mounted) return;
    await showPremiumErrorDialog(context, message: 'Could not open maps');
  }

  bool _isActiveCheckinAtCurrentVenue() {
    final activeVenueId = _activeCheckinVenueId;
    if (activeVenueId == null || activeVenueId.isEmpty) return false;

    final resolvedCurrentVenueId = _resolvedVenueIdForCurrentDetail;
    if (resolvedCurrentVenueId != null &&
        resolvedCurrentVenueId.isNotEmpty &&
        activeVenueId == resolvedCurrentVenueId) {
      return true;
    }

    final currentVenueId = widget.venue.id;
    if (currentVenueId.isNotEmpty && activeVenueId == currentVenueId) {
      return true;
    }

    final currentPlaceId = widget.venue.placeId;
    final activePlaceId = _activeCheckinVenuePlaceId;
    if (currentPlaceId != null &&
        currentPlaceId.isNotEmpty &&
        activePlaceId != null &&
        activePlaceId.isNotEmpty &&
        currentPlaceId == activePlaceId) {
      return true;
    }

    // Some google-only cards use placeId as id.
    if (activePlaceId != null &&
        activePlaceId.isNotEmpty &&
        currentVenueId == activePlaceId) {
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveCheckinHere = _isActiveCheckinAtCurrentVenue();
    final opening = _venueDetails?['openingHours'];
    final isOpen = opening?['open_now'] == true;
    final weekdayText = opening?['weekday_text'];
    final rating = _venueDetails?['rating'];
    final live = (_displayCheckinTotal ?? 0) > 0;
    final statusDotColor = live ? AppColors.teal : AppColors.orange;
    final address = (_venueDetails?['address'] ?? widget.venue.address ?? '')
        .toString()
        .trim();
    final followAvailable = widget.venue.isInDb && widget.venue.id.isNotEmpty;

    return Scaffold(
      backgroundColor: _pageBg,
      body: Stack(
        children: [
          // ── Scrollable content ──────────────────────────────────────────
          SingleChildScrollView(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// COVER HERO — tam genişlik, alta doğru sayfa zeminine erir
                SizedBox(
                  height: 210,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedImage(
                        _safeDisplayPhotoUrl(widget.venue.photoUrl),
                        fit: BoxFit.cover,
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          height: 120,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, _pageBg],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                /// COVER ALTI — cover'ı örtmek için 28px yukarı çekilir
                Transform.translate(
                  offset: const Offset(0, -28),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        /// IDENTITY — avatar + isim + durum
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _VenueDetailAvatarRing(
                              photoUrl: widget.venue.photoUrl,
                              hasStories: _headerStories.isNotEmpty,
                              allSeen:
                                  _headerStories.isNotEmpty &&
                                  _headerStories.every((s) => s.viewedByMe),
                              onTap: _headerStories.isNotEmpty
                                  ? _openStoryViewer
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      widget.venue.name,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        height: 1.1,
                                        letterSpacing: -0.3,
                                        color: _textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Row(
                                      children: [
                                        Container(
                                          width: 7,
                                          height: 7,
                                          decoration: BoxDecoration(
                                            color: statusDotColor,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            widget.venue.status,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: _textMuted,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),

                        /// CHECK-IN İSTATİSTİK SATIRI (varsa)
                        if (_displayCheckinTotal != null) ...[
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _headerCount(
                                Icons.people_rounded,
                                '$_displayCheckinTotal',
                              ),
                              ..._headerGenderPcts(),
                            ],
                          ),
                        ],

                        const SizedBox(height: 14),

                        /// ADDRESS
                        if (address.isNotEmpty) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.location_on_rounded,
                                size: 15,
                                color: AppColors.blue,
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  address,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _textMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],

                        /// OPEN / RATING / HOURS
                        if (opening != null || rating != null)
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 14,
                            runSpacing: 6,
                            children: [
                              if (opening != null)
                                Text(
                                  isOpen ? 'Open now' : 'Closed',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: isOpen
                                        ? AppColors.teal
                                        : AppColors.orange,
                                  ),
                                ),
                              if (rating != null)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      color: Color(0xFFFFC24B),
                                      size: 15,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      (rating as num).toStringAsFixed(1),
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: _textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        if (weekdayText != null && weekdayText.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            weekdayText[DateTime.now().weekday - 1],
                            style: TextStyle(fontSize: 12, color: _textFaint),
                          ),
                        ],

                        /// "İlk check-in ol" daveti
                        if (_displayCheckinTotal == null &&
                            !_loadingCheckinStats) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Be the first to check in.',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _textMuted,
                            ),
                          ),
                        ],

                        const SizedBox(height: 14),

                        /// ACTIONS — Follow · Directions (satır) + Check in (tam)
                        Row(
                          children: [
                            if (followAvailable) ...[
                              Expanded(child: _buildFollowButton()),
                              const SizedBox(width: 9),
                            ],
                            Expanded(child: _buildDirectionsButton()),
                          ],
                        ),
                        const SizedBox(height: 9),
                        _buildCheckinButton(hasActiveCheckinHere),

                        /// CHECK OUT — sadece bu venue'da aktif check-in varken
                        if (hasActiveCheckinHere) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton(
                              onPressed: _checkingOut
                                  ? null
                                  : () async {
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Check out?'),
                                          content: const Text(
                                            'You will leave this venue and your check-in will end.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: const Text('Cancel'),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              child: const Text('Check out'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirmed == true) await _checkout();
                                    },
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                              ),
                              child: _checkingOut
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Check out'),
                            ),
                          ),
                        ],

                        /// STORY TRAY
                        if (_resolvedVenueIdForCurrentDetail != null) ...[
                          const SizedBox(height: 18),
                          _sectionTitle(AppColors.magenta, 'Stories'),
                          // Check-in'li ama henüz story paylaşmamış kullanıcıyı
                          // teşvik et + baloncuğun ne olduğunu açıkla.
                          if (hasActiveCheckinHere &&
                              _storyStateKnown &&
                              !_hasMyStoryHere &&
                              !_storyUploading &&
                              !_isAnonymous) ...[
                            const SizedBox(height: 8),
                            _buildShareStoryHint(),
                          ],
                          const SizedBox(height: 10),
                          // Hiç story yok + kullanıcı burada check-in'li değil →
                          // ilk story'yi paylaşmaya teşvik eden CTA.
                          if (_noStoriesHere &&
                              !hasActiveCheckinHere &&
                              !_isAnonymous)
                            _buildFirstStoryCta(),
                          StoryTray(
                            key: ValueKey(
                              '${_resolvedVenueIdForCurrentDetail!}_$_storyTrayRefreshCount',
                            ),
                            venueId: _resolvedVenueIdForCurrentDetail!,
                            isUploading: _storyUploading,
                            onAddStory: hasActiveCheckinHere
                                ? _openAddStory
                                : null,
                            anonymousLocked: _isAnonymous,
                            onMyStoryStateChanged: (hasMine) {
                              if (mounted &&
                                  (hasMine != _hasMyStoryHere ||
                                      !_storyStateKnown)) {
                                setState(() {
                                  _hasMyStoryHere = hasMine;
                                  _storyStateKnown = true;
                                });
                              }
                            },
                            onStoriesEmptyChanged: (isEmpty) {
                              if (mounted && isEmpty != _noStoriesHere) {
                                setState(() => _noStoriesHere = isEmpty);
                              }
                            },
                          ),
                        ],

                        /// ABOUT
                        if (_enrichedVenueData?['description'] != null &&
                            (_enrichedVenueData!['description'] as String)
                                .isNotEmpty) ...[
                          const SizedBox(height: 18),
                          _buildDescriptionSection(
                            _enrichedVenueData!['description'] as String,
                          ),
                        ],

                        /// PHOTOS & VIDEOS (galeri — boşsa başlıkla birlikte gizlenir)
                        if (widget.venue.isInDb &&
                            widget.venue.id.isNotEmpty) ...[
                          if (_galleryCount > 0) ...[
                            const SizedBox(height: 18),
                            _sectionTitle(
                              AppColors.teal,
                              'Photos & Videos',
                              trailing: Text(
                                '$_galleryCount',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.teal,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          VenueGalleryStrip(
                            venueId: widget.venue.id,
                            onCountChanged: (count) {
                              if (mounted && count != _galleryCount) {
                                setState(() => _galleryCount = count);
                              }
                            },
                          ),
                        ],

                        /// UPCOMING EVENTS
                        if (_enrichedVenueData?['upcomingEvents'] is List &&
                            (_enrichedVenueData!['upcomingEvents'] as List)
                                .isNotEmpty) ...[
                          const SizedBox(height: 18),
                          _buildUpcomingEventsSection(
                            (_enrichedVenueData!['upcomingEvents'] as List)
                                .whereType<Map>()
                                .map(
                                  (e) => VenueUpcomingEvent.fromJson(
                                    Map<String, dynamic>.from(e),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Floating back button — cover üzerinde her zaman görünür ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 6,
            left: 12,
            child: AppBackButton.onCover(onTap: () => Navigator.pop(context)),
          ),
        ], // Stack children
      ), // Stack
    );
  }
}

// ─── Venue detail header avatar with story ring (stateless — state lives in parent) ───

class _VenueDetailAvatarRing extends StatelessWidget {
  final String photoUrl;
  final bool hasStories;
  final bool allSeen;
  final VoidCallback? onTap;

  static const _logoColors = [
    AppColors.magenta,
    AppColors.teal,
    AppColors.blue,
    AppColors.orange,
    AppColors.brand,
  ];

  const _VenueDetailAvatarRing({
    required this.photoUrl,
    required this.hasStories,
    required this.allSeen,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const avatarSize = 40.0;
    const ringWidth = 3.0;
    const gap = 2.5;
    const totalSize = avatarSize + (ringWidth + gap) * 2;

    final photo = _safeVenueDetailPhotoUrl(photoUrl);

    final avatar = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedImage(
        photo,
        width: avatarSize,
        height: avatarSize,
        fit: BoxFit.cover,
      ),
    );

    if (!hasStories) return avatar;

    final ringColors = allSeen
        ? [Colors.grey.shade400, Colors.grey.shade500]
        : _logoColors;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: totalSize,
        height: totalSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: ringWidth + gap,
              top: ringWidth + gap,
              child: avatar,
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _DetailRingPainter(
                  colors: ringColors,
                  strokeWidth: ringWidth,
                  radius: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRingPainter extends CustomPainter {
  final List<Color> colors;
  final double strokeWidth;
  final double radius;

  const _DetailRingPainter({
    required this.colors,
    required this.strokeWidth,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(strokeWidth / 2),
      Radius.circular(radius),
    );
    // Arkada ince kontrast halka → gradient halka fotoğraf/açık zeminde de
    // kaybolmadan belirgin dursun.
    final backing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + 1.5
      ..color = Colors.black.withValues(alpha: 0.25);
    canvas.drawRRect(rrect, backing);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = SweepGradient(
        colors: [...colors, colors.first],
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _DetailRingPainter old) =>
      old.colors != colors || old.strokeWidth != strokeWidth;
}

String _safeVenueDetailPhotoUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    return 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4';
  }
  return trimmed;
}
