import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorage {
  static const _storage = FlutterSecureStorage();

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _notificationOnboardingDoneKey = 'notification_onboarding_done';

  static Future<bool> isNotificationOnboardingDone() async {
    final v = await _storage.read(key: _notificationOnboardingDoneKey);
    return v == 'true';
  }

  static Future<void> setNotificationOnboardingDone() async {
    await _storage.write(key: _notificationOnboardingDoneKey, value: 'true');
  }

static Future<void> clearSession() async {
  await _storage.delete(key: _accessTokenKey);
  await _storage.delete(key: _refreshTokenKey);
}

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  static Future<String?> getAccessToken() =>
      _storage.read(key: _accessTokenKey);

  static Future<String?> getRefreshToken() =>
      _storage.read(key: _refreshTokenKey);

  static Future<void> clear() async {
    await _storage.deleteAll();
  }
}
