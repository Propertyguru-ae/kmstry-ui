import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
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

  const ChatRealtimeEnvelope({
    required this.event,
    required this.payload,
  });
}

class ChatRealtimeService {
  ChatRealtimeService._internal() {
    debugPrint('💬 [Realtime] Paylasilan socket servisi olusturuldu');
  }

  static final ChatRealtimeService _instance = ChatRealtimeService._internal();
  factory ChatRealtimeService() => _instance;

  io.Socket? _socket;
  String? _token;
  bool _disposed = false;
  final Set<String> _joinedChatIds = <String>{};

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

  Future<void> connect({
    required String token,
    required String chatId,
  }) async {
    if (_disposed) return;
    final normalizedChatId = chatId.trim();
    if (normalizedChatId.isEmpty) return;
    _joinedChatIds.add(normalizedChatId);

    await connectWithToken(token: token);
  }

  Future<void> connectWithToken({required String token}) async {
    if (_disposed) return;

    final shouldRecreateSocket =
        _socket == null ||
        _token != token ||
        !_isSameOrigin(_buildSocketBaseUrl(), _socket!.io.uri);

    _token = token;

    if (shouldRecreateSocket) {
      await disconnect();
      _createAndConnectSocket(token: token);
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
    final socket = _socket;
    if (socket != null) {
      socket.dispose();
      socket.disconnect();
    }
    _socket = null;
    debugPrint('💬 [Realtime] Socket baglantisi kapandi');
    _connectionController.add(ChatRealtimeConnectionState.disconnected);
  }

  Future<void> dispose() async {
    _disposed = true;
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

  void _createAndConnectSocket({required String token}) {
    final baseUrl = _buildSocketBaseUrl();
    final socket = io.io(
      baseUrl,
      io.OptionBuilder()
          .setPath('/socket.io')
          .setTransports(['websocket'])
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(1000)
          .setReconnectionDelay(1200)
          .setReconnectionDelayMax(8000)
          .setAuth({'token': token})
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .build(),
    );
    _socket = socket;
    debugPrint('💬 [Realtime] Yeni socket instance olusturuldu');
    _bindSocketListeners(socket);
    _connectionController.add(ChatRealtimeConnectionState.connecting);
  }

  void _bindSocketListeners(io.Socket socket) {
    socket.onConnect((_) {
      if (_disposed) return;
      debugPrint('💬 [Realtime] Socket baglandi');
      _connectionController.add(ChatRealtimeConnectionState.connected);
      _joinAllChats();
    });

    socket.onReconnect((_) {
      if (_disposed) return;
      debugPrint('💬 [Realtime] Socket yeniden baglandi');
      _connectionController.add(ChatRealtimeConnectionState.connected);
      _joinAllChats();
      _eventsController.add(
        const ChatRealtimeEnvelope(
          event: 'socket.reconnected',
          payload: <String, dynamic>{},
        ),
      );
    });

    socket.onReconnectAttempt((_) {
      if (_disposed) return;
      debugPrint('💬 [Realtime] Yeniden baglanma deneniyor');
      _connectionController.add(ChatRealtimeConnectionState.reconnecting);
    });

    socket.onReconnectError((_) {
      if (_disposed) return;
      debugPrint('💬 [Realtime] Yeniden baglanma hatasi');
      _connectionController.add(ChatRealtimeConnectionState.reconnecting);
    });

    socket.onDisconnect((_) {
      if (_disposed) return;
      debugPrint('💬 [Realtime] Socket baglantisi koptu');
      _connectionController.add(ChatRealtimeConnectionState.disconnected);
    });

    socket.onConnectError((_) {
      if (_disposed) return;
      debugPrint('💬 [Realtime] Socket baglanma hatasi');
      _connectionController.add(ChatRealtimeConnectionState.reconnecting);
    });

    socket.onError((_) {
      if (_disposed) return;
      debugPrint('💬 [Realtime] Socket genel hatasi');
      _connectionController.add(ChatRealtimeConnectionState.reconnecting);
    });

    const serverEvents = <String>[
      'message.created',
      'message.updated',
      'message.deleted',
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
        _handleIncomingEvent(event: event, rawData: data);
      });
    }
  }

  void _handleIncomingEvent({
    required String event,
    required dynamic rawData,
  }) {
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

    debugPrint('💬 [Realtime] Event alindi: $event payload=$payload');
    _eventsController.add(ChatRealtimeEnvelope(event: event, payload: payload));
  }

  void _joinAllChats() {
    for (final chatId in _joinedChatIds) {
      if (chatId.isEmpty) continue;
      _emitIfConnected('chat.join', {'chatId': chatId});
    }
  }

  void _emitIfConnected(String event, Map<String, dynamic> payload) {
    final socket = _socket;
    if (_disposed || socket == null || !socket.connected) return;
    socket.emit(event, payload);
  }

  Map<String, dynamic>? _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) {
      return data.map(
        (key, value) => MapEntry(key.toString(), value),
      );
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
