import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:socket_io_client/src/manager.dart';
import 'package:kmstry_frontend/features/chat/data/chat_realtime_service.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';

class _Socket extends io.Socket {
  _Socket(String url, Map<String, dynamic> options)
    : super(Manager(uri: url, options: {'autoConnect': false}), '/', options);
  int connects = 0;
  int disposals = 0;
  int disconnects = 0;
  @override
  io.Socket connect() {
    connects++;
    return this;
  }

  @override
  void dispose() {
    disposals++;
    clearListeners();
  }

  @override
  io.Socket disconnect() {
    disconnects++;
    return this;
  }

  Future<Map<String, dynamic>> handshake() {
    final result = Completer<Map<String, dynamic>>();
    (auth as Function)(
      (dynamic data) => result.complete(Map<String, dynamic>.from(data as Map)),
    );
    return result.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'photo updates and authenticated catch-up reach subscribers, duplicates do not',
    () async {
      late _Socket socket;
      final service = ChatRealtimeService.forTest(
        tokenProvider: () async => 'token',
        refreshToken: () async => null,
        deviceTokenProvider: () async => null,
        headerProvider: ({String? accessToken}) async => {},
        socketFactory: (url, options) => socket = _Socket(url, options),
      );
      final events = <ChatRealtimeEnvelope>[];
      final subscription = service.events.listen(events.add);
      await service.connectWithToken(token: 'token');
      socket.emitEvent([
        'venue.google-photos.sync',
        {'eventId': 'ready-1'},
      ]);
      final update = {'eventId': 'decision-1', 'placeId': 'ChIJplace123'};
      socket.emitEvent(['venue.google-photo.updated', update]);
      socket.emitEvent(['venue.google-photo.updated', update]);
      final moderation = {
        'eventId': 'moderation-1',
        'userId': 'owner',
        'itemId': 'review-1',
        'targetId': 'story',
        'targetType': 'PERSONAL_STORY',
      };
      socket.emitEvent(['content-moderation.updated', moderation]);
      socket.emitEvent(['content-moderation.updated', moderation]);
      await Future<void>.delayed(Duration.zero);
      expect(events.map((event) => event.event), [
        'venue.google-photos.sync',
        'venue.google-photo.updated',
        'content-moderation.updated',
      ]);
      expect(events[1].payload['placeId'], 'ChIJplace123');
      expect(events.last.payload['itemId'], 'review-1');
      await subscription.cancel();
      await service.dispose();
    },
  );
  test(
    'connections coalesce, fresh manager and fresh auth on every reconnect',
    () async {
      var storedToken = 'current-jwt';
      final sockets = <_Socket>[];
      final service = ChatRealtimeService.forTest(
        tokenProvider: () async => storedToken,
        refreshToken: () async => throw StateError('not expired'),
        deviceTokenProvider: () async => 'device',
        headerProvider: ({String? accessToken}) async => {},
        socketFactory: (url, options) {
          expect(options['forceNew'], true);
          expect(
            (options['extraHeaders'] as Map).containsKey('Authorization'),
            false,
          );
          expect(options['autoConnect'], false);
          final socket = _Socket(url, options);
          sockets.add(socket);
          return socket;
        },
      );
      await Future.wait(
        List.generate(4, (_) => service.connectWithToken(token: 'old-jwt')),
      );
      expect(sockets, hasLength(1));
      expect(sockets.single.connects, 1);
      expect((await sockets.single.handshake())['token'], 'current-jwt');
      storedToken = 'rotated-jwt';
      expect((await sockets.single.handshake())['token'], 'rotated-jwt');
      await service.connectWithToken(token: 'old-jwt');
      expect(sockets, hasLength(2));
      expect(sockets.first.disposals, 1);
      expect(sockets.first.disconnects, 0);
      await service.dispose();
    },
  );

  test(
    'expired socket JWT uses the same single-flight refresh as HTTP',
    () async {
      final expired =
          'h.${base64Url.encode(utf8.encode(jsonEncode({'exp': 1})))}.s';
      String? stored = expired;
      final fresh = Completer<String?>();
      var refreshes = 0;
      final previous = ApiClient.onRefreshToken;
      ApiClient.onRefreshToken = () async {
        refreshes++;
        stored = await fresh.future;
        return stored;
      };
      addTearDown(() => ApiClient.onRefreshToken = previous);
      late _Socket socket;
      final service = ChatRealtimeService.forTest(
        tokenProvider: () async => stored,
        refreshToken: ApiClient.refreshSessionToken,
        deviceTokenProvider: () async => null,
        headerProvider: ({String? accessToken}) async => {},
        socketFactory: (url, options) => socket = _Socket(url, options),
      );
      final connection = service.connectWithToken(token: expired);
      final httpRefresh = ApiClient.refreshSessionToken();
      await Future<void>.delayed(Duration.zero);
      fresh.complete('fresh-jwt');
      await connection;
      expect(await httpRefresh, 'fresh-jwt');
      expect(refreshes, 1);
      expect((await socket.handshake())['token'], 'fresh-jwt');
      stored = null; // Never fall back to a previous account's supplied JWT.
      expect(await socket.handshake(), isEmpty);
      await service.dispose();
    },
  );

  test('logout invalidates a connection still resolving credentials', () async {
    final token = Completer<String?>();
    var sockets = 0;
    final service = ChatRealtimeService.forTest(
      tokenProvider: () => token.future,
      refreshToken: () async => null,
      deviceTokenProvider: () async => null,
      headerProvider: ({String? accessToken}) async => {},
      socketFactory: (url, options) {
        sockets++;
        return _Socket(url, options);
      },
    );
    final connect = service.connectWithToken(token: 'old-user');
    await service.disconnect();
    token.complete('old-user');
    await connect;
    expect(sockets, 0);
    await service.dispose();
  });

  test(
    'clearing the stored session closes the socket and removes joined rooms',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      final sockets = <_Socket>[];
      final service = ChatRealtimeService.forTest(
        tokenProvider: () async => 'token',
        refreshToken: () async => null,
        deviceTokenProvider: () async => null,
        headerProvider: ({String? accessToken}) async => {},
        socketFactory: (url, options) {
          final socket = _Socket(url, options);
          sockets.add(socket);
          return socket;
        },
      );
      await service.connect(token: 'token', chatId: 'old-user-room');
      await SecureStorage.clearSession();
      expect(sockets.single.disposals, 1);
      await service.connectWithToken(token: 'token');
      expect(sockets, hasLength(2));
      expect(sockets.last.sendBuffer, isEmpty);
      await service.dispose();
    },
  );
}
