import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureStorage {
  static const _storage = FlutterSecureStorage();

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _notificationOnboardingDoneKey = 'notification_onboarding_done';
  static const _devicePermissionsDoneKey = 'device_permissions_done';

  static Future<bool> isNotificationOnboardingDone() async {
    // Keep this flag in app prefs (not keychain) so uninstall resets it.
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_notificationOnboardingDoneKey);
    return v == 'true';
  }

  static Future<void> setNotificationOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_notificationOnboardingDoneKey, 'true');
  }

  static Future<bool> isDevicePermissionsOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_devicePermissionsDoneKey);
    return v == 'true';
  }

  static Future<void> setDevicePermissionsOnboardingDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_devicePermissionsDoneKey, 'true');
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

  static Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  static Future<String?> read(String key) async {
    return await _storage.read(key: key);
  }

  static Future<void> clear() async {
    await _storage.deleteAll();
  }
}
