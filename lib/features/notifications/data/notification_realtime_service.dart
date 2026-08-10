import 'dart:async';

import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/chat/data/chat_realtime_service.dart';

class NotificationRealtimeEnvelope {
  final String event;
  final Map<String, dynamic> payload;

  const NotificationRealtimeEnvelope({
    required this.event,
    required this.payload,
  });
}

class NotificationRealtimeService {
  NotificationRealtimeService._internal() {
    _socket.events.listen(_onSocketEvent);
  }

  static final NotificationRealtimeService _instance =
      NotificationRealtimeService._internal();
  factory NotificationRealtimeService() => _instance;

  final ChatRealtimeService _socket = ChatRealtimeService();
  final StreamController<NotificationRealtimeEnvelope> _eventsController =
      StreamController<NotificationRealtimeEnvelope>.broadcast();
  final Set<String> _seenEventIds = <String>{};
  final List<String> _seenEventOrder = <String>[];
  static const int _maxSeenEvents = 800;

  Stream<NotificationRealtimeEnvelope> get events => _eventsController.stream;
  Stream<ChatRealtimeConnectionState> get connectionState =>
      _socket.connectionState;

  Future<void> ensureConnected() async {
    final token = await SecureStorage.getAccessToken();
    if (token == null || token.trim().isEmpty) return;
    await _socket.connectWithToken(token: token);
  }

  void _onSocketEvent(ChatRealtimeEnvelope envelope) {
    if (!_isNotificationEvent(envelope.event)) return;
    final payload = envelope.payload;
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
    _eventsController.add(
      NotificationRealtimeEnvelope(event: envelope.event, payload: payload),
    );
  }

  bool _isNotificationEvent(String event) {
    return event == 'notification.created' ||
        event == 'notification.updated' ||
        event == 'notification.read' ||
        event == 'socket.reconnected';
  }
}
