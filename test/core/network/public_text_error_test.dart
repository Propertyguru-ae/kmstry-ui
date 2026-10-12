import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';

void main() {
  test(
    'explains AWS unavailability without falsely claiming a policy rejection',
    () {
      final error = ApiException(
        statusCode: 503,
        data: const {'errorCode': 'PUBLIC_TEXT_CHECK_UNAVAILABLE'},
      );
      expect(isPublicTextRejection(error), isFalse);
      expect(publicTextErrorTitle(error), 'Text check unavailable');
      expect(
        publicTextErrorMessage(error, fallback: 'fallback'),
        contains("haven't been saved"),
      );
    },
  );

  test('explains a text length error safely', () {
    final error = ApiException(
      statusCode: 400,
      data: const {'errorCode': 'PUBLIC_TEXT_TOO_LONG'},
    );
    expect(
      publicTextErrorMessage(error, fallback: 'fallback'),
      contains('shorten it'),
    );
    expect(publicTextErrorTitle(error), 'Text too long');
  });
  test('maps typed public text rejection to the safe generic message', () {
    final error = ApiException(
      statusCode: 400,
      data: const {
        'errorCode': 'PUBLIC_TEXT_NOT_ALLOWED',
        'message': 'server message',
      },
    );

    expect(isPublicTextRejection(error), isTrue);
    expect(publicTextErrorTitle(error), 'Please edit your text');
    expect(
      publicTextErrorMessage(error, fallback: 'fallback'),
      publicTextRejectionMessage,
    );
  });

  test('maps multipart-wrapped response without exposing response content', () {
    final error = Exception(
      'Upload failed (400): {"errorCode":"PUBLIC_TEXT_NOT_ALLOWED"}',
    );

    expect(isPublicTextRejection(error), isTrue);
    expect(publicTextErrorTitle(error), 'Please edit your text');
    expect(
      publicTextErrorMessage(error, fallback: 'fallback'),
      publicTextRejectionMessage,
    );
  });

  test('keeps the screen-specific fallback for unrelated failures', () {
    expect(
      publicTextErrorTitle(
        Exception('offline'),
        fallback: 'Description not saved',
      ),
      'Description not saved',
    );
    expect(
      publicTextErrorMessage(Exception('offline'), fallback: 'Try again.'),
      'Try again.',
    );
  });
}
