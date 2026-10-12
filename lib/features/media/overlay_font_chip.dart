import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';

/// Metin editöründeki (foto önizleme + video composer) font stili balonu.
///
/// Uygulama diline uygun: seçili balon marka gradient'i (mavi → magenta),
/// seçili olmayanlar buzlu cam — her fotoğrafın üstünde okunur kalır. Etiket
/// kendi fontuyla yazılır (önizleme) ve farklı font metriklerinde bile
/// balonun tam ortasında durur (sabit strut yüksekliği).
class OverlayFontChip extends StatelessWidget {
  final String label;

  /// Fontun önizleme stili; renk ve boyut burada ezilir.
  final TextStyle fontStyle;
  final bool selected;
  final VoidCallback onTap;

  /// Etiket boyutu — el yazısı / dar fontlar balonda dengeli dursun diye
  /// fonta göre verilebilir.
  final double fontSize;

  const OverlayFontChip({
    super.key,
    required this.label,
    required this.fontStyle,
    required this.selected,
    required this.onTap,
    this.fontSize = 14.5,
  });

  static const double _height = 38;
  static final BorderRadius _radius = BorderRadius.circular(_height / 2);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (selected) return;
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        // Dış katman yalnızca gölge taşır (iç katman blur için kırpılıyor).
        decoration: BoxDecoration(
          borderRadius: _radius,
          boxShadow: [
            BoxShadow(
              color: AppColors.magenta.withValues(alpha: selected ? 0.35 : 0.0),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: _radius,
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              height: _height,
              constraints: const BoxConstraints(minWidth: 92),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: _radius,
                gradient: selected
                    ? const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [AppColors.blue, AppColors.magenta],
                      )
                    : null,
                color: selected ? null : Colors.black.withValues(alpha: 0.38),
                border: Border.all(
                  color: Colors.white.withValues(alpha: selected ? 0.35 : 0.22),
                ),
              ),
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                softWrap: false,
                // Georgia/Courier gibi fontların farklı ascent/descent
                // değerleri yazıyı yukarı/aşağı kaydırmasın.
                strutStyle: StrutStyle(
                  fontSize: fontSize,
                  height: 1.0,
                  forceStrutHeight: true,
                ),
                textHeightBehavior: const TextHeightBehavior(
                  applyHeightToFirstAscent: false,
                  applyHeightToLastDescent: false,
                ),
                style: fontStyle.copyWith(
                  color: Colors.white.withValues(alpha: selected ? 1.0 : 0.88),
                  fontSize: fontSize,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Font balonlarını dizer: sığıyorsa ekranda ortalı durur, sığmıyorsa
/// yatay kaydırılır (küçültülüp okunmaz hale gelmez).
class OverlayFontChipRow extends StatelessWidget {
  final List<Widget> chips;

  const OverlayFontChipRow({super.key, required this.chips});

  static const double _sidePadding = 16;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // Seçili balonun gölgesi kırpılmasın diye balondan biraz yüksek.
      height: 50,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: _sidePadding),
            child: ConstrainedBox(
              // En az ekran genişliği kadar → içerik sığınca ortalanır.
              constraints: BoxConstraints(
                minWidth: constraints.maxWidth - _sidePadding * 2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < chips.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    chips[i],
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
