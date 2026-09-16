import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../features/chat/data/chat_memory_cache.dart';
import '../config/app_config.dart';

class StoredSessionEnvironment {
  const StoredSessionEnvironment({
    required this.apiOrigin,
    required this.buildEnv,
  });

  final String apiOrigin;
  final String buildEnv;
}

class SecureStorage {
  static const _storage = FlutterSecureStorage();

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _notificationOnboardingDoneKey = 'notification_onboarding_done';
  static const _devicePermissionsDoneKey = 'device_permissions_done';
  static const _introSeenKey = 'intro_seen';
  static const _pendingInterestedUserIdsKey = 'pending_interested_user_ids';
  static const _sessionApiOriginKey = 'session_api_origin';
  static const _sessionBuildEnvKey = 'session_build_env';
  static const _registeredDeviceTokenKey = 'registered_device_token';

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

  static Future<bool> isIntroSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_introSeenKey);
    return value == 'true';
  }

  static Future<void> setIntroSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_introSeenKey, 'true');
  }

  static Future<Set<String>> getPendingInterestedUserIds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingInterestedUserIdsKey);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      return decoded
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> addPendingInterestedUserId(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return;
    final ids = await getPendingInterestedUserIds();
    ids.add(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _pendingInterestedUserIdsKey,
      jsonEncode(ids.toList()),
    );
  }

  static Future<void> removePendingInterestedUserId(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return;
    final ids = await getPendingInterestedUserIds();
    ids.remove(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _pendingInterestedUserIdsKey,
      jsonEncode(ids.toList()),
    );
  }

  static Future<void> clearSession() async {
    ChatMemoryCache.shared.clear();
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _sessionApiOriginKey);
    await _storage.delete(key: _sessionBuildEnvKey);
    await _storage.delete(key: _registeredDeviceTokenKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingInterestedUserIdsKey);
  }

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
    await _storage.write(key: _sessionApiOriginKey, value: AppConfig.baseUrl);
    await _storage.write(key: _sessionBuildEnvKey, value: AppConfig.buildEnv);
  }

  static Future<StoredSessionEnvironment?> getSessionEnvironment() async {
    final apiOrigin = await _storage.read(key: _sessionApiOriginKey);
    final buildEnv = await _storage.read(key: _sessionBuildEnvKey);
    if (apiOrigin == null || buildEnv == null) return null;
    return StoredSessionEnvironment(apiOrigin: apiOrigin, buildEnv: buildEnv);
  }

  static Future<void> bindExistingSessionToCurrentEnvironment() async {
    await _storage.write(key: _sessionApiOriginKey, value: AppConfig.baseUrl);
    await _storage.write(key: _sessionBuildEnvKey, value: AppConfig.buildEnv);
  }

  static Future<void> saveRegisteredDeviceToken(String token) async {
    await _storage.write(key: _registeredDeviceTokenKey, value: token);
  }

  static Future<String?> getRegisteredDeviceToken() =>
      _storage.read(key: _registeredDeviceTokenKey);

  static Future<void> clearRegisteredDeviceToken() =>
      _storage.delete(key: _registeredDeviceTokenKey);

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
    ChatMemoryCache.shared.clear();
    await _storage.deleteAll();
  }
}
