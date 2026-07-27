import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Metin overlay'inin stil ön-ayarları (Instagram'daki Modern/Classic/Signature
/// şeridine karşılık gelir).
enum _TextFontStyle { modern, classic, typewriter }

extension _TextFontStyleX on _TextFontStyle {
  String get label => switch (this) {
        _TextFontStyle.modern => 'Modern',
        _TextFontStyle.classic => 'Classic',
        _TextFontStyle.typewriter => 'Typewriter',
      };

  TextStyle base(Color color) => switch (this) {
        _TextFontStyle.modern => TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        _TextFontStyle.classic => TextStyle(
            color: color,
            fontFamily: 'Georgia',
            fontWeight: FontWeight.w600,
          ),
        _TextFontStyle.typewriter => TextStyle(
            color: color,
            fontFamily: 'Courier',
            fontWeight: FontWeight.w700,
          ),
      };
}

/// Fotoğraf çekimi sonrası önizleme + Instagram tarzı metin düzenleme ekranı.
/// Yazı: sürüklenebilir, iki parmakla büyütülüp küçültülebilir ve döndürülebilir;
/// font stili, renk paleti, hizalama ve arka plan (pill) seçenekleri vardır.
/// "Use Photo" ile onaylanınca yazı görüntüye kalıcı gömülür (burn-in);
/// indir butonu kompozit hâli galeriye kaydeder.
class PreviewScreen extends StatefulWidget {
  final File file;

  /// Kamera çekiminden geliyorsa: ham fotoğraf ANINDA gösterilir, ağır
  /// orientation/crop/resize işlemesi arka planda yapılıp hazır olunca
  /// gösterim güncellenir. Bu ikisi null ise (galeriden vb.) işleme yapılmaz.
  final bool? isFrontCamera;
  final double? screenAr;

  const PreviewScreen({
    super.key,
    required this.file,
    this.isFrontCamera,
    this.screenAr,
  });

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  final GlobalKey _composeKey = GlobalKey();
  final TextEditingController _textController = TextEditingController();

  // ---- Overlay state ----
  String _text = '';
  Color _color = Colors.white;
  Offset? _offset; // null → ekran ortası
  double _scale = 1.0;
  double _rotation = 0.0; // radyan
  double _fontSize = 28; // sol dikey slider ile ayarlanır (Instagram gibi)
  TextAlign _align = TextAlign.center;
  _TextFontStyle _fontStyle = _TextFontStyle.modern;

  bool _editing = false;
  bool _busy = false;

  // Instant-preview state: önce ham dosya gösterilir, işleme bitince değişir.
  late File _displayFile;
  bool _processing = false;
  bool _mirrorInstant = false; // ham ön-kamera fotoğrafını gösterirken aynala

  // Pinch jesti için başlangıç değerleri.
  double _gestureStartScale = 1.0;
  double _gestureStartRotation = 0.0;

  @override
  void initState() {
    super.initState();
    // Released davranışı: ham kamera dosyasını olduğu gibi kullan. Flutter'ın
    // native decoder'ı EXIF orientation + ayna bayrağını doğru uyguluyor.
    // `image` paketiyle re-encode etmek (bakeOrientation) ayna bayrağını
    // düşürüp ön kamera fotoğrafını ters çeviriyordu — o yüzden işleme kaldırıldı.
    _displayFile = widget.file;
    _processing = false;
    _mirrorInstant = false;
  }

  static const List<Color> _palette = [
    Colors.white,
    Colors.black,
    AppColors.magenta,
    AppColors.blue,
    AppColors.teal,
    AppColors.orange,
    Color(0xFFFF3B30), // kırmızı
    Color(0xFFFFCC00), // sarı
    Color(0xFF34C759), // yeşil
    Color(0xFF5E5CE6), // indigo
    Color(0xFFFF2D95), // pembe
    Color(0xFF8E8E93), // gri
  ];

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  bool get _hasText => _text.trim().isNotEmpty;

  Color get _effectiveTextColor => _color;

  TextStyle get _overlayStyle {
    return _fontStyle.base(_color).copyWith(
          fontSize: _fontSize,
          shadows: const [Shadow(blurRadius: 8, color: Colors.black45)],
        );
  }

  // ---------- Burn-in / kaydetme ----------

  Future<File> _composedFile() async {
    // İşlenmiş dosya varsa onu kullan (ham değil).
    if (!_hasText) return _displayFile;

    final boundary = _composeKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) return _displayFile;

    final logicalWidth = boundary.size.width;
    final pixelRatio = logicalWidth > 0 ? (1080 / logicalWidth) : 3.0;
    final uiImage = await boundary.toImage(pixelRatio: pixelRatio);
    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return widget.file;

    final decoded = img.decodePng(byteData.buffer.asUint8List());
    if (decoded == null) return widget.file;
    img.Image fixed = decoded;
    if (fixed.width > 720) {
      final targetH = (720 * fixed.height / fixed.width).round();
      fixed = img.copyResize(
        fixed,
        width: 720,
        height: targetH,
        interpolation: img.Interpolation.linear,
      );
    }
    final jpgBytes = img.encodeJpg(fixed, quality: 92);

    final dir = await getTemporaryDirectory();
    final filePath = path.join(
      dir.path,
      '${DateTime.now().millisecondsSinceEpoch}_edited.jpg',
    );
    return File(filePath).writeAsBytes(jpgBytes, flush: true);
  }

  Future<void> _usePhoto() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // İşleme henüz bitmediyse bitene kadar bekle (kullanıcı hemen onayladıysa).
      await _awaitProcessing();
      final result = await _composedFile();
      if (!mounted) return;
      // TEK pop: sonucu CameraScreen'e döndür. Kamera bunu await edip kendini
      // kapatır (aşağıya bak). Böylece kamera "alttan" pop edilmiyor ve CameraX
      // surface dispose crash'i olmuyor.
      Navigator.pop(context, result);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// İşleme sürüyorsa bitene kadar bekler (en fazla ~5 sn güvenlik sınırı).
  Future<void> _awaitProcessing() async {
    var waited = 0;
    while (_processing && waited < 5000 && mounted) {
      await Future.delayed(const Duration(milliseconds: 50));
      waited += 50;
    }
  }

  Future<void> _download() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _awaitProcessing();
      final result = await _composedFile();
      await Gal.putImage(result.path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved to gallery'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } on GalException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.type == GalExceptionType.accessDenied
                ? 'Photo library permission is required to save.'
                : 'Could not save. Please try again.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- Düzenleme ----------

  void _openEditor() {
    _textController.text = _text;
    setState(() => _editing = true);
  }

  void _closeEditor() {
    setState(() {
      _text = _textController.text.trim();
      _editing = false;
    });
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

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Görüntü + yazı: burn-in için RepaintBoundary ile sarılı.
          Positioned.fill(
            child: RepaintBoundary(
              key: _composeKey,
              child: Stack(
                children: [
                  Positioned.fill(
                    // Ham ön-kamera fotoğrafını gösterirken aynala (kamera
                    // önizlemesi de aynalıydı); işlenmiş dosya zaten aynalı.
                    child: Transform(
                      alignment: Alignment.center,
                      transform: _mirrorInstant
                          ? (Matrix4.identity()..scaleByDouble(-1.0, 1.0, 1.0, 1.0))
                          : Matrix4.identity(),
                      child: Image.file(
                        _displayFile,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                    ),
                  ),
                  if (_hasText && !_editing) _buildPlacedText(screen),
                ],
              ),
            ),
          ),

          // Sağ üst araçlar.
          if (!_editing)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 12,
              child: Column(
                children: [
                  _ToolButton(
                    icon: Icons.text_fields_rounded,
                    onTap: _openEditor,
                  ),
                  const SizedBox(height: 12),
                  _ToolButton(icon: Icons.download_rounded, onTap: _download),
                ],
              ),
            ),

          if (_editing) _buildEditor(context),

          if (!_editing) _buildBottomButtons(),
        ],
      ),
    );
  }

  /// Fotoğrafın üzerine yerleştirilmiş yazı — sürükle + pinch (ölçek/rotasyon).
  Widget _buildPlacedText(Size screen) {
    final center = _offset ?? Offset(screen.width / 2, screen.height / 2);
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: _openEditor,
        onScaleStart: (details) {
          _gestureStartScale = _scale;
          _gestureStartRotation = _rotation;
        },
        onScaleUpdate: (details) {
          setState(() {
            // Tek parmak sürükleme de scale jestinin focalPoint delta'sıyla gelir.
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
                  child: Container(
                    width: 320,
                    alignment: Alignment.center,
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

  /// Instagram tarzı düzenleme modu: üstte Done, ortada metin, altta stil araçları.
  Widget _buildEditor(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Positioned.fill(
      child: Container(
        // Arka plan şeffaf — fotoğraf olduğu gibi görünür, kutu/karartma yok.
        color: Colors.transparent,
        child: Column(
          children: [
            // Üst bar — Done.
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

            // Metin alanı — kutu/çerçeve yok, yazı doğrudan fotoğrafın
            // üzerinde (Instagram gibi). Solda dikey boyut slider'ı.
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
                          cursorColor: _effectiveTextColor,
                          style: _overlayStyle,
                          // Global temadaki filled/fillColor kutu çiziyordu —
                          // burada tamamen şeffaf: sadece imleç ve yazı görünür.
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

                  // Sol kenarda dikey yazı boyutu slider'ı (Instagram gibi).
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
                              onChanged: (v) =>
                                  setState(() => _fontSize = v),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Alt araç şeridi — klavyenin hemen üstünde.
            Padding(
              padding: EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset : 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Font stili seçici (Modern / Classic / Typewriter).
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: _TextFontStyle.values.map((style) {
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
                                  .base(
                                    selected ? Colors.black : Colors.white,
                                  )
                                  .copyWith(fontSize: 15),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Araçlar: hizalama + arka plan + renk paleti.
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        _EditorToolChip(
                          icon: _alignIcon,
                          onTap: _cycleAlign,
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

  Widget _buildBottomButtons() {
    return Positioned(
      left: 24,
      right: 24,
      bottom: 24,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: const VisualDensity(
                    horizontal: VisualDensity.minimumDensity,
                    vertical: VisualDensity.minimumDensity,
                  ),
                  backgroundColor: Colors.transparent,
                  side: const BorderSide(color: Colors.white70),
                  foregroundColor: Colors.white,
                ),
                child: const Text("Retake"),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _busy ? null : _usePhoto,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: const VisualDensity(
                    horizontal: VisualDensity.minimumDensity,
                    vertical: VisualDensity.minimumDensity,
                  ),
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Text("Use Photo"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ToolButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black38,
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onTap,
      ),
    );
  }
}

class _EditorToolChip extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _EditorToolChip({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white24,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: Colors.white),
      ),
    );
  }
}
