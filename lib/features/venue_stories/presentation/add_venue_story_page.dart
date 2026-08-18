import 'dart:io';
import 'package:kmstry_frontend/features/media/text_overlay_composer.dart';
import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/features/camera/presentation/camera_screen.dart';
import '../data/venue_story_repository.dart';

class AddVenueStoryPage extends StatefulWidget {
  final String venueId;
  const AddVenueStoryPage({super.key, required this.venueId});

  @override
  State<AddVenueStoryPage> createState() => _AddVenueStoryPageState();
}

class _AddVenueStoryPageState extends State<AddVenueStoryPage> {
  final _repo = VenueStoryRepository();
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openCamera());
  }

  Future<void> _openCamera() async {
    if (!mounted) return;

    // Video akışı CapturedMedia (dosya + text overlay) dönebilir — dosyayı
    // çıkar (venue story'de overlay şimdilik desteklenmiyor).
    final dynamic captureResult = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CameraScreen(
          useFrontCamera: false,
          optimizeForUpload: true,
        ),
      ),
    );

    if (!mounted) return;
    final File? captured = captureResult is CapturedMedia
        ? captureResult.file
        : captureResult as File?;
    if (captured == null) {
      Navigator.pop(context);
      return;
    }

    await _upload(captured);
  }

  Future<void> _upload(File file) async {
    if (!mounted) return;

    final ext = file.path.toLowerCase();
    final isVideo =
        ext.endsWith('.mp4') || ext.endsWith('.mov') || ext.endsWith('.avi');

    setState(() => _uploading = true);

    try {
      await _repo.createVenueStory(
        venueId: widget.venueId,
        file: file,
        mediaType: isVideo ? 'video' : 'photo',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _uploading = false);
      await showPremiumErrorDialog(
        context,
        message: 'Could not upload story. Please try again.',
      );
      if (mounted) Navigator.pop(context);
      return;
    }

    if (!mounted) return;
    try {
      showSuccessSnackBar(context, message: 'Story shared!');
    } catch (_) {}
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: _uploading
            ? const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5),
                  SizedBox(height: 18),
                  Text(
                    'Uploading...',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              )
            : const CircularProgressIndicator(
                color: Colors.white, strokeWidth: 2.5),
      ),
    );
  }
}
