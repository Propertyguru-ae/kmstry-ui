import 'dart:developer';
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/media/media_text_overlay.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'package:kmstry_frontend/core/media/signed_media_resolver.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/media_upload_progress_dialog.dart';
import 'package:kmstry_frontend/core/ui/media_viewer_buttons.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/features/camera/presentation/camera_route.dart';
import 'package:kmstry_frontend/features/camera/presentation/camera_screen.dart';
import 'package:kmstry_frontend/features/media/text_overlay_composer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:kmstry_frontend/features/checkin/services/avatar_crop_helper.dart';
import 'package:kmstry_frontend/features/checkin/services/active_checkin_service.dart';
import 'package:kmstry_frontend/features/reports/presentation/report_user_sheet.dart';
import '../../checkin/data/checkin_repository.dart';
import '../../checkin/data/checkin_profile_model.dart';
import '../../checkin/data/owner_moment_sequence.dart';
import '../../content_moderation/data/pending_public_media.dart';
import '../../stories/presentation/owner_story_upload.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

/// Keep the originating profile visible underneath an interactive dismissal.
Route<bool> momentsViewerRoute({required WidgetBuilder builder}) =>
    PageRouteBuilder<bool>(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    );

class MomentsViewerPage extends StatefulWidget {
  final List<CheckinProfileMedia> media;
  final int initialIndex;
  final bool allowFeature;
  final String? checkinId;
  final String? reportedUserId;
  final CheckinRepository? repository;
  final void Function(String mediaId, bool checkinInactivated)? onDeleted;
  final String? pendingUploadId;
  final PendingPublicMediaService? uploads;
  final VoidCallback? onCreateMoment;

  const MomentsViewerPage({
    super.key,
    required this.media,
    required this.initialIndex,
    this.allowFeature = false,
    this.checkinId,
    this.reportedUserId,
    this.repository,
    this.onDeleted,
    this.pendingUploadId,
    this.uploads,
    this.onCreateMoment,
  });

  @override
  State<MomentsViewerPage> createState() => _MomentsViewerPageState();
}

class _MomentsViewerPageState extends State<MomentsViewerPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const double _dismissDragDistance = 90;
  static const double _dismissDragVelocity = 650;
  late final AnimationController _dismissController;
  bool _dismissing = false;
  late PageController _controller;
  late int _currentIndex;
  late final CheckinRepository _repo;
  bool _loading = false; // sadece "featured yap" işlemi (yıldız spinner'ı)
  bool _deleting = false;
  late List<CheckinProfileMedia> _media;
  bool _hasChanged = false;
  VideoPlayerController? _videoController;
  int _setupSeq = 0;
  late final PendingPublicMediaService _uploads =
      widget.uploads ?? PendingPublicMediaService.instance;
  late final int _uploadSession;
  OwnerMomentSequence? _ownerSequence;
  List<OwnerMomentEntry> _entries = [];
  bool _closingUpload = false;
  bool _paused = false;
  OwnerMomentEntry? get _currentEntry =>
      _entries.isEmpty ? null : _entries[_currentIndex];

  Widget _withTextOverlay(CheckinProfileMedia item, Widget child) {
    if (item.textOverlay == null) return child;
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        MediaTextOverlayView(overlay: item.textOverlay!),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _dismissController = AnimationController.unbounded(vsync: this);
    _uploadSession = _uploads.sessionGeneration;

    // 🔥 HATA BURADAYDI
    _media = List.from(widget.media);
    _repo = widget.repository ?? CheckinRepository();

    _entries = [for (final item in _media) OwnerMomentEntry(media: item)];
    if (widget.allowFeature && widget.checkinId != null) {
      WidgetsBinding.instance.addObserver(this);
      _ownerSequence = OwnerMomentSequence(
        checkinId: widget.checkinId!,
        published: _media,
        uploads: _uploads,
        loadPublished: () => _repo.getCheckinProfile(widget.checkinId!),
      );
      _entries = _ownerSequence!.entries;
      _ownerSequence!.addListener(_onUploadChanged);
    }
    _currentIndex = _entries.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, _entries.length - 1);
    if (widget.pendingUploadId != null) {
      final index = _ownerSequence?.indexOf(widget.pendingUploadId!) ?? -1;
      if (index >= 0) {
        _currentIndex = index;
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => _closeUpload());
      }
    }
    _controller = PageController(initialPage: _currentIndex);

    // İlk item video ise başlat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupVideoIfNeeded(_currentIndex);
    });
  }

  void _onUploadChanged() {
    if (!mounted || _closingUpload) return;
    final sequence = _ownerSequence!;
    final previous = _currentEntry;
    final next = sequence.entries;
    if (!sequence.sessionValid || next.isEmpty) {
      _closeUpload();
      return;
    }
    final matching = previous == null ? -1 : sequence.indexOf(previous.key);
    final index = matching >= 0
        ? matching
        : _currentIndex.clamp(0, next.length - 1);
    final mediaChanged =
        previous?.key != next[index].key ||
        (previous?.pending != null) != (next[index].pending != null);
    setState(() {
      _entries = next;
      _media = List.of(sequence.published);
      _currentIndex = index;
      if (previous?.pending != null && next[index].media != null) {
        _hasChanged = true;
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _closingUpload) return;
      if (_controller.hasClients &&
          (_controller.page?.round() ?? index) != index) {
        _controller.jumpToPage(index);
      }
      if (mediaChanged) unawaited(_setupVideoIfNeeded(index));
    });
  }

  void _closeUpload() {
    if (!mounted || _closingUpload) return;
    setState(() => _closingUpload = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, _hasChanged);
    });
  }

  void _handleVerticalDragStart(DragStartDetails _) {
    if (_closingUpload || _dismissing) return;
    _dismissController.stop();
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    if (_closingUpload || _dismissing) return;
    _dismissController.value =
        (_dismissController.value + (details.primaryDelta ?? 0)).clamp(
          0.0,
          MediaQuery.sizeOf(context).height,
        );
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    if (_closingUpload || _dismissing) return;
    final dismiss =
        _dismissController.value > _dismissDragDistance ||
        (details.primaryVelocity ?? 0) > _dismissDragVelocity;
    unawaited(_finishVerticalDrag(dismiss: dismiss));
  }

  void _handleVerticalDragCancel() {
    if (!_closingUpload && !_dismissing) {
      unawaited(_finishVerticalDrag(dismiss: false));
    }
  }

  Future<void> _finishVerticalDrag({required bool dismiss}) async {
    _dismissing = dismiss;
    try {
      await _dismissController
          .animateTo(
            dismiss ? MediaQuery.sizeOf(context).height : 0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          )
          .orCancel;
    } on TickerCanceled {
      return;
    }
    if (mounted && dismiss) _closeUpload();
  }

  Future<void> _createMoment() async {
    final pending = _currentEntry?.pending;
    final route = ModalRoute.of(context);
    final create = widget.onCreateMoment;
    _closeUpload();
    if (pending != null && ownerStoryHasNoPreview(pending)) {
      _uploads.dismiss(pending.id);
    }
    await route?.completed;
    if (_uploads.isCurrentSession(_uploadSession)) create?.call();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) setState(() => _paused = state != AppLifecycleState.resumed);
  }

  Future<void> _setupVideoIfNeeded(int index) async {
    if (_closingUpload || index < 0 || index >= _entries.length) return;
    final seq = ++_setupSeq;
    _videoController?.dispose();
    _videoController = null;
    final item = _entries[index].media;
    if (item == null) return;
    if (item.mediaType != MediaType.video) return;

    var mediaUrl = item.url;
    final reference = item.mediaReference;
    if (reference != null &&
        reference.canRefresh &&
        (mediaUrl.isEmpty ||
            reference.expiresAt?.isBefore(
                  DateTime.now().add(const Duration(seconds: 10)),
                ) ==
                true)) {
      final refreshed = await SignedMediaResolver.instance.refreshOnce(
        reference,
      );
      if (refreshed != null && refreshed.url.isNotEmpty) {
        mediaUrl = refreshed.url;
      }
    }
    if (!mounted || _closingUpload || mediaUrl.isEmpty || seq != _setupSeq) {
      return;
    }

    final controller = VideoPlayerController.networkUrl(Uri.parse(mediaUrl));

    try {
      await controller.initialize();
    } catch (error) {
      log('Moment video initialize error: $error');
      await controller.dispose();
      return;
    }

    // Eğer bu arada yeni bir setup çağrısı geldiyse bu sonucu kullanma
    if (!mounted || _closingUpload || seq != _setupSeq) {
      controller.dispose();
      return;
    }

    await controller.setLooping(true);
    await controller.play();

    _videoController = controller;

    if (mounted) setState(() {});
  }

  Future<void> _setFeatured() async {
    final selected = _currentEntry!.media!;
    if (selected.mediaType != MediaType.photo) {
      await showPremiumErrorDialog(
        context,
        message: 'Only photos can be featured.',
      );
      return;
    }

    try {
      setState(() => _loading = true);
      await _repo.setFeaturedPhoto(selected.id);
      if (!_uploads.isCurrentSession(_uploadSession)) return;
      if (!selected.isFeatured && widget.checkinId != null) {
        for (final crop in _uploads.forKind(
          PendingPublicMediaKind.checkinAvatar,
        )) {
          if (crop.checkinId == widget.checkinId) _uploads.dismiss(crop.id);
        }
        ActiveCheckinService().featuredPhotoChanged(
          checkinId: widget.checkinId!,
          mediaId: selected.id,
          url: selected.url,
          reference: selected.mediaReference,
        );
      }
      ActiveCheckinService().notifyMediaUpdated();
      if (!mounted) return;

      setState(() {
        _media = _media.map((m) {
          return m.copyWith(isFeatured: m.id == selected.id);
        }).toList();
        _hasChanged = true;
      });
      _ownerSequence?.updatePublished(_media);
    } catch (e) {
      log("Feature error: $e");
      if (!mounted) return;
      await showPremiumErrorDialog(
        context,
        message: 'Failed to set featured media',
      );
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      if (mounted) {
        await _showFeaturedCropPrompt(selected);
      }
    } catch (e) {
      log("Featured avatar crop/upload error: $e");
      if (mounted) {
        await showPremiumErrorDialog(
          context,
          message: 'Featured updated, but avatar crop could not be saved.',
        );
      }
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _reportCurrentMedia() async {
    final targetUserId = widget.reportedUserId;
    if (_media.isEmpty || targetUserId == null || targetUserId.isEmpty) return;

    await _videoController?.pause();
    if (!mounted) return;
    final reported = await showReportUserSheet(
      context,
      targetUserId: targetUserId,
      title: 'Report this moment?',
      checkinMediaId: _currentEntry!.media!.id,
    );
    if (!mounted) return;
    if (reported) {
      Navigator.pop(context, true);
      return;
    }
    if (_videoController?.value.isInitialized == true) {
      await _videoController?.play();
    }
  }

  Future<void> _showFeaturedCropPrompt(CheckinProfileMedia selected) async {
    final checkinId = widget.checkinId;
    if (checkinId == null || checkinId.isEmpty) return;

    final colors = Theme.of(context).colorScheme;
    final shouldCrop = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.onSurface.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Use as your check-in avatar?',
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Adjust how this featured photo appears on your profile while this check-in is active.',
                  style: TextStyle(
                    color: colors.onSurface.withValues(alpha: 0.62),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.crop_rounded),
                  title: const Text('Adjust crop'),
                  onTap: () => Navigator.pop(ctx, true),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.check_circle_outline_rounded),
                  title: const Text('Use as is'),
                  onTap: () => Navigator.pop(ctx, false),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (shouldCrop != true || !mounted) return;

    final localFile = await _downloadMediaToTemp(selected);
    if (!mounted) return;
    if (localFile == null) {
      throw Exception('Could not download selected featured photo for crop');
    }

    final cropped = await cropSquareAvatar(context, localFile);
    if (!mounted ||
        cropped == null ||
        !_uploads.isCurrentSession(_uploadSession)) {
      return;
    }

    await _repo.uploadCheckinAvatar(checkinId: checkinId, file: cropped);
    _hasChanged = true;
  }

  Future<File?> _downloadMediaToTemp(CheckinProfileMedia media) async {
    try {
      var mediaUrl = media.url;
      final reference = media.mediaReference;
      if (reference != null &&
          reference.canRefresh &&
          (mediaUrl.isEmpty ||
              reference.expiresAt?.isBefore(
                    DateTime.now().add(const Duration(seconds: 10)),
                  ) ==
                  true)) {
        final refreshed = await SignedMediaResolver.instance.refreshOnce(
          reference,
        );
        if (refreshed != null && refreshed.url.isNotEmpty) {
          mediaUrl = refreshed.url;
        }
      }
      if (mediaUrl.isEmpty) return null;
      final response = await http.get(Uri.parse(mediaUrl));
      if (response.statusCode >= 400) return null;
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/kmstry-featured-avatar-${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(response.bodyBytes, flush: true);
      return file;
    } catch (e) {
      log('Featured avatar download error: $e');
      return null;
    }
  }

  Future<void> _deleteMedia(CheckinProfileMedia media) async {
    final isLastMoment = _media.length == 1;
    final choice = await _confirmDelete(media, isLastMoment: isLastMoment);
    if (!mounted) return;
    if (choice == _DeleteChoice.retake) {
      await _retakeMoment(media);
      return;
    }
    if (choice != _DeleteChoice.delete) return;

    setState(() => _deleting = true);
    final session = PendingPublicMediaService.instance.sessionGeneration;

    try {
      final checkinInactivated = await _repo.deletePhoto(media.id);
      if (!PendingPublicMediaService.instance.isCurrentSession(session)) return;

      widget.onDeleted?.call(media.id, checkinInactivated);
      if (checkinInactivated) {
        ActiveCheckinService().clear();
      } else {
        ActiveCheckinService().notifyMediaUpdated();
      }
      // A successful delete still updates the parent if the viewer was closed
      // while the request was in flight. Never update a different session.
      if (!mounted) return;

      // Story mantığı: silinince listeden çıkar. Başka post varsa bir sonrakini
      // göster; hiç kalmadıysa kapanıp profile dön.
      _media.removeWhere((m) => m.id == media.id);
      _hasChanged = true;
      if (_ownerSequence != null) {
        _ownerSequence!.removePublished(media.id);
        if (checkinInactivated) _closeUpload();
        if (mounted) setState(() => _deleting = false);
        return;
      }
      _entries = [for (final item in _media) OwnerMomentEntry(media: item)];

      if (_media.isEmpty) {
        if (checkinInactivated) {
          showSuccessSnackBar(
            context,
            message: 'Moment deleted. Your check-in is now inactive.',
            icon: Icons.location_off_outlined,
          );
        }
        Navigator.pop(context, true);
        return;
      }

      // Silinen item mevcut index'teydi; liste kaydığı için aynı index artık
      // bir sonraki postu gösterir. Son item silindiyse bir geri git.
      final newIndex = _currentIndex >= _media.length
          ? _media.length - 1
          : _currentIndex;

      setState(() {
        _currentIndex = newIndex;
        _deleting = false;
      });
      _controller.jumpToPage(newIndex);
      await _setupVideoIfNeeded(newIndex);
      return;
    } catch (e) {
      log("Delete error: $e");
      if (!mounted) return;
      await showPremiumErrorDialog(
        context,
        message: 'Moment could not be deleted. Please try again.',
      );
    }

    if (mounted) setState(() => _deleting = false);
  }

  Future<_DeleteChoice> _confirmDelete(
    CheckinProfileMedia media, {
    required bool isLastMoment,
  }) async {
    final typeLabel = media.mediaType == MediaType.video ? 'video' : 'photo';
    // Retake yalnızca son moment'ta ve kendi check-in'imizde anlamlı: yeni
    // çekim eskisinin yerine geçer, check-in aktif kalır.
    final canRetake = isLastMoment && (widget.checkinId?.isNotEmpty ?? false);
    final title = isLastMoment
        ? 'Delete your last moment?'
        : 'Delete $typeLabel?';
    final message = isLastMoment
        ? canRetake
              ? 'Your check-in stays active only while you have at least one moment. Retake it to keep your check-in going.'
              : 'Your check-in stays active only while you have at least one moment. Deleting this will end your check-in.'
        : 'This $typeLabel will be removed from your Moments. This can\'t be undone.';

    // Light/dark uyumlu popup — uygulamanın premium dialog paleti
    // (showPremiumPromptDialog) ile aynı yüzey/metin renkleri. İçerik ortalı,
    // butonlar alt alta ve popup genişliğinde.
    final result = await showDialog<_DeleteChoice>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        final surface = isDark ? const Color(0xFF121A2B) : Colors.white;
        final borderColor = isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.05);
        final titleColor = isDark ? Colors.white : AppColors.lightTextPrimary;
        final bodyColor = isDark
            ? const Color(0xFFB4C2D8)
            : AppColors.lightTextSecondary;
        // Koyu zeminde okunaklı kalması için dark'ta daha açık kırmızı.
        final danger = isDark
            ? const Color(0xFFFF6B6B)
            : const Color(0xFFE5484D);

        void pick(_DeleteChoice c) => Navigator.of(dialogContext).pop(c);
        final buttonShape = RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        );
        const buttonText = TextStyle(
          fontSize: 15.5,
          fontWeight: FontWeight.w700,
        );

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 14),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.18),
                  blurRadius: 34,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: danger.withValues(alpha: isDark ? 0.16 : 0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      color: danger,
                      size: 30,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: bodyColor,
                    fontSize: 14.5,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 22),
                if (canRetake) ...[
                  // Birincil (olumlu) aksiyon: standart mavi buton.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: AppColors.blue,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.blue.withValues(
                            alpha: isDark ? 0.30 : 0.22,
                          ),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: FilledButton.icon(
                      onPressed: () => pick(_DeleteChoice.retake),
                      icon: const Icon(Icons.camera_alt_rounded, size: 19),
                      label: const Text('Retake', style: buttonText),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shape: buttonShape,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // İkincil yıkıcı aksiyon: tonal (yumuşak kırmızı dolgu) —
                  // gradient butonla yarışmaz, iki temada da dengeli durur.
                  FilledButton(
                    onPressed: () => pick(_DeleteChoice.delete),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      elevation: 0,
                      backgroundColor: danger.withValues(
                        alpha: isDark ? 0.16 : 0.10,
                      ),
                      foregroundColor: danger,
                      overlayColor: danger.withValues(alpha: 0.12),
                      shape: buttonShape,
                    ),
                    child: const Text(
                      'Delete & end check-in',
                      style: buttonText,
                    ),
                  ),
                ] else
                  FilledButton(
                    onPressed: () => pick(_DeleteChoice.delete),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      elevation: 0,
                      backgroundColor: danger,
                      foregroundColor: Colors.white,
                      shape: buttonShape,
                    ),
                    child: Text(
                      isLastMoment ? 'Delete & end check-in' : 'Delete',
                      style: buttonText,
                    ),
                  ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => pick(_DeleteChoice.cancel),
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    foregroundColor: bodyColor,
                    shape: buttonShape,
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    return result ?? _DeleteChoice.cancel;
  }

  /// Son moment'ı yeniden çek: kamera açılır, yeni foto/video yüklenir ve
  /// backend eskisini (replaceMediaId) yeni kayıttan SONRA siler — check-in
  /// hiçbir an moment'sız kalmaz, inaktif olmaz.
  Future<void> _retakeMoment(CheckinProfileMedia oldMedia) async {
    final checkinId = widget.checkinId;
    if (checkinId == null || checkinId.isEmpty) return;

    await _videoController?.pause();

    final camera = await Permission.camera.request();
    if (!mounted) return;
    if (!camera.isGranted) {
      await showPremiumErrorDialog(
        context,
        title: 'Camera access needed',
        message: 'Allow camera access in Settings to retake your Moment.',
      );
      return;
    }

    final dynamic captureResult = await Navigator.of(context).push(
      cameraRoute(
        builder: (_) => const CameraScreen.publicMedia(
          useFrontCamera: true,
          optimizeForUpload: true,
        ),
      ),
    );
    if (!mounted) return;

    final File? file = captureResult is CapturedMedia
        ? captureResult.file
        : captureResult as File?;
    final overlay = captureResult is CapturedMedia
        ? captureResult.overlay
        : null;
    if (file == null) {
      // Kamera iptal edildi — mevcut moment'a geri dön.
      if (_videoController?.value.isInitialized == true) {
        await _videoController?.play();
      }
      return;
    }

    final path = file.path.toLowerCase();
    final isVideo =
        path.endsWith('.mp4') ||
        path.endsWith('.mov') ||
        path.endsWith('.avi') ||
        path.endsWith('.m4v');

    final progress = MediaUploadProgressController(
      title: 'Updating your Moment',
      message: isVideo
          ? 'Uploading your new video…'
          : 'Uploading your new photo…',
    );
    await progress.show(context);

    Object? error;
    try {
      await _repo.uploadCheckinMedia(
        checkinId: checkinId,
        file: file,
        // Tek moment olacağı için yeni fotoğraf featured olur (video olamaz).
        isFeatured: !isVideo,
        textOverlayJson: overlay?.toJsonString(),
        replaceMediaId: oldMedia.id,
      );
    } catch (e) {
      error = e;
    } finally {
      await progress.close();
      progress.dispose();
    }

    if (!mounted) return;

    if (error != null) {
      log('Retake moment error: $error');
      final raw = error.toString();
      final tooLarge =
          raw.contains('(413)') || raw.contains('Request Entity Too Large');
      await showPremiumErrorDialog(
        context,
        title: 'Moment not updated',
        message: tooLarge
            ? 'This video is too large. Please record a shorter one.'
            : 'We couldn\'t update your Moment. Your current one is still there — please try again.',
      );
      if (_videoController?.value.isInitialized == true) {
        await _videoController?.play();
      }
      return;
    }

    ActiveCheckinService().notifyMediaUpdated();
    _hasChanged = true;
    showSuccessSnackBar(context, message: 'Moment updated!');
    // Yeni medyanın imzalı URL'ini profil yeniden yüklerken alır.
    Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _setupSeq++;
    _dismissController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _ownerSequence?.removeListener(_onUploadChanged);
    _ownerSequence?.dispose();
    _videoController?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_closingUpload) {
      return const Scaffold(backgroundColor: Colors.transparent);
    }
    if (_entries.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              const Center(
                child: Text(
                  'No moments available',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.pop(context, _hasChanged),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final currentMedia = _currentEntry!.media;
    final pending = _currentEntry!.pending;
    final canFeaturePhoto =
        currentMedia?.mediaType == MediaType.photo && !currentMedia!.isFeatured;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBuilder(
        animation: _dismissController,
        builder: (context, child) {
          final height = MediaQuery.sizeOf(context).height;
          final opacity = (1 - _dismissController.value / height).clamp(
            0.0,
            1.0,
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                key: const ValueKey('moment-dismiss-background'),
                color: Colors.black.withValues(alpha: opacity),
              ),
              Transform.translate(
                key: const ValueKey('moment-drag-surface'),
                offset: Offset(0, _dismissController.value),
                child: child,
              ),
            ],
          );
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: _handleVerticalDragStart,
          onVerticalDragUpdate: _handleVerticalDragUpdate,
          onVerticalDragEnd: _handleVerticalDragEnd,
          onVerticalDragCancel: _handleVerticalDragCancel,
          child: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: _entries.length,
                onPageChanged: (index) async {
                  setState(() => _currentIndex = index);
                  await _setupVideoIfNeeded(index);
                },
                itemBuilder: (context, index) {
                  final entry = _entries[index];
                  if (entry.pending != null) {
                    return OwnerStoryUploadMedia(
                      key: ValueKey(entry.key),
                      item: entry.pending!,
                      paused: _paused || _currentIndex != index,
                    );
                  }
                  final item = entry.media!;

                  // 🖼 PHOTO
                  if (item.mediaType == MediaType.photo) {
                    return _withTextOverlay(
                      item,
                      SizedBox.expand(
                        child: CachedImage(
                          item.url,
                          mediaReference: item.mediaReference,
                          fit: BoxFit.cover,
                        ),
                      ),
                    );
                  }

                  // 🎬 VIDEO
                  if (_videoController != null &&
                      _videoController!.value.isInitialized &&
                      _currentIndex == index) {
                    return _withTextOverlay(
                      item,
                      SizedBox.expand(
                        child: FittedBox(
                          fit: BoxFit.cover,
                          clipBehavior: Clip.hardEdge,
                          child: SizedBox(
                            width: _videoController!.value.size.width,
                            height: _videoController!.value.size.height,
                            child: VideoPlayer(_videoController!),
                          ),
                        ),
                      ),
                    );
                  }
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                },
              ),

              // ÜST KISIM — venue galerisiyle aynı düzen: koyu karartma,
              // güvenli alanın 38px altında solda "1 / 9" sayacı, sağda ortak
              // report / close.
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: MediaViewerTopScrim(),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 38, 12, 0),
                    child: Row(
                      children: [
                        // Venue galerisi gibi "1 / 9" sayacı (story ile
                        // karışmasın diye üstte ilerleme çizgisi yok).
                        if (_entries.isNotEmpty)
                          MediaViewerCounterPill(
                            index: _currentIndex.clamp(0, _entries.length - 1),
                            count: _entries.length,
                          ),
                        const Spacer(),
                        if (!widget.allowFeature &&
                            widget.reportedUserId?.isNotEmpty == true)
                          MediaViewerReportButton(
                            onPressed: _reportCurrentMedia,
                          ),
                        MediaViewerCloseButton(onPressed: _closeUpload),
                      ],
                    ),
                  ),
                ),
              ),
              if (pending != null &&
                  pending.state != PendingPublicMediaState.published)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                    child: OwnerStoryUploadStatus(
                      item: pending,
                      onCreateStory: widget.onCreateMoment == null
                          ? null
                          : _createMoment,
                      onDismiss: () => _uploads.dismiss(pending.id),
                    ),
                  ),
                ),
              // ⭐ FEATURE + 🗑 DELETE
              if (widget.allowFeature && currentMedia != null)
                Positioned(
                  bottom: 40,
                  left: 20,
                  right: 20,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // FEATURE — glass buton, featured'da teal accent.
                      _GlassCircleButton(
                        onTap: !canFeaturePhoto || _loading || _deleting
                            ? null
                            : _setFeatured,
                        busy: _loading,
                        icon: currentMedia.isFeatured
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        iconColor: currentMedia.isFeatured
                            ? AppColors.tealDark
                            : canFeaturePhoto
                            ? Colors.white
                            : Colors.white38,
                        spinnerColor: AppColors.tealDark,
                      ),

                      // DELETE — glass buton, magenta accent.
                      _GlassCircleButton(
                        onTap: _loading || _deleting
                            ? null
                            : () => _deleteMedia(currentMedia),
                        busy: _deleting,
                        icon: Icons.delete_outline_rounded,
                        iconColor: AppColors.magentaDark,
                        spinnerColor: AppColors.magentaDark,
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
}

/// Uygulama geneli glassmorphism buton — buzlu cam daire, ince kenarlık.
/// Moments viewer'daki featured/delete aksiyonları için kullanılır.
class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({
    required this.onTap,
    required this.icon,
    required this.iconColor,
    this.busy = false,
    this.spinnerColor = Colors.white,
  });

  final VoidCallback? onTap;
  final IconData icon;
  final Color iconColor;
  final bool busy;
  final Color spinnerColor;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Material(
          color: Colors.white.withValues(alpha: 0.12),
          child: InkWell(
            onTap: onTap,
            child: Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
              ),
              child: busy
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: spinnerColor,
                      ),
                    )
                  : Icon(icon, color: iconColor, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}

/// Son moment silme dialog'unun sonucu.
enum _DeleteChoice { cancel, retake, delete }
