import 'package:flutter/material.dart';
import 'dart:ui'; // Glassmorphism efekti için
import '../../auth/data/auth_repository.dart';
import '../../checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/moments_viewer_page.dart';
import 'dart:io';
import '../../checkin/data/checkin_profile_model.dart';
import 'package:kmstry_frontend/features/camera/presentation/camera_screen.dart';
import 'package:permission_handler/permission_handler.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Map<String, dynamic>? _user;
  bool _loading = true;
  Map<String, dynamic>? _activeCheckin;
  List<CheckinProfileMedia> _media = [];

  final CheckinRepository _checkinRepo = CheckinRepository();
  String? _checkinVibe;

  bool _isExpanded = false;

  bool _uploadingMoment = false;
  final TextEditingController _vibeController = TextEditingController();
  bool _savingVibe = false;

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
            if (hasThumbnail)
              Image.network(
                thumbnail,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: Colors.black87),
              )
            else
              Container(color: Colors.black87),
            const Center(
              child: Icon(
                Icons.play_circle_fill,
                color: Colors.white,
                size: 30,
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
        child: Image.network(
          media.url,
          fit: BoxFit.cover,
        ),
      );
    }
    return const SizedBox(width: thumbWidth, height: thumbHeight);
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
    });
    try {
      final me = await AuthRepository().getMe();
      print('ME :  $me');

      List<CheckinProfileMedia> media = [];

      String? checkinVibe;
      // 1) Aktif check-in varsa getProfile(checkinId) ile o check-in'in fotoğraflarını al (backend getProfile)
      final activeCheckin = me['active_checkin'];
      final checkinId = activeCheckin is Map
          ? activeCheckin['id'] as String?
          : null;
      if (checkinId != null && checkinId.isNotEmpty) {
        try {
          final profile = await _checkinRepo.getCheckinProfile(checkinId);
          print('PROFILE :  $profile');
          print('PROFILE PHOTOS :  ${profile.checkin.vibe}');
          checkinVibe = profile.checkin.vibe ?? '';
          print('CHECKIN VIBE :  $checkinVibe');
          if (profile.media.isNotEmpty) {
            media = profile.media;
          }
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _user = me;
        _activeCheckin = me['active_checkin'];
        _checkinVibe = checkinVibe;
        _media = media;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  bool _checkTextOverflow(String text, double maxWidth, TextStyle style) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 3,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

    return textPainter.didExceedMaxLines;
  }

  Future<void> _addMomentPhoto() async {
    if (_activeCheckin == null) return;

    final checkinId = _activeCheckin!['id'] as String;

    try {
      final hasPermission = await _ensureCameraPermission();
      if (!hasPermission) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera permission is required.'),
          ),
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

    final checkinId = _activeCheckin!['id'] as String;

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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
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

    print('CHECKIN VIBE geliyor mu  :  $_checkinVibe');
    print('active ceckin geliyor mu  :  $_activeCheckin');
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          /// 1. DİNAMİK ARKA PLAN (Resim yoksa şık bir Gradient)
          Positioned.fill(
            child: hasImage
                ? Image.network(featuredMedia.url, fit: BoxFit.cover)
                : _buildModernEmptyStateBackground(),
          ),

          /// 2. BLUR & GRADIENT KATMANI (Daha derin bir görünüm için)
          if (!hasImage)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: Container(color: Colors.black.withOpacity(0.2)),
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
                    Colors.black,
                    Colors.black.withOpacity(0.4),
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
                const Spacer(),

                /// KULLANICI BİLGİLERİ
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_user?['full_name'] ?? 'Guest'} ${_user?['age'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
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
                          const Text(
                            'Online',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      /// BIO VEYA NO CHECK-IN UYARISI (Şık bir kutu içinde)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(
                            hasImage ? 0.1 : 0.05,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.1),
                          ),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final vibeText = _activeCheckin != null
                                ? (_checkinVibe ?? 'Hello! This is my bio...')
                                : '✨ You do not have an active check-in.';

                            final style = TextStyle(
                              color: Colors.white.withOpacity(0.9),
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
                                              style: const TextStyle(
                                                color: Colors.white,
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
                                            child: const Icon(
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
                      const Text(
                        "Moments",
                        style: TextStyle(
                          color: Colors.white,
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
                                  children: const [
                                    Icon(
                                      Icons.camera_alt_outlined,
                                      size: 18,
                                      color: Colors.white70,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      "Add more",
                                      style: TextStyle(
                                        color: Colors.white70,
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
  Widget _buildModernEmptyStateBackground() {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFF0F0F0F)),
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
                color: Colors.deepPurple.withOpacity(0.3),
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
                color: Colors.blueAccent.withOpacity(0.15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
