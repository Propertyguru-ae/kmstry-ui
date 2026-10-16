import 'dart:convert';
import '../storage/secure_storage.dart';

/// Shared by foreground display, notification taps and data-only background
/// delivery. Venue/personal contexts belong to the same authenticated user.
class PushAudience {
  static bool _suspended = false;
  static void suspend() => _suspended = true;
  static void resume() => _suspended = false;

  static Future<bool> isCurrent(Map<String, dynamic> data) async {
    if (_suspended) return false;
    final revision = SecureStorage.sessionRevision;
    final access = await SecureStorage.getAccessToken();
    final refresh = await SecureStorage.getRefreshToken();
    final sessionId = await SecureStorage.getPushSessionId();
    if (_suspended ||
        revision != SecureStorage.sessionRevision ||
        access == null ||
        refresh == null ||
        sessionId == null) {
      return false;
    }
    try {
      final claims =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(base64Url.normalize(access.split('.')[1])),
                ),
              )
              as Map;
      return claims['sub'] != null &&
          data['recipientUserId'] == claims['sub'] &&
          data['pushSessionId'] == sessionId;
    } catch (_) {
      return false;
    }
  }
}
