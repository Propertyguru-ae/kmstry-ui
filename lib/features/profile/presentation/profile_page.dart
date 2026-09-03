import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/media/text_overlay_composer.dart';
import 'dart:async';
import 'dart:ui'; // Glassmorphism efekti için
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import '../../auth/data/auth_repository.dart';
import '../../checkin/data/checkin_repository.dart';
import '../../checkin/services/active_checkin_service.dart';
import '../../checkin/services/quick_checkin_launcher.dart';
import 'package:kmstry_frontend/core/layout/app_shell.dart';
import 'package:kmstry_frontend/features/venue/presentation/moments_viewer_page.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_detail_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/followed_venues_page.dart';
import 'dart:io';
import '../../checkin/data/checkin_profile_model.dart';
import 'package:kmstry_frontend/features/camera/presentation/camera_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:kmstry_frontend/features/profile/presentation/profile_settings_page.dart';
import 'package:kmstry_frontend/features/profile/presentation/edit_profile_page.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';
import 'package:kmstry_frontend/features/people/presentation/friends_list_page.dart';
import 'package:kmstry_frontend/features/profile/presentation/settings_page.dart';
import 'package:kmstry_frontend/core/permissions/notification_permission_service.dart';
import 'package:kmstry_frontend/core/push/push_manager.dart';
import 'package:kmstry_frontend/core/checkin/checkin_ping_manager.dart';
import 'package:kmstry_frontend/core/user/user_session.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/ui/destructive_confirmation_dialog.dart';
import 'package:kmstry_frontend/core/ui/app_logo.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_context_onboarding_page.dart';
import 'package:kmstry_frontend/features/stories/data/story_model.dart';
import 'package:kmstry_frontend/features/stories/data/story_repository.dart';
import 'package:kmstry_frontend/features/stories/data/story_viewed_cache.dart';
import 'package:kmstry_frontend/features/stories/presentation/story_viewer_page.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  // Story yüklenirken avatar halkası döner (venue detay/home ile aynı efekt).
  late final AnimationController _storySpin;
  Map<String, dynamic>? _user;
  MeContextModel? _meContext;
  bool _loading = true;
  Map<String, dynamic>? _activeCheckin;
  List<CheckinProfileMedia> _media = [];
  List<CheckinVisitedPlace> _visitedPlaces = [];

  final CheckinRepository _checkinRepo = CheckinRepository();
  final VenueContextRepository _venueContextRepository =
      VenueContextRepository();
  final MatchRepository _matchRepo = MatchRepository();
  final StoryRepository _storyRepo = StoryRepository();

  /// Friends (match) sayısı — null iken "—" gösterilir.
  int? _friendCount;
  int? _followedVenueCount;

  /// Aktif check-in'in mekânı (header'daki lokasyon satırı için).
  Venue? _activeVenue;

  String? _checkinVibe;

  /// Sunucudaki kalıcı bio; check-in vibe boşsa gösterim için kullanılır.
  String? _profileBio;
  String? _activeCheckinVenueIdFromProfile;
  List<String> _checkinWhatBrings = [];

  /// "What brings you to Kmstry" seçenekleri (edit sheet için) — lazy yüklenir.
  List<String> _whatBringsOptions = [];
  bool _savingWhatBrings = false;

  bool _isExpanded = false;
  bool _areMomentsExpanded = false;
  int _selectedProfileTab = 0;

  bool _uploadingMoment = false;
  bool _uploadingStory = false;
  bool _openingStory = false; // kamera açılışı sırasında çift-tıklama guard'ı
  bool _isAnonymous = false; // profil yüklemesinden cache'lenir → anında kamera
  bool _openingVenueDetail = false;
  final Set<String> _updatingProfileVisibilityIds = {};
  final Set<String> _deletingVisitedPlaceIds = {};
  List<StoryItem> _myStories = [];
  Set<String> _viewedStoryIds = {};
  final TextEditingController _vibeController = TextEditingController();
  bool _savingVibe = false;
  String? _profileErrorMessage;
  final NotificationPermissionService _notificationPermissionService =
      NotificationPermissionService();
  bool _showNotificationWarning = false;
  final Map<String, String?> _videoPosterPathByUrl = {};
  final Map<String, Future<String?>> _videoPosterFutureByUrl = {};
  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<String?> _getVideoPoster(String url) {
    final cachedPath = _videoPosterPathByUrl[url];
    if (cachedPath != null && cachedPath.isNotEmpty) {
      return Future.value(cachedPath);
    }
    final pending = _videoPosterFutureByUrl[url];
    if (pending != null) return pending;

    final future = _generateVideoPoster(url);
    _videoPosterFutureByUrl[url] = future;
    return future;
  }

  Future<String?> _generateVideoPoster(String url) async {
    try {
      final path = await VideoThumbnail.thumbnailFile(
        video: url,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 420,
        quality: 72,
      );
      _videoPosterPathByUrl[url] = path;
      return path;
    } catch (_) {
      _videoPosterPathByUrl[url] = null;
      return null;
    } finally {
      _videoPosterFutureByUrl.remove(url);
    }
  }

  Widget _buildVideoPosterLayer(
    CheckinProfileMedia media, {
    required BoxFit fit,
    double? width,
    double? height,
  }) {
    final thumbnail = media.thumbnailUrl;
    final hasThumbnail = thumbnail != null && thumbnail.isNotEmpty;
    if (hasThumbnail) {
      return CachedImage(
        thumbnail,
        width: width,
        height: height,
        fit: fit,
        errorWidget: (context) => Container(color: Colors.black87),
      );
    }

    return FutureBuilder<String?>(
      future: _getVideoPoster(media.url),
      builder: (context, snapshot) {
        final posterPath = snapshot.data;
        if (posterPath != null && posterPath.isNotEmpty) {
          return Image.file(
            File(posterPath),
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (context, error, stackTrace) =>
                Container(color: Colors.black87),
          );
        }
        return Container(color: Colors.black87);
      },
    );
  }

  bool _isVideoFile(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.3gp') ||
        lower.endsWith('.mkv');
  }

  Future<bool> _ensureCameraPermission() async {
    final camera = await Permission.camera.request();
    return camera.isGranted;
  }

  Widget _buildMediaThumb(CheckinProfileMedia media) {
    const thumbWidth = 85.0;
    const thumbHeight = 110.0;

    if (media.mediaType == MediaType.video) {
      return SizedBox(
        width: thumbWidth,
        height: thumbHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildVideoPosterLayer(media, fit: BoxFit.cover),

            /// Play icon
            const Center(
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white,
                size: 32,
              ),
            ),

            /// Duration badge
            if (media.durationSeconds != null)
              Positioned(
                bottom: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _formatDuration(media.durationSeconds!),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    if (media.mediaType == MediaType.photo) {
      return SizedBox(
        width: thumbWidth,
        height: thumbHeight,
        child: CachedImage(media.url, fit: BoxFit.cover),
      );
    }

    return const SizedBox(width: thumbWidth, height: thumbHeight);
  }

  Widget _buildVideoCover({
    required CheckinProfileMedia media,
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
    double iconSize = 52,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildVideoPosterLayer(media, fit: fit, width: width, height: height),
        Center(
          child: Icon(
            Icons.play_circle_fill,
            color: Colors.white,
            size: iconSize,
          ),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _storySpin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    // AuthGate/AppShell may have just fetched /me during login/account switch.
    // Profile should still render from the latest account snapshot on first open.
    _loadProfile(forceRefresh: true);
    _refreshNotificationWarningState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _storySpin.dispose();
    _vibeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshNotificationWarningState();
    }
  }

  /// Aktif check-in'in "yıldızlanan" (featured) fotoğrafının URL'i — varsa
  /// avatarda gösterilir. Aktif check-in yoksa veya featured fotoğraf yoksa
  /// null döner (o zaman gerçek profil fotosu / boş kullanılır).
  String? get _featuredCheckinPhotoUrl {
    if (_activeCheckin == null) return null;
    for (final m in _media) {
      if (m.isFeatured && m.mediaType == MediaType.photo && m.url.isNotEmpty) {
        return m.url;
      }
    }
    return null;
  }

  String? get _activeCheckinAvatarPhotoUrl {
    final raw =
        (_activeCheckin?['avatarPhoto'] ?? _activeCheckin?['avatar_photo'])
            ?.toString()
            .trim();
    return raw != null && raw.isNotEmpty && raw.toLowerCase() != 'null'
        ? raw
        : null;
  }

  List<String> _extractWhatBrings(Map<String, dynamic>? activeCheckin) {
    if (activeCheckin == null) return const [];
    final raw =
        activeCheckin['what_brings_to_kmstry'] ??
        activeCheckin['whatBringsToKmstry'];
    if (raw is! List) return const [];
    return raw
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  Map<String, dynamic>? _extractActiveCheckin(Map<String, dynamic> me) {
    final raw = me['activeCheckin'] ?? me['active_checkin'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  String? _activeCheckinId() {
    final value = _activeCheckin?['id'];
    final id = value?.toString().trim();
    if (id == null || id.isEmpty) return null;
    return id;
  }

  String _formatWhatBringsLabel(String raw) {
    final normalized = raw
        .toLowerCase()
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
    if (normalized.isEmpty) return raw;
    return normalized;
  }

  String? _extractActiveCheckinVenueId(Map<String, dynamic>? activeCheckin) {
    if (activeCheckin == null) return null;
    final direct = activeCheckin['venueId'] ?? activeCheckin['venue_id'];
    final directId = direct?.toString().trim();
    if (directId != null && directId.isNotEmpty) return directId;
    final nested = activeCheckin['venue'];
    if (nested is Map) {
      final nestedId = nested['id'] ?? nested['venueId'] ?? nested['venue_id'];
      final value = nestedId?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  Venue? _venueFromActiveCheckin(Map<String, dynamic>? activeCheckin) {
    if (activeCheckin == null) return null;
    final nested = activeCheckin['venue'];
    if (nested is! Map) return null;
    final map = Map<String, dynamic>.from(nested);
    final venueId = _extractActiveCheckinVenueId(activeCheckin);
    if ((map['id'] == null || map['id'].toString().isEmpty) &&
        venueId != null &&
        venueId.isNotEmpty) {
      map['id'] = venueId;
    }
    if ((map['source'] == null || map['source'].toString().isEmpty)) {
      map['source'] = 'db';
    }
    if ((map['isInDb'] == null) && (map['is_in_db'] == null)) {
      map['isInDb'] = true;
    }
    if ((map['canCheckin'] == null) && (map['can_checkin'] == null)) {
      map['canCheckin'] = true;
    }
    final parsed = Venue.fromJson(map);
    if (parsed.id.isEmpty) return null;
    return parsed;
  }

  Future<String?> _resolveActiveCheckinVenueId() async {
    final fromPayload = _extractActiveCheckinVenueId(_activeCheckin);
    if (fromPayload != null && fromPayload.isNotEmpty) return fromPayload;

    final fromProfile = _activeCheckinVenueIdFromProfile?.trim();
    if (fromProfile != null && fromProfile.isNotEmpty) return fromProfile;

    final checkinId = _activeCheckinId();
    if (checkinId == null) return null;

    try {
      final profile = await _checkinRepo.getCheckinProfile(checkinId);
      final venueId = profile.checkin.venueId?.trim();
      if (venueId == null || venueId.isEmpty) return null;
      if (mounted) {
        setState(() => _activeCheckinVenueIdFromProfile = venueId);
      }
      return venueId;
    } catch (_) {
      return null;
    }
  }

  Future<Venue?> _loadActiveCheckinVenue() async {
    final fromPayload = _venueFromActiveCheckin(_activeCheckin);
    if (fromPayload != null) return fromPayload;
    final venueId = await _resolveActiveCheckinVenueId();
    if (venueId == null || venueId.isEmpty) return null;
    try {
      final venueData = await _venueContextRepository.getVenueById(venueId);
      final map = Map<String, dynamic>.from(venueData);
      if ((map['id'] == null || map['id'].toString().isEmpty)) {
        map['id'] = venueId;
      }
      if ((map['source'] == null || map['source'].toString().isEmpty)) {
        map['source'] = 'db';
      }
      if ((map['isInDb'] == null) && (map['is_in_db'] == null)) {
        map['isInDb'] = true;
      }
      if ((map['canCheckin'] == null) && (map['can_checkin'] == null)) {
        map['canCheckin'] = true;
      }
      final parsed = Venue.fromJson(map);
      if (parsed.id.isEmpty) return null;
      return parsed;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadActiveVenueForHeader() async {
    final venue = await _loadActiveCheckinVenue();
    if (!mounted || venue == null) return;
    setState(() => _activeVenue = venue);
  }

  Future<void> _openActiveVenueDetail() async {
    if (_openingVenueDetail || _activeCheckin == null) return;
    setState(() => _openingVenueDetail = true);
    try {
      final venue = await _loadActiveCheckinVenue();
      if (!mounted) return;
      if (venue == null) {
        await showPremiumErrorDialog(
          context,
          message: 'Active check-in venue could not be loaded.',
        );
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VenueDetailPage(venue: venue)),
      );
      if (mounted) unawaited(_loadMyStories());
    } finally {
      if (mounted) {
        setState(() => _openingVenueDetail = false);
      }
    }
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

  Future<void> _refreshNotificationWarningState() async {
    try {
      final permissionState = await _notificationPermissionService
          .readStateFromBackend();
      // If user enabled system notifications from Settings, sync account preference.
      if (permissionState.systemGranted && !permissionState.accountPreference) {
        await AuthRepository().updatePermissions({
          'notificationPermissionGranted': true,
        });
        await PushManager.instance.reconcileNotificationState();
      }
      final refreshedState = await _notificationPermissionService
          .readStateFromBackend();
      if (!mounted) return;
      setState(() {
        _showNotificationWarning = !refreshedState.effectiveStatus;
      });
    } catch (_) {}
  }

  Future<void> _enableNotificationsFromProfile() async {
    final status = await Permission.notification.status;
    final systemGranted =
        status.isGranted || status == PermissionStatus.provisional;
    if (!systemGranted) {
      final granted = await PushManager.instance.handlePermissionFlow();
      if (granted) {
        await _refreshNotificationWarningState();
        return;
      }
      await openAppSettings();
      return;
    }

    try {
      await AuthRepository().updatePermissions({
        'notificationPermissionGranted': true,
      });
    } catch (_) {}
    await PushManager.instance.reconcileNotificationState();
    await _refreshNotificationWarningState();
  }

  Future<void> _loadFriendCount() async {
    try {
      final matches = await _matchRepo.getMatches();
      if (!mounted) return;
      setState(() => _friendCount = matches.length);
    } catch (_) {
      // Sessiz geç — istatistik "—" kalır.
    }
  }

  Future<void> _loadFollowedVenueCount() async {
    try {
      final venues = await _venueContextRepository.getFollowedVenues();
      if (!mounted) return;
      setState(() => _followedVenueCount = venues.length);
    } catch (_) {
      // Sessiz geç — istatistik "—" kalır.
    }
  }

  Future<void> _loadMyStories() async {
    try {
      final stories = await _storyRepo.getMyStories();
      // İzlenme durumu KALICI cache'ten yüklenir — aksi halde başka sayfaya
      // geçip profile dönünce _viewedStoryIds sıfırlanıp halka tekrar renkli
      // görünüyordu (izlenmiş olmasına rağmen).
      final persistedViewed = await StoryViewedCache.loadAll();
      if (!mounted) return;
      setState(() {
        _myStories = stories;
        final activeIds = stories.map((s) => s.id).toSet();
        _viewedStoryIds = {
          ..._viewedStoryIds,
          ...persistedViewed,
        }.intersection(activeIds);
      });
    } catch (e) {
      debugPrint('Profile stories fetch failed: $e');
    }
  }

  int _firstUnseenStoryIndex() {
    final index = _myStories.indexWhere(
      (story) => !story.viewedByMe && !_viewedStoryIds.contains(story.id),
    );
    return index == -1 ? 0 : index;
  }

  bool get _hasUnseenProfileStories => _myStories.any(
    (story) => !story.viewedByMe && !_viewedStoryIds.contains(story.id),
  );

  Future<void> _openMyStoryViewer(String photo) async {
    final realStories = _myStories
        .where((story) => !story.isUploadingPlaceholder)
        .toList();
    if (realStories.isEmpty) return;

    final meGroup = StoryGroup(
      user: StoryUser(id: 'me', fullName: 'Me', photo: photo),
      stories: realStories,
      isCurrentUserOwner: true,
    );

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StoryViewerPage(
          groups: [meGroup],
          initialStoryIndex: _firstUnseenStoryIndex(),
        ),
      ),
    );

    if (!mounted) return;
    if (result is StoryViewerResult && result.lastStoryIndex >= 0) {
      final ids = result.allFinished
          ? realStories.map((s) => s.id)
          : [
              for (
                int i = 0;
                i <= result.lastStoryIndex && i < realStories.length;
                i++
              )
                realStories[i].id,
            ];
      setState(() => _viewedStoryIds = {..._viewedStoryIds, ...ids});
    }
    unawaited(_loadMyStories());
  }

  Future<void> _openAddStoryFromProfile() async {
    final checkinId = _activeCheckinId();
    if (checkinId == null || _uploadingStory || _openingStory) return;

    // Anonim kontrolünü cache'lenmiş bayrakla anında yap — ağ çağrısı
    // beklemeden kamera açılsın.
    if (_isAnonymous) {
      _showAnonymousStoryBlockedDialog();
      return;
    }

    _openingStory = true;
    final dynamic captureResult;
    try {
      captureResult = await Navigator.push(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => const CameraScreen(useFrontCamera: true),
        ),
      );
    } finally {
      _openingStory = false;
    }

    final File? file = captureResult is CapturedMedia
        ? captureResult.file
        : captureResult as File?;
    final storyOverlay = captureResult is CapturedMedia
        ? captureResult.overlay
        : null;
    if (file == null || !mounted) return;

    final isVideo = _isVideoFile(file.path);
    final overlay = Overlay.maybeOf(context, rootOverlay: true);

    setState(() => _uploadingStory = true);
    _storySpin.repeat();
    try {
      await _storyRepo.createStory(
        checkinId: checkinId,
        file: file,
        mediaType: isVideo ? 'video' : 'photo',
        textOverlayJson: storyOverlay?.toJsonString(),
      );

      if (mounted) {
        await _loadMyStories();
      }

      final venueName = (_activeVenue?.name.trim().isNotEmpty ?? false)
          ? _activeVenue!.name
          : 'your venue';
      if (overlay != null) {
        showStorySharedCard(
          overlay,
          mediaFile: file,
          venueName: venueName,
          isVideo: isVideo,
        );
      }
    } catch (e, st) {
      debugPrint('❌ Profile story upload error: $e\n$st');
      if (!mounted) return;
      await showPremiumErrorDialog(context, message: 'Upload failed: $e');
    } finally {
      _storySpin.stop();
      _storySpin.value = 0;
      if (mounted) setState(() => _uploadingStory = false);
    }
  }

  Future<void> _loadProfile({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _profileErrorMessage = null;
    });
    // İstatistikleri arka planda çek — profil yüklemesini bloklamasın.
    unawaited(_loadFriendCount());
    unawaited(_loadFollowedVenueCount());
    unawaited(_loadMyStories());

    try {
      final me = await AuthRepository().getMe(forceRefresh: forceRefresh);
      _isAnonymous = me['isAnonymous'] == true;

      List<CheckinProfileMedia> media = [];
      List<CheckinVisitedPlace> visitedPlaces = [];

      String? checkinVibe;
      String? activeCheckinVenueId;
      // 1) Aktif check-in varsa getProfile(checkinId) ile o check-in'in fotoğraflarını al (backend getProfile)
      final activeCheckin = _extractActiveCheckin(me);
      activeCheckinVenueId = _extractActiveCheckinVenueId(activeCheckin);
      final checkinId = activeCheckin?['id']?.toString();
      if (checkinId != null && checkinId.isNotEmpty) {
        try {
          final profile = await _checkinRepo.getCheckinProfile(checkinId);
          checkinVibe = profile.checkin.vibe ?? '';
          final profileVenueId = profile.checkin.venueId?.trim();
          if (profileVenueId != null && profileVenueId.isNotEmpty) {
            activeCheckinVenueId = profileVenueId;
          }
          if (profile.media.isNotEmpty) {
            media = profile.media;
          }
          visitedPlaces = profile.visitedPlaces;
        } catch (e) {
          debugPrint('Profile checkin fetch failed: $e');
          _profileErrorMessage =
              'Moments could not be loaded. Pull to refresh or try again.';
        }
      }

      final currentUserId = me['id']?.toString();
      if (currentUserId != null && currentUserId.isNotEmpty) {
        try {
          final myHistory = await _checkinRepo.getMyProfileHistory();
          if (myHistory.isNotEmpty || visitedPlaces.isEmpty) {
            visitedPlaces = myHistory;
          }
        } catch (e) {
          debugPrint('Profile visited places fetch failed: $e');
        }
      }

      if (!mounted) return;
      final bioRaw = (me['bio'] ?? me['bio_text'])?.toString().trim();
      setState(() {
        _user = me;
        _meContext = MeContextModel.fromMe(me);
        _profileBio = (bioRaw != null && bioRaw.isNotEmpty) ? bioRaw : null;
        _activeCheckin = activeCheckin;
        _activeCheckinVenueIdFromProfile = activeCheckinVenueId;
        _checkinWhatBrings = _extractWhatBrings(activeCheckin);
        _checkinVibe = checkinVibe;
        _media = media;
        _visitedPlaces = visitedPlaces;
        _activeVenue = _venueFromActiveCheckin(activeCheckin);
        _loading = false;
      });
      // Uygulama geneline aktif check-in'i senkronla — venue detay sayfası
      // ("Who's here?" vs "Check in") ve ping yöneticisi bunu okur. Taze
      // login/uygulama açılışında ActiveCheckinService boş olabiliyor.
      final activeCheckinId = activeCheckin?['id']?.toString();
      if (activeCheckin != null &&
          activeCheckinId != null &&
          activeCheckinId.isNotEmpty) {
        ActiveCheckinService().setActiveCheckin(
          activeCheckinId,
          venueId: activeCheckinVenueId,
          userId: currentUserId,
        );
      } else {
        ActiveCheckinService().clear();
      }

      // Payload'da venue yoksa arka planda id ile çekip header'ı güncelle.
      if (activeCheckin != null && _activeVenue == null) {
        unawaited(_loadActiveVenueForHeader());
      }
    } catch (e) {
      debugPrint('Profile load failed: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _profileErrorMessage =
            'Profile data could not be loaded. Please retry.';
      });
    }
  }

  bool _checkTextOverflow(String text, double maxWidth, TextStyle style) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 2,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

    return textPainter.didExceedMaxLines;
  }

  Future<void> _addMomentPhoto() async {
    if (_activeCheckin == null) {
      if (!mounted) return;
      await showPremiumErrorDialog(
        context,
        message: 'To add moments, you need an active check-in first.',
      );
      return;
    }
    final checkinId = _activeCheckinId();
    if (checkinId == null) {
      if (!mounted) return;
      await showPremiumErrorDialog(
        context,
        message: 'Active check-in data is missing.',
      );
      return;
    }

    try {
      final hasPermission = await _ensureCameraPermission();
      if (!hasPermission) {
        if (!mounted) return;
        await showPremiumErrorDialog(
          context,
          message: 'Camera permission is required.',
        );
        return;
      }

      if (!mounted) return;
      final navigator = Navigator.of(this.context);
      // 🔥 Kendi kamera ekranımızı açıyoruz
      // Video akışı CapturedMedia (dosya + text overlay) dönebilir.
      final dynamic captureResult = await navigator.push(
        MaterialPageRoute(
          builder: (_) => const CameraScreen(
            useFrontCamera: true, // selfie
            optimizeForUpload: true,
          ),
        ),
      );

      if (!mounted) return;
      final File? capturedMedia = captureResult is CapturedMedia
          ? captureResult.file
          : captureResult as File?;
      final capturedOverlay = captureResult is CapturedMedia
          ? captureResult.overlay
          : null;
      if (capturedMedia == null) return;

      // Check-in aninda tek video kurali profile'a da uygulaniyor.
      if (_isVideoFile(capturedMedia.path) &&
          _media.any((m) => m.mediaType == MediaType.video)) {
        if (!mounted) return;
        await showPremiumErrorDialog(
          this.context,
          message: 'You can upload only 1 video.',
        );
        return;
      }

      setState(() => _uploadingMoment = true);

      await _checkinRepo.uploadCheckinMedia(
        checkinId: checkinId,
        file: capturedMedia,
        textOverlayJson: capturedOverlay?.toJsonString(),
        isFeatured: false,
      );

      await _loadProfile();
    } catch (e) {
      final raw = e.toString();
      if (raw.contains('Media upload failed (413)') ||
          raw.contains('413 Request Entity Too Large')) {
        if (!mounted) return;
        await showPremiumErrorDialog(
          this.context,
          message:
              'Video boyutu sunucu limitini asiyor. Lutfen daha kisa bir video cekin.',
        );
        return;
      }
      final clean = raw
          .replaceAll(RegExp(r'^Exception:\s*'), '')
          .replaceAll(RegExp(r'^Media upload failed \(\d+\):\s*'), '')
          .trim();
      if (!mounted) return;
      await showPremiumErrorDialog(
        this.context,
        message: clean.isEmpty
            ? 'Video could not be uploaded. Please try again.'
            : clean,
      );
    } finally {
      if (mounted) {
        setState(() => _uploadingMoment = false);
      }
    }
  }

  /// Merkezi bio/vibe metni: check-in varken önce vibe, yoksa profil bio’su.
  String _centralBioVibeTextForEdit() {
    final vibeTrim = (_checkinVibe ?? '').trim();
    final bioTrim = (_profileBio ?? '').trim();
    if (_activeCheckin != null) {
      return vibeTrim.isNotEmpty ? vibeTrim : bioTrim;
    }
    return bioTrim;
  }

  Future<void> _openEditVibeModal() async {
    _vibeController.text = _centralBioVibeTextForEdit();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF121925).withValues(alpha: 0.92)
                      : colors.surface.withValues(alpha: 0.94),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : colors.onSurface.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Edit bio',
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: _vibeController,
                      maxLength: 150,
                      maxLines: 4,
                      style: TextStyle(color: colors.onSurface),
                      decoration: InputDecoration(
                        hintText:
                            'What others see on your profile and when you check in.',
                        hintStyle: TextStyle(
                          color: colors.onSurface.withValues(alpha: 0.55),
                        ),
                        filled: true,
                        fillColor: isDark
                            ? Colors.white.withValues(alpha: 0.04)
                            : colors.surfaceContainerHighest.withValues(
                                alpha: 0.45,
                              ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _savingVibe ? null : _saveVibe,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.primary,
                          foregroundColor: colors.onPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _savingVibe
                            ? SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.onPrimary,
                                ),
                              )
                            : const Text("Save"),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveVibe() async {
    final checkinId = _activeCheckinId();

    setState(() => _savingVibe = true);

    try {
      final next = _vibeController.text.trim();
      if (checkinId != null) {
        await _checkinRepo.updateVibe(checkinId: checkinId, vibe: next);
      }
      await AuthRepository().updateMe({'bio': next});

      if (!mounted) return;

      setState(() {
        if (checkinId != null) {
          _checkinVibe = next;
        }
        _profileBio = next.isEmpty ? null : next;
        _user?['bio'] = next;
      });

      Navigator.pop(context); // modal kapanır
    } catch (e) {
      await showPremiumErrorDialog(context, message: 'Failed to update bio');
    }

    if (mounted) setState(() => _savingVibe = false);
  }

  /// Profilden "What brings you to Kmstry" seçimlerini düzenleme sheet'i.
  /// Aktif check-in'in tag'lerini yeniden seçip kaydeder (max 3).
  Future<void> _openEditWhatBrings() async {
    final checkinId = _activeCheckinId();
    if (checkinId == null) return;

    // Seçenekleri lazy yükle.
    if (_whatBringsOptions.isEmpty) {
      try {
        final options = await _checkinRepo.getWhatBringsOptions();
        if (mounted) setState(() => _whatBringsOptions = options);
      } catch (_) {}
    }
    if (!mounted) return;

    final selected = <String>{..._checkinWhatBrings};

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final colors = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        const lightCardFill = Color(0xFFF8FBFD);
        const lightCardBorder = Color(0xFFE6EEF4);

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 10,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "What brings you to Kmstry?",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: _whatBringsOptions.map((option) {
                        final isSel = selected.contains(option);
                        return GestureDetector(
                          onTap: () {
                            setModalState(() {
                              if (isSel) {
                                selected.remove(option);
                              } else {
                                selected.add(option);
                              }
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? AppTheme.brandPrimary.withValues(
                                      alpha: 0.12,
                                    )
                                  : (isDark ? colors.surface : lightCardFill),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSel
                                    ? AppTheme.brandPrimary
                                    : (isDark
                                          ? colors.onSurface.withValues(
                                              alpha: 0.1,
                                            )
                                          : lightCardBorder),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatWhatBringsLabel(option),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: colors.onSurface,
                                  ),
                                ),
                                if (isSel)
                                  const Icon(
                                    Icons.check_circle,
                                    color: AppTheme.brandPrimary,
                                  ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _savingWhatBrings
                          ? null
                          : () async {
                              await _saveWhatBrings(
                                checkinId,
                                selected.toList(),
                                sheetContext,
                              );
                            },
                      child: _savingWhatBrings
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveWhatBrings(
    String checkinId,
    List<String> values,
    BuildContext sheetContext,
  ) async {
    setState(() => _savingWhatBrings = true);
    try {
      final saved = await _checkinRepo.updateWhatBrings(
        checkinId: checkinId,
        values: values,
      );
      if (!mounted) return;
      setState(() => _checkinWhatBrings = saved);
      if (sheetContext.mounted) Navigator.pop(sheetContext);
    } catch (_) {
      if (mounted) {
        await showPremiumErrorDialog(
          context,
          message: 'Failed to update your selections',
        );
      }
    } finally {
      if (mounted) setState(() => _savingWhatBrings = false);
    }
  }

  String get _usernameLabel {
    final username =
        (_user?['username'] ?? _user?['user_name'])?.toString().trim() ?? '';
    if (username.isNotEmpty) return '@${username.toLowerCase()}';
    return _user?['fullName'] ?? '';
  }

  bool get _hasMultipleAccounts {
    final ctx = _meContext;
    if (ctx == null) return false;
    final venueCount = ctx.memberVenues.where((v) => v.isActive).length;
    return (ctx.hasPersonalProfile ? 1 : 0) + venueCount > 1;
  }

  Widget _buildAppBarTitle(ThemeData theme, bool isDark) {
    return GestureDetector(
      onTap: () => _showAccountPicker(context),
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _usernameLabel,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 22,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ],
      ),
    );
  }

  void _showAccountPicker(BuildContext context) {
    final meCtx = _meContext;
    if (meCtx == null) return;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accountVenues = meCtx.memberVenues
        .where((v) => v.isActive || v.isPendingOwnerClaim)
        .toList();
    final isPersonalActive =
        !(meCtx.lastActiveContext?.toUpperCase().contains('VENUE') ?? false);

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 16, bottom: 8),
              decoration: BoxDecoration(
                color: colors.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Hesap listesi — 3'ten fazlası scroll edilebilir
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(sheetCtx).size.height * 0.35,
              ),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  // Personal account
                  if (meCtx.hasPersonalProfile)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: colors.primary.withValues(alpha: 0.12),
                        child: Icon(
                          Icons.person_outline,
                          color: colors.primary,
                        ),
                      ),
                      title: Text(
                        _usernameLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                      subtitle: Text(
                        'Personal',
                        style: TextStyle(
                          color: colors.onSurface.withValues(alpha: 0.55),
                          fontSize: 12,
                        ),
                      ),
                      trailing: isPersonalActive
                          ? Icon(Icons.check_circle, color: colors.primary)
                          : null,
                      onTap: isPersonalActive
                          ? null
                          : () async {
                              Navigator.pop(sheetCtx);
                              try {
                                await AuthRepository().switchContext(
                                  lastActiveContext: 'PERSONAL',
                                );
                                if (!context.mounted) return;
                                Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const AppShell(openProfileTab: true),
                                  ),
                                  (r) => false,
                                );
                              } catch (_) {}
                            },
                    ),
                  // Venue accounts
                  ...accountVenues.map((venue) {
                    final isActive =
                        !isPersonalActive && (meCtx.activeVenueId == venue.id);
                    final isPending = venue.isPendingOwnerClaim;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isPending
                            ? colors.onSurface.withValues(alpha: 0.08)
                            : colors.primary.withValues(alpha: 0.12),
                        child: Icon(
                          isPending
                              ? Icons.hourglass_top_rounded
                              : Icons.storefront,
                          color: isPending
                              ? colors.onSurface.withValues(alpha: 0.45)
                              : colors.primary,
                        ),
                      ),
                      title: Text(
                        venue.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                      subtitle: Text(
                        isPending ? 'Pending review' : (venue.role ?? 'Venue'),
                        style: TextStyle(
                          color: colors.onSurface.withValues(alpha: 0.55),
                          fontSize: 12,
                        ),
                      ),
                      trailing: isPending
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Pending',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.orange,
                                ),
                              ),
                            )
                          : isActive
                          ? Icon(Icons.check_circle, color: colors.primary)
                          : null,
                      onTap: isActive
                          ? null
                          : () {
                              // Smooth in-place switch → lands on the venue's
                              // Profile tab (no full shell rebuild).
                              Navigator.pop(sheetCtx);
                              AppShellNav.of(
                                context,
                              )?.switchToVenueProfile(venue);
                            },
                    );
                  }),
                ],
              ),
            ),
            const Divider(height: 1),
            // Add Venue Account
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.add, color: colors.primary, size: 22),
              ),
              title: Text(
                'Add Venue Account',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const VenueContextOnboardingPage(fromAppShell: true),
                  ),
                );
              },
            ),
            // Go to Accounts Center
            ListTile(
              leading: Icon(
                Icons.manage_accounts_outlined,
                color: colors.onSurface,
              ),
              title: Text(
                'Go to Accounts Center',
                style: TextStyle(color: colors.onSurface),
              ),
              onTap: () {
                Navigator.pop(sheetCtx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPage()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.logout, color: colors.error),
              title: Text(
                'Log out',
                style: TextStyle(
                  color: colors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () async {
                final rootContext = context;
                Navigator.pop(sheetCtx);
                await _logout(rootContext);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
    if (mounted) await _loadProfile();
  }

  Future<void> _logout(BuildContext context) async {
    try {
      CheckinPingManager.I.stop();
      ActiveCheckinService().clear();
      UserSession.instance.clear();
      await AuthRepository().logout();
      if (!context.mounted) return;

      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AuthRoutes.login, (route) => false);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_loading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        ),
      );
    }

    // Aktif check-in varsa "yıldızlanan" (featured) check-in fotoğrafı avatara
    // konur — kullanıcının o mekandaki temsili. Check-in expire olunca
    // (_activeCheckin null, _media boş) otomatik gerçek profil fotosuna döner;
    // profil fotosu yoksa boş kalır.
    // Aktif check-in'e özel cropped avatar/featured foto öncelikli. Böylece
    // check-in temsili profil fotoğrafını kalıcı olarak ezmez.
    // Profil fotoğrafı olan kullanıcıda o kalıcı kalır; featured/check-in
    // avatarı yalnızca profil fotoğrafı olmayan kullanıcıda avatara düşer.
    final userPhoto = (_user?['photo'] ?? '').toString().trim();
    final activeAvatar =
        _activeCheckinAvatarPhotoUrl ?? _featuredCheckinPhotoUrl;
    final photo = (userPhoto.isNotEmpty ? userPhoto : (activeAvatar ?? ''))
        .toString();
    final fullName = (_user?['fullName'] ?? _user?['full_name'] ?? '')
        .toString()
        .trim();
    final bio = (_user?['bio'] ?? '').toString().trim();
    final onSurface = isDark ? Colors.white : Colors.black;
    final subColor = isDark ? Colors.white60 : Colors.black54;
    final canAddMore = _activeCheckin != null && _media.length < 6;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        title: _buildAppBarTitle(theme, isDark),
        leading: const AppLogo(),
        actions: [
          IconButton(
            onPressed: _openSettings,
            icon: Icon(Icons.menu, color: isDark ? Colors.white : Colors.black),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.grey[200],
            height: 1,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadProfile(forceRefresh: true),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Ortalanmış avatar + altında istatistikler ───────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Stack(
                  children: [
                    // Sağ üst köşede glass "Edit profile" butonu.
                    Positioned(
                      top: 0,
                      right: 0,
                      child: _GlassEditButton(
                        onTap: _openEditProfile,
                        isDark: isDark,
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildProfileAvatar(photo, isDark),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildStat(
                              _friendCount?.toString() ?? '—',
                              'Friends',
                              onSurface,
                              subColor,
                              inactive: _friendCount == null,
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const FriendsListPage(),
                                  ),
                                );
                                if (mounted) unawaited(_loadFriendCount());
                              },
                            ),
                            const SizedBox(width: 56),
                            _buildStat(
                              _followedVenueCount?.toString() ?? '—',
                              'Venues',
                              onSurface,
                              subColor,
                              inactive: _followedVenueCount == null,
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const FollowedVenuesPage(),
                                  ),
                                );
                                if (mounted) {
                                  unawaited(_loadFollowedVenueCount());
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              // ── İsim + bio + edit ───────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (fullName.isNotEmpty)
                          Flexible(
                            child: Text(
                              fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: onSurface,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (bio.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        bio,
                        style: TextStyle(
                          color: onSurface,
                          fontSize: 14,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // ── Aktif check-in lokasyonu ────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildActiveCheckinRow(isDark, onSurface, subColor),
              ),
              const SizedBox(height: 18),
              // ── Check-in tag'leri (varsa) — grid'in üstünde ─────────────
              if (_activeCheckinId() != null) ...[
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.grey[200]!,
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          'What brings you to KMSTRY?',
                          style: TextStyle(
                            color: onSurface.withValues(alpha: 0.76),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            // "more +" — check-in tag'lerini profilden düzenle.
                            // En başta ki kullanıcı kolayca görüp düzenleyebilsin.
                            GestureDetector(
                              onTap: _openEditWhatBrings,
                              child: Container(
                                margin: const EdgeInsets.only(right: 7),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.06)
                                      : Colors.grey.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: onSurface.withValues(alpha: 0.18),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _checkinWhatBrings.isEmpty
                                          ? 'Add'
                                          : 'more',
                                      style: TextStyle(
                                        color: onSurface.withValues(
                                          alpha: 0.78,
                                        ),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    Icon(
                                      Icons.add_rounded,
                                      size: 15,
                                      color: onSurface.withValues(alpha: 0.78),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            ..._checkinWhatBrings.map((raw) {
                              return Container(
                                margin: const EdgeInsets.only(right: 7),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.brandPrimary.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: AppTheme.brandPrimary.withValues(
                                      alpha: 0.28,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  _formatWhatBringsLabel(raw),
                                  style: TextStyle(
                                    color: onSurface,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              Divider(
                height: 1,
                thickness: 1,
                color: onSurface.withValues(alpha: 0.12),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildProfileContentTabs(onSurface, subColor, isDark),
              ),
              const SizedBox(height: 16),
              if (_selectedProfileTab == 0)
                _buildMomentsGrid(canAddMore, isDark, subColor)
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildVisitedPlacesSection(
                    places: _visitedPlaces,
                    isDark: isDark,
                    subColor: subColor,
                    onSurface: onSurface,
                  ),
                ),
              SizedBox(height: MediaQuery.paddingOf(context).bottom + 92),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileAvatar(String photo, bool isDark) {
    const avatarSize = 132.0;
    const ringWidth = 3.0;
    const gap = 2.5;
    const radius = 32.0;
    final hasStories = _myStories.isNotEmpty;
    // Yükleme sırasında da halka görünür (döner).
    final showRing = hasStories || _uploadingStory;
    final totalSize = showRing
        ? avatarSize + ((ringWidth + gap) * 2)
        : avatarSize;
    final ringColors = (_uploadingStory || _hasUnseenProfileStories)
        ? _ProfileStoryRingPainter.logoColors
        : [Colors.grey.shade400, Colors.grey.shade500];

    final avatar = Container(
      width: avatarSize,
      height: avatarSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: showRing
            ? null
            : Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.grey[300]!,
                width: 1,
              ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: photo.isNotEmpty
            ? CachedImage(
                photo,
                fit: BoxFit.cover,
                errorWidget: (_) => _avatarFallback(isDark),
              )
            : _avatarFallback(isDark),
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: (hasStories && !_uploadingStory)
              ? () => _openMyStoryViewer(photo)
              : null,
          child: SizedBox(
            width: totalSize,
            height: totalSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                avatar,
                if (showRing)
                  Positioned.fill(
                    child: _uploadingStory
                        // Yükleme sırasında halka döner (venue/home ile aynı).
                        ? RotationTransition(
                            turns: _storySpin,
                            child: CustomPaint(
                              painter: _ProfileStoryRingPainter(
                                colors: ringColors,
                                strokeWidth: ringWidth,
                                radius: radius + gap,
                              ),
                            ),
                          )
                        : CustomPaint(
                            painter: _ProfileStoryRingPainter(
                              colors: ringColors,
                              strokeWidth: ringWidth,
                              radius: radius + gap,
                            ),
                          ),
                  ),
              ],
            ),
          ),
        ),
        // Avatar'ın sağ altına "+" — fotoğraf ekleme (şimdilik yalnızca görsel).
        Positioned(
          right: -2,
          bottom: -2,
          child: GestureDetector(
            onTap: _activeCheckinId() == null || _uploadingStory
                ? null
                : _openAddStoryFromProfile,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _activeCheckinId() == null
                    ? (isDark ? Colors.white24 : Colors.black26)
                    : AppTheme.brandPrimary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2.5,
                ),
              ),
              child: _uploadingStory
                  ? const Padding(
                      padding: EdgeInsets.all(6),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      // Check-in yoksa story eklenemez → kilit; varsa "+".
                      _activeCheckinId() == null
                          ? Icons.lock_rounded
                          : Icons.add_rounded,
                      color: Colors.white,
                      size: _activeCheckinId() == null ? 14 : 18,
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveCheckinRow(bool isDark, Color onSurface, Color subColor) {
    if (_activeCheckin == null) {
      return Row(
        children: [
          Icon(Icons.location_off_outlined, size: 18, color: subColor),
          const SizedBox(width: 6),
          Text(
            'No active check-in',
            style: TextStyle(color: subColor, fontSize: 14),
          ),
        ],
      );
    }
    final rawVenue = _activeCheckin?['venue'];
    final rawName = (rawVenue is Map ? rawVenue['name'] : null)
        ?.toString()
        .trim();
    final venueName = (_activeVenue?.name.isNotEmpty ?? false)
        ? _activeVenue!.name
        : (rawName != null && rawName.isNotEmpty ? rawName : 'Checked in');
    return InkWell(
      onTap: _openingVenueDetail ? null : _openActiveVenueDetail,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              Icons.location_on_rounded,
              size: 18,
              color: AppTheme.brandPrimary,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                venueName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onSurface,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, size: 18, color: subColor),
          ],
        ),
      ),
    );
  }

  Widget _avatarFallback(bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFEDEDED),
      child: Icon(
        Icons.person_rounded,
        size: 44,
        color: isDark ? Colors.white38 : Colors.black26,
      ),
    );
  }

  /// Instagram tarzı istatistik sütunu. [inactive] ise gri gösterilir.
  Widget _buildStat(
    String value,
    String label,
    Color color,
    Color sub, {
    bool inactive = false,
    VoidCallback? onTap,
  }) {
    final valueColor = inactive ? sub.withValues(alpha: 0.78) : color;
    final labelColor = inactive ? sub.withValues(alpha: 0.72) : color;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            color: labelColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: content,
      ),
    );
  }

  Widget _buildProfileContentTabs(
    Color onSurface,
    Color subColor,
    bool isDark,
  ) {
    Widget tab({
      required int index,
      required IconData icon,
      required String label,
    }) {
      final selected = _selectedProfileTab == index;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _selectedProfileTab = index),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.brandPrimary.withValues(
                      alpha: isDark ? 0.22 : 0.14,
                    )
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? AppTheme.brandPrimary.withValues(alpha: 0.48)
                    : onSurface.withValues(alpha: 0.10),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? AppTheme.brandPrimary : subColor,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? onSurface : subColor,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab(index: 0, icon: Icons.auto_awesome_rounded, label: 'Moments'),
        const SizedBox(width: 8),
        tab(index: 1, icon: Icons.place_rounded, label: 'Visited Places'),
      ],
    );
  }

  Widget _buildVisitedPlacesSection({
    required List<CheckinVisitedPlace> places,
    required bool isDark,
    required Color subColor,
    required Color onSurface,
  }) {
    if (places.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 4),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.place_outlined, size: 46, color: subColor),
              const SizedBox(height: 12),
              Text(
                'No visited places shared yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: onSurface,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Turn on "Show on my profile" when you check in to publish a place here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: subColor, fontSize: 13.5, height: 1.3),
              ),
            ],
          ),
        ),
      );
    }

    // Kartlara sabit yükseklik ver → içerik farkı (ör. "Hidden from others")
    // kartları kesmez. Liste iç-scroll DEĞİL: shrinkWrap ile satır içi açılır,
    // sayfa tek parça kayar (altında boşluk/çift-scroll oluşmaz).
    const tileHeight = 94.0;
    const separatorHeight = 9.0;

    return ListView.separated(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: places.length,
      separatorBuilder: (_, _) => const SizedBox(height: separatorHeight),
      itemBuilder: (_, index) => SizedBox(
        height: tileHeight,
        child: _buildVisitedPlaceTile(
          place: places[index],
          isDark: isDark,
          subColor: subColor,
          onSurface: onSurface,
        ),
      ),
    );
  }

  Widget _buildVisitedPlaceTile({
    required CheckinVisitedPlace place,
    required bool isDark,
    required Color subColor,
    required Color onSurface,
  }) {
    final photo = (place.venuePhoto ?? '').trim();
    final isVisible = place.showOnProfile;
    final isUpdating = _updatingProfileVisibilityIds.contains(place.id);
    final isDeleting = _deletingVisitedPlaceIds.contains(place.id);
    final accent = isDark ? AppColors.blueDark : AppColors.blueLight;
    final error = Theme.of(context).colorScheme.error;
    return InkWell(
      onTap: () => _openVisitedVenueDetail(place),
      borderRadius: BorderRadius.circular(17),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? const [Color(0xFF101A2E), Color(0xFF0A1120)]
                : const [Colors.white, Color(0xFFF3F8FC)],
          ),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: isVisible
                ? accent.withValues(alpha: isDark ? 0.30 : 0.22)
                : subColor.withValues(alpha: 0.16),
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.22)
                  : const Color(0xFF18324D).withValues(alpha: 0.08),
              blurRadius: 13,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(17),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.center,
            colors: [
              accent.withValues(alpha: isVisible ? 0.08 : 0.025),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            Opacity(
              opacity: isVisible ? 1 : 0.48,
              child: Container(
                width: 56,
                height: 56,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    colors: isVisible
                        ? [AppColors.blue, AppColors.magenta]
                        : [
                            subColor.withValues(alpha: 0.35),
                            subColor.withValues(alpha: 0.12),
                          ],
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: photo.isNotEmpty
                      ? CachedImage(
                          photo,
                          fit: BoxFit.cover,
                          errorWidget: (_) =>
                              _buildVisitedPlacePlaceholder(isDark, subColor),
                        )
                      : _buildVisitedPlacePlaceholder(isDark, subColor),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.venueName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onSurface,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.place_outlined, size: 13, color: accent),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          _visitedPlaceSubtitle(place),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: subColor,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 12, color: subColor),
                      const SizedBox(width: 3),
                      Text(
                        _formatVisitedDate(place.checkedInAt),
                        style: TextStyle(
                          color: subColor,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _visitedPlaceActionButton(
                  tooltip: isVisible
                      ? 'Hide from profile'
                      : 'Show on my profile',
                  backgroundColor: accent.withValues(alpha: 0.12),
                  onPressed: (isUpdating || isDeleting)
                      ? null
                      : () => _toggleVisitedPlaceVisibility(place),
                  icon: isUpdating
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.brandPrimary,
                          ),
                        )
                      : Icon(
                          isVisible
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_outlined,
                          color: isVisible ? AppTheme.brandPrimary : subColor,
                          size: 22,
                        ),
                ),
                const SizedBox(width: 5),
                _visitedPlaceActionButton(
                  tooltip: 'Delete visited place',
                  backgroundColor: error.withValues(alpha: 0.10),
                  onPressed: (isUpdating || isDeleting)
                      ? null
                      : () => _deleteVisitedPlace(place),
                  icon: isDeleting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: error,
                          ),
                        )
                      : Icon(
                          Icons.delete_outline_rounded,
                          color: error,
                          size: 22,
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _visitedPlaceActionButton({
    required String tooltip,
    required Color backgroundColor,
    required VoidCallback? onPressed,
    required Widget icon,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
      child: IconButton(
        tooltip: tooltip,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: icon,
      ),
    );
  }

  Future<void> _toggleVisitedPlaceVisibility(CheckinVisitedPlace place) async {
    if (_updatingProfileVisibilityIds.contains(place.id)) return;
    final next = !place.showOnProfile;
    final previousPlaces = List<CheckinVisitedPlace>.from(_visitedPlaces);

    setState(() {
      _updatingProfileVisibilityIds.add(place.id);
      _visitedPlaces = _visitedPlaces
          .map(
            (item) =>
                item.id == place.id ? item.copyWith(showOnProfile: next) : item,
          )
          .toList();
    });

    try {
      await _checkinRepo.updateProfileVisibility(
        checkinId: place.id,
        showOnProfile: next,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _visitedPlaces = previousPlaces;
      });
      await showPremiumErrorDialog(
        context,
        message: 'Profile visibility could not be updated. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() => _updatingProfileVisibilityIds.remove(place.id));
      }
    }
  }

  Future<void> _deleteVisitedPlace(CheckinVisitedPlace place) async {
    if (_deletingVisitedPlaceIds.contains(place.id)) return;
    final confirmed = await showDestructiveConfirmationDialog(
      context,
      title: 'Delete this visited place?',
      message:
          '${place.venueName} and its associated check-in content will be permanently removed from your history. This cannot be undone.',
      confirmLabel: 'Delete visited place',
    );
    if (!confirmed || !mounted) return;

    setState(() => _deletingVisitedPlaceIds.add(place.id));
    try {
      await _checkinRepo.deleteVisitedPlace(place.id);
      if (!mounted) return;
      setState(() {
        _visitedPlaces.removeWhere((item) => item.id == place.id);
      });
    } catch (_) {
      if (!mounted) return;
      await showPremiumErrorDialog(
        context,
        message: 'Visited place could not be deleted. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() => _deletingVisitedPlaceIds.remove(place.id));
      }
    }
  }

  Widget _buildVisitedPlacePlaceholder(bool isDark, Color subColor) {
    return Container(
      color: isDark ? const Color(0xFF252D3D) : const Color(0xFFE9EEF5),
      child: Icon(Icons.place_rounded, color: subColor, size: 28),
    );
  }

  String _visitedPlaceSubtitle(CheckinVisitedPlace place) {
    final type = (place.venueType ?? '').trim();
    if (type.isEmpty) return 'Venue';
    return _formatWhatBringsLabel(type);
  }

  String _formatVisitedDate(DateTime date) {
    final local = date.toLocal();
    if (local.millisecondsSinceEpoch == 0) return '';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '${months[local.month - 1]} ${local.day} · $hour:$minute $period';
  }

  Future<void> _openVisitedVenueDetail(CheckinVisitedPlace place) async {
    final venueId = (place.venueId ?? '').trim();
    if (venueId.isEmpty) return;
    Venue? venue;
    try {
      final venueData = await _venueContextRepository.getVenueById(venueId);
      final map = Map<String, dynamic>.from(venueData);
      if ((map['id'] == null || map['id'].toString().isEmpty)) {
        map['id'] = venueId;
      }
      if ((map['source'] == null || map['source'].toString().isEmpty)) {
        map['source'] = 'db';
      }
      if ((map['isInDb'] == null) && (map['is_in_db'] == null)) {
        map['isInDb'] = true;
      }
      if ((map['canCheckin'] == null) && (map['can_checkin'] == null)) {
        map['canCheckin'] = true;
      }
      venue = Venue.fromJson(map);
      if (venue.id.isEmpty) venue = null;
    } catch (_) {
      venue = null;
    }
    final resolvedVenue =
        venue ??
        Venue(
          id: venueId,
          name: place.venueName,
          type: place.venueType ?? 'venue',
          status: 'Open',
          address: '',
          city: '',
          photoUrl: (place.venuePhoto ?? '').trim(),
          latitude: 0.0,
          longitude: 0.0,
          tag: '#Visited',
          source: 'db',
          isInDb: true,
          canCheckin: true,
        );
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VenueDetailPage(venue: resolvedVenue)),
    );
    if (mounted) unawaited(_loadMyStories());
  }

  /// Hiç check-in'i olmayan kullanıcıya moments boş ekranında yönlendirme:
  /// hızlı check-in başlat veya haritada mekan keşfet.
  Widget _buildEmptyMomentsCta(bool isDark, Color sub) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Ana aksiyon: hızlı check-in — navbar butonuyla aynı blue→teal gradient
        SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [AppColors.blue, AppColors.teal],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.blue.withValues(alpha: 0.30),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => QuickCheckinLauncher().launch(context),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_location_alt_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Quick check-in',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // İkincil aksiyon: haritada keşfet — tema-güvenli dolgu + kontrast metin
        SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.14)
                    : Colors.black.withValues(alpha: 0.10),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => AppShellNav.of(
                  context,
                )?.selectTabId(kPersonalDiscoverTabId),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.explore_outlined,
                        size: 20,
                        color: isDark
                            ? Colors.white
                            : AppColors.lightTextPrimary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Discover on map',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Colors.white
                              : AppColors.lightTextPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMomentsGrid(bool canAddMore, bool isDark, Color sub) {
    final hasAny = _media.isNotEmpty || canAddMore;
    if (!hasAny) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.camera_alt_outlined, size: 48, color: sub),
              const SizedBox(height: 12),
              Text(
                'No moments yet',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Check in to a venue and share your moments.',
                textAlign: TextAlign.center,
                style: TextStyle(color: sub, fontSize: 13.5),
              ),
              const SizedBox(height: 20),
              // ── CTA: hızlı check-in (gradient) + haritada keşfet
              _buildEmptyMomentsCta(isDark, sub),
            ],
          ),
        ),
      );
    }

    // Eski tasarım: yatay kaydırmalı dikdörtgen moment kartları + "+".
    const cardWidth = 132.0;
    const cardHeight = 176.0;
    final itemCount = _media.length + (canAddMore ? 1 : 0);
    return SizedBox(
      height: cardHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (canAddMore && index == _media.length) {
            return _buildAddMomentCard(isDark, cardWidth, cardHeight);
          }
          final media = _media[index];
          return GestureDetector(
            onTap: () async {
              final reload = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MomentsViewerPage(
                    media: _media,
                    initialIndex: index,
                    allowFeature: true,
                    checkinId: _activeCheckinId(),
                  ),
                ),
              );
              if (reload == true) await _loadProfile();
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: _buildMomentCard(media),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Yeni moment ekleme kartı ("+") — aktif check-in varken çalışır.
  Widget _buildAddMomentCard(bool isDark, double w, double h) {
    return GestureDetector(
      onTap: _uploadingMoment ? null : _addMomentPhoto,
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161616) : const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
        child: Center(
          child: _uploadingMoment
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.add_rounded, size: 32, color: AppTheme.brandPrimary),
        ),
      ),
    );
  }

  /// Dikdörtgen moment kartı: alanı doldurur (cover); video ise poster + play.
  Widget _buildMomentCard(CheckinProfileMedia media) {
    if (media.mediaType == MediaType.video) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _buildVideoPosterLayer(media, fit: BoxFit.cover),
          const Center(
            child: Icon(Icons.play_circle_fill, color: Colors.white, size: 30),
          ),
        ],
      );
    }
    return CachedImage(
      media.url,
      fit: BoxFit.cover,
      errorWidget: (_) => Container(color: const Color(0xFF1E1E1E)),
    );
  }

  Future<void> _openEditProfile() async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfilePage(user: _user ?? const {}),
      ),
    );
    if (updated == true && mounted) {
      await _loadProfile(forceRefresh: true);
    }
  }

  /// RESİM OLMADIĞINDA GÖRÜNECEK MODERN GRADIENT
  Widget _buildModernEmptyStateBackground(bool isDark, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFF1F5F9),
      ),
      child: Stack(
        children: [
          // Sol üst köşe ışığı
          Positioned(
            top: -100,
            left: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withOpacity(
                  isDark ? 0.25 : 0.15,
                ),
              ),
            ),
          ),
          // Sağ orta ışık
          Positioned(
            top: 200,
            right: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? AppTheme.brandPrimary.withOpacity(0.15)
                    : theme.colorScheme.secondary.withOpacity(0.15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddMomentTile() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: _uploadingMoment ? null : _addMomentPhoto,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            width: 85,
            height: 110,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: AppTheme.brandPrimary.withValues(
                  alpha: isDark ? 0.38 : 0.28,
                ),
                width: 1.6,
              ),
            ),
            child: Center(
              child: _uploadingMoment
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.onSurface.withValues(alpha: 0.75),
                      ),
                    )
                  : Icon(
                      Icons.add_rounded,
                      size: 28,
                      color: colors.onSurface.withValues(alpha: 0.72),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Frosted-glass "Edit profile" pill for the profile header's top-right.
class _GlassEditButton extends StatelessWidget {
  const _GlassEditButton({required this.onTap, required this.isDark});

  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? Colors.white : Colors.black87;
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.45),
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: fg.withValues(alpha: 0.18)),
              ),
              child: Icon(Icons.edit_outlined, size: 17, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileStoryRingPainter extends CustomPainter {
  final List<Color> colors;
  final double strokeWidth;
  final double radius;

  static const logoColors = [
    AppColors.magenta,
    AppColors.teal,
    AppColors.blue,
    AppColors.orange,
    AppColors.brand,
  ];

  const _ProfileStoryRingPainter({
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
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = SweepGradient(
        colors: [...colors, colors.first],
      ).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _ProfileStoryRingPainter oldDelegate) =>
      oldDelegate.colors != colors ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.radius != radius;
}
