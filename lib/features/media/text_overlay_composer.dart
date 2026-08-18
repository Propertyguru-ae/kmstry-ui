import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/features/media/media_text_overlay.dart';

/// Kamera akışında yakalanan medya + (varsa) metin overlay'i sonucu.
/// PreviewVideoScreen "Use Video" ile bunu pop'lar; check-in ve story
/// akışları dosyayı ve overlay'i buradan alır.
class CapturedMedia {
  final File file;
  final MediaTextOverlay? overlay;

  const CapturedMedia({required this.file, this.overlay});
}

/// Instagram tarzı metin overlay editörü + yerleştirilmiş yazı katmanı.
///
/// [child] (video önizlemesi vb.) üzerine sarılır. Editör kapalıyken
/// yerleştirilen yazı sürükle/pinch-zoom/döndürme jestlerini destekler;
/// [openEditor] ile düzenleme modu açılır (şeffaf zemin, sol dikey boyut
/// slider'ı, font stili çipleri, hizalama + renk paleti).
///
/// Parent, [TextOverlayComposerState.buildOverlay] ile normalize edilmiş
/// [MediaTextOverlay] verisini alır (yazı yoksa null).
class TextOverlayComposer extends StatefulWidget {
  final Widget child;

  /// Düzenleme modu değiştiğinde çağrılır — parent kendi butonlarını gizlesin.
  final ValueChanged<bool>? onEditingChanged;

  const TextOverlayComposer({
    super.key,
    required this.child,
    this.onEditingChanged,
  });

  @override
  State<TextOverlayComposer> createState() => TextOverlayComposerState();
}

enum _OverlayFontStyle { modern, classic, typewriter }

extension _OverlayFontStyleX on _OverlayFontStyle {
  String get label => switch (this) {
        _OverlayFontStyle.modern => 'Modern',
        _OverlayFontStyle.classic => 'Classic',
        _OverlayFontStyle.typewriter => 'Typewriter',
      };

  String get wireName => switch (this) {
        _OverlayFontStyle.modern => 'modern',
        _OverlayFontStyle.classic => 'classic',
        _OverlayFontStyle.typewriter => 'typewriter',
      };

  TextStyle base(Color color) => switch (this) {
        _OverlayFontStyle.modern => TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        _OverlayFontStyle.classic => TextStyle(
            color: color,
            fontFamily: 'Georgia',
            fontWeight: FontWeight.w600,
          ),
        _OverlayFontStyle.typewriter => TextStyle(
            color: color,
            fontFamily: 'Courier',
            fontWeight: FontWeight.w700,
          ),
      };
}

class TextOverlayComposerState extends State<TextOverlayComposer> {
  final TextEditingController _textController = TextEditingController();

  String _text = '';
  Color _color = Colors.white;
  Offset? _offset; // null → ekran ortası
  double _scale = 1.0;
  double _rotation = 0.0;
  double _fontSize = 28;
  TextAlign _align = TextAlign.center;
  _OverlayFontStyle _fontStyle = _OverlayFontStyle.modern;

  bool _editing = false;

  double _gestureStartScale = 1.0;
  double _gestureStartRotation = 0.0;

  static const List<Color> _palette = [
    Colors.white,
    Colors.black,
    AppColors.magenta,
    AppColors.blue,
    AppColors.teal,
    AppColors.orange,
    Color(0xFFFF3B30),
    Color(0xFFFFCC00),
    Color(0xFF34C759),
    Color(0xFF5E5CE6),
    Color(0xFFFF2D95),
    Color(0xFF8E8E93),
  ];

  bool get isEditing => _editing;
  bool get hasText => _text.trim().isNotEmpty;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  /// Yazı varsa ekran boyutuna göre normalize edilmiş overlay verisi döndürür.
  MediaTextOverlay? buildOverlay() {
    if (!hasText) return null;
    final screen = MediaQuery.of(context).size;
    final center = _offset ?? Offset(screen.width / 2, screen.height / 2);
    return MediaTextOverlay(
      text: _text,
      colorValue: _color.toARGB32(),
      fontSizeNorm: (_fontSize / screen.width).clamp(0.02, 0.3),
      fontStyle: _fontStyle.wireName,
      align: switch (_align) {
        TextAlign.left => 'left',
        TextAlign.right => 'right',
        _ => 'center',
      },
      xNorm: (center.dx / screen.width).clamp(0.0, 1.0),
      yNorm: (center.dy / screen.height).clamp(0.0, 1.0),
      scale: _scale,
      rotation: _rotation,
    );
  }

  void openEditor() {
    _textController.text = _text;
    setState(() => _editing = true);
    widget.onEditingChanged?.call(true);
  }

  void _closeEditor() {
    setState(() {
      _text = _textController.text.trim();
      _editing = false;
    });
    widget.onEditingChanged?.call(false);
  }

  void _cycleAlign() {
    setState(() {
      _align = switch (_align) {
        TextAlign.center => TextAlign.left,
        TextAlign.left => TextAlign.right,
        _ => TextAlign.center,
      };
    });
  }

  IconData get _alignIcon => switch (_align) {
        TextAlign.left => Icons.format_align_left,
        TextAlign.right => Icons.format_align_right,
        _ => Icons.format_align_center,
      };

  TextStyle get _overlayStyle => _fontStyle.base(_color).copyWith(
        fontSize: _fontSize,
        shadows: const [Shadow(blurRadius: 8, color: Colors.black45)],
      );

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (hasText && !_editing) _buildPlacedText(screen),
        if (_editing) _buildEditor(context),
      ],
    );
  }

  Widget _buildPlacedText(Size screen) {
    final center = _offset ?? Offset(screen.width / 2, screen.height / 2);
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: openEditor,
        onScaleStart: (details) {
          _gestureStartScale = _scale;
          _gestureStartRotation = _rotation;
        },
        onScaleUpdate: (details) {
          setState(() {
            _offset = (_offset ??
                    Offset(screen.width / 2, screen.height / 2)) +
                details.focalPointDelta;
            _scale = (_gestureStartScale * details.scale).clamp(0.4, 4.0);
            _rotation = _gestureStartRotation + details.rotation;
          });
        },
        child: Stack(
          children: [
            Positioned(
              left: center.dx - 160,
              top: center.dy - 60,
              child: Transform.rotate(
                angle: _rotation,
                child: Transform.scale(
                  scale: _scale,
                  child: SizedBox(
                    width: 320,
                    child: Text(
                      _text,
                      textAlign: _align,
                      style: _overlayStyle,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Positioned.fill(
      child: Container(
        color: Colors.transparent,
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16, top: 8),
                  child: GestureDetector(
                    onTap: _closeEditor,
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 48),
                      child: TextField(
                        controller: _textController,
                        autofocus: true,
                        maxLines: 4,
                        minLines: 1,
                        maxLength: 120,
                        textAlign: _align,
                        cursorColor: _color,
                        style: _overlayStyle,
                        decoration: const InputDecoration(
                          isCollapsed: true,
                          filled: false,
                          fillColor: Colors.transparent,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          counterText: '',
                          contentPadding: EdgeInsets.zero,
                        ),
                        onSubmitted: (_) => _closeEditor(),
                      ),
                    ),
                  ),
                  Positioned(
                    left: -8,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: SizedBox(
                        height: 220,
                        child: RotatedBox(
                          quarterTurns: -1,
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 3,
                              activeTrackColor: Colors.white,
                              inactiveTrackColor: Colors.white30,
                              thumbColor: Colors.white,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 9,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 16,
                              ),
                            ),
                            child: Slider(
                              value: _fontSize,
                              min: 14,
                              max: 64,
                              onChanged: (v) => setState(() => _fontSize = v),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                bottom: bottomInset > 0 ? bottomInset : 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: _OverlayFontStyle.values.map((style) {
                        final selected = style == _fontStyle;
                        return GestureDetector(
                          onTap: () => setState(() => _fontStyle = style),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: selected ? Colors.white : Colors.white24,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              style.label,
                              style: style
                                  .base(selected ? Colors.black : Colors.white)
                                  .copyWith(fontSize: 15),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        GestureDetector(
                          onTap: _cycleAlign,
                          child: Container(
                            width: 36,
                            height: 36,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            decoration: const BoxDecoration(
                              color: Colors.white24,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _alignIcon,
                              size: 20,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        ..._palette.map((color) {
                          final selected = color == _color;
                          return GestureDetector(
                            onTap: () => setState(() => _color = color),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              margin: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 4,
                              ),
                              width: selected ? 34 : 28,
                              height: selected ? 34 : 28,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: selected ? 3 : 1.5,
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
