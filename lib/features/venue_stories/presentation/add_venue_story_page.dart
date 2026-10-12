import 'package:kmstry_frontend/features/stories/data/story_upload_coordinator.dart';
import 'dart:io';
import 'package:kmstry_frontend/features/media/text_overlay_composer.dart';
import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/camera/presentation/camera_screen.dart';
import 'package:kmstry_frontend/features/camera/presentation/camera_route.dart';

class AddVenueStoryPage extends StatefulWidget {
  final String venueId;
  const AddVenueStoryPage({super.key, required this.venueId});

  /// Hidden coordinator: only the camera itself should animate into view.
  /// Keeping this route transparent preserves the venue behind the camera.
  static Route<bool> route(String venueId) {
    return PageRouteBuilder<bool>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, animation, secondaryAnimation) =>
          AddVenueStoryPage(venueId: venueId),
    );
  }

  @override
  State<AddVenueStoryPage> createState() => _AddVenueStoryPageState();
}

class _AddVenueStoryPageState extends State<AddVenueStoryPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openCamera());
  }

  Future<void> _openCamera() async {
    if (!mounted) return;

    // Video capture keeps text as metadata; preserve it through upload.
    // All camera entry points use the same transition; the underlying venue
    // profile stays still instead of sliding to the left.
    final dynamic captureResult = await Navigator.push(
      context,
      cameraRoute(
        builder: (_) => const CameraScreen.publicMedia(
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

    final overlay = captureResult is CapturedMedia
        ? captureResult.overlay
        : null;
    await _upload(captured, overlay?.toJsonString());
  }

  Future<void> _upload(File file, String? textOverlayJson) async {
    if (!mounted) return;

    StoryUploadCoordinator.instance.shareVenue(
      file: file,
      venueId: widget.venueId,
      textOverlayJson: textOverlayJson,
    );
    final route = ModalRoute.of(context);
    if (route?.isActive == true) route!.navigator?.removeRoute(route, true);
  }

  @override
  Widget build(BuildContext context) {
    // The route closes as soon as the story is queued. No blank loading page
    // or upload dialog: the owner preview lives on the underlying venue screen.
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: SizedBox.shrink(),
    );
  }
}
