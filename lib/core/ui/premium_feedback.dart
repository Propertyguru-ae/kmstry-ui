import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

/// Ekranın ortasında beliren fade-in/out toast — light/dark mode uyumlu.
void showSuccessSnackBar(
  BuildContext context, {
  required String message,
  IconData icon = Icons.check_circle_rounded,
  Duration duration = const Duration(seconds: 3),
}) {
  if (!context.mounted) return;

  final colorScheme = Theme.of(context).colorScheme;
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _CenteredToast(
      message: message,
      icon: icon,
      colorScheme: colorScheme,
      duration: duration,
      onDone: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );

  overlay.insert(entry);
}

class _CenteredToast extends StatefulWidget {
  final String message;
  final IconData icon;
  final ColorScheme colorScheme;
  final Duration duration;
  final VoidCallback onDone;

  const _CenteredToast({
    required this.message,
    required this.icon,
    required this.colorScheme,
    required this.duration,
    required this.onDone,
  });

  @override
  State<_CenteredToast> createState() => _CenteredToastState();
}

class _CenteredToastState extends State<_CenteredToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();

    Future.delayed(widget.duration, () {
      if (mounted) {
        _ctrl.reverse().then((_) => widget.onDone());
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;
    return Positioned.fill(
      child: IgnorePointer(
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: FadeTransition(
              opacity: _opacity,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: cs.inverseSurface,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, color: cs.primary, size: 22),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        widget.message,
                        style: TextStyle(
                          color: cs.onInverseSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showPremiumErrorDialog(
  BuildContext context, {
  required String message,
  String title = 'Something went wrong',
  String buttonText = 'OK',
}) async {
  if (!context.mounted) return;
  final colors = Theme.of(context).colorScheme;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: colors.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(
            color: colors.onSurface.withValues(alpha: 0.86),
            height: 1.35,
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(buttonText),
          ),
        ],
      );
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// STORY SHARED CELEBRATION CARD
// ─────────────────────────────────────────────────────────────────────────────

/// Alttan slide-up ile beliren "Story shared!" kutlama kartı.
/// [overlay]     — async gap'ten önce yakalanmış OverlayState (sayfadan bağımsız).
/// [mediaFile]   — yüklenen fotoğraf/video dosyası (önizleme için).
/// [venueName]   — mekanın adı.
/// [isVideo]     — video ise önizlemede kamera ikonu gösterilir.
/// [onViewStory] — "View Story" butonuna basılınca çağrılır (opsiyonel).
void showStorySharedCard(
  OverlayState overlay, {
  required File mediaFile,
  required String venueName,
  bool isVideo = false,
  VoidCallback? onViewStory,
}) {
  if (!overlay.mounted) return;

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _StorySharedCard(
      mediaFile: mediaFile,
      venueName: venueName,
      isVideo: isVideo,
      onViewStory: onViewStory,
      onDone: () {
        if (entry.mounted) entry.remove();
      },
    ),
  );

  overlay.insert(entry);
}

class _StorySharedCard extends StatefulWidget {
  final File mediaFile;
  final String venueName;
  final bool isVideo;
  final VoidCallback? onViewStory;
  final VoidCallback onDone;

  const _StorySharedCard({
    required this.mediaFile,
    required this.venueName,
    required this.isVideo,
    required this.onDone,
    this.onViewStory,
  });

  @override
  State<_StorySharedCard> createState() => _StorySharedCardState();
}

class _StorySharedCardState extends State<_StorySharedCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;
  Future<String?>? _videoThumbnailFuture;

  static const Duration _inDuration = Duration(milliseconds: 380);
  static const Duration _stayDuration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _videoThumbnailFuture = VideoThumbnail.thumbnailFile(
        video: widget.mediaFile.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 200,
        quality: 75,
      );
    }
    _ctrl = AnimationController(vsync: this, duration: _inDuration);
    _slide = Tween<Offset>(
      begin: const Offset(0, 1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

    _ctrl.forward();

    Future.delayed(_stayDuration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _ctrl.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomPad = mq.padding.bottom;

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _dismiss,
          child: Stack(
            children: [
              // Dim backdrop — sadece kart dışına basınca dismiss
              Positioned.fill(
                child: FadeTransition(
                  opacity: _fade,
                  child: Container(color: Colors.black.withValues(alpha: 0.35)),
                ),
              ),

              // Kart
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SlideTransition(
                  position: _slide,
                  child: GestureDetector(
                    onTap: () {}, // kartın kendisine basınca dismiss olmasın
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        margin: EdgeInsets.fromLTRB(16, 0, 16, bottomPad + 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1F2E),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.10),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.45),
                              blurRadius: 32,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ── Başlık
                              const Row(
                                children: [
                                  Text(
                                    '🎉',
                                    style: TextStyle(fontSize: 20),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Story shared!',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),

                              // ── Önizleme + Bilgi
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Thumbnail
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: SizedBox(
                                      width: 72,
                                      height: 96,
                                      child: widget.isVideo
                                          ? FutureBuilder<String?>(
                                              future: _videoThumbnailFuture,
                                              builder: (_, snap) {
                                                final path = snap.data;
                                                return Stack(
                                                  fit: StackFit.expand,
                                                  children: [
                                                    if (path != null)
                                                      Image.file(
                                                        File(path),
                                                        fit: BoxFit.cover,
                                                      )
                                                    else
                                                      Container(color: Colors.black87),
                                                    const Center(
                                                      child: Icon(
                                                        Icons.play_circle_fill_rounded,
                                                        color: Colors.white,
                                                        size: 32,
                                                      ),
                                                    ),
                                                  ],
                                                );
                                              },
                                            )
                                          : Image.file(
                                              widget.mediaFile,
                                              fit: BoxFit.cover,
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),

                                  // Metin
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF22C55E)
                                                .withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: const Color(0xFF22C55E)
                                                  .withValues(alpha: 0.35),
                                            ),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.circle,
                                                color: Color(0xFF22C55E),
                                                size: 7,
                                              ),
                                              SizedBox(width: 5),
                                              Text(
                                                'Live now',
                                                style: TextStyle(
                                                  color: Color(0xFF22C55E),
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.location_on_rounded,
                                              color: Colors.white54,
                                              size: 14,
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                widget.venueName,
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
