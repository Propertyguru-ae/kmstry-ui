import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:kmstry_frontend/core/permissions/notification_permission_service.dart';
import '../network/api_client.dart';
import '../storage/secure_storage.dart';
import '../../features/auth/data/auth_repository.dart';

class PushManager {
  PushManager._();
  static final PushManager instance = PushManager._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final ApiClient _api = ApiClient();
  final AuthRepository _auth = AuthRepository();
  final NotificationPermissionService _notificationPermissionService =
      NotificationPermissionService();

  bool _initialized = false;
  String? _lastRegisteredToken;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    _messaging.onTokenRefresh.listen((token) async {
      if (kDebugMode) {
        debugPrint("🔄 FCM token refreshed: $token");
      }
      await _tryRegisterToken(token);
    });
  }

  Future<void> ensureRegisteredIfAllowed() async {
    try {
      final permissionState = await _notificationPermissionService
          .readStateFromBackend();
      if (!permissionState.effectiveStatus) {
        if (kDebugMode) {
          debugPrint(
            "⛔ Notifications not effective. "
            "system=${permissionState.systemStatus}, "
            "account=${permissionState.accountPreference}",
          );
        }
        return;
      }

      final token = await _messaging.getToken();
      if (token == null) return;

      await _tryRegisterToken(token);
    } catch (e) {
      if (kDebugMode) {
        debugPrint("⚠️ ensureRegisteredIfAllowed error: $e");
      }
    }
  }

  Future<void> reconcileNotificationState() async {
    try {
      await _notificationPermissionService
          .reconcileBackendPreferenceWithSystem();
      await ensureRegisteredIfAllowed();
    } catch (_) {}
  }

  Future<bool> handlePermissionFlow() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      final authorized =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;

      if (!authorized) {
        return false;
      }

      await _auth.updatePermissions({"notificationPermissionGranted": true});

      try {
        final token = await _messaging.getToken();
        if (token != null) {
          await _tryRegisterToken(token);
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint("⚠️ Could not fetch FCM token after allow: $e");
        }
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint("⚠️ handlePermissionFlow error: $e");
      }
      return false;
    }
  }

  Future<void> _tryRegisterToken(String token) async {
    if (_lastRegisteredToken == token) {
      debugPrint("🔥 FCM TOKEN: $token");
      if (kDebugMode) {
        debugPrint("⚠️ Token already registered.");
      }
      return;
    }

    final accessToken = await SecureStorage.getAccessToken();
    if (accessToken == null) return;

    try {
      await _api.post(
        "/users/me/device-token",
        body: {"token": token, "platform": defaultTargetPlatform.name},
        headers: {"Authorization": "Bearer $accessToken"},
      );

      _lastRegisteredToken = token;

      if (kDebugMode) {
        debugPrint("✅ FCM token registered.");
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint("❌ Token register failed: $e");
      }
    }
  }
}
