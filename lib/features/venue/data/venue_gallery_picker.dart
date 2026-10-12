import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:kmstry_frontend/core/media/public_media_upload_policy.dart';

import 'venue_gallery_upload_coordinator.dart';

/// Shared by venue Home and Profile. Filter results too: platform pickers can
/// return a stale/unsupported selection despite the requested file type.
Future<List<File>> pickVenueGalleryMedia() async {
  final result = await FilePicker.platform.pickFiles(
    type: PublicMediaUploadPolicy.allowVideo ? FileType.media : FileType.image,
    allowMultiple: true,
  );
  return (result?.files ?? [])
      .map((file) => file.path)
      .whereType<String>()
      .where(VenueGalleryUploadCoordinator.isMediaPath)
      .where(
        (path) =>
            PublicMediaUploadPolicy.allowVideo ||
            !VenueGalleryUploadCoordinator.isVideoPath(path),
      )
      .map(File.new)
      .toList();
}
