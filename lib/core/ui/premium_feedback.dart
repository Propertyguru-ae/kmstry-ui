import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';

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

void showErrorToast(
  BuildContext context, {
  required String message,
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
      icon: Icons.error_outline_rounded,
      colorScheme: colorScheme,
      duration: duration,
      onDone: () {
        if (entry.mounted) entry.remove();
      },
      isError: true,
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
  final bool isError;

  const _CenteredToast({
    required this.message,
    required this.icon,
    required this.colorScheme,
    required this.duration,
    required this.onDone,
    this.isError = false,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
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
                    Icon(
                      widget.icon,
                      color: widget.isError ? cs.error : cs.primary,
                      size: 22,
                    ),
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
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
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
// CHECK-IN EXPIRED / RENEWAL DIALOG
// ─────────────────────────────────────────────────────────────────────────────

/// "Check-in süren doldu" — uygulama diline uygun premium yenileme dialog'u.
/// `true` döner → kullanıcı yenilemek istedi.
Future<bool> showCheckinExpiredDialog(
  BuildContext context, {
  required String venueLabel,
}) async {
  if (!context.mounted) return false;
  final isDark = Theme.of(context).brightness == Brightness.dark;

  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) {
      final surface = isDark ? const Color(0xFF121A2B) : Colors.white;
      final titleColor = isDark ? Colors.white : AppColors.lightTextPrimary;
      final bodyColor = isDark
          ? const Color(0xFFB4C2D8)
          : AppColors.lightTextSecondary;

      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.05),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.18),
                blurRadius: 34,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Gradient ikon tile'ı
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.blue, AppColors.magenta],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.magenta.withValues(alpha: 0.35),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.timer_off_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 18),

                // ── Title
                Text(
                  'Your check-in expired',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),

                // ── Description
                Text.rich(
                  TextSpan(
                    style: TextStyle(
                      color: bodyColor,
                      fontSize: 14.5,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                    children: [
                      const TextSpan(text: 'Looks like you\'re still at '),
                      TextSpan(
                        text: venueLabel,
                        style: TextStyle(
                          color: titleColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const TextSpan(
                        text:
                            '. Want to extend your check-in for 3 more hours?',
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 22),

                // ── Yenile (gradient)
                SizedBox(
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        colors: [AppColors.blue, AppColors.magenta],
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.pop(ctx, true),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 15),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.refresh_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Renew check-in',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15.5,
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
                const SizedBox(height: 6),

                // ── Not now
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    foregroundColor: bodyColor,
                  ),
                  child: const Text(
                    'Not now',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return result == true;
}

// ─────────────────────────────────────────────────────────────────────────────
// GENERIC PREMIUM PROMPT DIALOG (positive CTA)
// ─────────────────────────────────────────────────────────────────────────────

/// Uygulama geneli premium bilgilendirme/CTA dialog'u — gradient ikon tile'ı,
/// kalın başlık, açıklama, gradient birincil buton + hafif "not now" butonu.
/// Birincil butona basılırsa `true`, iptal/dismiss'te `false` döner.
Future<bool> showPremiumPromptDialog(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Not now',
  IconData? confirmIcon,
}) async {
  if (!context.mounted) return false;
  final isDark = Theme.of(context).brightness == Brightness.dark;

  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) {
      final surface = isDark ? const Color(0xFF121A2B) : Colors.white;
      final titleColor = isDark ? Colors.white : AppColors.lightTextPrimary;
      final bodyColor = isDark
          ? const Color(0xFFB4C2D8)
          : AppColors.lightTextSecondary;

      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.05),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.18),
                blurRadius: 34,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.blue, AppColors.magenta],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.magenta.withValues(alpha: 0.35),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: Colors.white, size: 32),
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
                SizedBox(
                  width: double.infinity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: const LinearGradient(
                        colors: [AppColors.blue, AppColors.magenta],
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.pop(ctx, true),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (confirmIcon != null) ...[
                                Icon(
                                  confirmIcon,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                              ],
                              Text(
                                confirmLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15.5,
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
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    foregroundColor: bodyColor,
                  ),
                  child: Text(
                    cancelLabel,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return result == true;
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
                                  Text('🎉', style: TextStyle(fontSize: 20)),
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
                                                      Container(
                                                        color: Colors.black87,
                                                      ),
                                                    const Center(
                                                      child: Icon(
                                                        Icons
                                                            .play_circle_fill_rounded,
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFF22C55E,
                                            ).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            border: Border.all(
                                              color: const Color(
                                                0xFF22C55E,
                                              ).withValues(alpha: 0.35),
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
