import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:kmstry_frontend/features/media/media_text_overlay.dart';
import 'package:kmstry_frontend/features/media/text_overlay_composer.dart';
import 'package:video_player/video_player.dart';

class PreviewVideoScreen extends StatefulWidget {
  final File file;

  /// true ise yalnızca izleme modu: Retake / Use Video butonları yerine
  /// kapat butonu gösterilir (örn. check-in'de eklenen videoyu tekrar izlemek).
  final bool viewOnly;

  /// İzleme modunda videonun üstüne çizilecek metin overlay'i (varsa).
  final MediaTextOverlay? overlay;

  const PreviewVideoScreen({
    super.key,
    required this.file,
    this.viewOnly = false,
    this.overlay,
  });

  @override
  State<PreviewVideoScreen> createState() => _PreviewVideoScreenState();
}

class _PreviewVideoScreenState extends State<PreviewVideoScreen> {
  late VideoPlayerController _videoController;
  final GlobalKey<TextOverlayComposerState> _composerKey =
      GlobalKey<TextOverlayComposerState>();
  bool _ready = false;
  bool _saving = false;
  bool _editingText = false;

  Future<void> _download() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await Gal.putVideo(widget.file.path);
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
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _videoController = VideoPlayerController.file(widget.file);
    _videoController.initialize().then((_) {
      if (!mounted) return;
      _videoController
        ..setLooping(true)
        ..play();
      setState(() => _ready = true);
    });
  }

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }

  Widget _buildVideoLayer() {
    if (!_ready) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: Colors.white,
          ),
        ),
      );
    }
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: _videoController.value.size.width,
        height: _videoController.value.size.height,
        child: VideoPlayer(_videoController),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Video + (çekim modunda) metin overlay composer'ı.
          Positioned.fill(
            child: widget.viewOnly
                ? Stack(
                    children: [
                      Positioned.fill(child: _buildVideoLayer()),
                      // İzleme modunda kayıtlı overlay'i çiz.
                      if (widget.overlay != null)
                        Positioned.fill(
                          child: MediaTextOverlayView(
                            overlay: widget.overlay!,
                          ),
                        ),
                    ],
                  )
                : TextOverlayComposer(
                    key: _composerKey,
                    onEditingChanged: (editing) =>
                        setState(() => _editingText = editing),
                    child: _buildVideoLayer(),
                  ),
          ),

          // Sağ üst araçlar: yazı ekle (çekim modu) + indir (+ izleme modunda kapat).
          if (!_editingText)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              right: 12,
              child: Column(
                children: [
                  if (widget.viewOnly)
                    Material(
                      color: Colors.black38,
                      shape: const CircleBorder(),
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                  if (widget.viewOnly) const SizedBox(height: 12),
                  if (!widget.viewOnly)
                    Material(
                      color: Colors.black38,
                      shape: const CircleBorder(),
                      child: IconButton(
                        icon: const Icon(
                          Icons.text_fields_rounded,
                          color: Colors.white,
                        ),
                        onPressed: () =>
                            _composerKey.currentState?.openEditor(),
                      ),
                    ),
                  if (!widget.viewOnly) const SizedBox(height: 12),
                  Material(
                    color: Colors.black38,
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.download_rounded,
                              color: Colors.white,
                            ),
                      onPressed: _download,
                    ),
                  ),
                ],
              ),
            ),

          if (!widget.viewOnly && !_editingText)
            Positioned(
              left: 24,
              right: 24,
              bottom: 24,
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
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
                        onPressed: () {
                          final overlay =
                              _composerKey.currentState?.buildOverlay();
                          // TEK pop: sonucu CameraScreen'e döndür; kamera kendini
                          // kapatır (alttan pop yok → CameraX crash yok).
                          Navigator.pop(
                            context,
                            CapturedMedia(
                              file: widget.file,
                              overlay: overlay,
                            ),
                          );
                        },
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
                        child: const Text("Use Video"),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
