import 'dart:convert';

import 'package:flutter/material.dart';

/// Video (ve ileride foto) üzerine eklenen metin overlay'inin veri modeli.
///
/// Videoya gömme (burn-in) yapılmaz — overlay JSON olarak backend'e gider
/// (`CheckinMedia.text_overlay` / `Story.text_overlay`) ve izleyen herkesin
/// ekranında [MediaTextOverlayView] ile videonun üstüne çizilir.
///
/// Konum/boyut cihazlar arası tutarlılık için normalize saklanır:
/// - [xNorm]/[yNorm]: metin merkezinin ekrana oranı (0..1)
/// - [fontSizeNorm]: font boyutunun ekran genişliğine oranı
class MediaTextOverlay {
  final String text;
  final int colorValue;
  final double fontSizeNorm;
  final String fontStyle; // 'modern' | 'classic' | 'typewriter'
  final String align; // 'left' | 'center' | 'right'
  final double xNorm;
  final double yNorm;
  final double scale;
  final double rotation; // radyan

  const MediaTextOverlay({
    required this.text,
    required this.colorValue,
    required this.fontSizeNorm,
    this.fontStyle = 'modern',
    this.align = 'center',
    this.xNorm = 0.5,
    this.yNorm = 0.5,
    this.scale = 1.0,
    this.rotation = 0.0,
  });

  Color get color => Color(colorValue);

  TextAlign get textAlign => switch (align) {
        'left' => TextAlign.left,
        'right' => TextAlign.right,
        _ => TextAlign.center,
      };

  /// Canvas genişliğine göre gerçek font boyutu.
  double fontSizeFor(double canvasWidth) =>
      (fontSizeNorm * canvasWidth).clamp(10.0, 120.0);

  TextStyle styleFor(double canvasWidth) {
    final base = switch (fontStyle) {
      'classic' => TextStyle(
          color: color,
          fontFamily: 'Georgia',
          fontWeight: FontWeight.w600,
        ),
      'typewriter' => TextStyle(
          color: color,
          fontFamily: 'Courier',
          fontWeight: FontWeight.w700,
        ),
      _ => TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
    };
    return base.copyWith(
      fontSize: fontSizeFor(canvasWidth),
      shadows: const [Shadow(blurRadius: 8, color: Colors.black45)],
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'color': colorValue,
        'fontSizeNorm': fontSizeNorm,
        'fontStyle': fontStyle,
        'align': align,
        'xNorm': xNorm,
        'yNorm': yNorm,
        'scale': scale,
        'rotation': rotation,
      };

  String toJsonString() => jsonEncode(toJson());

  static MediaTextOverlay? fromJson(dynamic json) {
    if (json == null) return null;
    Map<String, dynamic>? map;
    if (json is Map<String, dynamic>) {
      map = json;
    } else if (json is String && json.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(json);
        if (decoded is Map<String, dynamic>) map = decoded;
      } catch (_) {
        return null;
      }
    }
    if (map == null) return null;

    final text = map['text'];
    if (text is! String || text.trim().isEmpty) return null;

    double toD(dynamic v, double fallback) =>
        v is num ? v.toDouble() : fallback;

    return MediaTextOverlay(
      text: text,
      colorValue: map['color'] is num
          ? (map['color'] as num).toInt()
          : 0xFFFFFFFF,
      fontSizeNorm: toD(map['fontSizeNorm'], 0.07).clamp(0.02, 0.3),
      fontStyle: map['fontStyle'] is String ? map['fontStyle'] as String : 'modern',
      align: map['align'] is String ? map['align'] as String : 'center',
      xNorm: toD(map['xNorm'], 0.5).clamp(0.0, 1.0),
      yNorm: toD(map['yNorm'], 0.5).clamp(0.0, 1.0),
      scale: toD(map['scale'], 1.0).clamp(0.2, 5.0),
      rotation: toD(map['rotation'], 0.0),
    );
  }
}

/// [MediaTextOverlay]'i verilen canvas boyutunda medyanın üstüne çizer.
/// Story viewer'da, check-in medya önizlemesinde vb. kullanılır.
/// Dokunmaları engellemez ([IgnorePointer]).
class MediaTextOverlayView extends StatelessWidget {
  final MediaTextOverlay overlay;

  const MediaTextOverlayView({super.key, required this.overlay});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          const boxWidth = 320.0;
          return Stack(
            children: [
              Positioned(
                left: overlay.xNorm * w - boxWidth / 2,
                top: overlay.yNorm * h - 60,
                child: Transform.rotate(
                  angle: overlay.rotation,
                  child: Transform.scale(
                    scale: overlay.scale,
                    child: SizedBox(
                      width: boxWidth,
                      child: Text(
                        overlay.text,
                        textAlign: overlay.textAlign,
                        style: overlay.styleFor(w),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
