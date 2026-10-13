import '../storage/secure_storage.dart';
import 'upload_session_identity.dart';

class RequestSessionChanged extends StateError {
  RequestSessionChanged() : super('REQUEST_SESSION_CHANGED');
}

/// Identity fence, not authorization: the server still verifies every JWT.
/// A token refresh may rotate credentials; login/logout must never replay work.
class RequestSession {
  RequestSession(Map<String, String>? headers)
    : revision = SecureStorage.sessionRevision,
      initialToken = bearer(headers);

  final int revision;
  final String? initialToken;

  static String? bearer(Map<String, String>? headers) {
    for (final entry in (headers ?? const <String, String>{}).entries) {
      if (entry.key.toLowerCase() == 'authorization') {
        final match = RegExp(
          r'^Bearer\s+(.+)$',
          caseSensitive: false,
        ).firstMatch(entry.value);
        return match?.group(1);
      }
    }
    return null;
  }

  void check() {
    if (revision != SecureStorage.sessionRevision) {
      throw RequestSessionChanged();
    }
  }

  Future<String?> currentToken({String? candidate}) async {
    check();
    if (initialToken == null) return null;
    final current = await SecureStorage.getAccessToken();
    check();
    if (current == null ||
        (current != initialToken && !sameUploadOwner(initialToken!, current)) ||
        (candidate != null && candidate != current)) {
      throw RequestSessionChanged();
    }
    return current;
  }
}
