import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/checkin/data/moment_upload_failure.dart';

void main() {
  for (final entry in {
    'Maximum 1 video allowed per check-in': 'VIDEO_LIMIT',
    'Maximum 6 media files allowed per check-in': 'MOMENT_LIMIT',
    'Check-in not found or expired': 'CHECKIN_EXPIRED',
    'Unsupported file type for story media.': 'UNSUPPORTED_MEDIA',
    'PUBLIC_TEXT_REJECTED': 'CONTENT_POLICY',
    'PUBLIC_VIDEO_DISABLED': 'PUBLIC_VIDEO_DISABLED',
  }.entries) {
    test('maps ${entry.value} without guessing check-in is inactive', () {
      final failure = MomentUploadFailure.fromResponse(
        400,
        jsonEncode({'message': entry.key}),
      );
      expect(failure.code, entry.value);
      expect(failure.statusCode, 400);
      if (entry.value != 'CHECKIN_EXPIRED') {
        expect(failure.message, isNot(contains('check-in has ended')));
      }
    });
  }
  for (final entry in {
    401: 'AUTH_REQUIRED',
    403: 'NOT_ALLOWED',
    404: 'UPLOAD_NOT_FOUND',
    413: 'FILE_TOO_LARGE',
    429: 'RATE_LIMITED',
  }.entries) {
    test('maps HTTP ${entry.key}', () {
      expect(MomentUploadFailure.fromResponse(entry.key, '').code, entry.value);
    });
  }
  test('never exposes raw responses in user message or diagnostic code', () {
    for (final body in [
      '<html>internal-secret</html>',
      jsonEncode({
        'message': 'internal-secret private://object?credential=secret',
      }),
    ]) {
      final failure = MomentUploadFailure.fromResponse(400, body);
      expect(failure.code, 'UPLOAD_REJECTED');
      expect(failure.message, isNot(contains('internal-secret')));
      expect(failure.toString(), 'UPLOAD_REJECTED');
    }
  });
  test('app verification failure is distinct from expired login', () {
    final failure = MomentUploadFailure.fromResponse(
      401,
      '{"errorCode":"APP_CHECK_REQUIRED","message":"App attestation required."}',
    );
    expect(failure.code, 'APP_CHECK_REQUIRED');
  });

  test(
    'video disabled directs the user to a photo without blaming check-in',
    () {
      final failure = MomentUploadFailure.fromResponse(
        400,
        '{"errorCode":"PUBLIC_VIDEO_DISABLED"}',
      );
      expect(
        failure.message,
        'Video sharing is currently unavailable. Please choose a photo.',
      );
      expect(failure.code, isNot('CHECKIN_EXPIRED'));
    },
  );
}
