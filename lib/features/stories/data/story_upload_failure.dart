import 'dart:convert';
import 'package:kmstry_frontend/core/media/public_media_upload_policy.dart';

import '../../content_moderation/data/pending_public_media.dart';

/// Keep only known reasons, never API bodies, storage URLs or overlay text.
class StoryUploadFailure extends PublicMediaUploadRejected {
  const StoryUploadFailure(this.code, this.message, {this.statusCode})
    : super(code);

  final String code;
  final String message;
  final int? statusCode;

  factory StoryUploadFailure.fromResponse(int status, String body) {
    var reason = '';
    var textCategories = <String>[];
    try {
      final data = jsonDecode(body);
      if (data is Map) {
        final categories = data['textPolicyCategories'];
        if (categories is List) {
          textCategories = categories.whereType<String>().toList();
        }
        final message = data['message'];
        reason = [
          data['code'],
          data['errorCode'],
          data['error'],
          if (message is String) message,
          if (message is List) ...message.whereType<String>(),
        ].whereType<String>().join(' ').toLowerCase();
      }
    } on FormatException {
      // Gateways can return HTML. Do not expose it to the UI or logs.
    }
    (String, String) result;
    if (reason.contains('aws_sharing_')) {
      result = ('AWS_SHARING_PERMISSION_REQUIRED',
        'Nothing was shared. Review your AWS safety-check permission and try again.');
    } else if (reason.contains('app_check_required')) {
      result = (
        'APP_CHECK_REQUIRED',
        'App verification could not be completed. Please reopen KMSTRY and try again.',
      );
    } else if (status == 401) {
      result = (
        'AUTH_REQUIRED',
        'Your session expired. Sign in again to share a story.',
      );
    } else if (reason.contains('public_video_disabled')) {
      result = (
        'PUBLIC_VIDEO_DISABLED',
        PublicMediaUploadPolicy.videoUnavailableMessage,
      );
    } else if (reason.contains('anonymous_story_blocked')) {
      result = (
        'ANONYMOUS_STORY_BLOCKED',
        'Turn off Anonymous Mode to share a story.',
      );
    } else if (reason.contains('plan_upgrade_required')) {
      result = (
        'PLAN_UPGRADE_REQUIRED',
        'Your venue needs the Social plan to share stories.',
      );
    } else if (reason.contains('check-in has expired') ||
        reason.contains('check-in not found')) {
      result = (
        'CHECKIN_EXPIRED',
        'This check-in has ended. Start a new check-in to share a story.',
      );
    } else if (reason.contains('public_text') ||
        reason.contains('text_policy')) {
      result = ('CONTENT_POLICY', _textPolicyMessage(textCategories));
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
    } else if (reason.contains('unsupported')) {
      result = (
        'UNSUPPORTED_MEDIA',
        'This media format is not supported. Please take a new photo or choose a supported image.',
      );
    } else if (status == 403) {
      result = (
        'NOT_ALLOWED',
        'This story could not be shared from the current account. Please check your account and try again.',
      );
    } else {
      result = (
        'UPLOAD_REJECTED',
        'Your story could not be shared. Please try again or choose another file.',
      );
    }
    return StoryUploadFailure(result.$1, result.$2, statusCode: status);
  }

  static String _textPolicyMessage(List<String> categories) {
    const labels = {
      'PROFANITY_OR_SLUR': 'profanity or slurs',
      'THREAT': 'threatening language',
      'SELF_HARM_ENCOURAGEMENT': 'encouragement of self-harm',
      'CHILD_SEXUAL_ABUSE': 'child sexual abuse references',
      'SEXUAL_TEXT': 'sexual language',
      'SPAM_OR_SCAM': 'spam or scam signals',
      'MULTIPLE_LINKS': 'multiple web links',
    };
    final reasons = categories.take(16).map((c) => labels[c]).nonNulls.toSet();
    final why = reasons.isEmpty
        ? 'the text you added did not pass our content safety check'
        : 'the text you added was flagged for ${reasons.join('; ')}';
    return 'Your story was not shared because $why. '
        'Change or remove that text before creating a new story. '
        'This upload is not visible to anyone else.';
  }
}
