import 'dart:io';
import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/permissions/location_permission_service.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/checkin/services/active_checkin_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:kmstry_frontend/features/camera/presentation/camera_screen.dart';

enum MediaType { photo, video }

class LocalMedia {
  final File file;
  final MediaType type;

  LocalMedia({required this.file, required this.type});
}

class CheckInPage extends StatefulWidget {
  final String venueId;
  /// Haritadan seçilen mekânın koordinatları; check-in isteğinde gönderilir (backend doğrulaması).
  final double venueLatitude;
  final double venueLongitude;

  const CheckInPage({
    super.key,
    required this.venueId,
    required this.venueLatitude,
    required this.venueLongitude,
  });
  @override
  State<CheckInPage> createState() => _CheckInPageState();
}

class _CheckInPageState extends State<CheckInPage> {
  final TextEditingController _vibeController = TextEditingController();
  static const int _maxWhatBringsSelections = 3;
  List<String> _whatBringsOptions = [];
  bool _isLoadingOptions = true;
  final Set<String> _selectedWhatBrings = <String>{};

  // Birden fazla fotoğrafı tutmak için liste yapısı
  final List<LocalMedia> _media = [];
  final int _maxMedia = 6;

  final _repo = CheckinRepository();
  final LocationPermissionService _locationPermissionService =
      LocationPermissionService();
  bool _isSubmitting = false;
  static const int _vibeMaxLength = 150;

  // Öne çıkarılan fotoğrafın indeksi (varsayılan olarak ilk fotoğraf)
  int _featuredIndex = 0;
  String _formatOptionLabel(String key) {
    return key
        .toLowerCase()
        .split('_')
        .map(
          (word) =>
              word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1),
        )
        .join(' ');
  }

  int get _featuredPhotoIndex {
    if (_featuredIndex >= 0 &&
        _featuredIndex < _media.length &&
        _media[_featuredIndex].type == MediaType.photo) {
      return _featuredIndex;
    }
    return _media.indexWhere((m) => m.type == MediaType.photo);
  }

  void _openWhatBringsSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        const lightCardFill = Color(0xFFF8FBFD);
        const lightCardBorder = Color(0xFFE6EEF4);

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20),
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
                  const SizedBox(height: 20),

                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: _whatBringsOptions.map((option) {
                        final selected = _selectedWhatBrings.contains(option);
                        return GestureDetector(
                          onTap: () {
                            setModalState(() {
                              if (selected) {
                                _selectedWhatBrings.remove(option);
                              } else {
                                if (_selectedWhatBrings.length >=
                                    _maxWhatBringsSelections) {
                                  return;
                                }
                                _selectedWhatBrings.add(option);
                              }
                            });
                            setState(() {});
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppTheme.brandPrimary.withValues(alpha: 0.12)
                                  : (isDark ? colors.surface : lightCardFill),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected
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
                                  _formatOptionLabel(option),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: colors.onSurface,
                                  ),
                                ),
                                if (selected)
                                  Icon(
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
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Done"),
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

  Future<bool> _ensureCameraPermission() async {
    final result = await Permission.camera.request();
    debugPrint('📸 Camera permission result: $result');

    if (result.isGranted) return true;

    if (result.isPermanentlyDenied) {
      if (!mounted) return false;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Camera access required'),
          content: const Text(
            'Please enable camera access from Settings to take photos and record videos.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                openAppSettings();
                Navigator.pop(context);
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
    }

    return false;
  }

  @override
  void initState() {
    super.initState();
    _loadWhatBringsOptions();
    _prefillVibeFromProfileBio();
  }

  /// Kalıcı profil bio’su varsa vibe alanına varsayılan olarak yüklenir.
  Future<void> _prefillVibeFromProfileBio() async {
    try {
      final me = await AuthRepository().getMe();
      final raw = (me['bio'] ?? me['bio_text'])?.toString().trim();
      if (!mounted || raw == null || raw.isEmpty) return;
      if (_vibeController.text.trim().isNotEmpty) return;
      setState(() => _vibeController.text = raw);
    } catch (_) {}
  }

  Future<void> _loadWhatBringsOptions() async {
    try {
      final options = await _repo.getWhatBringsOptions();
      setState(() {
        _whatBringsOptions = options;
        _isLoadingOptions = false;
      });
    } catch (e) {
      debugPrint('❌ Failed to load what brings options: $e');
      setState(() => _isLoadingOptions = false);
    }
  }

  MediaType _resolveMediaType(File file) {
    final lower = file.path.toLowerCase();
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.webm')) {
      return MediaType.video;
    }
    return MediaType.photo;
  }

  Future<void> _openCameraAndAddMedia() async {
    if (_media.length >= _maxMedia) {
      await showPremiumErrorDialog(
        context,
        message: 'You can add up to 6 items.',
      );
      return;
    }

    final hasPermission = await _ensureCameraPermission();
    if (!hasPermission) return;
    if (!mounted) return;

    final File? captured = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CameraScreen(useFrontCamera: false),
      ),
    );

    if (captured == null) return;

    final selectedType = _resolveMediaType(captured);
    final hasExistingVideo = _media.any((m) => m.type == MediaType.video);
    if (selectedType == MediaType.video && hasExistingVideo) {
      if (!mounted) return;
      await showPremiumErrorDialog(
        context,
        message: 'You can upload only 1 video.',
      );
      return;
    }

    setState(() {
      _media.add(LocalMedia(file: File(captured.path), type: selectedType));
    });
  }

  /// Fotoğrafı listeden kaldırma
  void _removeMedia(int index) {
    setState(() {
      _media.removeAt(index);
      if (_featuredIndex >= _media.length) {
        _featuredIndex = 0;
      }
    });
  }

  /// Fotoğrafı öne çıkan olarak işaretleme
  void _setFeatured(int index) {
    if (_media[index].type != MediaType.photo) {
      showPremiumErrorDialog(
        context,
        message: 'Only photos can be featured.',
      );
      return;
    }
    setState(() {
      _featuredIndex = index;
    });
  }

  Future<void> _showPhotoRequiredDialog() async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Photo required'),
        content: const Text(
          'You must upload at least one photo to complete your check-in. '
          'A featured photo is required.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitCheckin() async {
    if (_media.isEmpty) return;
    final hasAtLeastOnePhoto = _media.any(
      (item) => item.type == MediaType.photo,
    );
    if (!hasAtLeastOnePhoto) {
      await _showPhotoRequiredDialog();
      return;
    }
    if (_vibeController.text.trim().characters.length > _vibeMaxLength) {
      await showPremiumErrorDialog(context, message: 'Vibe is too long.');
      return;
    }

    final hasLocationPermission = await _ensureLocationPermissionForCheckin();
    if (!hasLocationPermission) return;

    setState(() => _isSubmitting = true);

    try {
      // Seçilen venue’nun konumu; evden testte de mekânın kayıtlı koordinatı gider.
      final latitude = widget.venueLatitude;
      final longitude = widget.venueLongitude;

      // 1️⃣ Check-in oluştur
      final vibeText = _vibeController.text.trim();
      final checkinId = await _repo.createCheckin(
        venueId: widget.venueId,
        latitude: latitude,
        longitude: longitude,
        vibe: vibeText,
        whatBringsYou: _selectedWhatBrings.toList(),
      );
      ActiveCheckinService().setActiveCheckin(checkinId);

      try {
        await AuthRepository().updateMe({'bio': vibeText});
      } catch (_) {}

      // 2️⃣ Fotoğrafları yükle
      final featuredPhotoIndex = _featuredPhotoIndex;
      for (int i = 0; i < _media.length; i++) {
        await _repo.uploadCheckinMedia(
          checkinId: checkinId,
          file: _media[i].file,
          isFeatured:
              _media[i].type == MediaType.photo && i == featuredPhotoIndex,
        );
      }

      // ✅ Başarılı
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      debugPrint('❌ Check-in error: $e');
      if (!mounted) return;
      await showPremiumErrorDialog(context, message: 'Check-in failed');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<bool> _ensureLocationPermissionForCheckin() async {
    var status = await _locationPermissionService.status();
    if (!status.isGranted) {
      status = await _locationPermissionService.request();
    }
    if (status.isGranted) return true;

    if (!mounted) return false;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Location required'),
        content: const Text(
          'Location permission is required to complete check-in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(context);
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: Icon(Icons.close, color: colors.onSurface, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Check in',
          style: TextStyle(
            color: colors.onSurface,
            fontWeight: FontWeight.w800,
            fontSize: 22,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// INFORMATION TEXT
            Text(
              'Select your featured photo by tapping on it. This will represents you at this venue.',
              style: TextStyle(
                color: colors.onSurface.withValues(alpha: 0.65),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),

            /// PHOTOS SECTION
            Text(
              'Photos',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 12),

            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ...List.generate(_media.length, (index) {
                  final item = _media[index];

                  return _buildMediaBox(
                    index: index,
                    isFeatured: _featuredPhotoIndex == index,
                    media: item,
                  );
                }),

                if (_media.length < _maxMedia) _buildAddBox(),
              ],
            ),

            const SizedBox(height: 30),

            /// VIBE SECTION
            Text(
              'Vibe',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _vibeController,
              maxLines: 4,
              maxLength: _vibeMaxLength,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                setState(() {}); // Buton aktif/pasif için gerekli
              },
              buildCounter:
                  (
                    context, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) {
                    final visibleLength =
                        _vibeController.text.characters.length;

                    final remaining = _vibeMaxLength - visibleLength;
                    final isWarning = remaining <= 20;

                    return Text(
                      "$visibleLength / $_vibeMaxLength",
                      style: TextStyle(
                        fontSize: 12,
                        color: isWarning
                            ? colors.secondary
                            : colors.onSurface.withValues(alpha: 0.65),
                        fontWeight: isWarning
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    );
                  },

              decoration: InputDecoration(
                hintText: 'Say something that helps people pick up your vibe.',
                hintStyle: TextStyle(
                  color: colors.onSurface.withValues(alpha: 0.5),
                  fontSize: 14,
                ),
                filled: true,
                fillColor: theme.brightness == Brightness.dark
                    ? colors.surface.withValues(alpha: 0.75)
                    : const Color(0xFFF8FBFD),
                contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: theme.brightness == Brightness.dark
                        ? colors.onSurface.withValues(alpha: 0.14)
                        : const Color(0xFFE6EEF4),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: theme.brightness == Brightness.dark
                        ? colors.onSurface.withValues(alpha: 0.14)
                        : const Color(0xFFE6EEF4),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppTheme.brandPrimary.withValues(alpha: 0.45),
                    width: 1.1,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'What brings you to Kmstry?',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Select one or more (up to 3)',
              style: TextStyle(
                color: colors.onSurface.withValues(alpha: 0.65),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'This is optional, but it helps us rank people at the venue '
              'from most compatible to least compatible for you.',
              style: TextStyle(
                color: colors.onSurface.withValues(alpha: 0.7),
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            if (_isLoadingOptions)
              const Center(child: CircularProgressIndicator())
            else
              GestureDetector(
                onTap: _openWhatBringsSelector,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? colors.surface : const Color(0xFFF8FBFD),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.brandPrimary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _selectedWhatBrings.isEmpty
                              ? 'Select options'
                              : _selectedWhatBrings
                                    .map(_formatOptionLabel)
                                    .join(', '),
                          style: TextStyle(
                            color: _selectedWhatBrings.isEmpty
                                ? colors.onSurface.withValues(alpha: 0.5)
                                : colors.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 40),

            /// CHECK IN BUTTON
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: (_media.isEmpty || _isSubmitting)
                    ? null
                    : _submitCheckin,
                style: ElevatedButton.styleFrom(
                  foregroundColor: theme.brightness == Brightness.dark
                      ? Colors.black
                      : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isSubmitting
                    ? CircularProgressIndicator(
                        color: theme.brightness == Brightness.dark
                            ? Colors.black
                            : Colors.white,
                      )
                    : Text(
                        'Check in',
                        style: TextStyle(
                          color: theme.brightness == Brightness.dark
                              ? Colors.black
                              : Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  /// Fotoğraf kutusu tasarımı (Yıldızlı seçim özelliği ile)
  Widget _buildMediaBox({
    required int index,
    required bool isFeatured,
    required LocalMedia media,
  }) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    double size = (MediaQuery.of(context).size.width - 64) / 3;

    final child = media.type == MediaType.photo
        ? ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(
              media.file,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: isDark ? colors.surface : const Color(0xFFF8FBFD),
              child: const Center(
                child: Icon(
                  Icons.play_circle_fill,
                  color: Colors.white,
                  size: 42,
                ),
              ),
            ),
          );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () => _setFeatured(index),
          child: Container(
            width: size,
            height: size * 1.3,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: isDark
                  ? colors.surface.withValues(alpha: 0.8)
                  : const Color(0xFFF8FBFD),
              border: isFeatured
                  ? Border.all(color: AppTheme.brandPrimary, width: 2.5)
                  : null,
            ),
            child: child,
          ),
        ),

        // Delete button
        Positioned(
          top: -5,
          right: -5,
          child: GestureDetector(
            onTap: () => _removeMedia(index),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.72)
                    : Colors.black.withValues(alpha: 0.64),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18),
                  width: 0.8,
                ),
              ),
              child: const Icon(Icons.close, size: 12, color: Colors.white),
            ),
          ),
        ),

        // Featured star
        if (isFeatured)
          Positioned(
            left: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark ? colors.surface : const Color(0xFFF8FBFD),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.star, size: 14, color: Color(0xFFFFD700)),
            ),
          ),
      ],
    );
  }

  /// Yeni fotoğraf ekleme kutusu
  Widget _buildAddBox() {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    double size = (MediaQuery.of(context).size.width - 64) / 3;

    return GestureDetector(
      onTap: _openCameraAndAddMedia,
      child: Container(
        width: size,
        height: size * 1.3,
        decoration: BoxDecoration(
          color: isDark ? colors.surface : const Color(0xFFF8FBFD),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colors.primary.withValues(alpha: 0.25),
            width: 2,
          ),
        ),
        child: Icon(
          Icons.add,
          size: 30,
          color: colors.onSurface.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}
