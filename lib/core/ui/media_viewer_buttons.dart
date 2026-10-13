import 'package:flutter/material.dart';

/// Tam ekran medya görüntüleyicilerinin (story, moment, mekan galerisi) üst
/// sağındaki aksiyon butonları — uygulama genelinde TEK görünüm.
///
/// Story görüntüleyicisinin stili esas alınır: arka plansız beyaz ikon,
/// standart 24px boyut, 48px dokunma alanı. Ekran üstündeki koyu karartma
/// ([MediaViewerTopScrim]) ile birlikte parlak fotoğraflarda da okunur.
class MediaViewerIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// true → ikon yerine küçük beyaz spinner (ör. yükleme iptal ediliyor).
  final bool busy;

  const MediaViewerIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: busy ? null : onPressed,
      icon: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : Icon(icon, color: Colors.white),
    );
  }
}

class MediaViewerReportButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const MediaViewerReportButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) => MediaViewerIconButton(
    icon: Icons.flag_outlined,
    tooltip: 'Report',
    onPressed: onPressed,
  );
}

class MediaViewerDeleteButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String tooltip;
  final bool busy;
  const MediaViewerDeleteButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'Delete',
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) => MediaViewerIconButton(
    icon: Icons.delete_outline_rounded,
    tooltip: tooltip,
    onPressed: onPressed,
    busy: busy,
  );
}

class MediaViewerCloseButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const MediaViewerCloseButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) => MediaViewerIconButton(
    icon: Icons.close,
    tooltip: 'Close',
    onPressed: onPressed,
  );
}

/// Görüntüleyicinin sol üstündeki "1 / 9" sayacı — venue galerisi, event
/// galerisi ve momentlerde aynı.
class MediaViewerCounterPill extends StatelessWidget {
  /// 0 tabanlı görünen sayfa.
  final int index;
  final int count;
  const MediaViewerCounterPill({
    super.key,
    required this.index,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '${index + 1} / $count',
        style: const TextStyle(
          fontSize: 13,
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Görüntüleyicinin üstündeki koyu karartma — beyaz ikonlar/metin parlak
/// medyada kaybolmasın (story görüntüleyicisindekiyle aynı).
class MediaViewerTopScrim extends StatelessWidget {
  final double height;
  const MediaViewerTopScrim({super.key, this.height = 120});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.55), Colors.transparent],
          ),
        ),
      ),
    );
  }
}
