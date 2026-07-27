import 'dart:io';
import 'package:kmstry_frontend/features/media/media_text_overlay.dart';
import 'package:kmstry_frontend/features/media/text_overlay_composer.dart';
import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/features/camera/presentation/camera_screen.dart';
import 'package:kmstry_frontend/features/stories/data/story_repository.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';

class AddStoryPage extends StatefulWidget {
  final String checkinId;
  const AddStoryPage({super.key, required this.checkinId});

  @override
  State<AddStoryPage> createState() => _AddStoryPageState();
}

class _AddStoryPageState extends State<AddStoryPage> {
  final _repo = StoryRepository();
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startFlow());
  }

  /// Anonymous users can't share a story (it would reveal them at the venue).
  /// Warn early — before the camera opens. The backend enforces this too.
  Future<void> _startFlow() async {
    if (!mounted) return;
    try {
      // Force a fresh fetch — a cached /me may predate a just-toggled Anonymous
      // Mode, which would let the camera open only to be rejected on upload.
      final me = await AuthRepository().getMe(forceRefresh: true);
      if (me['isAnonymous'] == true) {
        if (!mounted) return;
        await showPremiumErrorDialog(
          context,
          message:
              "You're in Anonymous Mode. Turn it off to share a story — otherwise no one can see it.",
        );
        if (mounted) Navigator.pop(context);
        return;
      }
    } catch (_) {
      // Best-effort; the backend still blocks anonymous story creation.
    }
    if (!mounted) return;
    await _openCamera();
  }

  Future<void> _openCamera() async {
    if (!mounted) return;

    // Fotoğraf akışı File, video akışı CapturedMedia (dosya + text overlay) döner.
    final dynamic result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CameraScreen(
          useFrontCamera: true,
          optimizeForUpload: true,
         // isStory: true,
        ),
      ),
    );

    if (!mounted) return;
    if (result == null) {
      Navigator.pop(context);
      return;
    }
    final File captured =
        result is CapturedMedia ? result.file : result as File;
    final MediaTextOverlay? overlay =
        result is CapturedMedia ? result.overlay : null;

    await _upload(captured, overlay);
  }

  Future<void> _upload(File file, MediaTextOverlay? overlay) async {
    if (!mounted) return;

    final ext = file.path.toLowerCase();
    final isVideo = ext.endsWith('.mp4') || ext.endsWith('.mov') || ext.endsWith('.avi');

    setState(() => _uploading = true);

    bool success = false;
    try {
      await _repo.createStory(
        checkinId: widget.checkinId,
        file: file,
        mediaType: isVideo ? 'video' : 'photo',
        textOverlayJson: overlay?.toJsonString(),
      );
      success = true;
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      final blockedByAnonymous =
          e.toString().contains('ANONYMOUS_STORY_BLOCKED');
      await showPremiumErrorDialog(
        context,
        message: blockedByAnonymous
            ? "You're in Anonymous Mode. Turn it off to share a story."
            : 'Could not upload story. Please try again.',
      );
      if (mounted) Navigator.pop(context);
      return;
    }

    if (!mounted || !success) return;
    try {
      showSuccessSnackBar(context, message: 'Story shared successfully!');
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
                  CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
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
            : const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
      ),
    );
  }
}
