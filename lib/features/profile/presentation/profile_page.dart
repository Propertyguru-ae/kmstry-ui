import 'package:flutter/material.dart';
import 'dart:ui'; // Glassmorphism efekti için
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import '../../auth/data/auth_repository.dart';
import '../../checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/moments_viewer_page.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_detail_page.dart';
import 'dart:io';
import '../../checkin/data/checkin_profile_model.dart';
import 'package:kmstry_frontend/features/camera/presentation/camera_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:kmstry_frontend/features/profile/presentation/profile_settings_page.dart';
import 'package:kmstry_frontend/core/permissions/notification_permission_service.dart';
import 'package:kmstry_frontend/core/push/push_manager.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with WidgetsBindingObserver {
  Map<String, dynamic>? _user;
  bool _loading = true;
  Map<String, dynamic>? _activeCheckin;
  List<CheckinProfileMedia> _media = [];

  final CheckinRepository _checkinRepo = CheckinRepository();
  final VenueContextRepository _venueContextRepository =
      VenueContextRepository();
  String? _checkinVibe;

  /// Sunucudaki kalıcı bio; check-in vibe boşsa gösterim için kullanılır.
  String? _profileBio;
  String? _activeCheckinVenueIdFromProfile;
  List<String> _checkinWhatBrings = [];

  bool _isExpanded = false;
  bool _areMomentsExpanded = false;

  bool _uploadingMoment = false;
  bool _openingVenueDetail = false;
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
      return Image.network(
        thumbnail,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => Container(color: Colors.black87),
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
        child: Image.network(media.url, fit: BoxFit.cover),
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
        _buildVideoPosterLayer(
          media,
          fit: fit,
          width: width,
          height: height,
        ),
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
    _loadProfile();
    _refreshNotificationWarningState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _vibeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshNotificationWarningState();
    }
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
    } finally {
      if (mounted) {
        setState(() => _openingVenueDetail = false);
      }
    }
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

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _profileErrorMessage = null;
    });
    try {
      final me = await AuthRepository().getMe();
      print('ME :  $me');

      List<CheckinProfileMedia> media = [];

      String? checkinVibe;
      String? activeCheckinVenueId;
      // 1) Aktif check-in varsa getProfile(checkinId) ile o check-in'in fotoğraflarını al (backend getProfile)
      final activeCheckin = _extractActiveCheckin(me);
      activeCheckinVenueId = _extractActiveCheckinVenueId(activeCheckin);
      final checkinId = activeCheckin?['id']?.toString();
      if (checkinId != null && checkinId.isNotEmpty) {
        try {
          final profile = await _checkinRepo.getCheckinProfile(checkinId);
          print('PROFILE :  $profile');
          //print('PROFILE PHOTOS :  ${profile.checkin.vibe}');
          checkinVibe = profile.checkin.vibe ?? '';
          final profileVenueId = profile.checkin.venueId?.trim();
          if (profileVenueId != null && profileVenueId.isNotEmpty) {
            activeCheckinVenueId = profileVenueId;
          }
          //print('CHECKIN VIBE :  $checkinVibe');
          for (final m in profile.media) {
            print("MEDIA ITEM:");
            print("url: ${m.url}");
            print("thumbnail: ${m.thumbnailUrl}");
            print("type: ${m.mediaType}");
            print("duration: ${m.durationSeconds}");
          }
          if (profile.media.isNotEmpty) {
            media = profile.media;
          }
        } catch (e) {
          debugPrint('Profile checkin fetch failed: $e');
          _profileErrorMessage =
              'Moments could not be loaded. Pull to refresh or try again.';
        }
      }

      if (!mounted) return;
      final bioRaw = (me['bio'] ?? me['bio_text'])?.toString().trim();
      setState(() {
        _user = me;
        _profileBio = (bioRaw != null && bioRaw.isNotEmpty) ? bioRaw : null;
        _activeCheckin = activeCheckin;
        _activeCheckinVenueIdFromProfile = activeCheckinVenueId;
        _checkinWhatBrings = _extractWhatBrings(activeCheckin);
        _checkinVibe = checkinVibe;
        _media = media;
        _loading = false;
      });
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
      final File? capturedMedia = await navigator.push<File>(
        MaterialPageRoute(
          builder: (_) => const CameraScreen(
            useFrontCamera: true, // selfie
            optimizeForUpload: true,
          ),
        ),
      );

      if (!mounted) return;
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

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileSettingsPage()),
    );
    if (mounted) await _loadProfile();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_loading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        ),
      );
    }
    CheckinProfileMedia? featuredMedia;
    if (_media.isNotEmpty) {
      featuredMedia = _media.firstWhere(
        (m) => m.isFeatured,
        orElse: () => _media.first,
      );
    }

    final bool hasFeaturedMedia = featuredMedia != null;
    final bool hasFeaturedPhoto =
        featuredMedia != null && featuredMedia.mediaType == MediaType.photo;

    //print('CHECKIN VIBE geliyor mu  :  $_checkinVibe');
    ///print('active ceckin geliyor mu  :  $_activeCheckin');
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          /// 1. DİNAMİK ARKA PLAN (Resim yoksa şık bir Gradient)
          Positioned.fill(
            child: !hasFeaturedMedia
                ? _buildModernEmptyStateBackground(isDark, theme)
                : hasFeaturedPhoto
                ? Image.network(
                    featuredMedia.url,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        _buildModernEmptyStateBackground(isDark, theme),
                  )
                : _buildVideoCover(
                    media: featuredMedia,
                    fit: BoxFit.cover,
                    iconSize: 60,
                  ),
          ),

          /// 2. BLUR & GRADIENT KATMANI (Daha derin bir görünüm için)
          if (!hasFeaturedPhoto)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: Container(
                  color: isDark
                      ? Colors.black.withOpacity(0.2)
                      : Colors.black.withOpacity(0.16),
                ),
              ),
            ),

          /// 3. STANDART KARARTMA (Yazı okunabilirliği için)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    isDark ? Colors.black : Colors.black.withOpacity(0.92),
                    isDark
                        ? Colors.black.withOpacity(0.4)
                        : Colors.black.withOpacity(0.5),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.4, 0.8],
                ),
              ),
            ),
          ),

          /// 4. İÇERİK (scroll + min yükseklik: Spacer taşması ve küçük ekranlar)
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Top Action Bar with Settings
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(
                                    onPressed: _openSettings,
                                    icon: Icon(
                                      Icons.settings_outlined,
                                      color: isDark ? Colors.white : Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_profileErrorMessage != null)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.errorContainer,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _profileErrorMessage!,
                                          style: TextStyle(
                                            color: theme
                                                .colorScheme
                                                .onErrorContainer,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: _loadProfile,
                                        child: const Text('Retry'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            /// KULLANICI BİLGİLERİ
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_activeCheckin != null) ...[
                                    OutlinedButton.icon(
                                      onPressed: _openingVenueDetail
                                          ? null
                                          : _openActiveVenueDetail,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        side: BorderSide(
                                          color: Colors.white.withValues(
                                            alpha: 0.4,
                                          ),
                                        ),
                                        backgroundColor: Colors.black.withValues(
                                          alpha: 0.22,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 7,
                                        ),
                                        minimumSize: const Size(0, 34),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: const VisualDensity(
                                          horizontal: -1,
                                          vertical: -1,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        textStyle: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      icon: _openingVenueDetail
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.location_on_outlined,
                                              size: 15,
                                            ),
                                      label: const Text('Here now'),
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${_user?['fullName'] ?? 'Guest'} ${_user?['age'] ?? ''}',
                                          style: TextStyle(
                                            fontSize: 34,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.white,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: Color(
                                            0xFF00FF75,
                                          ), // Daha canlı bir yeşil
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Color(0xFF00FF75),
                                              blurRadius: 4,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        (() {
                                          final username =
                                              (_user?['username'] ??
                                                      _user?['user_name'])
                                                  ?.toString()
                                                  .trim();
                                          if (username == null ||
                                              username.isEmpty) {
                                            return 'Online';
                                          }
                                          return '@${username.toLowerCase()}';
                                        })(),
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_showNotificationWarning) ...[
                                    const SizedBox(height: 14),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: theme.colorScheme.primary
                                              .withValues(alpha: 0.35),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "Turn on notifications so you don't miss matches.",
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              ElevatedButton(
                                                onPressed:
                                                    _enableNotificationsFromProfile,
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor:
                                                      theme.colorScheme.primary,
                                                  foregroundColor: theme
                                                      .colorScheme
                                                      .onPrimary,
                                                  minimumSize: const Size(
                                                    0,
                                                    40,
                                                  ),
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                  visualDensity:
                                                      const VisualDensity(
                                                        horizontal:
                                                            VisualDensity
                                                                .minimumDensity,
                                                        vertical: VisualDensity
                                                            .minimumDensity,
                                                      ),
                                                ),
                                                child: const Text('Enable'),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 20),

                                  /// BIO / VIBE glass kartı (şeffaf + blur)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: BackdropFilter(
                                      filter: ImageFilter.blur(
                                        sigmaX: 14,
                                        sigmaY: 14,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 14,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              Colors.white.withValues(
                                                alpha: hasFeaturedPhoto ? 0.14 : 0.10,
                                              ),
                                              Colors.white.withValues(
                                                alpha: hasFeaturedPhoto ? 0.06 : 0.03,
                                              ),
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.18,
                                            ),
                                          ),
                                        ),
                                        child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        final vibeTrim = (_checkinVibe ?? '')
                                            .trim();
                                        final bioTrim = (_profileBio ?? '')
                                            .trim();
                                        // Merkezi metin: check-in + vibe veya bio; yalnız bio; yoksa uyarı.
                                        final vibeText = _activeCheckin != null
                                            ? (vibeTrim.isNotEmpty
                                                  ? vibeTrim
                                                  : (bioTrim.isNotEmpty
                                                        ? bioTrim
                                                        : 'Hello! This is my bio...'))
                                            : (bioTrim.isNotEmpty
                                                  ? bioTrim
                                                  : '✨ You do not have an active check-in.');

                                        final style = TextStyle(
                                          color: Colors.white.withOpacity(0.9),
                                          fontSize: 15,
                                          height: 1.4,
                                        );

                                        final isOverflowing =
                                            _checkTextOverflow(
                                              vibeText,
                                              constraints.maxWidth -
                                                  30, // 👈 ikon için boşluk
                                              style,
                                            );

                                          return AnimatedSize(
                                          duration: const Duration(
                                            milliseconds: 250,
                                          ),
                                          curve: Curves.easeInOut,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                vibeText,
                                                style: style,
                                                maxLines: _isExpanded
                                                    ? null
                                                    : 2,
                                                overflow: _isExpanded
                                                    ? TextOverflow.visible
                                                    : TextOverflow.ellipsis,
                                              ),

                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 8,
                                                ),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    // 👈 See more sadece overflow varsa
                                                    if (isOverflowing)
                                                      GestureDetector(
                                                        onTap: () {
                                                          setState(() {
                                                            _isExpanded =
                                                                !_isExpanded;
                                                          });
                                                        },
                                                        child: Text(
                                                          _isExpanded
                                                              ? 'See less'
                                                              : 'See more',
                                                          style: TextStyle(
                                                            color: Colors.white,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                      )
                                                    else
                                                      const SizedBox(), // boşluk dengesi için
                                                    // Merkezi bio/vibe düzenleme (check-in olsun olmasın).
                                                    GestureDetector(
                                                      onTap: _openEditVibeModal,
                                                      child: Icon(
                                                        Icons.edit_outlined,
                                                        size: 18,
                                                        color: Colors.white70,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                  ),

                                  if (_activeCheckin != null &&
                                      _checkinWhatBrings.isNotEmpty) ...[
                                    const SizedBox(height: 14),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: _checkinWhatBrings.map((item) {
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? AppTheme.brandPrimary
                                                      .withValues(alpha: 0.22)
                                                : const Color(
                                                    0xFFEAF1FF,
                                                  ),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            border: Border.all(
                                              color: AppTheme.brandPrimary
                                                  .withValues(alpha: 0.45),
                                            ),
                                          ),
                                          child: Text(
                                            _formatWhatBringsLabel(item),
                                            style: TextStyle(
                                              color: isDark
                                                  ? Colors.white
                                                  : AppTheme.brandPrimary,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            const SizedBox(height: 6),

                            if (_media.isNotEmpty ||
                                _activeCheckin != null) ...[
                              Padding(
                                padding: const EdgeInsets.only(
                                  left: 28,
                                  right: 24,
                                ),
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _areMomentsExpanded =
                                          !_areMomentsExpanded;
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 6,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.start,
                                      children: [
                                        Text(
                                          _areMomentsExpanded
                                              ? 'Close moments'
                                              : 'See moments',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          _areMomentsExpanded
                                              ? Icons.keyboard_arrow_up_rounded
                                              : Icons
                                                    .keyboard_arrow_down_rounded,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeInOut,
                                child: _areMomentsExpanded
                                    ? Column(
                                        children: [
                                          const SizedBox(height: 8),
                                          const SizedBox(height: 8),
                                          SizedBox(
                                            height: 110,
                                            child: ListView.separated(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 24,
                                                  ),
                                              scrollDirection: Axis.horizontal,
                                              itemCount:
                                                  _media.length +
                                                  ((_activeCheckin != null &&
                                                          _media.length < 6)
                                                      ? 1
                                                      : 0),
                                              separatorBuilder: (_, __) =>
                                                  const SizedBox(width: 12),
                                              itemBuilder: (context, index) {
                                                final canAddMore =
                                                    _activeCheckin != null &&
                                                    _media.length < 6;
                                                if (canAddMore &&
                                                    index == _media.length) {
                                                  return _buildAddMomentTile();
                                                }
                                                return GestureDetector(
                                                  onTap: () async {
                                                    final reload =
                                                        await Navigator.push(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (_) =>
                                                                MomentsViewerPage(
                                                                  media: _media,
                                                                  initialIndex:
                                                                      index,
                                                                  allowFeature:
                                                                      true,
                                                                ),
                                                          ),
                                                        );

                                                    if (reload == true) {
                                                      await _loadProfile();
                                                    }
                                                  },
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          15,
                                                        ),
                                                    child: _buildMediaThumb(
                                                      _media[index],
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                          const SizedBox(height: 30),
                                        ],
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                            const SizedBox(height: 26),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
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
