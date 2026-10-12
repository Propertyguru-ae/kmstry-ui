import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/network/authenticated_multipart_upload.dart';
import 'package:kmstry_frontend/core/network/multipart_upload.dart';
import 'package:kmstry_frontend/core/network/upload_session_identity.dart';

String _token(String owner, [int version = 1]) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': owner, 'version': version})))}.signature';

class _Harness {
  String? token = _token('owner');
  bool active = true;
  int refreshes = 0;
  int forcedAppChecks = 0;
  final requests = <http.MultipartRequest>[];
  final bodies = <String>[];
  final cancellation = MultipartUploadCancellation();
  Future<String?> Function()? refresh;
  Future<Map<String, String>> Function()? forceAppCheck;
  Future<http.StreamedResponse> Function(int)? respond;
  Future<void> Function(int)? building;

  late final upload = AuthenticatedMultipartUpload(
    readToken: () async => token,
    refreshToken: () async {
      refreshes++;
      if (refresh != null) return refresh!();
      return token = _token('owner', 2);
    },
    headers: ({String? accessToken}) async => {
      'Authorization': 'Bearer $accessToken',
      'x-kmstry-build-env': 'staging',
      'x-kmstry-app-version': '1.0.1',
      'X-Firebase-AppCheck': 'current-app-check',
    },
    appCheckHeaders: ({bool forceRefresh = false}) async {
      expect(forceRefresh, true);
      forcedAppChecks++;
      return forceAppCheck != null
          ? forceAppCheck!()
          : {'X-Firebase-AppCheck': 'fresh-app-check'};
    },
    sender: (request, {required timeout, cancellation}) async {
      expect(timeout, const Duration(minutes: 5));
      requests.add(request);
      bodies.add(await request.finalize().bytesToString());
      return respond != null
          ? respond!(requests.length)
          : _response(requests.length == 1 ? 401 : 201);
    },
  );

  Future<http.Response> send() => upload.send(
    initialToken: _token('owner'),
    isCurrentSession: () => active,
    cancellation: cancellation,
    timeout: const Duration(minutes: 5),
    createRequest: (headers) async {
      await building?.call(requests.length + 1);
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://example.test/checkins/checkin-1/stories'),
      );
      request.headers.addAll(headers);
      request.fields.addAll({
        'upload_id': 'upload-100-200',
        'media_type': 'video',
        'textOverlay': '{"text":"safe caption"}',
      });
      // Each attempt creates a fresh, single-use stream.
      request.files.add(http.MultipartFile.fromString('file', 'video-bytes'));
      return request;
    },
  );
}

http.StreamedResponse _response(
  int status, {
  String body = '{}',
  Map<String, String>? headers,
}) => http.StreamedResponse(
  Stream.value(utf8.encode(body)),
  status,
  headers: headers ?? const {},
);

void main() {
  test('JWT 401 refreshes once and rebuilds the same upload', () async {
    final h = _Harness();
    expect((await h.send()).statusCode, 201);
    expect(h.refreshes, 1);
    expect(h.forcedAppChecks, 0);
    expect(h.requests, hasLength(2));
    expect(identical(h.requests.first, h.requests.last), false);
    expect(
      h.requests.last.headers['Authorization'],
      'Bearer ${_token('owner', 2)}',
    );
    expect(h.requests.last.headers['x-kmstry-build-env'], 'staging');
    expect(h.requests.last.headers['x-kmstry-app-version'], '1.0.1');
    expect(h.requests.first.fields, h.requests.last.fields);
    for (final body in h.bodies) {
      expect(body, contains('video-bytes'));
      expect(body, contains('upload-100-200'));
      expect(body, contains('safe caption'));
    }
  });

  test('second JWT 401 stops, not an infinite refresh loop', () async {
    final h = _Harness()..respond = (_) async => _response(401);
    expect((await h.send()).statusCode, 401);
    expect(h.requests, hasLength(2));
    expect(h.refreshes, 1);
  });

  test(
    'failed refresh returns the original rejection without replay',
    () async {
      final h = _Harness()..refresh = () async => null;
      expect((await h.send()).statusCode, 401);
      expect(h.requests, hasLength(1));
      expect(h.refreshes, 1);
    },
  );

  test('concurrent refresh already saved a new token: reuse it', () async {
    final h = _Harness();
    h.respond = (attempt) async {
      if (attempt == 1) {
        h.token = _token('owner', 3);
        return _response(401);
      }
      return _response(201);
    };
    expect((await h.send()).statusCode, 201);
    expect(h.refreshes, 0);
    expect(
      h.requests.last.headers['Authorization'],
      'Bearer ${_token('owner', 3)}',
    );
  });

  test('already rotated token is used before the first upload', () async {
    final h = _Harness()
      ..token = _token('owner', 3)
      ..respond = (_) async => _response(201);
    await h.send();
    expect(
      h.requests.single.headers['Authorization'],
      'Bearer ${_token('owner', 3)}',
    );
    expect(h.refreshes, 0);
  });

  for (final headerOnly in [false, true]) {
    test(
      'App Check 401 refreshes only App Check: header=$headerOnly',
      () async {
        final h = _Harness()
          ..respond = (attempt) async => attempt == 1
              ? _response(
                  401,
                  body: headerOnly
                      ? '{}'
                      : '{"errorCode":"APP_CHECK_REQUIRED"}',
                  headers: headerOnly
                      ? {'x-kmstry-app-check-retry': 'refresh'}
                      : null,
                )
              : _response(201);
        expect((await h.send()).statusCode, 201);
        expect(h.requests, hasLength(2));
        expect(h.refreshes, 0);
        expect(h.forcedAppChecks, 1);
        expect(
          h.requests.last.headers['Authorization'],
          'Bearer ${_token('owner')}',
        );
        expect(
          h.requests.last.headers['X-Firebase-AppCheck'],
          'fresh-app-check',
        );
      },
    );
  }

  test('second App Check failure never refreshes JWT or logs out', () async {
    final h = _Harness()
      ..respond = (_) async =>
          _response(401, body: '{"errorCode":"APP_CHECK_REQUIRED"}');
    expect((await h.send()).statusCode, 401);
    expect(h.requests, hasLength(2));
    expect(h.refreshes, 0);
    expect(h.forcedAppChecks, 1);
    expect(h.active, true);
  });

  test(
    'unavailable App Check token does not retry without verification',
    () async {
      final h = _Harness();
      h.forceAppCheck = () async => {};
      h.respond = (_) async =>
          _response(401, body: '{"errorCode":"APP_CHECK_REQUIRED"}');
      expect((await h.send()).statusCode, 401);
      expect(h.requests, hasLength(1));
      expect(h.refreshes, 0);
    },
  );

  for (final status in [200, 201, 400, 403, 408, 413, 429, 500, 502]) {
    test('status $status never causes credential refresh or replay', () async {
      final h = _Harness()..respond = (_) async => _response(status);
      expect((await h.send()).statusCode, status);
      expect(h.requests, hasLength(1));
      expect(h.refreshes, 0);
      expect(h.forcedAppChecks, 0);
    });
  }

  for (final error in [
    const SocketException('Disconnected'),
    TimeoutException('Timed out'),
    http.ClientException('Connection closed'),
  ]) {
    test('${error.runtimeType} never replays an uncertain upload', () async {
      final h = _Harness()..respond = (_) async => throw error;
      await expectLater(h.send(), throwsA(same(error)));
      expect(h.requests, hasLength(1));
      expect(h.refreshes, 0);
    });
  }

  for (final value in [null, '', 'invalid', _token('another-owner')]) {
    test('invalid/different owner cannot send: $value', () async {
      final h = _Harness()..token = value;
      await expectLater(h.send(), throwsStateError);
      expect(h.requests, isEmpty);
      expect(h.refreshes, 0);
    });
  }

  test(
    'logout during request preparation prevents the first transfer',
    () async {
      final h = _Harness();
      h.building = (_) async => h.active = false;
      await expectLater(h.send(), throwsStateError);
      expect(h.requests, isEmpty);
    },
  );

  test(
    'logout while refreshing prevents replay even for the same owner',
    () async {
      final h = _Harness();
      h.refresh = () async {
        h.active = false;
        return h.token = _token('owner', 2);
      };
      await expectLater(h.send(), throwsStateError);
      expect(h.requests, hasLength(1));
    },
  );

  test(
    'account change during refresh never sends the other account token',
    () async {
      final h = _Harness();
      h.refresh = () async => h.token = _token('another-owner');
      await expectLater(h.send(), throwsStateError);
      expect(h.requests, hasLength(1));
    },
  );

  test(
    'refresh returning a different owner is refused even before persistence',
    () async {
      final h = _Harness()..refresh = () async => _token('another-owner');
      await expectLater(h.send(), throwsStateError);
      expect(h.requests, hasLength(1));
    },
  );

  test('cancellation during refresh prevents the second upload', () async {
    final h = _Harness();
    h.refresh = () async {
      h.cancellation.cancel();
      return h.token = _token('owner', 2);
    };
    await expectLater(h.send(), throwsA(isA<PublicMediaUploadCancelled>()));
    expect(h.requests, hasLength(1));
  });

  test(
    'default refresher shares the existing single-flight JWT refresh',
    () async {
      final original = ApiClient.onRefreshToken;
      addTearDown(() => ApiClient.onRefreshToken = original);
      var token = _token('owner');
      var refreshes = 0;
      final refreshStarted = Completer<void>();
      final finishRefresh = Completer<void>();
      ApiClient.onRefreshToken = () async {
        refreshes++;
        refreshStarted.complete();
        await finishRefresh.future;
        return token = _token('owner', 2);
      };
      final upload = AuthenticatedMultipartUpload(
        readToken: () async => token,
        headers: ({String? accessToken}) async => {
          'Authorization': 'Bearer $accessToken',
        },
        sender: (request, {required timeout, cancellation}) async => _response(
          request.headers['Authorization'] == 'Bearer ${_token('owner')}'
              ? 401
              : 201,
        ),
      );
      Future<http.Response> send() => upload.send(
        initialToken: _token('owner'),
        isCurrentSession: () => true,
        createRequest: (headers) async => http.MultipartRequest(
          'POST',
          Uri.parse('https://example.test/stories'),
        )..headers.addAll(headers),
      );
      final first = send();
      final second = send();
      await refreshStarted.future;
      await Future<void>.delayed(Duration.zero);
      finishRefresh.complete();
      expect((await Future.wait([first, second])).map((r) => r.statusCode), [
        201,
        201,
      ]);
      expect(refreshes, 1);
    },
  );

  test(
    'token parsing is partitioning, not acceptance of malformed identity',
    () {
      expect(uploadTokenOwner('broken'), isNull);
      expect(uploadTokenOwner('header.e30.signature'), isNull);
      expect(sameUploadOwner(_token('owner'), _token('owner', 2)), true);
      expect(sameUploadOwner(_token('owner'), _token('other')), false);
    },
  );

  test('real HTTP 401 rebuilds and resends the file only once', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = <String>[];
    final authorization = <String?>[];
    server.listen((request) async {
      received.add(await utf8.decoder.bind(request).join());
      authorization.add(request.headers.value('Authorization'));
      request.response.statusCode = received.length == 1 ? 401 : 201;
      request.response.write('{}');
      await request.response.close();
    });
    var token = _token('owner');
    final upload = AuthenticatedMultipartUpload(
      readToken: () async => token,
      refreshToken: () async => token = _token('owner', 2),
      headers: ({String? accessToken}) async => {
        'Authorization': 'Bearer $accessToken',
      },
    );
    final cancellation = MultipartUploadCancellation();
    final response = await upload.send(
      initialToken: _token('owner'),
      isCurrentSession: () => true,
      cancellation: cancellation,
      createRequest: (headers) async {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('http://127.0.0.1:${server.port}/stories'),
        );
        request.headers.addAll(headers);
        request.fields['upload_id'] = 'upload-100-200';
        request.files.add(
          http.MultipartFile.fromString('file', 'test-video-bytes'),
        );
        return request;
      },
    );
    expect(response.statusCode, 201);
    expect(received, hasLength(2));
    expect(
      received.every(
        (body) =>
            body.contains('test-video-bytes') &&
            body.contains('upload-100-200'),
      ),
      true,
    );
    expect(authorization, [
      'Bearer ${_token('owner')}',
      'Bearer ${_token('owner', 2)}',
    ]);
    expect(cancellation.isCancelled, false);
  });
}
