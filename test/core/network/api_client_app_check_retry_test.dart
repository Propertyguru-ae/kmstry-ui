import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';

void main() {
  final originalRefresh = ApiClient.onRefreshToken;
  final originalExpired = ApiClient.onSessionExpired;

  tearDown(() {
    ApiClient.onRefreshToken = originalRefresh;
    ApiClient.onSessionExpired = originalExpired;
  });

  test(
    'App Check 401 refreshes App Check once without expiring the session',
    () async {
      final requests = <http.Request>[];
      var forced = 0;
      var sessionExpired = 0;
      var jwtRefresh = 0;
      ApiClient.onSessionExpired = () async => sessionExpired++;
      ApiClient.onRefreshToken = () async {
        jwtRefresh++;
        return 'new-jwt';
      };
      final api = ApiClient(
        client: MockClient((request) async {
          requests.add(request);
          if (requests.length == 1) {
            return http.Response(
              jsonEncode({'errorCode': 'APP_CHECK_REQUIRED'}),
              401,
            );
          }
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
        appCheckHeaderProvider: ({bool forceRefresh = false}) async {
          if (forceRefresh) forced++;
          return {
            'X-Firebase-AppCheck': forceRefresh
                ? 'fresh-app-check'
                : 'stale-app-check',
          };
        },
      );

      expect(
        await api.post(
          '/users/me/device-token',
          body: {'token': 'test'},
          headers: {'Authorization': 'Bearer current-jwt'},
        ),
        {'ok': true},
      );
      expect(requests, hasLength(2));
      expect(requests.last.headers['X-Firebase-AppCheck'], 'fresh-app-check');
      expect(requests.last.headers['Authorization'], 'Bearer current-jwt');
      expect(forced, 1);
      expect(jwtRefresh, 0);
      expect(sessionExpired, 0);
    },
  );

  test(
    'a second App Check 401 stops after one retry and does not log out',
    () async {
      var requests = 0;
      var forced = 0;
      var sessionExpired = 0;
      ApiClient.onSessionExpired = () async => sessionExpired++;
      final api = ApiClient(
        client: MockClient((request) async {
          requests++;
          return http.Response(
            jsonEncode({'errorCode': 'APP_CHECK_REQUIRED'}),
            401,
          );
        }),
        appCheckHeaderProvider: ({bool forceRefresh = false}) async {
          if (forceRefresh) forced++;
          return {'X-Firebase-AppCheck': forceRefresh ? 'fresh' : 'stale'};
        },
      );

      await expectLater(
        api.get(
          '/users/me/device-token',
          headers: {'Authorization': 'Bearer jwt'},
        ),
        throwsA(isA<ApiException>()),
      );
      expect(requests, 2);
      expect(forced, 1);
      expect(sessionExpired, 0);
    },
  );

  test(
    'header-only App Check 401 retries even on an unauthenticated request',
    () async {
      final requests = <http.Request>[];
      var forced = 0;
      var jwtRefresh = 0;
      ApiClient.onRefreshToken = () async {
        jwtRefresh++;
        return 'new-jwt';
      };
      final api = ApiClient(
        client: MockClient((request) async {
          requests.add(request);
          if (requests.length == 1) {
            return http.Response(
              '{}',
              401,
              headers: {'x-kmstry-app-check-retry': 'refresh'},
            );
          }
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
        appCheckHeaderProvider: ({bool forceRefresh = false}) async {
          if (forceRefresh) forced++;
          return {'X-Firebase-AppCheck': forceRefresh ? 'fresh' : 'stale'};
        },
      );

      expect(await api.post('/auth/login', body: {'email': 'test'}), {
        'ok': true,
      });
      expect(requests, hasLength(2));
      expect(requests.last.headers['X-Firebase-AppCheck'], 'fresh');
      expect(forced, 1);
      expect(jwtRefresh, 0);
    },
  );

  test(
    'JWT refresh retry preserves App Check and can handle a later App Check 401',
    () async {
      final requests = <http.Request>[];
      var forced = 0;
      var jwtRefresh = 0;
      var sessionExpired = 0;
      ApiClient.onRefreshToken = () async {
        jwtRefresh++;
        return 'new-jwt';
      };
      ApiClient.onSessionExpired = () async => sessionExpired++;
      final api = ApiClient(
        client: MockClient((request) async {
          requests.add(request);
          if (requests.length == 1) return http.Response('{}', 401);
          if (requests.length == 2) {
            return http.Response(
              jsonEncode({'errorCode': 'APP_CHECK_REQUIRED'}),
              401,
            );
          }
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
        appCheckHeaderProvider: ({bool forceRefresh = false}) async {
          if (forceRefresh) forced++;
          return {'X-Firebase-AppCheck': forceRefresh ? 'fresh' : 'stale'};
        },
      );

      expect(
        await api.get('/auth/me', headers: {'Authorization': 'Bearer old-jwt'}),
        {'ok': true},
      );
      expect(requests, hasLength(3));
      expect(requests[1].headers['Authorization'], 'Bearer new-jwt');
      expect(requests[1].headers['X-Firebase-AppCheck'], 'stale');
      expect(requests[2].headers['X-Firebase-AppCheck'], 'fresh');
      expect(jwtRefresh, 1);
      expect(forced, 1);
      expect(sessionExpired, 0);
    },
  );
}
