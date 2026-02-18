import 'package:flutter/material.dart';
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

enum CaptureMode { photo, video }

class CameraScreen extends StatefulWidget {
  final bool useFrontCamera;

  const CameraScreen({super.key, this.useFrontCamera = false});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late CameraDescription _currentCamera;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  int _maxSeconds = 5; // şimdilik 5, premium'da 15 yapacağız
  bool _isReady = false;
  CaptureMode _mode = CaptureMode.photo;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    _currentCamera = cameras.firstWhere(
      (cam) =>
          cam.lensDirection ==
          (widget.useFrontCamera
              ? CameraLensDirection.front
              : CameraLensDirection.back),
    );

    _controller = CameraController(
      _currentCamera,
      ResolutionPreset.high,
      enableAudio: true,
    );

    await _controller.initialize();

    if (!mounted) return;

    setState(() {
      _isReady = true;
    });
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
      ResolutionPreset.high,
      enableAudio: true,
    );

    await _controller.initialize();

    _currentCamera = newCamera;

    if (!mounted) return;

    setState(() {});
  }

  Future<void> _takePicture() async {
    if (!_controller.value.isInitialized) return;

    final image = await _controller.takePicture();

    final dir = await getTemporaryDirectory();
    final filePath = path.join(
      dir.path,
      "${DateTime.now().millisecondsSinceEpoch}.jpg",
    );

    File savedImage = await File(image.path).copy(filePath);

    // -------- ORIENTATION FIX --------
    final bytes = await savedImage.readAsBytes();
    final decoded = img.decodeImage(bytes);

    if (decoded != null) {
      // EXIF orientation uygula
      img.Image fixed = img.bakeOrientation(decoded);

      if (_currentCamera.lensDirection == CameraLensDirection.front) {
        fixed = img.flipHorizontal(fixed);
      }

      final fixedBytes = img.encodeJpg(fixed, quality: 95);
      await savedImage.writeAsBytes(fixedBytes, flush: true);
    }

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PreviewScreen(file: savedImage)),
    );
  }

  Future<void> _startVideo() async {
    final micStatus = await Permission.microphone.request();
    debugPrint('🎤 Microphone permission result: $micStatus');

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Microphone permission is required for video with sound. Photo mode can still be used.',
          ),
        ),
      );
      return;
    }

    await _controller.startVideoRecording();

    setState(() {
      _isRecording = true;
      _recordSeconds = 0;
    });

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
    _recordTimer?.cancel();

    final video = await _controller.stopVideoRecording();

    setState(() {
      _isRecording = false;
    });

    final dir = await getTemporaryDirectory();
    final filePath = path.join(
      dir.path,
      "${DateTime.now().millisecondsSinceEpoch}.mp4",
    );

    final savedVideo = await File(video.path).copy(filePath);

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PreviewVideoScreen(file: savedVideo)),
    );
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

          if (_mode == CaptureMode.video && _isRecording)
            Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.fiber_manual_record,
                    color: Colors.red,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _recordSeconds.toString().padLeft(2, '0'),
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          if (!_isRecording)
            Positioned(
              bottom: 120,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _mode = CaptureMode.photo),
                    child: Text(
                      "PHOTO",
                      style: TextStyle(
                        color: _mode == CaptureMode.photo
                            ? Colors.white
                            : Colors.white54,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 40),
                  GestureDetector(
                    onTap: () => setState(() => _mode = CaptureMode.video),
                    child: Text(
                      "VIDEO",
                      style: TextStyle(
                        color: _mode == CaptureMode.video
                            ? Colors.white
                            : Colors.white54,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),

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
                GestureDetector(
                  onTap: () async {
                    if (_mode == CaptureMode.photo) {
                      await _takePicture();
                    } else {
                      if (_isRecording) {
                        await _stopVideo();
                      } else {
                        await _startVideo();
                      }
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 75,
                    height: 75,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      color: _mode == CaptureMode.video
                          ? Colors.red
                          : Colors.transparent,
                    ),
                    child: _mode == CaptureMode.video && _isRecording
                        ? Center(
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(
                                  6,
                                ), // kare efekti
                              ),
                            ),
                          )
                        : null,
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
        ],
      ),
    );
  }
}
