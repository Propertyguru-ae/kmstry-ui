import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';

/// Personal signup / onboarding akışının tüm birincil CTA'ları için tek stil.
///
/// Marka gradyanı (blue → purple → magenta), sabit yükseklik/radius, dahili
/// loading spinner ve disabled (0.5 opacity + tık kapalı) davranışı buradan
/// yönetilir. Sayfalar yalnızca [label]/[onPressed]/[loading] verir.
///
/// İkincil (ghost/text) eylemler — ör. "Skip" — için [PrimaryButton.secondary].
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool trailingArrow;

  /// true → ghost/text stili (Skip vb.). false → dolu gradyan.
  final bool _secondary;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.trailingArrow = false,
  }) : _secondary = false;

  const PrimaryButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
  })  : loading = false,
        trailingArrow = false,
        _secondary = true;

  static const _blue = AppColors.blue; // #1A9FE8 — logo mavisi
  static const _blueBright = AppColors.blueDark; // #4EC8FF

  @override
  Widget build(BuildContext context) {
    if (_secondary) return _buildSecondary();
    return _buildPrimary();
  }

  Widget _buildPrimary() {
    final enabled = onPressed != null && !loading;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onPressed : null,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: _blue,
              boxShadow: [
                BoxShadow(
                  color: _blue.withValues(alpha: 0.30),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Container(
              height: 52,
              alignment: Alignment.center,
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (trailingArrow) ...[
                          const SizedBox(width: 9),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecondary() {
    return SizedBox(
      height: 52,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: _blueBright,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
