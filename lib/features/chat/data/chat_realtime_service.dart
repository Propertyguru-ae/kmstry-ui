import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/network/app_request_headers.dart';
import 'package:kmstry_frontend/core/network/app_check_token_cache.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/push/push_manager.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

enum ChatRealtimeConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
}

class ChatRealtimeEnvelope {
  final String event;
  final Map<String, dynamic> payload;

  const ChatRealtimeEnvelope({required this.event, required this.payload});
}

class ChatRealtimeService {
  ChatRealtimeService._internal({
    Future<String?> Function()? tokenProvider,
    Future<String?> Function()? refreshToken,
    Future<String?> Function()? deviceTokenProvider,
    io.Socket Function(String, Map<String, dynamic>)? socketFactory,
    Future<Map<String, String>> Function({String? accessToken})? headerProvider,
  }) : _tokenProvider = tokenProvider ?? SecureStorage.getAccessToken,
       _refreshToken = refreshToken ?? ApiClient.refreshSessionToken,
       _deviceTokenProvider =
           deviceTokenProvider ??
           (() => PushManager.instance.getDeviceTokenForRealtime()),
       _socketFactory =
           socketFactory ?? ((url, options) => io.io(url, options)),
       _headerProvider = headerProvider ?? AppRequestHeaders.build {
    debugPrint('💬 [Realtime] Paylasilan socket servisi olusturuldu');
    _sessionEndSubscription = SecureStorage.sessionEnded.listen((_) {
      unawaited(disconnect());
    });
  }

  static final ChatRealtimeService _instance = ChatRealtimeService._internal();
  factory ChatRealtimeService() => _instance;

  @visibleForTesting
  ChatRealtimeService.forTest({
    required Future<String?> Function() tokenProvider,
    required Future<String?> Function() refreshToken,
    required Future<String?> Function() deviceTokenProvider,
    required io.Socket Function(String, Map<String, dynamic>) socketFactory,
    required Future<Map<String, String>> Function({String? accessToken})
    headerProvider,
  }) : this._internal(
         tokenProvider: tokenProvider,
         refreshToken: refreshToken,
         deviceTokenProvider: deviceTokenProvider,
         socketFactory: socketFactory,
         headerProvider: headerProvider,
       );

  final Future<String?> Function() _tokenProvider;
  final Future<String?> Function() _refreshToken;
  final Future<String?> Function() _deviceTokenProvider;
  final io.Socket Function(String, Map<String, dynamic>) _socketFactory;
  final Future<Map<String, String>> Function({String? accessToken})
  _headerProvider;
  Future<void>? _connecting;
  StreamSubscription<void>? _sessionEndSubscription;
  int _generation = 0;

  io.Socket? _socket;
  String? _token;
  String? _deviceToken;
  bool _disposed = false;
  final Set<String> _joinedChatIds = <String>{};

  /// Presence heartbeat: backend'te `presence:user:<id>` key'i 120s TTL ile
  /// tutuluyor. Bağlı ama boşta duran bir socket'te bu key yenilenmezse 2dk
  /// sonra expire olup kullanıcı yanlışlıkla "offline" görünüyor. Bu timer,
  /// socket bağlıyken periyodik `presence.ping` atarak TTL'i canlı tutar.
  Timer? _presenceHeartbeat;
  static const Duration _presenceHeartbeatInterval = Duration(seconds: 45);

  final Set<String> _seenEventIds = <String>{};
  final List<String> _seenEventOrder = <String>[];
  static const int _maxSeenEvents = 1200;

  final StreamController<ChatRealtimeEnvelope> _eventsController =
      StreamController<ChatRealtimeEnvelope>.broadcast();
  final StreamController<ChatRealtimeConnectionState> _connectionController =
      StreamController<ChatRealtimeConnectionState>.broadcast();

  Stream<ChatRealtimeEnvelope> get events => _eventsController.stream;
  Stream<ChatRealtimeConnectionState> get connectionState =>
      _connectionController.stream;

  Future<void> connect({required String token, required String chatId}) async {
    if (_disposed) return;
    final normalizedChatId = chatId.trim();
    if (normalizedChatId.isEmpty) return;
    _joinedChatIds.add(normalizedChatId);

    await connectWithToken(token: token);
  }

  Future<void> connectWithToken({required String token}) async {
    if (_disposed) return;
    // Callers may have read their token before an HTTP refresh. Always resolve
    // storage again, and coalesce Home/list/detail's simultaneous connections.
    final current = _connecting;
    if (current != null) return current;
    final request = _connectCurrentSession(_generation);
    _connecting = request;
    try {
      await request;
    } finally {
      if (identical(_connecting, request)) _connecting = null;
    }
  }

  Future<String?> _currentAccessToken() async {
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) return null;
    final expiry = jwtExpiry(token);
    if (expiry != null &&
        !expiry.isAfter(DateTime.now().add(const Duration(seconds: 30)))) {
      return _refreshToken();
    }
    return token;
  }

  Future<void> _connectCurrentSession(int generation) async {
    String? token;
    String? deviceToken;
    try {
      token = await _currentAccessToken();
    } catch (_) {
      // HTTP/session management owns logout. A transient socket failure does
      // not expire a valid session or escape into Flutter's error handler.
      return;
    }
    try {
      deviceToken = await _deviceTokenProvider().timeout(
        const Duration(seconds: 2),
      );
    } catch (_) {
      // FCM is optional for chat; unavailable/slow push registration must not
      // delay the HTTP-backed conversation or prevent a socket connection.
      deviceToken = null;
    }
    if (_disposed || generation != _generation || token == null) return;

    final shouldRecreateSocket =
        _socket == null ||
        _token != token ||
        _deviceToken != deviceToken ||
        !_isSameOrigin(_buildSocketBaseUrl(), _socket!.io.uri);

    _token = token;
    _deviceToken = deviceToken;

    if (shouldRecreateSocket) {
      _closeSocket();
      _createAndConnectSocket(token: token, deviceToken: deviceToken);
      return;
    }

    if (_socket != null && _socket!.connected) {
      _joinAllChats();
      return;
    }

    _connectionController.add(ChatRealtimeConnectionState.connecting);
    debugPrint('💬 [Realtime] Mevcut socket baglaniyor');
    _socket?.connect();
  }

  Future<void> disconnect() async {
    _generation++;
    _connecting = null;
    _closeSocket();
    _token = null;
    _deviceToken = null;
    _joinedChatIds.clear();
    _seenEventIds.clear();
    _seenEventOrder.clear();
    _connectionController.add(ChatRealtimeConnectionState.disconnected);
  }

  void _closeSocket() {
    _stopPresenceHeartbeat();
    final socket = _socket;
    _socket = null;
    // dispose already disconnects; doing both races the transport's close.
    socket?.dispose();
    debugPrint('💬 [Realtime] Socket baglantisi kapandi');
  }

  Future<void> dispose() async {
    _disposed = true;
    await _sessionEndSubscription?.cancel();
    await disconnect();
    await _eventsController.close();
    await _connectionController.close();
  }

  void sendTypingStart({required String chatId}) {
    final normalized = chatId.trim();
    if (normalized.isEmpty) return;
    _joinedChatIds.add(normalized);
    _emitIfConnected('typing.start', {'chatId': normalized});
  }

  void sendTypingStop({required String chatId}) {
    final normalized = chatId.trim();
    if (normalized.isEmpty) return;
    _joinedChatIds.add(normalized);
    _emitIfConnected('typing.stop', {'chatId': normalized});
  }

  /// Okundu bilgisini socket üzerinden işaretle → anlık "seen" (HTTP hop yok).
  /// Sunucu markRead çalıştırıp chat.read'i odaya broadcast eder.
  void sendChatRead({required String chatId}) {
    final normalized = chatId.trim();
    if (normalized.isEmpty) return;
    _emitIfConnected('chat.read', {'chatId': normalized});
  }

  void joinChat(String chatId) {
    final normalized = chatId.trim();
    if (normalized.isEmpty) return;
    _joinedChatIds.add(normalized);
    debugPrint('💬 [Realtime] chat.join => $normalized');
    _emitIfConnected('chat.join', {'chatId': normalized});
  }

  void leaveChat(String chatId) {
    final normalized = chatId.trim();
    if (normalized.isEmpty) return;
    _joinedChatIds.remove(normalized);
    debugPrint('💬 [Realtime] chat.leave => $normalized');
    _emitIfConnected('chat.leave', {'chatId': normalized});
  }

  void _createAndConnectSocket({
    required String token,
    required String? deviceToken,
  }) {
    final baseUrl = _buildSocketBaseUrl();
    final generation = _generation;
    late final io.Socket socket;
    socket = _socketFactory(
      baseUrl,
      io.OptionBuilder()
          .setPath('/socket.io')
          .setTransports(['websocket'])
          .disableAutoConnect()
          // The package caches Managers by origin even after socket.dispose.
          // Never inherit a previous session's auth closure or headers.
          .enableForceNew()
          .enableReconnection()
          .setReconnectionAttempts(1000)
          .setReconnectionDelay(1200)
          .setReconnectionDelayMax(8000)
          // Socket.IO calls this again for every reconnect. App Check tokens
          // are short lived, so never freeze one into the socket options.
          .setAuthFn((callback) {
            unawaited(
              _buildSocketAuth(deviceToken: deviceToken).then((auth) {
                if (!_disposed &&
                    generation == _generation &&
                    identical(_socket, socket)) {
                  callback(auth);
                }
              }),
            );
          })
          .setExtraHeaders({
            // JWT lives only in the fresh auth callback. A stale Authorization
            // fallback must never survive logout or a token rotation.
            if (deviceToken != null && deviceToken.isNotEmpty)
              'x-device-token': deviceToken,
          })
          .build(),
    );
    _socket = socket;
    debugPrint('💬 [Realtime] Yeni socket instance olusturuldu');
    _bindSocketListeners(socket);
    _connectionController.add(ChatRealtimeConnectionState.connecting);
    socket.connect();
  }

  Future<Map<String, dynamic>> _buildSocketAuth({
    required String? deviceToken,
  }) async {
    String? token;
    Map<String, String> headers;
    try {
      token = await _currentAccessToken();
      if (token == null) return const {};
      headers = await _headerProvider(accessToken: token);
    } catch (_) {
      return const {}; // Fail closed; never replay an expired JWT.
    }
    return <String, dynamic>{
      'token': token,
      if (deviceToken != null && deviceToken.isNotEmpty)
        'deviceToken': deviceToken,
      'appCheckToken': ?headers['X-Firebase-AppCheck'],
      'appVersion': ?headers['x-kmstry-app-version'],
      'buildNumber': ?headers['x-kmstry-build-number'],
      'buildEnv': ?headers['x-kmstry-build-env'],
      'platform': ?headers['x-kmstry-platform'],
      'osVersion': ?headers['x-kmstry-os-version'],
    };
  }

  void _bindSocketListeners(io.Socket socket) {
    socket.onConnect((_) {
      if (_disposed || !identical(_socket, socket)) return;
      debugPrint('💬 [Realtime] Socket baglandi');
      _connectionController.add(ChatRealtimeConnectionState.connected);
      _joinAllChats();
      _startPresenceHeartbeat();
    });

    socket.onReconnect((_) {
      if (_disposed || !identical(_socket, socket)) return;
      debugPrint('💬 [Realtime] Socket yeniden baglandi');
      _connectionController.add(ChatRealtimeConnectionState.connected);
      _joinAllChats();
      _startPresenceHeartbeat();
      _eventsController.add(
        const ChatRealtimeEnvelope(
          event: 'socket.reconnected',
          payload: <String, dynamic>{},
        ),
      );
    });

    socket.onReconnectAttempt((_) {
      if (_disposed || !identical(_socket, socket)) return;
      debugPrint('💬 [Realtime] Yeniden baglanma deneniyor');
      _connectionController.add(ChatRealtimeConnectionState.reconnecting);
    });

    socket.onReconnectError((_) {
      if (_disposed || !identical(_socket, socket)) return;
      debugPrint('💬 [Realtime] Yeniden baglanma hatasi');
      _connectionController.add(ChatRealtimeConnectionState.reconnecting);
    });

    socket.onDisconnect((_) {
      if (_disposed || !identical(_socket, socket)) return;
      debugPrint('💬 [Realtime] Socket baglantisi koptu');
      _stopPresenceHeartbeat();
      _connectionController.add(ChatRealtimeConnectionState.disconnected);
    });

    socket.onConnectError((_) {
      if (_disposed || !identical(_socket, socket)) return;
      debugPrint('💬 [Realtime] Socket baglanma hatasi');
      _connectionController.add(ChatRealtimeConnectionState.reconnecting);
    });

    socket.onError((_) {
      if (_disposed || !identical(_socket, socket)) return;
      debugPrint('💬 [Realtime] Socket genel hatasi');
      _connectionController.add(ChatRealtimeConnectionState.reconnecting);
    });

    const serverEvents = <String>[
      'content-moderation.updated',
      'venue.google-photo.updated',
      'venue.google-photos.sync',
      'message.created',
      'message.updated',
      'message.deleted',
      'message.reaction',
      'notification.created',
      'notification.updated',
      'notification.read',
      'chat.unread.updated',
      'chat.updated',
      'chat.read',
      'presence.online',
      'presence.offline',
      'typing.start',
      'typing.stop',
    ];
    for (final event in serverEvents) {
      socket.on(event, (data) {
        if (!identical(_socket, socket)) return;
        _handleIncomingEvent(event: event, rawData: data);
      });
    }
  }

  void _handleIncomingEvent({required String event, required dynamic rawData}) {
    if (_disposed) return;
    final payload = _asMap(rawData);
    if (payload == null) return;

    final eventId = payload['eventId']?.toString();
    final snakeEventId = payload['event_id']?.toString();
    final normalizedEventId = (eventId != null && eventId.isNotEmpty)
        ? eventId
        : ((snakeEventId != null && snakeEventId.isNotEmpty)
              ? snakeEventId
              : null);
    if (normalizedEventId != null) {
      if (_seenEventIds.contains(normalizedEventId)) return;
      _seenEventIds.add(normalizedEventId);
      _seenEventOrder.add(normalizedEventId);
      if (_seenEventOrder.length > _maxSeenEvents) {
        final removed = _seenEventOrder.removeAt(0);
        _seenEventIds.remove(removed);
      }
    }

    debugPrint('💬 [Realtime] Event alindi: $event');
    _eventsController.add(ChatRealtimeEnvelope(event: event, payload: payload));
  }

  void _joinAllChats() {
    for (final chatId in _joinedChatIds) {
      if (chatId.isEmpty) continue;
      _emitIfConnected('chat.join', {'chatId': chatId});
    }
  }

  void _startPresenceHeartbeat() {
    _presenceHeartbeat?.cancel();
    // Bağlanır bağlanmaz bir kez gönder, sonra periyodik yenile.
    _emitIfConnected('presence.ping', const <String, dynamic>{});
    _presenceHeartbeat = Timer.periodic(_presenceHeartbeatInterval, (_) {
      if (_disposed) return;
      _emitIfConnected('presence.ping', const <String, dynamic>{});
    });
  }

  void _stopPresenceHeartbeat() {
    _presenceHeartbeat?.cancel();
    _presenceHeartbeat = null;
  }

  /// Uygulama ön plana geldiğinde çağrılır — presence'i anında "online" yapar.
  void notifyForeground() {
    _emitIfConnected('presence.ping', const <String, dynamic>{});
  }

  /// Uygulama arka plana alındığında çağrılır — socket OS tarafından bir süre
  /// canlı kalabildiği için, karşı tarafın hemen "offline" görmesi adına proaktif
  /// olarak away sinyali gönderir.
  void notifyAway() {
    _emitIfConnected('presence.away', const <String, dynamic>{});
  }

  void _emitIfConnected(String event, Map<String, dynamic> payload) {
    final socket = _socket;
    if (_disposed || socket == null || !socket.connected) return;
    socket.emit(event, payload);
  }

  Map<String, dynamic>? _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return data.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  String _buildSocketBaseUrl() {
    final uri = Uri.parse(AppConfig.baseUrl);
    // Socket.IO istemcisi origin olarak http/https URL bekler.
    // WebSocket upgrade'i istemci tarafından otomatik yönetilir.
    return uri.replace(path: '', query: null, fragment: null).toString();
  }

  bool _isSameOrigin(String expectedUrl, String? currentUrl) {
    if (currentUrl == null || currentUrl.isEmpty) return false;
    final expected = Uri.tryParse(expectedUrl);
    final current = Uri.tryParse(currentUrl);
    if (expected == null || current == null) return false;
    return expected.scheme == current.scheme &&
        expected.host == current.host &&
        expected.port == current.port;
  }
}
