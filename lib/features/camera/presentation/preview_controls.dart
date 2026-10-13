import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';

// Foto ve video önizleme ekranlarının ORTAK kontrolleri — iki ekran birebir
// aynı görünsün diye tek yerde. Sağ üst: X / Tt / indir (yarı saydam daire).
// Alt: Retake (koyu hap) + Use (uygulama mavisi).

/// Sağ üst araç butonu (X, Tt, indir).
class PreviewToolButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool loading;

  const PreviewToolButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.loading = false,
  });

  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black38,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        icon: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon, color: Colors.white),
        onPressed: onTap,
      ),
    );
  }
}

/// Alt aksiyon butonu. [primary] → uygulama mavisi (Use); değilse yarı
/// saydam koyu hap (Retake).
class PreviewActionButton extends StatelessWidget {
  const PreviewActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.primary,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: enabled || loading ? 1 : 0.48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          // Primary (Use/Send): uygulama mavisi. Secondary: fotoğraf üstünde
          // her iki modda okunur yarı-saydam koyu pill + ince beyaz kenar.
          color: primary
              ? AppColors.blue
              : Colors.black.withValues(alpha: 0.40),
          borderRadius: BorderRadius.circular(14),
          border: primary
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.28)),
          boxShadow: primary && enabled
              ? [
                  BoxShadow(
                    color: AppColors.blue.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(0, 46),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            elevation: 0,
            shadowColor: Colors.transparent,
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: loading
              ? const SizedBox(
                  width: 19,
                  height: 19,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 18),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
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

/// Önizleme alt şeridi: solda Retake, sağda mavi onay (Use).
class PreviewBottomActions extends StatelessWidget {
  const PreviewBottomActions({
    super.key,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.onCancel,
    required this.onConfirm,
    this.confirmIcon,
    this.confirming = false,
  });

  final String cancelLabel;
  final String confirmLabel;
  final IconData? confirmIcon;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;
  final bool confirming;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: PreviewActionButton(
            label: cancelLabel,
            icon: cancelLabel == 'Retake'
                ? Icons.refresh_rounded
                : Icons.arrow_back_rounded,
            primary: false,
            onPressed: onCancel,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: PreviewActionButton(
            label: confirmLabel,
            icon: confirmIcon ?? Icons.check_rounded,
            primary: true,
            loading: confirming,
            onPressed: onConfirm,
          ),
        ),
      ],
    );
  }
}
