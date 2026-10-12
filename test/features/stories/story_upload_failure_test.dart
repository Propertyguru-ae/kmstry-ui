import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/stories/data/story_upload_failure.dart';

void main() {
  test(
    'text rejection explains only confirmed safe categories and next step',
    () {
      final failure = StoryUploadFailure.fromResponse(
        400,
        '{"errorCode":"PUBLIC_TEXT_NOT_ALLOWED","textPolicyCategories":["PROFANITY_OR_SLUR","private@example.com"],"message":"secret"}',
      );
      expect(failure.message, contains('profanity or slurs'));
      expect(failure.message, contains('Change or remove that text'));
      expect(failure.message, contains('not visible to anyone else'));
      expect(failure.message, isNot(contains('private@example.com')));
      expect(failure.message, isNot(contains('secret')));
    },
  );

  test(
    'older backend rejection stays actionable without inventing a category',
    () {
      final failure = StoryUploadFailure.fromResponse(
        400,
        '{"errorCode":"PUBLIC_TEXT_NOT_ALLOWED"}',
      );
      expect(failure.message, contains('text you added did not pass'));
      expect(failure.message, isNot(contains('profanity')));
    },
  );
  for (final sample in [
    (401, '{"message":"Unauthorized"}', 'AUTH_REQUIRED'),
    (401, '{"errorCode":"APP_CHECK_REQUIRED"}', 'APP_CHECK_REQUIRED'),
    (400, '{"message":"Check-in has expired"}', 'CHECKIN_EXPIRED'),
    (404, '{"message":"Check-in not found"}', 'CHECKIN_EXPIRED'),
    (403, '{"errorCode":"ANONYMOUS_STORY_BLOCKED"}', 'ANONYMOUS_STORY_BLOCKED'),
    (403, '{"error":"ANONYMOUS_STORY_BLOCKED"}', 'ANONYMOUS_STORY_BLOCKED'),
    (403, '{"code":"PLAN_UPGRADE_REQUIRED"}', 'PLAN_UPGRADE_REQUIRED'),
    (400, '{"message":"PUBLIC_TEXT_POLICY_REJECT"}', 'CONTENT_POLICY'),
    (
      400,
      '{"message":"Unsupported file type for story."}',
      'UNSUPPORTED_MEDIA',
    ),
    (413, '', 'FILE_TOO_LARGE'),
    (429, '', 'RATE_LIMITED'),
    (400, '{"errorCode":"PUBLIC_VIDEO_DISABLED"}', 'PUBLIC_VIDEO_DISABLED'),
  ]) {
    test('recognizes ${sample.$3} without retaining the body', () {
      final failure = StoryUploadFailure.fromResponse(sample.$1, sample.$2);
      expect(failure.code, sample.$3);
      expect(failure.statusCode, sample.$1);
    });
  }

  test(
    'disabled video explains photo-only sharing, not a content violation',
    () {
      final failure = StoryUploadFailure.fromResponse(
        400,
        '{"errorCode":"PUBLIC_VIDEO_DISABLED","message":"private"}',
      );
      expect(
        failure.message,
        'Video sharing is currently unavailable. Please choose a photo.',
      );
      expect(failure.code, isNot('CONTENT_POLICY'));
    },
  );

  test('unknown JSON and gateway errors never expose private details', () {
    for (final body in [
      '{"message":"secret token and https://storage/private.mp4?signature=secret"}',
      '<html>secret token</html>',
    ]) {
      final failure = StoryUploadFailure.fromResponse(400, body);
      expect(failure.code, 'UPLOAD_REJECTED');
      expect(failure.message, isNot(contains('secret')));
      expect(failure.toString(), isNot(contains('secret')));
    }
  });
}
