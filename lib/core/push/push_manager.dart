import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
  final Set<String> _activeChatIds = <String>{};
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
        if (!_shouldSuppressForegroundNotification(message)) {
          await _showLocalNotification(message);
        }
      }
      _foregroundMessagesController.add(message);
    });
  }

  void markChatVisible(String chatId) {
    final normalized = chatId.trim();
    if (normalized.isEmpty) return;
    _activeChatIds.add(normalized);
  }

  void markChatHidden(String chatId) {
    final normalized = chatId.trim();
    if (normalized.isEmpty) return;
    _activeChatIds.remove(normalized);
  }

  Future<String?> getDeviceTokenForRealtime() => _getFcmToken();

  bool _shouldSuppressForegroundNotification(RemoteMessage message) {
    final type = message.data['type']?.toString();
    if (type != 'new_message') return false;
    final camelChatId = message.data['chatId']?.toString().trim();
    final snakeChatId = message.data['chat_id']?.toString().trim();
    final chatId = camelChatId != null && camelChatId.isNotEmpty
        ? camelChatId
        : snakeChatId;
    if (chatId == null || chatId.isEmpty) return false;
    return _activeChatIds.contains(chatId);
  }

  /// Oturum kapanınca (logout / hesap silme) çağrılır.
  ///
  /// Backend, logout'ta kullanıcının tüm device token'larını `is_active=false`
  /// yapar. Aynı fiziksel cihazın FCM token'ı değişmediği için, in-memory
  /// `_lastRegisteredToken` guard'ı sıfırlanmazsa bir sonraki login'de
  /// `_tryRegisterToken` "zaten kayıtlı" deyip atlar ve yeni kullanıcının
  /// token'ı backend'de hiç aktifleşmez → push gelmez. Bu yüzden guard'ı
  /// sıfırlıyoruz; böylece sonraki login token'ı yeniden register eder.
  void onSessionEnded() {
    _lastRegisteredToken = null;
  }

  Future<void> ensureRegisteredIfAllowed() async {
    try {
      debugPrint('[PUSH] ensureRegisteredIfAllowed: start');
      final permissionState = await _notificationPermissionService
          .readStateFromBackend();
      debugPrint(
        '[PUSH] permissionState: system=${permissionState.systemStatus}, account=${permissionState.accountPreference}, effective=${permissionState.effectiveStatus}',
      );
      if (!permissionState.effectiveStatus) {
        debugPrint('[PUSH] ⛔ effectiveStatus=false — token kaydedilmiyor');
        return;
      }

      await _forceRefreshTokenIfStale();

      final token = await _getFcmToken();
      debugPrint(
        '[PUSH] fcmToken=${token == null ? "NULL" : "${token.substring(0, 20)}..."}',
      );
      if (token == null) return;

      await _tryRegisterToken(token);
    } catch (e) {
      debugPrint('[PUSH] ⚠️ ensureRegisteredIfAllowed error: $e');
    }
  }

  static const _pushVersionKey = 'push_token_app_version';
  static const _pushLastForceRefreshKey = 'push_token_last_force_refresh';
  static const _staleAfter = Duration(days: 7);

  /// Bir FCM/APNs token sunucu tarafında (Apple/Google) sessizce geçersiz
  /// olabilir — client'a hiçbir şekilde haber verilmez, [onTokenRefresh]
  /// tetiklenmez. Bu yüzden token'ın kendisi "değişmediği" sürece backend'e
  /// tekrar gönderilmez ve push sessizce kesilir.
  ///
  /// Çözüm: (a) her yeni app versiyonunda, (b) en az 7 günde bir,
  /// Firebase'den token'ı sil ve sıfırdan yenisini al — kullanıcının
  /// uygulamayı silip yeniden kurmasına gerek kalmadan.
  Future<void> _forceRefreshTokenIfStale() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = '${info.version}+${info.buildNumber}';

      final storedVersion = await SecureStorage.read(_pushVersionKey);
      final lastRefreshRaw = await SecureStorage.read(_pushLastForceRefreshKey);
      final lastRefresh = lastRefreshRaw != null
          ? DateTime.tryParse(lastRefreshRaw)
          : null;
      final isStale =
          lastRefresh == null ||
          DateTime.now().difference(lastRefresh) > _staleAfter;

      if (storedVersion == currentVersion && !isStale) return;

      debugPrint(
        '[PUSH] 🔁 force token refresh — versionChanged=${storedVersion != currentVersion} stale=$isStale',
      );

      try {
        await _messaging.deleteToken();
      } catch (e) {
        debugPrint('[PUSH] deleteToken failed (non-fatal): $e');
      }
      // Reset in-memory guard so the freshly-issued token is always re-sent
      // even if Firebase happens to hand back the same string.
      _lastRegisteredToken = null;

      await SecureStorage.write(_pushVersionKey, currentVersion);
      await SecureStorage.write(
        _pushLastForceRefreshKey,
        DateTime.now().toIso8601String(),
      );
    } catch (e) {
      debugPrint('[PUSH] ⚠️ _forceRefreshTokenIfStale error: $e');
    }
  }

  Future<void> reconcileNotificationState() async {
    try {
      debugPrint('[PUSH] reconcileNotificationState: start');
      await _notificationPermissionService
          .reconcileBackendPreferenceWithSystem();
      await ensureRegisteredIfAllowed();
      debugPrint('[PUSH] reconcileNotificationState: done');
    } catch (e) {
      debugPrint('[PUSH] reconcileNotificationState error: $e');
    }
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
          debugPrint(
            "⚠️ APNs token still null after retries — skipping FCM token fetch",
          );
        }
        return null;
      }
    }
    return _messaging.getToken();
  }

  /// Shows a heads-up local notification for a foreground FCM message (Android only).
  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final title =
        notification?.title ?? (message.data['title'] as String? ?? '');
    final body = notification?.body ?? (message.data['body'] as String? ?? '');

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
    final payload = message.data.isNotEmpty ? jsonEncode(message.data) : null;

    // Use a stable ID derived from the message so rapid duplicate messages
    // replace rather than stack.
    final id = (message.messageId ?? '').hashCode;

    try {
      await notificationsPlugin.show(
        id,
        title,
        body,
        details,
        payload: payload,
      );
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
    debugPrint('[PUSH] _tryRegisterToken: start');
    if (_lastRegisteredToken == token) {
      debugPrint('[PUSH] token zaten kayıtlı, skip');
      return;
    }

    final accessToken = await SecureStorage.getAccessToken();
    debugPrint('[PUSH] accessToken=${accessToken == null ? "NULL" : "var"}');
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
        debugPrint('[PUSH] ✅ FCM token registered (attempt $attempt)');
        return;
      } catch (e) {
        debugPrint(
          '[PUSH] ❌ FCM token register failed (attempt $attempt/$_maxRegisterAttempts): $e',
        );

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
