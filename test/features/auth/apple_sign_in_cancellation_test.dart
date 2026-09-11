import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/auth/data/apple_sign_in_cancellation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

void main() {
  test('treats closing the Apple authorization sheet as cancellation', () {
    const error = SignInWithAppleAuthorizationException(
      code: AuthorizationErrorCode.canceled,
      message: 'The user canceled the authorization attempt.',
    );

    expect(isAppleSignInCancellation(error), isTrue);
  });

  test('supports native and wrapped iOS cancellation variants', () {
    final platformError = PlatformException(
      code: 'authorization-error/canceled',
      message: 'The operation was cancelled.',
    );
    const nativeCodeError = SignInWithAppleAuthorizationException(
      code: AuthorizationErrorCode.unknown,
      message:
          'The operation could not be completed. '
          '(com.apple.AuthenticationServices.AuthorizationError error 1001.)',
    );

    expect(isAppleSignInCancellation(platformError), isTrue);
    expect(isAppleSignInCancellation(nativeCodeError), isTrue);
  });

  test('does not add an app error after closing Apple account setup', () {
    const accountSetupDismissed = SignInWithAppleAuthorizationException(
      code: AuthorizationErrorCode.unknown,
      message:
          'The operation could not be completed. '
          '(com.apple.AuthenticationServices.AuthorizationError error 1000.)',
    );

    expect(isAppleSignInCancellation(accountSetupDismissed), isTrue);
  });

  test('does not hide real Apple authorization failures', () {
    const error = SignInWithAppleAuthorizationException(
      code: AuthorizationErrorCode.failed,
      message: 'Authorization failed.',
    );

    expect(isAppleSignInCancellation(error), isFalse);
    expect(
      isAppleSignInCancellation(
        PlatformException(
          code: 'authorization-error/failed',
          message: 'Authorization failed.',
        ),
      ),
      isFalse,
    );
    expect(isAppleSignInCancellation(Exception('network error')), isFalse);
  });
}
