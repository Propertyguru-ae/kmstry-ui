import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:kmstry_frontend/core/notifications/notifications_service.dart';
import 'package:kmstry_frontend/core/permissions/notification_permission_service.dart';
import '../network/api_client.dart';
import '../storage/secure_storage.dart';
import '../../features/auth/data/auth_repository.dart';
import 'push_audience.dart';
import 'push_logout_queue.dart';

class PushManager with WidgetsBindingObserver {
  PushManager._({ApiClient? api, NotificationPermissionService? permissions})
    : _api = api ?? ApiClient(),
      _notificationPermissionService =
          permissions ?? NotificationPermissionService();

  @visibleForTesting
  factory PushManager.forTesting({
    required ApiClient api,
    required NotificationPermissionService permissions,
  }) => PushManager._(api: api, permissions: permissions);
  static final PushManager instance = PushManager._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final ApiClient _api;
  final AuthRepository _auth = AuthRepository();
  final NotificationPermissionService _notificationPermissionService;

  bool _initialized = false;
  String? _lastRegisteredToken;
  int? _lastRegisteredRevision;
  int _generation = 0;
  bool _acceptingRegistrations = true;
  Future<void> _transport = Future.value();
  Future<void>? _registrationFlight;
  int? _registrationGeneration;
  int? _registrationRevision;

  // Firebase mutations must finish before a new account obtains/registers a
  // token. Timing out deleteToken would let it delete the next account's token.
  Future<T> _withTransport<T>(Future<T> Function() action) {
    final next = _transport.then((_) => action());
    _transport = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  final Set<String> _activeChatIds = <String>{};
  final StreamController<RemoteMessage> _foregroundMessagesController =
      StreamController<RemoteMessage>.broadcast();

  Stream<RemoteMessage> get foregroundMessages =>
      _foregroundMessagesController.stream;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(PushLogoutQueue.retryPending());
    SecureStorage.sessionEnded.listen((_) => onSessionEnded());

    // Display foreground notifications ourselves, after checking the audience.
    if (Platform.isIOS) {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: false,
        sound: false,
      );
    }

    _messaging.onTokenRefresh.listen((token) async {
      if (kDebugMode) {
        debugPrint('🔄 FCM token refreshed');
      }
      // Read the current SDK token after queued transport cleanup. The event
      // itself may have been emitted for the previous account's token.
      await ensureRegisteredIfAllowed();
    });

    FirebaseMessaging.onMessage.listen((message) async {
      if (!await PushAudience.isCurrent(message.data)) return;
      if (kDebugMode) {
        debugPrint("🔔 Foreground push alindi: ${message.messageId}");
      }
      if (!_shouldSuppressForegroundNotification(message)) {
        await _showLocalNotification(message);
      }
      if (await PushAudience.isCurrent(message.data)) {
        _foregroundMessagesController.add(message);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(PushLogoutQueue.retryPending());
    unawaited(ensureRegisteredIfAllowed());
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

  /// Fence every in-flight registration/display as soon as the session ends.
  void onSessionEnded() {
    _generation++;
    _acceptingRegistrations = false;
    PushAudience.suspend();
    _lastRegisteredToken = null;
    _lastRegisteredRevision = null;
    _activeChatIds.clear();
  }

  void endSessionTransport() {
    onSessionEnded();
    unawaited(
      _withTransport(() async {
        await SecureStorage.write(_rotationPendingKey, 'true');
        try {
          await notificationsPlugin.cancelAll();
        } catch (_) {}
        try {
          await _messaging.setAutoInitEnabled(false);
        } catch (_) {}
        try {
          await _messaging.deleteToken();
          await SecureStorage.write(_rotationPendingKey, 'false');
        } catch (_) {
          // Durable, session-scoped server revocation is retried independently.
        }
      }),
    );
  }

  Future<void> ensureRegisteredIfAllowed() {
    if (_registrationFlight != null &&
        _registrationGeneration == _generation &&
        _registrationRevision == SecureStorage.sessionRevision) {
      return _registrationFlight!;
    }
    _registrationGeneration = _generation;
    _registrationRevision = SecureStorage.sessionRevision;
    late final Future<void> flight;
    flight = _ensureRegisteredIfAllowed().whenComplete(() {
      if (identical(_registrationFlight, flight)) _registrationFlight = null;
    });
    return _registrationFlight = flight;
  }

  Future<void> _ensureRegisteredIfAllowed() async {
    final generation = _generation;
    final revision = SecureStorage.sessionRevision;
    bool current() =>
        !AuthRepository.isLoggingOut &&
        generation == _generation &&
        revision == SecureStorage.sessionRevision;
    try {
      if (await SecureStorage.getAccessToken() == null || !current()) return;
      // Waiting may time out; the mutation itself stays serialized. Login can
      // continue while an offline Firebase SDK finishes its old cleanup.
      await _transport.timeout(const Duration(seconds: 2));
      if (!current()) return;
      _acceptingRegistrations = true;
      debugPrint('[PUSH] ensureRegisteredIfAllowed: start');
      final permissionState = await _notificationPermissionService
          .readStateFromBackend();
      if (!current()) return;
      debugPrint(
        '[PUSH] permissionState: system=${permissionState.systemStatus}, account=${permissionState.accountPreference}, effective=${permissionState.effectiveStatus}',
      );
      if (!permissionState.effectiveStatus) {
        debugPrint('[PUSH] ⛔ effectiveStatus=false — token kaydedilmiyor');
        return;
      }

      await _withTransport(() async {
        if (!current()) return;
        await _messaging.setAutoInitEnabled(true);
        if (!current()) return;
        await _forceRefreshTokenIfStale();
      });
      if (!current()) return;

      final token = await _getFcmToken();
      debugPrint('[PUSH] FCM token available=${token != null}');
      if (token == null || !current()) return;

      await _tryRegisterToken(token);
    } catch (e) {
      debugPrint('[PUSH] ⚠️ ensureRegisteredIfAllowed error: $e');
    }
  }

  static const _pushVersionKey = 'push_token_app_version';
  static const _pushLastForceRefreshKey = 'push_token_last_force_refresh';
  static const _staleAfter = Duration(days: 7);
  static const _rotationPendingKey = 'push_token_rotation_pending';

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
      final rotationPending =
          await SecureStorage.read(_rotationPendingKey) == 'true';
      final lastRefresh = lastRefreshRaw != null
          ? DateTime.tryParse(lastRefreshRaw)
          : null;
      final isStale =
          lastRefresh == null ||
          DateTime.now().difference(lastRefresh) > _staleAfter;

      if (storedVersion == currentVersion && !isStale && !rotationPending) {
        return;
      }

      debugPrint(
        '[PUSH] 🔁 force token refresh — versionChanged=${storedVersion != currentVersion} stale=$isStale',
      );

      try {
        await _messaging.deleteToken();
        await SecureStorage.write(_rotationPendingKey, 'false');
        await SecureStorage.clearRegisteredDeviceToken();
      } catch (e) {
        debugPrint('[PUSH] deleteToken failed (non-fatal): $e');
        if (rotationPending) rethrow;
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
      if (await SecureStorage.read(_rotationPendingKey) == 'true') rethrow;
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
    final revision = SecureStorage.sessionRevision;
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

      if (revision != SecureStorage.sessionRevision) return false;
      await _auth.updatePermissions({"notificationPermissionGranted": true});
      if (revision != SecureStorage.sessionRevision) return false;

      try {
        await ensureRegisteredIfAllowed();
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
  Future<String?> _getFcmToken() => _withTransport(_readFcmToken);

  Future<String?> _readFcmToken() async {
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

  /// Foreground banners on both platforms are gated by account and session.
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

    final details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
      ),
    );

    // Payload = message.data as JSON → used by tap handler for routing.
    final payload = message.data.isNotEmpty ? jsonEncode(message.data) : null;

    // Use a stable ID derived from the message so rapid duplicate messages
    // replace rather than stack.
    final id = (message.messageId ?? '').hashCode;

    try {
      if (!await PushAudience.isCurrent(message.data)) return;
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
    final generation = _generation;
    final revision = SecureStorage.sessionRevision;
    bool current() =>
        !AuthRepository.isLoggingOut &&
        _acceptingRegistrations &&
        generation == _generation &&
        revision == SecureStorage.sessionRevision;
    if (!current()) return;
    debugPrint('[PUSH] _tryRegisterToken: start');
    if (_lastRegisteredToken == token && _lastRegisteredRevision == revision) {
      debugPrint('[PUSH] token zaten kayıtlı, skip');
      return;
    }

    final accessToken = await SecureStorage.getAccessToken();
    debugPrint('[PUSH] authenticated=${accessToken != null}');
    if (accessToken == null || !current()) return;

    for (int attempt = 1; attempt <= _maxRegisterAttempts; attempt++) {
      try {
        final refreshToken = await SecureStorage.getRefreshToken();
        if (refreshToken == null || !current()) return;
        final result = await _api.post(
          "/users/me/device-token",
          body: {
            "token": token,
            "platform": defaultTargetPlatform.name.toLowerCase(),
            "refreshToken": refreshToken,
          },
          headers: {"Authorization": "Bearer $accessToken"},
        );

        // Success — record so we don't re-register the same token.
        if (!current()) return;
        final sessionId = result['session_id'];
        if (sessionId is! String || sessionId.isEmpty) return;
        final saved = await SecureStorage.savePushRegistration(
          expectedRevision: revision,
          token: token,
          sessionId: sessionId,
        );
        if (!saved || !current()) return;
        _lastRegisteredToken = token;
        _lastRegisteredRevision = revision;
        PushAudience.resume();
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
        if (!current()) return;
      }
    }
  }
}
