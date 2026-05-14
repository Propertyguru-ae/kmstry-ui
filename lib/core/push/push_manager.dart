import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:kmstry_frontend/core/permissions/notification_permission_service.dart';
import 'dart:async';
import 'dart:io';
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
  final StreamController<RemoteMessage> _foregroundMessagesController =
      StreamController<RemoteMessage>.broadcast();

  Stream<RemoteMessage> get foregroundMessages =>
      _foregroundMessagesController.stream;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // iOS: uygulama açıkken gelen bildirimleri sistem banner'ı olarak göster
    if (Platform.isIOS) {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    _messaging.onTokenRefresh.listen((token) async {
      if (kDebugMode) {
        debugPrint("🔄 FCM token refreshed: $token");
      }
      await _tryRegisterToken(token);
    });

    FirebaseMessaging.onMessage.listen((message) {
      if (kDebugMode) {
        debugPrint("🔔 Foreground push alindi: ${message.messageId}");
      }
      _foregroundMessagesController.add(message);
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

      final token = await _getFcmToken();
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
        final token = await _getFcmToken();
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

  /// iOS'ta APNs token sistem tarafından asenkron verilir.
  /// FCM token almadan önce APNs token'inin hazır olmasini bekler
  /// (max 5 saniye, 500ms aralıklarla retry).
  Future<String?> _getFcmToken() async {
    if (Platform.isIOS) {
      String? apns;
      for (int i = 0; i < 10; i++) {
        apns = await _messaging.getAPNSToken();
        if (apns != null) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (apns == null) {
        if (kDebugMode) {
          debugPrint("⚠️ APNs token still null after retries — skipping FCM token fetch");
        }
        return null;
      }
    }
    return _messaging.getToken();
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
        body: {"token": token, "platform": defaultTargetPlatform.name.toLowerCase()},
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
