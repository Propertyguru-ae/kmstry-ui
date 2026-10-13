import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/ui/primary_button.dart';
import '../../content_moderation/data/pending_public_media.dart';
import '../../content_moderation/presentation/pending_public_media_preview.dart';
import '../../media/media_text_overlay.dart';

bool ownerStoryHasNoPreview(PendingPublicMedia item) =>
    item.state == PendingPublicMediaState.rejected ||
    item.state == PendingPublicMediaState.failed ||
    item.state == PendingPublicMediaState.cancelled;

bool ownerStoryIsNotShared(PendingPublicMedia item) =>
    item.state == PendingPublicMediaState.rejected ||
    item.state == PendingPublicMediaState.failed;

/// Enough time to read the explanation; press-and-hold pauses as usual.
Duration ownerStoryFeedbackDuration(PendingPublicMedia item) {
  final words = (item.message ?? '').split(RegExp(r'\s+')).length;
  return Duration(seconds: (3 + (words / 3).ceil()).clamp(8, 30));
}

/// Local media only. This widget never requests a public/private storage URL.
class OwnerStoryUploadMedia extends StatefulWidget {
  const OwnerStoryUploadMedia({
    super.key,
    required this.item,
    this.paused = false,
  });
  final PendingPublicMedia item;
  final bool paused;

  @override
  State<OwnerStoryUploadMedia> createState() => _OwnerStoryUploadMediaState();
}

class _OwnerStoryUploadMediaState extends State<OwnerStoryUploadMedia> {
  VideoPlayerController? _video;
  int _generation = 0;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(covariant OwnerStoryUploadMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.localPath != widget.item.localPath ||
        ownerStoryHasNoPreview(oldWidget.item) !=
            ownerStoryHasNoPreview(widget.item)) {
      _prepare();
    } else if (widget.paused != oldWidget.paused && _ready) {
      if (widget.paused) {
        _video?.pause();
      } else {
        _video?.play();
      }
    }
  }

  Future<void> _prepare() async {
    final generation = ++_generation;
    final previous = _video;
    _video = null;
    _ready = false;
    await previous?.dispose();
    final item = widget.item;
    if (!mounted ||
        generation != _generation ||
        !item.isVideo ||
        ownerStoryHasNoPreview(item) ||
        item.localPath.isEmpty) {
      return;
    }
    try {
      if (!await File(item.localPath).exists() ||
          !mounted ||
          generation != _generation) {
        return;
      }
      final controller = VideoPlayerController.file(File(item.localPath));
      _video = controller;
      await controller.initialize();
      if (!mounted || generation != _generation) return;
      await controller.setLooping(true);
      if (!mounted || generation != _generation) return;
      setState(() => _ready = true);
      if (!widget.paused) await controller.play();
    } catch (_) {
      // A temporary encoder file may have been cleaned up. Keep its retained
      // poster visible; never replace it with an endless loading indicator.
    }
  }

  @override
  void dispose() {
    _generation++;
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (ownerStoryHasNoPreview(widget.item)) {
      return const ColoredBox(color: Color(0xFF10131B));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        PendingPublicMediaPreview(item: widget.item, fit: BoxFit.contain),
        if (_ready && _video != null)
          Center(
            child: AspectRatio(
              aspectRatio: _video!.value.aspectRatio,
              child: VideoPlayer(_video!),
            ),
          ),
        if (widget.item.textOverlay != null &&
            (_ready || widget.item.previewPath?.isNotEmpty == true))
          Positioned.fill(
            child: MediaTextOverlayView(overlay: widget.item.textOverlay!),
          ),
      ],
    );
  }
}

/// A compact, non-blocking footer inside the normal story viewer.
class OwnerStoryUploadStatus extends StatelessWidget {
  const OwnerStoryUploadStatus({
    super.key,
    required this.item,
    this.onCreateStory,
    this.onDismiss,
    this.action,
  });
  final PendingPublicMedia item;
  final VoidCallback? onCreateStory;
  final VoidCallback? onDismiss;

  /// Kartın butonlar alanına eklenen ek eylem (ör. event fotoğrafını kaldır);
  /// her durumda gösterilir.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final state = item.state;
    final terminal = ownerStoryHasNoPreview(item);
    final moment = item.kind == PendingPublicMediaKind.checkinMoment;
    // Event fotoğrafı ve venue galerisi: "photo" / "video".
    final eventPhoto =
        item.kind == PendingPublicMediaKind.eventPhoto ||
        item.kind == PendingPublicMediaKind.venueGallery;
    final noun = moment
        ? 'Moment'
        : eventPhoto
        ? (item.isVideo ? 'video' : 'photo')
        : 'story';
    final title = switch (state) {
      PendingPublicMediaState.published => 'Shared',
      PendingPublicMediaState.rejected || PendingPublicMediaState.failed =>
        moment
            ? 'Moment not shared'
            : eventPhoto
            ? (item.isVideo ? 'Video not shared' : 'Photo not shared')
            : 'Story not shared',
      PendingPublicMediaState.cancelled => 'Upload cancelled',
      PendingPublicMediaState.delayed => 'Taking longer',
      PendingPublicMediaState.underReview => 'Under review',
      PendingPublicMediaState.connectionIssue => 'Check connection',
      _ => 'Sharing',
    };
    final message = switch (state) {
      PendingPublicMediaState.rejected =>
        item.message?.trim().isNotEmpty == true
            ? item.message!
            : 'This $noun did not meet our community guidelines.',
      PendingPublicMediaState.failed =>
        item.message?.trim().isNotEmpty == true
            ? item.message!
            : 'This $noun could not be uploaded. You can create a new $noun.',
      PendingPublicMediaState.cancelled => 'This $noun was not shared.',
      PendingPublicMediaState.delayed =>
        'Your $noun is still processing. It isn’t visible to others yet. You can leave this screen.',
      PendingPublicMediaState.underReview =>
        item.message?.trim().isNotEmpty == true
            ? item.message!
            : 'Your $noun needs a closer look before it can be shared. You can leave this screen.',
      PendingPublicMediaState.connectionIssue =>
        'We’re waiting for confirmation. Your $noun isn’t visible to others yet.',
      _ => null,
    };
    // Duruma göre renk + ikon: paylaşılıyor (mavi), beklemede / incelemede
    // (turuncu), paylaşılmadı (kırmızı), iptal (gri).
    final rejected =
        state == PendingPublicMediaState.rejected ||
        state == PendingPublicMediaState.failed;
    final sharing = publicMediaIsSharing(item);
    final accent = rejected
        ? const Color(0xFFFF6B6B)
        : state == PendingPublicMediaState.cancelled
        ? const Color(0xFF9AA3B2)
        : sharing
        ? AppColors.blueDark
        : AppColors.orange;
    final icon = switch (state) {
      PendingPublicMediaState.rejected => Icons.block_rounded,
      PendingPublicMediaState.failed => Icons.error_outline_rounded,
      PendingPublicMediaState.cancelled => Icons.close_rounded,
      PendingPublicMediaState.underReview => Icons.shield_outlined,
      PendingPublicMediaState.delayed => Icons.hourglass_bottom_rounded,
      PendingPublicMediaState.connectionIssue => Icons.wifi_off_rounded,
      _ => Icons.cloud_upload_outlined,
    };
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .55,
          ),
          // Uygulamanın koyu kart/popup yüzeyiyle aynı.
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF121A2B).withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: sharing
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.8,
                                  color: accent,
                                  semanticsLabel: 'Sharing',
                                ),
                              )
                            : Icon(icon, color: accent, size: 19),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (state == PendingPublicMediaState.uploading &&
                      item.progress != null) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: item.progress!.clamp(0, 1),
                        minHeight: 3,
                        color: AppColors.blueDark,
                        backgroundColor: Colors.white12,
                      ),
                    ),
                  ],
                  if (message != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      message,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (action != null) ...[const SizedBox(height: 12), action!],
                  if (terminal &&
                      (onCreateStory != null || onDismiss != null)) ...[
                    const SizedBox(height: 16),
                    // Uygulama genelindeki standart butonlar.
                    if (onCreateStory != null)
                      PrimaryButton(
                        label: 'Create new $noun',
                        onPressed: onCreateStory,
                      ),
                    if (onDismiss != null) ...[
                      if (onCreateStory != null) const SizedBox(height: 4),
                      PrimaryButton.secondary(
                        label: 'Dismiss',
                        onPressed: onDismiss,
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
