import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../../../../main.dart'; // cameras buradan geliyor
import 'preview_screen.dart';
import 'package:image/image.dart' as img;
import 'preview_video_screen.dart';
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import '../data/video_mirror.dart';
import '../data/volume_shutter.dart';

class CameraScreen extends StatefulWidget {
  final bool useFrontCamera;
  final bool optimizeForUpload;

  const CameraScreen({
    super.key,
    this.useFrontCamera = false,
    this.optimizeForUpload = false,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with SingleTickerProviderStateMixin {
  late CameraController _controller;
  late CameraDescription _currentCamera;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  final int _maxSeconds =
      60; // maksimum video süresi (Instagram tarzı halka bununla dolar)
  bool _isReady = false;
  bool _cameraPermissionDenied = false;
  bool _cameraPermissionPermanentlyDenied = false;
  bool _microphoneGranted = false;
  bool _isRecording = false;
  bool _processingVideo = false;

  // ---- Instagram tarzı basılı-tut jest state'i ----
  /// Kayıt long-press ile mi başladı — parmak çekilince direkt durur.
  bool _gestureRecording = false;

  /// Parmak hâlâ ekranda mı (izin dialogu sırasında kalkarsa kayıt başlamasın).
  bool _longPressActive = false;
  // Reentrancy guard'ları — çift tetiklenmeyi engeller (örn. max süre timer'ı
  // ile parmak bırakma aynı anda stop çağırabilir).
  bool _isStartingVideo = false;
  bool _isStoppingVideo = false;
  bool _isCapturingPhoto = false;

  /// Buton etrafındaki logo-renkli şerit — loading gibi 0→1 arası
  /// _maxSeconds sürede butonun etrafında ilerler.
  late final AnimationController _ringController = AnimationController(
    vsync: this,
    duration: Duration(seconds: _maxSeconds),
  );

  ResolutionPreset _captureResolutionPreset() {
    // Her zaman yüksek çözünürlük — 720p (high) tüm platformlarda iyi kalite/boyut dengesi.
    return ResolutionPreset.high;
  }

  Future<void> _forceFlashOff() async {
    try {
      await _controller.setFlashMode(FlashMode.off);
    } catch (_) {
      // Some devices/cameras may not support flash mode control.
    }
  }

  @override
  void initState() {
    super.initState();
    VolumeShutter.listen(_handleVolumeShutter);
    _initCamera();
  }

  Future<void> _handleVolumeShutter() async {
    if (!mounted || !_isReady || _processingVideo) return;
    await _takePicture();
  }

  Future<void> _setVolumeShutterEnabled(bool enabled) async {
    try {
      await VolumeShutter.setEnabled(enabled);
    } on PlatformException {
      // Unsupported platform/version: retain the normal system button behavior.
    } on MissingPluginException {
      // Allows widget tests and non-mobile targets to use the camera screen.
    }
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (!mounted) return;
      setState(() {
        _cameraPermissionDenied = true;
        _cameraPermissionPermanentlyDenied = status.isPermanentlyDenied;
        _isReady = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _cameraPermissionDenied = false;
      _cameraPermissionPermanentlyDenied = false;
    });
    _microphoneGranted = await Permission.microphone.isGranted;

    _currentCamera = cameras.firstWhere(
      (cam) =>
          cam.lensDirection ==
          (widget.useFrontCamera
              ? CameraLensDirection.front
              : CameraLensDirection.back),
    );

    _controller = CameraController(
      _currentCamera,
      _captureResolutionPreset(),
      enableAudio: true,
    );

    try {
      await _controller.initialize();
      // Portre modunu kilitle — hem fotoğraf hem video her zaman dikey çekilsin.
      await _controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await _forceFlashOff();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cameraPermissionDenied = true;
        _isReady = false;
      });
      return;
    }

    if (!mounted) return;

    setState(() {
      _isReady = true;
    });
    await _setVolumeShutterEnabled(true);
  }

  Future<void> _switchCamera() async {
    final newLensDirection =
        _currentCamera.lensDirection == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;

    final newCamera = cameras.firstWhere(
      (cam) => cam.lensDirection == newLensDirection,
    );

    await _controller.dispose();

    _controller = CameraController(
      newCamera,
      _captureResolutionPreset(),
      enableAudio: true,
    );

    await _controller.initialize();
    await _controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
    await _forceFlashOff();

    _currentCamera = newCamera;

    if (!mounted) return;

    setState(() {});
  }

  Future<void> _takePicture() async {
    if (!_controller.value.isInitialized) return;
    if (_isCapturingPhoto || _isRecording) return;
    _isCapturingPhoto = true;
    try {
      await _takePictureInner();
    } finally {
      _isCapturingPhoto = false;
    }
  }

  Future<void> _takePictureInner() async {
    // Ekranın gerçek oranını async'ten önce oku (context await sonrası geçersiz olabilir).
    // Bu oran = kullanıcının kamera önizlemesinde tam gördüğü alan.
    final screenSize = MediaQuery.of(context).size;
    final screenAr =
        screenSize.width / screenSize.height; // örn. 390/844 ≈ 0.462

    final image = await _controller.takePicture();

    final dir = await getTemporaryDirectory();
    final filePath = path.join(
      dir.path,
      "${DateTime.now().millisecondsSinceEpoch}.jpg",
    );

    final File savedImage = await File(image.path).copy(filePath);

    // -------- ORIENTATION + MIRROR FIX (release davranışı) --------
    // Bu düzeltme her zaman burada (çekimden hemen sonra, preview'dan önce)
    // yapılıyordu ve TestFlight'ta doğru çalışıyor. Yeni kamera/yazı UI'ını
    // eklerken yanlışlıkla kaldırılmıştı → ön kamera aynalı (selfie) upload
    // ediliyordu. Geri getiriyoruz.
    final bytes = await savedImage.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded != null) {
      // 1) EXIF orientation uygula → piksel verisi doğru yöne döner.
      img.Image fixed = img.bakeOrientation(decoded);

      // 2) Ön kamera aynalama: CameraX ön kamera STILL fotoğrafını aynalı
      // (selfie görünümü) kaydediyor; gerçeğe uygun olması (elin sağdaysa
      // sağda) için geri çeviriyoruz.
      if (_currentCamera.lensDirection == CameraLensDirection.front) {
        fixed = img.flipHorizontal(fixed);
      }

      // NOT: Eski "yataysa 90° döndür" adımı KALDIRILDI — Android'de
      // bakeOrientation sonrası fotoğrafları yanlış çeviriyordu.
      // bakeOrientation + lockCaptureOrientation yönü zaten doğru veriyor.

      // 3) Kamera önizlemesinde görülen alanla birebir eşleştir
      //    (preview BoxFit.cover ile ekranı dolduruyordu → aynı center-crop).
      final imageAr = fixed.width / fixed.height;
      if ((imageAr - screenAr).abs() > 0.005) {
        if (imageAr > screenAr) {
          final newW = (fixed.height * screenAr).round();
          final x = ((fixed.width - newW) / 2).round();
          fixed = img.copyCrop(
            fixed,
            x: x,
            y: 0,
            width: newW,
            height: fixed.height,
          );
        } else {
          final newH = (fixed.width / screenAr).round();
          final y = ((fixed.height - newH) / 2).round();
          fixed = img.copyCrop(
            fixed,
            x: 0,
            y: y,
            width: fixed.width,
            height: newH,
          );
        }
      }

      // Video ile aynı genişlik (720px) — AR korunur.
      if (fixed.width != 720) {
        final targetH = (720 * fixed.height / fixed.width).round();
        fixed = img.copyResize(
          fixed,
          width: 720,
          height: targetH,
          interpolation: img.Interpolation.linear,
        );
      }

      final fixedBytes = img.encodeJpg(fixed, quality: 92);
      await savedImage.writeAsBytes(fixedBytes, flush: true);
    }

    if (!mounted) return;

    // Preview'ı aç. Dosya artık doğru yönde/aynasız — PreviewScreen ham
    // gösterip yazı overlay'i ekliyor (isolate işleme yok).
    //
    // Preview'ı await ediyoruz: "Use Photo" ile sonuç dönerse kamerayı KENDİMİZ
    // kapatıp sonucu çağırana forward ediyoruz (standart desen). Böylece kamera
    // "alttan" pop edilmiyor ve CameraX surface dispose crash'i olmuyor.
    await _setVolumeShutterEnabled(false);
    if (!mounted) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PreviewScreen(
          file: savedImage,
          isFrontCamera:
              _currentCamera.lensDirection == CameraLensDirection.front,
          screenAr: screenAr,
        ),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      Navigator.pop(context, result);
    } else {
      await _setVolumeShutterEnabled(true);
    }
    // result == null → kullanıcı "Retake" dedi, kamerada kal.
  }

  /// [fromGesture] true ise kayıt basılı-tut jestiyle başlatılmıştır:
  /// izin akışı sırasında parmak kalktıysa kayıt hiç başlamaz ve parmak
  /// bırakılınca (kilitlenmediyse) otomatik durur.
  Future<void> _startVideo({bool fromGesture = false}) async {
    if (_isStartingVideo || _isRecording || !_controller.value.isInitialized) {
      return;
    }
    _isStartingVideo = true;
    try {
      await _startVideoInner(fromGesture: fromGesture);
    } finally {
      _isStartingVideo = false;
    }
  }

  Future<void> _startVideoInner({required bool fromGesture}) async {
    PermissionStatus micStatus;
    if (_microphoneGranted) {
      micStatus = PermissionStatus.granted;
    } else {
      final currentMicStatus = await Permission.microphone.status;
      micStatus = currentMicStatus.isGranted
          ? currentMicStatus
          : await Permission.microphone.request();
      if (micStatus.isGranted) {
        _microphoneGranted = true;
      }
    }

    if (micStatus.isPermanentlyDenied) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Microphone access required'),
          content: const Text(
            'Please enable microphone access from Settings to record videos with audio.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                openAppSettings();
                Navigator.pop(context);
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      return;
    }

    if (!micStatus.isGranted) {
      if (!mounted) return;
      await showPremiumErrorDialog(
        context,
        message:
            'Microphone permission is required for video with sound. Photo mode can still be used.',
      );
      return;
    }

    // İzin akışı (dialog) sırasında parmak kalktıysa jest kaydını başlatma.
    if (fromGesture && !_longPressActive) return;
    if (!mounted) return;

    await _controller.startVideoRecording();
    HapticFeedback.lightImpact();
    _ringController.forward(from: 0);

    setState(() {
      _isRecording = true;
      _recordSeconds = 0;
      _gestureRecording = fromGesture;
    });

    // Parmak, startVideoRecording await'i sırasında kalkmış olabilir —
    // kayıt başladıysa ve jest bittiyse hemen durdur.
    if (fromGesture && !_longPressActive) {
      unawaited(_stopVideo());
      return;
    }

    _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _recordSeconds++;
      });

      if (_recordSeconds >= _maxSeconds) {
        _stopVideo();
      }
    });
  }

  Future<void> _stopVideo() async {
    // Çift stop koruması: max süre timer'ı ile parmak bırakma / stop butonuna
    // basma aynı anda tetiklenebilir.
    if (_isStoppingVideo) return;
    // Controller'a da bak: state ile native kayıt durumu ayrışmış olabilir
    // (örn. önceki stop denemesi exception yediyse).
    if (!_isRecording && !_controller.value.isRecordingVideo) return;
    _isStoppingVideo = true;
    try {
      await _stopVideoInner();
    } finally {
      _isStoppingVideo = false;
    }
  }

  Future<void> _stopVideoInner() async {
    _recordTimer?.cancel();
    _ringController.stop();
    _ringController.reset();

    // stopVideoRecording çok kısa kayıtlarda / start-stop yarışında platform
    // exception atabilir. Ne olursa olsun UI state'i resetlenmeli — yoksa
    // buton "kayıtta" takılı kalır ve kayıt hiç durmuyor gibi görünür.
    XFile? video;
    try {
      video = await _controller.stopVideoRecording();
    } catch (e) {
      debugPrint('📹 stopVideoRecording failed: $e');
    }

    if (mounted) {
      setState(() {
        _isRecording = false;
        _gestureRecording = false;
      });
    } else {
      _isRecording = false;
      _gestureRecording = false;
    }

    if (video == null) return;

    final dir = await getTemporaryDirectory();
    final filePath = path.join(
      dir.path,
      "${DateTime.now().millisecondsSinceEpoch}.mp4",
    );

    File savedVideo = await File(video.path).copy(filePath);

    // Android'de CameraX ön kamera videosunu piksel verisine gömülü aynalı kaydeder.
    // iOS'ta bu sorun yok (preferredTransform metadata ile yönetilir).
    if (Platform.isAndroid &&
        _currentCamera.lensDirection == CameraLensDirection.front) {
      if (mounted) setState(() => _processingVideo = true);
      savedVideo = await VideoMirror.mirrorFront(savedVideo);
      if (mounted) setState(() => _processingVideo = false);
    }

    if (!mounted) return;
    // Preview'ı await et; "Use Video" ile sonuç dönerse kamerayı kendimiz
    // kapatıp forward et (fotoğrafla aynı standart desen — alttan pop yok).
    await _setVolumeShutterEnabled(false);
    if (!mounted) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PreviewVideoScreen(file: savedVideo)),
    );
    if (!mounted) return;
    if (result != null) {
      Navigator.pop(context, result);
    } else {
      await _setVolumeShutterEnabled(true);
    }
  }

  @override
  void dispose() {
    unawaited(_setVolumeShutterEnabled(false));
    VolumeShutter.stopListening();
    _recordTimer?.cancel();
    _ringController.dispose();
    // CameraX bazı geçiş durumlarında dispose'ta surface hatası atabiliyor;
    // exception'ın yukarı sızıp uygulamayı bozmasını engelle.
    try {
      _controller.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraPermissionDenied) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.no_photography_outlined,
                  color: Colors.white,
                  size: 56,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Camera permission is required.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                if (_cameraPermissionPermanentlyDenied)
                  ElevatedButton(
                    onPressed: openAppSettings,
                    child: const Text('Open Settings'),
                  )
                else
                  ElevatedButton(
                    onPressed: _initCamera,
                    child: const Text('Retry'),
                  ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_isReady) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller.value.previewSize!.height,
                height: _controller.value.previewSize!.width,
                child: CameraPreview(_controller),
              ),
            ),
          ),

          // Süre göstergesi şimdilik gizli — ilerleme butonun etrafındaki
          // renkli şeritten takip ediliyor.
          // PHOTO/VIDEO mod seçici kaldırıldı: tek dokunuş = fotoğraf,
          // basılı tut = video.
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // boş alan (denge için)
                const SizedBox(width: 60),

                // SHUTTER BUTTON
                // Tek dokunuş: fotoğraf. Basılı tut (Instagram tarzı): video —
                // parmak çekilince direkt durur; buton etrafında logo-renkli
                // şerit loading gibi ilerler.
                GestureDetector(
                  onTap: () async {
                    if (_isRecording) {
                      // Güvenlik ağı: state bir şekilde kayıtta takıldıysa
                      // dokunuş kaydı durdurur.
                      await _stopVideo();
                      return;
                    }
                    await _takePicture();
                  },
                  onLongPressStart: (_) {
                    if (_isRecording) return;
                    _longPressActive = true;
                    unawaited(_startVideo(fromGesture: true));
                  },
                  onLongPressEnd: (_) {
                    _longPressActive = false;
                    if (_gestureRecording) {
                      unawaited(_stopVideo());
                    }
                  },
                  onLongPressCancel: () {
                    _longPressActive = false;
                    if (_gestureRecording) {
                      unawaited(_stopVideo());
                    }
                  },
                  child: AnimatedBuilder(
                    animation: _ringController,
                    builder: (context, child) {
                      return CustomPaint(
                        // Kayıt sırasında logo-renkli şerit loading gibi
                        // butonun etrafında ilerler (60 sn'de tam tur).
                        foregroundPainter: _isRecording
                            ? _RecordRingPainter(
                                progress: _ringController.value,
                              )
                            : null,
                        child: child,
                      );
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      // Jest kaydı sırasında buton büyür (Instagram hissi).
                      width: _gestureRecording && _isRecording ? 92 : 75,
                      height: _gestureRecording && _isRecording ? 92 : 75,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          // Kayıt sırasında beyaz çerçeve yerine renkli şerit var.
                          color: _isRecording
                              ? Colors.transparent
                              : Colors.white,
                          width: 4,
                        ),
                        // Instagram tarzı: kırmızı yok — kayıtta hafif saydam
                        // beyaz zemin, ortada beyaz kare (stop).
                        color: _isRecording
                            ? Colors.white24
                            : Colors.transparent,
                      ),
                      child: _isRecording
                          ? Center(
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(
                                    6,
                                  ), // kare efekti (stop)
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
                ),

                // SWITCH CAMERA BUTTON
                if (!_isRecording)
                  IconButton(
                    icon: const Icon(
                      Icons.cameraswitch,
                      color: Colors.white,
                      size: 30,
                    ),
                    onPressed: _switchCamera,
                  )
                else
                  const SizedBox(
                    width: 48,
                  ), // layout bozulmasın diye placeholder
              ],
            ),
          ),

          Positioned(
            top: 50,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          if (_processingVideo)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 14),
                      Text(
                        'Processing…',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Kayıt sırasında shutter butonunun etrafında loading gibi ilerleyen,
/// logo renklerinden (magenta → mavi → teal → turuncu) oluşan renkli şerit.
/// [progress] 0→1: şerit saat 12'den başlayıp max sürede tam tur tamamlar.
class _RecordRingPainter extends CustomPainter {
  final double progress; // 0..1

  const _RecordRingPainter({required this.progress});

  static const List<Color> _logoColors = [
    AppColors.magenta,
    AppColors.blue,
    AppColors.teal,
    AppColors.orange,
    AppColors.magenta, // sweep başlangıca yumuşak dönsün
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    const strokeWidth = 5.0;
    final center = Offset(size.width / 2, size.height / 2);
    // Şerit, butonun hemen dışında dursun.
    final radius = (size.shortestSide / 2) + 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Saat 12'den başla (üst orta).
    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress.clamp(0.0, 1.0);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: _logoColors,
        transform: const GradientRotation(startAngle),
      ).createShader(rect);

    canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
  }

  @override
  bool shouldRepaint(_RecordRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
