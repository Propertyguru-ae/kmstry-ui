import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/permissions/location_permission_service.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/checkin/services/active_checkin_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:kmstry_frontend/features/camera/presentation/camera_screen.dart';
import 'package:kmstry_frontend/features/camera/presentation/preview_video_screen.dart';
import 'package:kmstry_frontend/features/media/media_compressor.dart';
import 'package:kmstry_frontend/features/media/media_text_overlay.dart';
import 'package:kmstry_frontend/features/media/text_overlay_composer.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

enum MediaType { photo, video }

class LocalMedia {
  final File file;
  final MediaType type;
  final String? thumbnailPath;

  /// Video üzerine eklenen metin overlay'i (client-render; videoya gömülmez).
  final MediaTextOverlay? textOverlay;

  LocalMedia({
    required this.file,
    required this.type,
    this.thumbnailPath,
    this.textOverlay,
  });
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
  // Senkron reentrancy kilidi — konum/GPS await'leri sürerken ikinci dokunuşun
  // ikinci bir check-in oluşturmasını engeller (buton-disable tek başına yetmez,
  // çünkü _isSubmitting create'ten hemen önce, await'lerden sonra set ediliyor).
  bool _submitLock = false;
  // Sıkıştırma SONRASI üst sınır. 60 sn'lik sıkıştırılmış video bunun altında
  // kalır; backend limiti 80MB, bu yüzden güvenli bir tampon bırakıyoruz.
  static const int _maxVideoUploadBytes = 50 * 1024 * 1024;
  static const int _vibeMaxLength = 150;
  // Aynı anda en fazla kaç medya yüklensin (paralel upload). Cihazı/bağlantıyı
  // boğmadan hız kazandıran denge değeri.
  static const int _maxConcurrentUploads = 3;

  // Upload progress state
  int _uploadCurrent = 0;
  int _uploadTotal = 1;
  String _uploadStepLabel = '';

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
                                  ? AppTheme.brandPrimary.withValues(
                                      alpha: 0.12,
                                    )
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

  /// Kalıcı profil bio'su varsa vibe alanına varsayılan olarak yüklenir.
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
        lower.endsWith('.webm') ||
        lower.endsWith('.3gp') ||
        lower.endsWith('.mkv')) {
      return MediaType.video;
    }
    return MediaType.photo;
  }

  Future<String?> _generateVideoThumbnail(String videoPath) async {
    try {
      return await VideoThumbnail.thumbnailFile(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 256,
        quality: 75,
      );
    } catch (_) {
      return null;
    }
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

    // Fotoğraf akışı File, video akışı CapturedMedia (dosya + text overlay) döner.
    final dynamic result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const CameraScreen(useFrontCamera: true, optimizeForUpload: true),
      ),
    );

    if (result == null) return;
    final File captured = result is CapturedMedia
        ? result.file
        : result as File;
    final MediaTextOverlay? capturedOverlay = result is CapturedMedia
        ? result.overlay
        : null;

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

    String? thumbPath;
    if (selectedType == MediaType.video) {
      thumbPath = await _generateVideoThumbnail(captured.path);
    }

    if (!mounted) return;
    setState(() {
      _media.add(
        LocalMedia(
          file: File(captured.path),
          type: selectedType,
          thumbnailPath: thumbPath,
          textOverlay: capturedOverlay,
        ),
      );
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

  /// Fotoğrafı öne çıkan olarak işaretleme (yalnızca fotoğraf kartlarındaki
  /// yıldız rozetinden çağrılır).
  void _setFeatured(int index) {
    if (_media[index].type != MediaType.photo) return;
    setState(() {
      _featuredIndex = index;
    });
  }

  /// Karta basınca eklenen medyayı büyük ekranda tekrar gösterir —
  /// kullanıcı check-in için ne eklediğini görebilsin.
  void _openMediaPreview(int index) {
    final media = _media[index];
    if (media.type == MediaType.video) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PreviewVideoScreen(
            file: media.file,
            viewOnly: true,
            overlay: media.textOverlay,
          ),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _CheckinPhotoPreviewScreen(file: media.file),
      ),
    );
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
    if (_submitLock) return;
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

    // Kilidi ilk kritik await'ten (konum izni) hemen önce senkron olarak al —
    // check ile set arasında await yok, yani ikinci dokunuş garanti bloklanır.
    if (_submitLock) return;
    _submitLock = true;
    // Butona basılır basılmaz ANINDA feedback: buton inactive olur ve overlay
    // "Getting your location..." ile açılır. (GPS high-accuracy 1-3 sn sürebilir;
    // eskiden bu süre boyunca buton boş duruyordu.)
    if (mounted) {
      setState(() {
        _isSubmitting = true;
        _uploadCurrent = 0;
        _uploadTotal = 1 + _media.length;
        _uploadStepLabel = 'Getting your location...';
      });
    }

    final hasLocationPermission = await _ensureLocationPermissionForCheckin();
    if (!hasLocationPermission) {
      _submitLock = false;
      if (mounted) setState(() => _isSubmitting = false);
      return;
    }

    // Gerçek cihaz konumu — backend, gerçek (test dışı) venue'lerde bunu venue
    // koordinatlarıyla karşılaştırıp 200m mesafe sınırını uygular. Alpha/Beta
    // test venue'lerinde backend mesafe kontrolünü zaten atlıyor (is_test_venue).
    //
    // HIZ: venue detay sayfası saniyeler önce taze bir GPS okuması yaptı ve OS
    // bunu cache'ledi. Burada önce getLastKnownPosition'ı (neredeyse anında)
    // kullanıyoruz; yoksa taze okumaya düşüyoruz. Backend kesin kontrolü zaten
    // yapıyor, o yüzden anlık koordinat yeterli.
    double latitude;
    double longitude;
    try {
      Position? position = await Geolocator.getLastKnownPosition();
      position ??= await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );
      latitude = position.latitude;
      longitude = position.longitude;
    } catch (_) {
      _submitLock = false;
      if (mounted) setState(() => _isSubmitting = false);
      if (mounted) {
        await showPremiumErrorDialog(
          context,
          message: 'Could not get your location. Please try again.',
        );
      }
      return;
    }

    if (mounted) {
      setState(() => _uploadStepLabel = 'Creating check-in...');
    }

    String? createdCheckinId;
    try {
      // 1️⃣ Check-in oluştur
      final vibeText = _vibeController.text.trim();
      final checkinId = await _repo.createCheckin(
        venueId: widget.venueId,
        latitude: latitude,
        longitude: longitude,
        vibe: vibeText,
        whatBringsYou: _selectedWhatBrings.toList(),
      );
      createdCheckinId = checkinId;
      ActiveCheckinService().setActiveCheckin(
        checkinId,
        venueId: widget.venueId,
      );

      if (mounted) setState(() => _uploadCurrent = 1);

      try {
        await AuthRepository().updateMe({'bio': vibeText});
      } catch (_) {}

      // 2️⃣ Medyaları paralel (en fazla 3 eş zamanlı) yükle.
      await _uploadCheckinMediaParallel(
        checkinId: checkinId,
        featuredPhotoIndex: _featuredPhotoIndex,
      );

      // ✅ Başarılı
      unawaited(MediaCompressor.cleanup());
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      debugPrint('❌ Check-in error: $e');
      if (createdCheckinId != null) {
        try {
          await _repo.checkout(createdCheckinId);
          ActiveCheckinService().clear();
        } catch (cleanupError) {
          debugPrint('⚠️ Check-in rollback failed: $cleanupError');
        }
      }
      if (!mounted) return;
      final raw = e.toString();
      if (raw.contains('Media upload failed (413)') ||
          raw.contains('413 Request Entity Too Large')) {
        await showPremiumErrorDialog(
          context,
          message:
              'Video boyutu sunucu limitini asiyor. Lutfen daha kisa bir video cekin.',
        );
      } else {
        await showPremiumErrorDialog(
          context,
          message: 'Check-in su an tamamlanamadi. Lutfen tekrar deneyin.',
        );
      }
    } finally {
      _submitLock = false;
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Medyaları en fazla [_maxConcurrentUploads] eş zamanlı olacak şekilde
  /// yükler — 6 fotoğraf tek tek beklemek yerine paralel gider, belirgin hızlı
  /// ve smooth hissettirir. Herhangi biri başarısız olursa hata yukarı fırlar
  /// ve dıştaki catch tüm check-in'i rollback eder (tutarlılık korunur).
  Future<void> _uploadCheckinMediaParallel({
    required String checkinId,
    required int featuredPhotoIndex,
  }) async {
    const maxConcurrent = _maxConcurrentUploads;
    var completed = 0;

    for (var start = 0; start < _media.length; start += maxConcurrent) {
      final end = (start + maxConcurrent).clamp(0, _media.length);
      await Future.wait([
        for (var i = start; i < end; i++)
          _uploadSingleMedia(
            checkinId: checkinId,
            index: i,
            isFeatured:
                _media[i].type == MediaType.photo && i == featuredPhotoIndex,
          ).then((_) {
            completed += 1;
            if (mounted) setState(() => _uploadCurrent = 1 + completed);
          }),
      ]);
    }
  }

  Future<void> _uploadSingleMedia({
    required String checkinId,
    required int index,
    required bool isFeatured,
  }) async {
    final item = _media[index];
    final isVideo = item.type == MediaType.video;

    // 1️⃣ Video ise yüklemeden önce sıkıştır — hem mobil veriyi hem yükleme
    //    süresini ciddi azaltır. Fotoğraflar çekimde zaten 720px'e küçültülüyor.
    File fileToUpload = item.file;
    if (isVideo) {
      if (mounted) {
        setState(() => _uploadStepLabel = 'Compressing video...');
      }
      fileToUpload = await MediaCompressor.compressVideo(item.file);

      final sizeBytes = await fileToUpload.length();
      if (sizeBytes > _maxVideoUploadBytes) {
        throw Exception('Video file is too large');
      }
    }

    if (mounted) {
      setState(() {
        _uploadStepLabel = isVideo
            ? 'Uploading video... this may take a moment'
            : 'Uploading photos...';
      });
    }

    final overlayJson = item.textOverlay?.toJsonString();

    // 2️⃣ Doğrudan Spaces'e (presigned URL) yükle — dosya backend'e uğramaz,
    //    daha hızlı ve backend'i yormaz. Herhangi bir aşama başarısız olursa
    //    stabil multipart yoluna düşerek yüklemeyi garanti altına alırız.
    try {
      final target = await _repo.createCheckinMediaUploadUrl(
        checkinId: checkinId,
        file: fileToUpload,
      );
      await _repo.uploadFileToSignedUrl(target: target, file: fileToUpload);
      await _repo.confirmCheckinMediaUpload(
        checkinId: checkinId,
        target: target,
        file: fileToUpload,
        isFeatured: isFeatured,
        textOverlayJson: overlayJson,
      );
    } catch (e) {
      debugPrint('⚠️ Direct upload failed, falling back to multipart: $e');
      await _repo.uploadCheckinMedia(
        checkinId: checkinId,
        file: fileToUpload,
        isFeatured: isFeatured,
        textOverlayJson: overlayJson,
      );
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
      body: Stack(
        children: [
          SingleChildScrollView(
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
                    hintText:
                        'Say something that helps people pick up your vibe.',
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
                        color: isDark
                            ? colors.surface
                            : const Color(0xFFF8FBFD),
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

          // ── Upload progress overlay ─────────────────────────────────────
          if (_isSubmitting) _buildUploadOverlay(theme),
        ],
      ),
    );
  }

  Widget _buildUploadOverlay(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final progress = _uploadTotal > 0
        ? (_uploadCurrent / _uploadTotal).clamp(0.0, 1.0)
        : null;

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Spinner
              SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 3.5,
                  backgroundColor: AppTheme.brandPrimary.withValues(
                    alpha: 0.18,
                  ),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppTheme.brandPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Step label
              Text(
                _uploadStepLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),

              // Linear progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: AppTheme.brandPrimary.withValues(
                    alpha: 0.15,
                  ),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppTheme.brandPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Sadece medya yüklenirken sade bir sayaç göster ("1 / 2 steps"
              // gibi teknik ifade yerine kullanıcı dostu). Hazırlık/oluşturma
              // aşamasında hiç sayı gösterme.
              Text(
                _media.length > 1 && _uploadCurrent > 1
                    ? 'Uploading ${(_uploadCurrent - 1).clamp(1, _media.length)} of ${_media.length}'
                    : 'Please wait...',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (media.thumbnailPath != null)
                  Image.file(File(media.thumbnailPath!), fit: BoxFit.cover)
                else
                  Container(
                    color: isDark ? colors.surface : const Color(0xFFF8FBFD),
                  ),
                const Center(
                  child: Icon(
                    Icons.play_circle_fill,
                    color: Colors.white,
                    size: 42,
                  ),
                ),
              ],
            ),
          );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          // Karta bas → medyayı büyük ekranda önizle.
          onTap: () => _openMediaPreview(index),
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

        // Featured star — fotoğraf kartlarında her zaman görünür ve tıklanabilir:
        // dolu altın yıldız = öne çıkan, soluk yıldız = basınca öne çıkar.
        if (media.type == MediaType.photo)
          Positioned(
            left: 8,
            bottom: 8,
            child: GestureDetector(
              onTap: () => _setFeatured(index),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDark ? colors.surface : const Color(0xFFF8FBFD),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  isFeatured ? Icons.star : Icons.star_border,
                  size: 14,
                  color: isFeatured
                      ? const Color(0xFFFFD700)
                      : colors.onSurface.withValues(alpha: 0.45),
                ),
              ),
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

/// Check-in'e eklenen fotoğrafı büyük ekranda tekrar gösteren salt-izleme
/// ekranı. Pinch-zoom destekler; boşluğa veya kapat butonuna basınca kapanır.
/// İndir butonu fotoğrafı galeriye kaydeder.
class _CheckinPhotoPreviewScreen extends StatefulWidget {
  final File file;

  const _CheckinPhotoPreviewScreen({required this.file});

  @override
  State<_CheckinPhotoPreviewScreen> createState() =>
      _CheckinPhotoPreviewScreenState();
}

class _CheckinPhotoPreviewScreenState
    extends State<_CheckinPhotoPreviewScreen> {
  bool _saving = false;

  Future<void> _download() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await Gal.putImage(widget.file.path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved to gallery'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } on GalException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.type == GalExceptionType.accessDenied
                ? 'Photo library permission is required to save.'
                : 'Could not save. Please try again.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Image.file(
                    widget.file,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Icon(
                        Icons.broken_image,
                        size: 64,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: Column(
              children: [
                Material(
                  color: Colors.black38,
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
                const SizedBox(height: 12),
                Material(
                  color: Colors.black38,
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.download_rounded,
                            color: Colors.white,
                          ),
                    onPressed: _download,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
