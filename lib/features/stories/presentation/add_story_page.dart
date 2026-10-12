import 'package:kmstry_frontend/features/stories/data/story_upload_coordinator.dart';
import 'dart:io';
import 'package:kmstry_frontend/features/media/media_text_overlay.dart';
import 'package:kmstry_frontend/features/media/text_overlay_composer.dart';
import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/features/camera/presentation/camera_screen.dart';
import 'package:kmstry_frontend/features/camera/presentation/camera_route.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';

class AddStoryPage extends StatefulWidget {
  final String checkinId;
  const AddStoryPage({super.key, required this.checkinId});

  static Route<bool> route(String checkinId) => PageRouteBuilder<bool>(
    opaque: false,
    barrierColor: Colors.transparent,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (_, _, _) => AddStoryPage(checkinId: checkinId),
  );

  @override
  State<AddStoryPage> createState() => _AddStoryPageState();
}

class _AddStoryPageState extends State<AddStoryPage> {
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
      cameraRoute(
        builder: (_) => const CameraScreen.publicMedia(
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
    final File captured = result is CapturedMedia
        ? result.file
        : result as File;
    final MediaTextOverlay? overlay = result is CapturedMedia
        ? result.overlay
        : null;

    await _upload(captured, overlay);
  }

  Future<void> _upload(File file, MediaTextOverlay? overlay) async {
    if (!mounted) return;

    StoryUploadCoordinator.instance.sharePersonal(
      file: file,
      checkinId: widget.checkinId,
      textOverlayJson: overlay?.toJsonString(),
    );
    final route = ModalRoute.of(context);
    if (route?.isActive == true) route!.navigator?.removeRoute(route, true);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: SizedBox.expand(),
    );
  }
}
