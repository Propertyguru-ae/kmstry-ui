import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';

/// Uygulama genelinde ortak geri butonu. Tek görünüm dili, iki varyant:
///
/// - [AppBackButton] — normal sayfalar (AppBar leading veya düz zemin): temaya
///   uyan yumuşak daire, ince kenarlık, logo mavisi/koyu slate ikon.
/// - [AppBackButton.onCover] — kapak görseli/hero üzerinde: koyu yarı saydam
///   daire + beyaz ikon (görsel üzerinde her zaman okunur).
///
/// [onTap] verilmezse `Navigator.maybePop()` çağrılır.
class AppBackButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool _onCover;

  const AppBackButton({super.key, this.onTap}) : _onCover = false;
  const AppBackButton.onCover({super.key, this.onTap}) : _onCover = true;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color bg;
    final Color fg;
    final BorderSide side;
    if (_onCover) {
      bg = Colors.black.withValues(alpha: 0.38);
      fg = Colors.white;
      side = BorderSide.none;
    } else {
      bg = isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.black.withValues(alpha: 0.04);
      fg = isDark ? AppColors.blueDark : const Color(0xFF334155);
      side = BorderSide(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.08),
      );
    }

    return Material(
      color: bg,
      shape: CircleBorder(side: side),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap ?? () => Navigator.of(context).maybePop(),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(Icons.arrow_back_ios_new_rounded, size: 17, color: fg),
        ),
      ),
    );
  }
}
