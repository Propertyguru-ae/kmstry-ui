import 'package:flutter/material.dart';
import 'dart:ui'; // Glassmorphism efekti için
import '../../auth/data/auth_repository.dart';
import '../../checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/moments_viewer_page.dart';
import 'dart:io';
import '../../checkin/data/checkin_profile_model.dart';
import 'package:kmstry_frontend/features/camera/presentation/camera_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:kmstry_frontend/features/profile/presentation/account_settings_page.dart';
import 'package:kmstry_frontend/core/permissions/notification_permission_service.dart';
import 'package:kmstry_frontend/core/push/push_manager.dart';

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
  String? _checkinVibe;
  List<String> _checkinWhatBrings = [];

  bool _isExpanded = false;

  bool _uploadingMoment = false;
  final TextEditingController _vibeController = TextEditingController();
  bool _savingVibe = false;
  String? _profileErrorMessage;
  final NotificationPermissionService _notificationPermissionService =
      NotificationPermissionService();
  bool _showNotificationWarning = false;
  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  bool _isVideoFile(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.webm');
  }

  Future<bool> _ensureCameraPermission() async {
    final camera = await Permission.camera.request();
    return camera.isGranted;
  }

  Widget _buildMediaThumb(CheckinProfileMedia media) {
    const thumbWidth = 85.0;
    const thumbHeight = 110.0;

    if (media.mediaType == MediaType.video) {
      final thumbnail = media.thumbnailUrl;
      final hasThumbnail = thumbnail != null && thumbnail.isNotEmpty;

      return SizedBox(
        width: thumbWidth,
        height: thumbHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            /// Thumbnail
            if (hasThumbnail)
              Image.network(
                thumbnail!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: Colors.black87),
              )
            else
              Container(color: Colors.black87),

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
      // 1) Aktif check-in varsa getProfile(checkinId) ile o check-in'in fotoğraflarını al (backend getProfile)
      final activeCheckin = _extractActiveCheckin(me);
      final checkinId = activeCheckin?['id']?.toString();
      if (checkinId != null && checkinId.isNotEmpty) {
        try {
          final profile = await _checkinRepo.getCheckinProfile(checkinId);
          print('PROFILE :  $profile');
          //print('PROFILE PHOTOS :  ${profile.checkin.vibe}');
          checkinVibe = profile.checkin.vibe ?? '';
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
      setState(() {
        _user = me;
        _activeCheckin = activeCheckin;
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
    if (_activeCheckin == null) return;
    final checkinId = _activeCheckinId();
    if (checkinId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Active check-in data is missing.')),
      );
      return;
    }

    try {
      final hasPermission = await _ensureCameraPermission();
      if (!hasPermission) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission is required.')),
        );
        return;
      }

      // 🔥 Kendi kamera ekranımızı açıyoruz
      final File? capturedMedia = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const CameraScreen(
            useFrontCamera: true, // selfie
          ),
        ),
      );

      if (capturedMedia == null) return;

      // Check-in aninda tek video kurali profile'a da uygulaniyor.
      if (_isVideoFile(capturedMedia.path) &&
          _media.any((m) => m.mediaType == MediaType.video)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You can upload only 1 video.")),
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
      print("Moment upload error: $e");
    } finally {
      if (mounted) {
        setState(() => _uploadingMoment = false);
      }
    }
  }

  Future<void> _openEditVibeModal() async {
    if (_activeCheckin == null) return;

    _vibeController.text = _checkinVibe ?? "";

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Edit your vibe",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _vibeController,
                  maxLength: 150,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "What's your vibe?",
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
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
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _savingVibe
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Text("Save"),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveVibe() async {
    if (_activeCheckin == null) return;
    final checkinId = _activeCheckinId();
    if (checkinId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Active check-in data is missing.')),
      );
      return;
    }

    setState(() => _savingVibe = true);

    try {
      await _checkinRepo.updateVibe(
        checkinId: checkinId,
        vibe: _vibeController.text.trim(),
      );

      if (!mounted) return;

      setState(() {
        _checkinVibe = _vibeController.text.trim();
      });

      Navigator.pop(context); // modal kapanır
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Failed to update vibe")));
    }

    if (mounted) setState(() => _savingVibe = false);
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AccountSettingsPage()),
    );
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

    final bool hasImage =
        featuredMedia != null && featuredMedia.mediaType == MediaType.photo;

    //print('CHECKIN VIBE geliyor mu  :  $_checkinVibe');
    //print('active ceckin geliyor mu  :  $_activeCheckin');
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          /// 1. DİNAMİK ARKA PLAN (Resim yoksa şık bir Gradient)
          Positioned.fill(
            child: hasImage
                ? Image.network(featuredMedia.url, fit: BoxFit.cover)
                : _buildModernEmptyStateBackground(isDark, theme),
          ),

          /// 2. BLUR & GRADIENT KATMANI (Daha derin bir görünüm için)
          if (!hasImage)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: Container(
                  color: isDark
                      ? Colors.black.withOpacity(0.2)
                      : Colors.white.withOpacity(0.2),
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
                    isDark ? Colors.black : Colors.white,
                    isDark
                        ? Colors.black.withOpacity(0.4)
                        : Colors.white.withOpacity(0.6),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.4, 0.8],
                ),
              ),
            ),
          ),

          /// 4. İÇERİK
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                          color: isDark
                              ? Colors.white
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_profileErrorMessage != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
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
                                color: theme.colorScheme.onErrorContainer,
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

                const Spacer(),

                /// KULLANICI BİLGİLERİ
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_user?['fullName'] ?? 'Guest'} ${_user?['age'] ?? ''}',
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : Colors.black87,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF00FF75), // Daha canlı bir yeşil
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
                              final username = (_user?['username'] ??
                                      _user?['user_name'])
                                  ?.toString()
                                  .trim();
                              if (username == null || username.isEmpty) {
                                return 'Online';
                              }
                              return '@${username.toLowerCase()}';
                            })(),
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black54,
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
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.35,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Turn on notifications so you don't miss matches.",
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white
                                      : theme.colorScheme.onSurface,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  ElevatedButton(
                                    onPressed: _enableNotificationsFromProfile,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          theme.colorScheme.primary,
                                      foregroundColor:
                                          theme.colorScheme.onPrimary,
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

                      /// BIO VEYA NO CHECK-IN UYARISI (Şık bir kutu içinde)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withOpacity(hasImage ? 0.1 : 0.05)
                              : Colors.black.withOpacity(
                                  hasImage ? 0.05 : 0.03,
                                ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withOpacity(0.1)
                                : Colors.black.withOpacity(0.05),
                          ),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final vibeText = _activeCheckin != null
                                ? (_checkinVibe ?? 'Hello! This is my bio...')
                                : '✨ You do not have an active check-in.';

                            final style = TextStyle(
                              color: isDark
                                  ? Colors.white.withOpacity(0.9)
                                  : Colors.black.withOpacity(0.8),
                              fontSize: 15,
                              height: 1.4,
                            );

                            final isOverflowing = _checkTextOverflow(
                              vibeText,
                              constraints.maxWidth - 30, // 👈 ikon için boşluk
                              style,
                            );

                            return AnimatedSize(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOut,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    vibeText,
                                    style: style,
                                    maxLines: _isExpanded ? null : 2,
                                    overflow: _isExpanded
                                        ? TextOverflow.visible
                                        : TextOverflow.ellipsis,
                                  ),

                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        // 👈 See more sadece overflow varsa
                                        if (isOverflowing)
                                          GestureDetector(
                                            onTap: () {
                                              setState(() {
                                                _isExpanded = !_isExpanded;
                                              });
                                            },
                                            child: Text(
                                              _isExpanded
                                                  ? 'See less'
                                                  : 'See more',
                                              style: TextStyle(
                                                color: isDark
                                                    ? Colors.white
                                                    : theme.colorScheme.primary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          )
                                        else
                                          const SizedBox(), // boşluk dengesi için
                                        // 👉 Kalem HER ZAMAN
                                        if (_activeCheckin != null)
                                          GestureDetector(
                                            onTap: _openEditVibeModal,
                                            child: Icon(
                                              Icons.edit_outlined,
                                              size: 18,
                                              color: isDark
                                                  ? Colors.white70
                                                  : Colors.black54,
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
                                color: theme.colorScheme.primary.withValues(
                                  alpha: isDark ? 0.22 : 0.14,
                                ),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: 0.45,
                                  ),
                                ),
                              ),
                              child: Text(
                                _formatWhatBringsLabel(item),
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
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

                const SizedBox(height: 30),

                /// MOMENTS HEADER
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Moments",
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      /// 📸 Add More sadece 6'dan az ise
                      if (_activeCheckin != null && _media.length < 6)
                        _uploadingMoment
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white70,
                                ),
                              )
                            : GestureDetector(
                                onTap: _addMomentPhoto,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.camera_alt_outlined,
                                      size: 18,
                                      color: isDark
                                          ? Colors.white70
                                          : theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      "Add more",
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white70
                                            : theme.colorScheme.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                /// MOMENTS LIST
                SizedBox(
                  height: 110,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    scrollDirection: Axis.horizontal,
                    itemCount: _media.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      return GestureDetector(
                        onTap: () async {
                          final reload = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MomentsViewerPage(
                                media: _media,
                                initialIndex: index,
                                allowFeature: true,
                              ),
                            ),
                          );

                          // MomentsViewerPage star ile featured seçince: Navigator.pop(context, true) dönüyor
                          if (reload == true) {
                            await _loadProfile();
                          }
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(15),
                          child: _buildMediaThumb(_media[index]),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 30),
              ],
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
                    ? Colors.blueAccent.withOpacity(0.15)
                    : theme.colorScheme.secondary.withOpacity(0.15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
