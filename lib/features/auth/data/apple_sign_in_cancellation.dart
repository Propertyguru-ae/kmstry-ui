import 'package:flutter/services.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Closing Apple's authorization sheet is a user decision, not a login error.
bool isAppleSignInCancellation(Object error) {
  if (error is SignInWithAppleAuthorizationException) {
    if (error.code == AuthorizationErrorCode.canceled) return true;

    // Some iOS/plugin combinations surface ASAuthorizationError.canceled
    // (native code 1001) as `unknown` while retaining the native message.
    // A device without an Apple Account can also show Apple's own actionable
    // Settings dialog and then return native code 1000 when that dialog is
    // closed. In both cases the native UI has already handled the interaction.
    return _containsAppleCancellationSignal(error.message);
  }

  if (error is PlatformException) {
    final code = error.code.trim().toLowerCase();
    if (code == 'authorization-error/canceled' ||
        code == 'authorization-error/cancelled') {
      return true;
    }
    return _containsAppleCancellationSignal(
      '${error.message ?? ''} ${error.details ?? ''}',
    );
  }

  return _containsAppleCancellationSignal(error.toString());
}

bool _containsAppleCancellationSignal(String value) {
  final normalized = value.toLowerCase();
  return normalized.contains('authorization-error/canceled') ||
      normalized.contains('authorization-error/cancelled') ||
      normalized.contains('authorizationerror error 1000') ||
      normalized.contains('asauthorizationerror error 1000') ||
      normalized.contains('authorizationerror error 1001') ||
      normalized.contains('asauthorizationerror error 1001') ||
      normalized.contains('user canceled the authorization attempt') ||
      normalized.contains('user cancelled the authorization attempt');
}
