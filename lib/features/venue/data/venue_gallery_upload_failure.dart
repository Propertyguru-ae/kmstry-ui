import 'dart:convert';

import '../../content_moderation/data/pending_public_media.dart';

/// Definite API rejections only. Transport/5xx outcomes remain unconfirmed and
/// must not be retried automatically or presented as a rejected photograph.
class VenueGalleryUploadFailure extends PublicMediaUploadRejected {
  const VenueGalleryUploadFailure(this.code, this.message, this.statusCode)
    : super(code);

  final String code;
  final String message;
  final int statusCode;

  factory VenueGalleryUploadFailure.fromResponse(int status, String body) {
    var reason = '';
    try {
      final data = jsonDecode(body);
      if (data is Map) {
        final message = data['message'];
        reason = [
          data['errorCode'],
          data['code'],
          if (message is String) message,
          if (message is List) ...message.whereType<String>(),
        ].whereType<String>().join(' ').toLowerCase();
      }
    } on FormatException {
      // A gateway's HTML is not user-facing copy or safe diagnostic data.
    }
    final (code, message) = switch (status) {
      _ when reason.contains('aws_sharing_') => (
        'AWS_SHARING_PERMISSION_REQUIRED',
        'Nothing was shared. Allow safety checks before adding photos.',
      ),
      _ when reason.contains('app_check_required') => (
        'APP_CHECK_REQUIRED',
        'App verification could not be completed. Reopen KMSTRY and try again.',
      ),
      401 => (
        'AUTH_REQUIRED',
        'Your session expired. Sign in again to add photos to your gallery.',
      ),
      _ when reason.contains('venue_approval_required') => (
        'VENUE_APPROVAL_REQUIRED',
        'Your venue ownership is still under review. Add photos after approval.',
      ),
      _ when reason.contains('public_video_disabled') => (
        'PUBLIC_VIDEO_DISABLED',
        'Video sharing is currently unavailable. Please choose a photo.',
      ),
      403 => (
        'NOT_ALLOWED',
        'You do not have permission to add photos to this venue. Check your venue access with the owner.',
      ),
      404 => (
        'VENUE_UNAVAILABLE',
        'This venue is no longer available. Return to your accounts and check your venue access.',
      ),
      413 => (
        'FILE_TOO_LARGE',
        'This file is too large. Please choose a smaller photo.',
      ),
      429 => (
        'RATE_LIMITED',
        'Too many upload attempts. Wait a moment and try again.',
      ),
      415 => (
        'UNSUPPORTED_MEDIA',
        'This file format is not supported. Please choose a JPEG, PNG or another supported photo.',
      ),
      _
          when reason.contains('unsupported') ||
              reason.contains('invalid image') =>
        (
          'UNSUPPORTED_MEDIA',
          'This photo could not be read. Please choose another photo.',
        ),
      _ => (
        'UPLOAD_REJECTED',
        'Your upload was not accepted. Please try again. If it keeps happening, contact support.',
      ),
    };
    return VenueGalleryUploadFailure(code, message, status);
  }
}
