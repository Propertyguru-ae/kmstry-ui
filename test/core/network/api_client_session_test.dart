import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/network/request_session.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';

String jwt(String owner, [int v = 1]) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': owner, 'v': v})))}.sig';

Future<dynamic> request(ApiClient api, String verb, String token) {
  final headers = {'authorization': 'Bearer $token'};
  switch (verb) {
    case 'GET':
      return api.get('/test', headers: headers);
    case 'POST':
      return api.post(
        '/test',
        headers: headers,
        body: {'content': 'old owner'},
      );
    case 'PATCH':
      return api.patch(
        '/test',
        headers: headers,
        body: {'content': 'old owner'},
      );
    case 'PUT':
      return api.put('/test', headers: headers, body: {'content': 'old owner'});
    default:
      return api.delete('/test', headers: headers);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final originalRefresh = ApiClient.onRefreshToken;
  final originalExpired = ApiClient.onSessionExpired;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SecureStorage.saveTokens(
      accessToken: jwt('a'),
      refreshToken: 'a-refresh',
    );
  });
  tearDown(() {
    ApiClient.onRefreshToken = originalRefresh;
    ApiClient.onSessionExpired = originalExpired;
  });

  for (final verb in ['GET', 'POST', 'PATCH', 'PUT', 'DELETE']) {
    for (final status in [200, 401]) {
      test(
        '$verb late $status does not replay or return old data after another login',
        () async {
          final first = Completer<http.Response>();
          final started = Completer<void>();
          var calls = 0, refreshes = 0, expiries = 0;
          ApiClient.onRefreshToken = () async {
            refreshes++;
            return jwt('b');
          };
          ApiClient.onSessionExpired = () async {
            expiries++;
          };
          final api = ApiClient(
            client: MockClient((_) {
              calls++;
              started.complete();
              return first.future;
            }),
            appCheckHeaderProvider: ({bool forceRefresh = false}) async => {},
          );
          final result = request(api, verb, jwt('a'));
          final rejected = expectLater(
            result,
            throwsA(isA<RequestSessionChanged>()),
          );
          await started.future;
          await SecureStorage.clearSession();
          await SecureStorage.saveTokens(
            accessToken: jwt('b'),
            refreshToken: 'b-refresh',
          );
          first.complete(http.Response('{}', status));
          await rejected;
          expect(calls, 1);
          expect(refreshes, 0);
          expect(expiries, 0);
        },
      );
    }
  }
  test('same-user logout/login is also a new session', () async {
    final gate = Completer<http.Response>();
    final started = Completer<void>();
    final api = ApiClient(
      client: MockClient((_) {
        started.complete();
        return gate.future;
      }),
      appCheckHeaderProvider: ({bool forceRefresh = false}) async => {},
    );
    final result = request(api, 'POST', jwt('a'));
    final rejected = expectLater(result, throwsA(isA<RequestSessionChanged>()));
    await started.future;
    await SecureStorage.clearSession();
    await SecureStorage.saveTokens(
      accessToken: jwt('a', 2),
      refreshToken: 'new',
    );
    gate.complete(http.Response('{}', 401));
    await rejected;
  });
  test('logout while App Check refreshes prevents replay', () async {
    final gate = Completer<Map<String, String>>();
    final forced = Completer<void>();
    var calls = 0;
    final api = ApiClient(
      client: MockClient((_) async {
        calls++;
        return http.Response('{"errorCode":"APP_CHECK_REQUIRED"}', 401);
      }),
      appCheckHeaderProvider: ({bool forceRefresh = false}) {
        if (forceRefresh) {
          forced.complete();
          return gate.future;
        }
        return Future.value({});
      },
    );
    final result = request(api, 'DELETE', jwt('a'));
    final rejected = expectLater(result, throwsA(isA<RequestSessionChanged>()));
    await forced.future;
    await SecureStorage.clearSession();
    gate.complete({'X-Firebase-AppCheck': 'fresh'});
    await rejected;
    expect(calls, 1);
  });
  test(
    'normal JWT rotation retries the same user, but never another user',
    () async {
      var calls = 0;
      ApiClient.onRefreshToken = () async {
        await SecureStorage.write('access_token', jwt('a', 2));
        return jwt('a', 2);
      };
      final api = ApiClient(
        client: MockClient((req) async {
          calls++;
          if (calls == 1) return http.Response('{}', 401);
          expect(req.headers['authorization'], 'Bearer ${jwt('a', 2)}');
          return http.Response('{"ok":true}', 200);
        }),
        appCheckHeaderProvider: ({bool forceRefresh = false}) async => {},
      );
      expect(await request(api, 'PATCH', jwt('a')), {'ok': true});
      expect(calls, 2);
    },
  );
  test('new session does not join an old in-flight token refresh', () async {
    final old = Completer<String?>();
    var calls = 0;
    ApiClient.onRefreshToken = () {
      calls++;
      return calls == 1 ? old.future : Future.value(jwt('b'));
    };
    final first = ApiClient.refreshSessionToken();
    await SecureStorage.clearSession();
    await SecureStorage.saveTokens(accessToken: jwt('b'), refreshToken: 'b');
    expect(await ApiClient.refreshSessionToken(), jwt('b'));
    old.complete(jwt('a', 2));
    expect(await first, isNull);
    expect(calls, 2);
  });
}
