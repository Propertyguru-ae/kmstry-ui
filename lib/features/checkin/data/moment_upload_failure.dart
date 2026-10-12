import 'dart:convert';
import 'package:kmstry_frontend/core/media/public_media_upload_policy.dart';

import '../../content_moderation/data/pending_public_media.dart';

/// Only allowlisted reasons reach the UI/logs, never raw API responses,
/// storage URLs, credentials or uploaded overlay text.
class MomentUploadFailure extends PublicMediaUploadRejected {
  const MomentUploadFailure(this.code, this.message, {this.statusCode})
    : super(code);

  final String code;
  final String message;
  final int? statusCode;

  factory MomentUploadFailure.fromResponse(int status, String body) {
    var reason = '';
    try {
      final data = jsonDecode(body);
      if (data is Map) {
        final message = data['message'];
        reason = [
          data['code'],
          data['errorCode'],
          if (message is String) message,
          if (message is List) ...message.whereType<String>(),
        ].whereType<String>().join(' ').toLowerCase();
      }
    } on FormatException {
      // A gateway may return HTML; never show it to the user.
    }

    (String, String) result;
    if (reason.contains('app_check_required')) {
      result = (
        'APP_CHECK_REQUIRED',
        'App verification could not be completed. Please reopen KMSTRY and try again.',
      );
    } else if (status == 401) {
      result = (
        'AUTH_REQUIRED',
        'Your session expired. Sign in again to share a Moment.',
      );
    } else if (reason.contains('public_video_disabled')) {
      result = (
        'PUBLIC_VIDEO_DISABLED',
        PublicMediaUploadPolicy.videoUnavailableMessage,
      );
    } else if (status == 413) {
      result = (
        'FILE_TOO_LARGE',
        'This file is too large. Please choose a smaller photo.',
      );
    } else if (status == 429) {
      result = (
        'RATE_LIMITED',
        'You are sharing too quickly. Wait a moment and try again.',
      );
    } else if (reason.contains('check-in not found or expired')) {
      result = (
        'CHECKIN_EXPIRED',
        'This check-in has ended. Start a new check-in to share a Moment.',
      );
    } else if (reason.contains('maximum 1 video')) {
      result = (
        'VIDEO_LIMIT',
        'You can share only 1 video per check-in. Remove the existing video before adding another.',
      );
    } else if (reason.contains('maximum 6 media')) {
      result = (
        'MOMENT_LIMIT',
        'You can share up to 6 Moments per check-in. Remove a Moment before adding another.',
      );
    } else if (reason.contains('public_text') ||
        reason.contains('text_policy')) {
      result = (
        'CONTENT_POLICY',
        'The text in this Moment does not meet our content guidelines. Please change it and try again.',
      );
    } else if (reason.contains('unsupported')) {
      result = (
        'UNSUPPORTED_MEDIA',
        'This media format is not supported. Please take a new photo or choose a supported image.',
      );
    } else if (status == 403) {
      result = (
        'NOT_ALLOWED',
        'This upload was not allowed. Please reopen the app and try again.',
      );
    } else if (status == 404) {
      result = (
        'UPLOAD_NOT_FOUND',
        'The upload service could not be reached. Please try again later.',
      );
    } else {
      result = (
        'UPLOAD_REJECTED',
        'This Moment could not be uploaded. Please try again or choose another file.',
      );
    }
    return MomentUploadFailure(result.$1, result.$2, statusCode: status);
  }
}
