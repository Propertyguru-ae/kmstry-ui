import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:kmstry_frontend/core/notifications/notifications_service.dart';
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

    FirebaseMessaging.onMessage.listen((message) async {
      if (kDebugMode) {
        debugPrint("🔔 Foreground push alindi: ${message.messageId}");
      }
      // Android: system doesn't display banners for foreground FCM messages.
      // iOS: setForegroundNotificationPresentationOptions handles it natively.
      if (Platform.isAndroid) {
        await _showLocalNotification(message);
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

  /// Shows a heads-up local notification for a foreground FCM message (Android only).
  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ??
        (message.data['title'] as String? ?? '');
    final body = notification?.body ??
        (message.data['body'] as String? ?? '');

    // Nothing to show.
    if (title.isEmpty && body.isEmpty) return;

    final androidDetails = AndroidNotificationDetails(
      kForegroundChannel.id,
      kForegroundChannel.name,
      channelDescription: kForegroundChannel.description,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      // Show over other apps (heads-up banner)
      fullScreenIntent: false,
    );

    final details = NotificationDetails(android: androidDetails);

    // Payload = message.data as JSON → used by tap handler for routing.
    final payload =
        message.data.isNotEmpty ? jsonEncode(message.data) : null;

    // Use a stable ID derived from the message so rapid duplicate messages
    // replace rather than stack.
    final id = (message.messageId ?? '').hashCode;

    try {
      await notificationsPlugin.show(id, title, body, details,
          payload: payload);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Local notification show failed: $e');
      }
    }
  }

  // Retry config: up to 3 attempts with exponential backoff between them.
  static const int _maxRegisterAttempts = 3;
  static const List<Duration> _registerRetryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 6),
  ];

  Future<void> _tryRegisterToken(String token) async {
    // Already successfully registered this exact token — nothing to do.
    if (_lastRegisteredToken == token) {
      if (kDebugMode) debugPrint("⚠️ FCM token already registered, skipping.");
      return;
    }

    final accessToken = await SecureStorage.getAccessToken();
    if (accessToken == null) return;

    for (int attempt = 1; attempt <= _maxRegisterAttempts; attempt++) {
      try {
        await _api.post(
          "/users/me/device-token",
          body: {
            "token": token,
            "platform": defaultTargetPlatform.name.toLowerCase(),
          },
          headers: {"Authorization": "Bearer $accessToken"},
        );

        // Success — record so we don't re-register the same token.
        _lastRegisteredToken = token;
        if (kDebugMode) {
          debugPrint("✅ FCM token registered (attempt $attempt).");
        }
        return;
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            "❌ FCM token register failed "
            "(attempt $attempt/$_maxRegisterAttempts): $e",
          );
        }

        final isLastAttempt = attempt == _maxRegisterAttempts;

        // Only retry on transient network errors — not on auth/client errors.
        final isRetryable = e is SocketException || e is TimeoutException;

        if (isLastAttempt || !isRetryable) {
          // All retries exhausted or non-retryable error.
          // _lastRegisteredToken stays unset → next reconcileNotificationState()
          // call (e.g. on app resume) will automatically retry.
          return;
        }

        await Future.delayed(_registerRetryDelays[attempt - 1]);
      }
    }
  }
}
