import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/core/push/push_audience.dart';
import 'package:kmstry_frontend/core/push/push_logout_queue.dart';
import 'package:kmstry_frontend/core/push/push_manager.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/permissions/notification_permission_service.dart';

String jwt(String user) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': user})))}.signature';
Future<void> login(String user, String session) async {
  await SecureStorage.saveTokens(
    accessToken: jwt(user),
    refreshToken: 'refresh-$session',
  );
  await SecureStorage.savePushRegistration(
    expectedRevision: SecureStorage.sessionRevision,
    token: 'fcm-$session',
    sessionId: session,
  );
  PushAudience.resume();
}

class AllowedNotifications extends NotificationPermissionService {
  @override
  Future<NotificationPermissionState> readStateFromBackend() async =>
      const NotificationPermissionState(
        systemStatus: NotificationSystemStatus.authorized,
        accountPreference: true,
      );
}

class RegistrationApi extends ApiClient {
  final started = Completer<void>();
  final response = Completer<Map<String, dynamic>>();
  Map<String, dynamic>? lastBody;
  @override
  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) {
    lastBody = body;
    started.complete();
    return response.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async => Firebase.initializeApp());
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    PushAudience.resume();
    PackageInfo.setMockInitialValues(
      appName: 'KMSTRY',
      packageName: 'test',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/firebase_messaging'),
          (call) async {
            if (call.method == 'Messaging#getToken') return {'token': 'fcm'};
            if (call.method == 'Messaging#setAutoInitEnabled') {
              return {'isAutoInitEnabled': (call.arguments as Map)['enabled']};
            }
            return null;
          },
        );
  });

  for (final type in [
    'new_message',
    'venue_member_joined',
    'event_capacity_milestone',
  ]) {
    test('$type is accepted only for the current user and login', () async {
      await login('alice', 'first');
      final data = {
        'type': type,
        'recipientUserId': 'alice',
        'pushSessionId': 'first',
      };
      expect(await PushAudience.isCurrent(data), isTrue);
      PushAudience.suspend();
      expect(await PushAudience.isCurrent(data), isFalse);
      await SecureStorage.clearSession();
      expect(await PushAudience.isCurrent(data), isFalse);
      await login('bob', 'second');
      expect(await PushAudience.isCurrent(data), isFalse);
      await login('alice', 'third');
      expect(await PushAudience.isCurrent(data), isFalse);
      expect(
        await PushAudience.isCurrent({...data, 'pushSessionId': 'third'}),
        isTrue,
      );
    });
  }

  test('logout fences a registration response already in flight', () async {
    await login('alice', 'first');
    final api = RegistrationApi();
    final manager = PushManager.forTesting(
      api: api,
      permissions: AllowedNotifications(),
    );
    final registering = manager.ensureRegisteredIfAllowed();
    await api.started.future;
    expect(api.lastBody!['refreshToken'], 'refresh-first');
    manager.onSessionEnded();
    await SecureStorage.clearSession();
    await login('bob', 'second');
    api.response.complete({'session_id': 'first'});
    await registering;
    expect(await SecureStorage.getPushSessionId(), 'second');
    expect(await SecureStorage.getRegisteredDeviceToken(), 'fcm-second');
  });

  test('late registration storage cannot recreate a cleared session', () async {
    await login('alice', 'first');
    final revision = SecureStorage.sessionRevision;
    await SecureStorage.clearSession();
    expect(
      await SecureStorage.savePushRegistration(
        expectedRevision: revision,
        token: 'late',
        sessionId: 'first',
      ),
      isFalse,
    );
    expect(await SecureStorage.getPushSessionId(), isNull);
  });

  test(
    'new login waits for the old Firebase deletion without blocking local logout',
    () async {
      await login('alice', 'first');
      final deleting = Completer<void>();
      final releaseDelete = Completer<void>();
      var deleteCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/firebase_messaging'),
            (call) async {
              if (call.method == 'Messaging#getToken') {
                return {'token': 'new-fcm'};
              }
              if (call.method == 'Messaging#setAutoInitEnabled') {
                return {
                  'isAutoInitEnabled': (call.arguments as Map)['enabled'],
                };
              }
              if (call.method == 'Messaging#deleteToken' &&
                  deleteCalls++ == 0) {
                deleting.complete();
                await releaseDelete.future;
              }
              return null;
            },
          );
      final api = RegistrationApi();
      final manager = PushManager.forTesting(
        api: api,
        permissions: AllowedNotifications(),
      );
      manager.endSessionTransport();
      await SecureStorage.clearSession();
      await deleting.future;
      expect(await SecureStorage.getAccessToken(), isNull);
      await login('bob', 'second');
      final registering = manager.ensureRegisteredIfAllowed();
      await Future<void>.delayed(Duration.zero);
      expect(api.started.isCompleted, isFalse);
      releaseDelete.complete();
      await api.started.future;
      expect(api.lastBody!['token'], 'new-fcm');
      expect(api.lastBody!['refreshToken'], 'refresh-second');
      api.response.complete({'session_id': 'second'});
      await registering;
      expect(await SecureStorage.getRegisteredDeviceToken(), 'new-fcm');
    },
  );

  test(
    'offline cleanup survives login and retries with only the old credentials',
    () async {
      await login('alice', 'first');
      await SecureStorage.clearSession();
      await login('bob', 'second');
      await PushLogoutQueue.retryPending(
        clientFactory: () =>
            MockClient((request) async => http.Response('unavailable', 503)),
      );
      expect((await SecureStorage.getPendingPushLogouts()).length, 1);
      await PushLogoutQueue.retryPending(
        clientFactory: () => MockClient((request) async {
          expect(jsonDecode(request.body), {
            'refreshToken': 'refresh-first',
            'deviceToken': 'fcm-first',
          });
          expect(request.headers.containsKey('authorization'), isFalse);
          return http.Response('{"success":true}', 201);
        }),
      );
      expect(await SecureStorage.getPendingPushLogouts(), isEmpty);
      expect(await SecureStorage.getRefreshToken(), 'refresh-second');
      expect(await SecureStorage.getPushSessionId(), 'second');
    },
  );

  test('durable cleanup preserves the original API environment', () async {
    await login('alice', 'first');
    await SecureStorage.write('session_api_origin', 'https://api.kmstry.net');
    await SecureStorage.write('session_build_env', 'staging');
    await SecureStorage.clearSession();
    await PushLogoutQueue.retryPending(
      clientFactory: () => MockClient((request) async {
        expect(request.url.toString(), 'https://api.kmstry.net/auth/logout');
        expect(request.headers['x-kmstry-build-env'], 'staging');
        return http.Response('{}', 401);
      }),
    );
    expect(await SecureStorage.getPendingPushLogouts(), isEmpty);
  });
}
