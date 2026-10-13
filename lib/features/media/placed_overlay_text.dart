import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Foto/video üzerine yerleştirilmiş yazı — Instagram tarzı jestler.
///
/// - Tek parmak: yalnızca yazının üstünden (cömert bir tutma payıyla)
///   başlarsa yazıyı sürükler; boş alana dokunmak yazıyı oynatmaz.
/// - İki parmak: ekranın HERHANGİ bir yerinde büyütür/küçültür ve döndürür
///   (iki parmağın da küçük yazının üstünde olması gerekmez).
/// - Dokunma: yalnızca yazıya dokununca [onTap] (düzenleyiciyi açar).
///
/// Yerleşim, izleyici tarafıyla ([MediaTextOverlayView]) birebir aynı formülü
/// kullanır (320px kutu, merkezin 60px üstünden başlar) — kayıtlı eski
/// overlay'ler kaymasın diye bu formül değiştirilmemeli.
class PlacedOverlayText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final TextAlign textAlign;

  /// Yazının ekrandaki merkezi; null → ekran ortası.
  final Offset? center;
  final double scale;
  final double rotation;
  final void Function(Offset center, double scale, double rotation) onTransform;
  final VoidCallback onTap;

  const PlacedOverlayText({
    super.key,
    required this.text,
    required this.style,
    required this.textAlign,
    required this.center,
    required this.scale,
    required this.rotation,
    required this.onTransform,
    required this.onTap,
  });

  static const double boxWidth = 320;
  static const double boxTopFromCenter = 60;

  @override
  State<PlacedOverlayText> createState() => _PlacedOverlayTextState();
}

class _PlacedOverlayTextState extends State<PlacedOverlayText> {
  static const double _minScale = 0.4;
  static const double _maxScale = 4.0;
  // ~4°: bu kadar yakınsa yazı düz açıya oturur.
  static const double _rotationSnap = 0.07;
  // Küçük yazıyı parmakla yakalamak kolay olsun.
  static const double _grabPadding = 28;

  final GlobalKey _textKey = GlobalKey();

  bool _moving = false;
  double _startScale = 1.0;
  double _startRotation = 0.0;
  bool _snapped = true;

  // Parmakların ham konumları. Flutter jesti ancak birkaç piksellik tolerans
  // aşılınca başlatır ve o mesafeyi delta'ya yansıtmaz; yazı parmağın
  // gerisinde kalmasın diye hareketi parmağın DEĞDİĞİ andan ölçüyoruz.
  final Map<int, Offset> _pointers = {};
  Offset? _baselineFocal;
  Offset _startCenter = Offset.zero;
  Offset _startFocal = Offset.zero;

  // Parmak eklenip/kalkınca Flutter jesti o anki konumdan yeniden başlatır;
  // temel odak noktası da o anki parmakların ortalaması olmalı.
  void _rebaseline() {
    if (_pointers.isEmpty) {
      _baselineFocal = null;
      return;
    }
    var sum = Offset.zero;
    for (final p in _pointers.values) {
      sum += p;
    }
    _baselineFocal = sum / _pointers.length.toDouble();
  }

  /// Yazının (dönmüş/ölçeklenmiş hâliyle) ekrandaki sınırları + tutma payı.
  Rect? _textBounds() {
    final box = _textKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;

    // Kutu 320px sabit; asıl yazı genişliği kısa metinde çok daha dar.
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      textAlign: widget.textAlign,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: box.size.width);
    final textWidth = painter.width;
    painter.dispose();

    final left = switch (widget.textAlign) {
      TextAlign.left || TextAlign.start => 0.0,
      TextAlign.right || TextAlign.end => box.size.width - textWidth,
      _ => (box.size.width - textWidth) / 2,
    };
    final corners = [
      Offset(left, 0),
      Offset(left + textWidth, 0),
      Offset(left, box.size.height),
      Offset(left + textWidth, box.size.height),
    ].map(box.localToGlobal).toList();

    var bounds = Rect.fromPoints(corners[0], corners[1]);
    for (final c in corners.skip(2)) {
      bounds = bounds.expandToInclude(Rect.fromCircle(center: c, radius: 0));
    }
    return bounds.inflate(_grabPadding);
  }

  bool _hitsText(Offset globalPosition) =>
      _textBounds()?.contains(globalPosition) ?? false;

  double _snapRotation(double rotation) {
    // [-π, π] aralığına indirip 0'a yakınlığı ölç.
    final normalized = math.atan2(math.sin(rotation), math.cos(rotation));
    final nearZero = normalized.abs() < _rotationSnap;
    if (nearZero && !_snapped) HapticFeedback.selectionClick();
    _snapped = nearZero;
    return nearZero ? 0.0 : rotation;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final center = widget.center ?? size.center(Offset.zero);

        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (e) {
            _pointers[e.pointer] = e.position;
            _rebaseline();
          },
          onPointerMove: (e) => _pointers[e.pointer] = e.position,
          onPointerUp: (e) {
            _pointers.remove(e.pointer);
            _rebaseline();
          },
          onPointerCancel: (e) {
            _pointers.remove(e.pointer);
            _rebaseline();
          },
          child: GestureDetector(
            // Tam ekran: iki parmaklı jest yazının dışında da yakalanır.
            behavior: HitTestBehavior.translucent,
            // Ölçek, parmakların değdiği andaki aralığa göre hesaplanır.
            dragStartBehavior: DragStartBehavior.down,
            onTapUp: (details) {
              if (_hitsText(details.globalPosition)) widget.onTap();
            },
            onScaleStart: (details) {
              // Parmak eklenip çıkınca Flutter jesti yeniden başlatır; her
              // başlangıçta o anki değerler temel alınır.
              _startScale = widget.scale;
              _startRotation = widget.rotation;
              _startCenter = center;
              _startFocal = _baselineFocal ?? details.focalPoint;
              _snapped = widget.rotation == 0;
              final wasMoving = _moving;
              // İki parmak her yerde; tek parmak yalnızca yazıya değdiyse.
              // İki parmaktan biri kalkınca kalan parmakla sürükleme sürer.
              _moving =
                  wasMoving ||
                  details.pointerCount >= 2 ||
                  _hitsText(_startFocal);
              if (_moving && !wasMoving) HapticFeedback.lightImpact();
            },
            onScaleUpdate: (details) {
              if (!_moving) return;
              final next = _startCenter + (details.focalPoint - _startFocal);
              widget.onTransform(
                // Yazı ekran dışına kaybolmasın.
                Offset(
                  next.dx.clamp(0.0, size.width),
                  next.dy.clamp(0.0, size.height),
                ),
                (_startScale * details.scale).clamp(_minScale, _maxScale),
                details.pointerCount >= 2
                    ? _snapRotation(_startRotation + details.rotation)
                    : widget.rotation,
              );
            },
            // Parmak sayısı değişince de "end" gelir; tamamen bırakılınca bitir.
            onScaleEnd: (_) {
              if (_pointers.isEmpty) _moving = false;
            },
            child: Stack(
              children: [
                Positioned(
                  left: center.dx - PlacedOverlayText.boxWidth / 2,
                  top: center.dy - PlacedOverlayText.boxTopFromCenter,
                  child: Transform.rotate(
                    angle: widget.rotation,
                    child: Transform.scale(
                      scale: widget.scale,
                      child: SizedBox(
                        key: _textKey,
                        width: PlacedOverlayText.boxWidth,
                        child: Text(
                          widget.text,
                          textAlign: widget.textAlign,
                          style: widget.style,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
