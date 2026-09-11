import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';

void main() {
  test('maps typed public text rejection to the safe generic message', () {
    final error = ApiException(
      statusCode: 400,
      data: const {
        'errorCode': 'PUBLIC_TEXT_NOT_ALLOWED',
        'message': 'server message',
      },
    );

    expect(isPublicTextRejection(error), isTrue);
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
    expect(
      publicTextErrorMessage(error, fallback: 'fallback'),
      publicTextRejectionMessage,
    );
  });

  test('keeps the screen-specific fallback for unrelated failures', () {
    expect(
      publicTextErrorMessage(Exception('offline'), fallback: 'Try again.'),
      'Try again.',
    );
  });
}
