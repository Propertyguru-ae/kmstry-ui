import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
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
  static final _sessionEnded = StreamController<void>.broadcast(sync: true);
  static Stream<void> get sessionEnded => _sessionEnded.stream;
  static int _sessionRevision = 0;
  static int get sessionRevision => _sessionRevision;
  static Future<void> _sessionWrites = Future.value();

  // Serialize token rotation and deletion so a refresh finishing during logout
  // cannot recreate half an old session after its keys were removed.
  static Future<T> _writeSession<T>(Future<T> Function() action) {
    final next = _sessionWrites.then((_) => action());
    _sessionWrites = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return next;
  }

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

  static Future<void> clearSession() {
    _sessionRevision++;
    _sessionEnded.add(null);
    ChatMemoryCache.shared.clear();
    return _writeSession(() async {
      await Future.wait([
        for (final key in [
          _accessTokenKey,
          _refreshTokenKey,
          _sessionApiOriginKey,
          _sessionBuildEnvKey,
          _registeredDeviceTokenKey,
        ])
          _storage.delete(key: key),
        SharedPreferences.getInstance().then((prefs) async {
          await prefs.remove(_pendingInterestedUserIdsKey);
        }),
      ]);
    });
  }

  static Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) {
    _sessionRevision++;
    return _writeSession(() => _saveTokens(accessToken, refreshToken));
  }

  /// A delayed sign-in may not reopen a session ended by logout, or replace
  /// another login that has already won. Check inside the serialized writer.
  static Future<bool> saveLoginTokens({
    required int expectedRevision,
    required String accessToken,
    required String refreshToken,
  }) => _writeSession(() async {
    if (expectedRevision != _sessionRevision) return false;
    final revision = ++_sessionRevision;
    await _saveTokens(accessToken, refreshToken);
    return revision == _sessionRevision;
  });

  static Future<bool> saveRefreshedTokens({
    required int expectedRevision,
    required String previousRefreshToken,
    required String accessToken,
    required String refreshToken,
  }) => _writeSession(() async {
    if (expectedRevision != _sessionRevision ||
        previousRefreshToken != await getRefreshToken()) {
      return false;
    }
    if (expectedRevision != _sessionRevision) return false;
    await _saveTokens(accessToken, refreshToken);
    return expectedRevision == _sessionRevision;
  });

  static Future<void> _saveTokens(
    String accessToken,
    String refreshToken,
  ) async {
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
    _sessionEnded.add(null);
    ChatMemoryCache.shared.clear();
    await _storage.deleteAll();
  }
}
