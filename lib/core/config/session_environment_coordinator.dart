import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../network/app_request_headers.dart';
import '../push/push_manager.dart';
import '../storage/secure_storage.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/stories/data/story_viewed_cache.dart';
import '../../features/venue_stories/data/venue_story_viewed_cache.dart';
import '../../features/venue/presentation/profile_preview_page.dart';
import 'app_config.dart';

enum SessionEnvironmentAction { keep, bindLegacy, clearForSwitch }

/// The first rollout upgrades an unbound staging session. Later releases
/// always have an explicit binding written with their auth tokens.
class SessionEnvironmentPolicy {
  SessionEnvironmentPolicy._();

  static SessionEnvironmentAction decide({
    required bool hasSession,
    required StoredSessionEnvironment? stored,
    required String currentApiOrigin,
    required String currentBuildEnv,
  }) {
    if (!hasSession) return SessionEnvironmentAction.keep;
    if (stored != null) {
      return stored.apiOrigin == currentApiOrigin &&
              stored.buildEnv == currentBuildEnv
          ? SessionEnvironmentAction.keep
          : SessionEnvironmentAction.clearForSwitch;
    }
    // Existing internal-test installs have no binding. They were staging.
    if (currentBuildEnv == 'staging' || currentBuildEnv.isEmpty) {
      return SessionEnvironmentAction.bindLegacy;
    }
    return SessionEnvironmentAction.clearForSwitch;
  }

  static String? oldApiOrigin({
    required StoredSessionEnvironment? stored,
    required String currentBuildEnv,
  }) {
    if (stored != null) return stored.apiOrigin;
    return currentBuildEnv == 'pre-prod' ? 'https://api.kmstry.net' : null;
  }
}

/// Runs before PushManager or any startup API request. A new API must never
/// receive an old API's persisted access/refresh tokens.
class SessionEnvironmentCoordinator {
  SessionEnvironmentCoordinator._();

  static const _knownApiOrigins = {
    'https://api.kmstry.net',
    'https://pre-prod-api.kmstry.net',
  };

  static Future<void> reconcile() async {
    final accessToken = await SecureStorage.getAccessToken();
    final refreshToken = await SecureStorage.getRefreshToken();
    final stored = await SecureStorage.getSessionEnvironment();
    final action = SessionEnvironmentPolicy.decide(
      hasSession: accessToken != null || refreshToken != null,
      stored: stored,
      currentApiOrigin: AppConfig.baseUrl,
      currentBuildEnv: AppConfig.buildEnv,
    );

    if (action == SessionEnvironmentAction.keep) return;
    if (action == SessionEnvironmentAction.bindLegacy) {
      await SecureStorage.bindExistingSessionToCurrentEnvironment();
      return;
    }

    final oldApi = SessionEnvironmentPolicy.oldApiOrigin(
      stored: stored,
      currentBuildEnv: AppConfig.buildEnv,
    );
    String? deviceToken = await SecureStorage.getRegisteredDeviceToken();
    if (deviceToken == null || deviceToken.isEmpty) {
      try {
        deviceToken = await FirebaseMessaging.instance.getToken().timeout(
          const Duration(seconds: 3),
        );
      } catch (_) {
        // FCM can be unavailable while offline; never use another user's token.
      }
    }

    if (refreshToken != null &&
        deviceToken != null &&
        deviceToken.isNotEmpty &&
        oldApi != null &&
        _knownApiOrigins.contains(oldApi) &&
        oldApi != AppConfig.baseUrl) {
      await _revokeOldInstallation(
        oldApi: oldApi,
        oldBuildEnv: stored?.buildEnv ?? 'staging',
        refreshToken: refreshToken,
        deviceToken: deviceToken,
      );
    }

    try {
      // Do not time out a mutating Firebase call: it could otherwise complete
      // late and delete a token newly registered by the next session.
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {
      // The server-side exact-token revocation above is the other cleanup path.
      // Neither path can be guaranteed while both networks are unavailable.
      if (kDebugMode) {
        debugPrint('[SESSION] FCM token rotation deferred by connectivity');
      }
    }

    await SecureStorage.clearSession();
    PushManager.instance.onSessionEnded();
    AuthRepository.invalidateMeCache();
    ProfilePreviewPage.clearActionStateCache();
    VenueStoryViewedCache.instance.clear();
    await StoryViewedCache.clearAll();
  }

  static Future<void> _revokeOldInstallation({
    required String oldApi,
    required String oldBuildEnv,
    required String refreshToken,
    required String deviceToken,
  }) async {
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        ...await AppRequestHeaders.appCheck(forceRefresh: true),
        ...await AppRequestHeaders.appMetadata(),
        'x-kmstry-build-env': oldBuildEnv,
      };
      final response = await http
          .post(
            Uri.parse('$oldApi/auth/logout-device'),
            headers: headers,
            body: jsonEncode({
              'refreshToken': refreshToken,
              'deviceToken': deviceToken,
            }),
          )
          .timeout(const Duration(seconds: 4));
      if (response.statusCode != 200 && kDebugMode) {
        debugPrint('[SESSION] Old installation revocation was not accepted');
      }
    } catch (_) {
      if (kDebugMode) {
        debugPrint('[SESSION] Old installation revocation unavailable');
      }
    }
  }
}
