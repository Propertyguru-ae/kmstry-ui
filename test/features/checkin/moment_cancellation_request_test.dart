import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';

class _Api extends ApiClient {
  final calls = <String>[];
  final tokens = <String?>[];
  Future<dynamic> Function() remove = () async => {
    'success': true,
    'checkin_id': 'checkin',
    'checkin_inactivated': false,
  };
  Future<dynamic> Function() status = () async => {
    'checkin_id': 'checkin',
    'can_join': true,
  };

  @override
  Future<dynamic> delete(String path, {Map<String, String>? headers}) {
    calls.add('DELETE $path');
    tokens.add(headers?['Authorization']);
    return remove();
  }

  @override
  Future<dynamic> get(
    String path, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 10),
  }) {
    calls.add('GET $path');
    tokens.add(headers?['Authorization']);
    return status();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'access_token': 'owner-token',
    }),
  );
  Future<bool> cancel(_Api api, {bool Function()? current}) =>
      CheckinRepository(apiClient: api).cancelMomentUpload(
        mediaId: 'second',
        checkinId: 'checkin',
        isCurrentSession: current ?? () => true,
      );
  ApiException missingMedia() =>
      ApiException(statusCode: 404, data: {'message': 'Media not found'});

  for (final inactive in [false, true]) {
    test(
      'deletes only the selected media; inactive=$inactive comes from server',
      () async {
        final api = _Api()
          ..remove = () async => {
            'success': true,
            'checkin_id': 'checkin',
            'checkin_inactivated': inactive,
          };
        expect(await cancel(api), inactive);
        expect(api.calls, ['DELETE /checkins/photos/second']);
        expect(api.tokens, ['Bearer owner-token']);
      },
    );
    test(
      'retry after lost DELETE response confirms check-in state; inactive=$inactive',
      () async {
        final api = _Api()
          ..remove = (() async => throw missingMedia())
          ..status = () async => {
            'checkin_id': 'checkin',
            'can_join': !inactive,
          };
        expect(await cancel(api), inactive);
        expect(api.calls, [
          'DELETE /checkins/photos/second',
          'GET /checkins/checkin/activation-status',
        ]);
        expect(api.tokens, everyElement('Bearer owner-token'));
      },
    );
  }
  test(
    'a missing endpoint is not mistaken for successful cancellation',
    () async {
      final api = _Api()
        ..remove = () async => throw ApiException(
          statusCode: 404,
          data: {'message': 'Cannot DELETE /checkins/photos/second'},
        );
      await expectLater(cancel(api), throwsA(isA<ApiException>()));
      expect(api.calls, hasLength(1));
    },
  );
  test(
    'missing entire check-in after confirmed missing media is inactive',
    () async {
      final api = _Api()
        ..remove = (() async => throw missingMedia())
        ..status = () async => throw ApiException(
          statusCode: 404,
          data: {'message': 'Check-in not found'},
        );
      expect(await cancel(api), true);
    },
  );
  for (final response in [
    null,
    {'success': false},
    {'success': true, 'checkin_id': 'other', 'checkin_inactivated': false},
    {'success': true, 'checkin_id': 'checkin'},
  ]) {
    test(
      'does not accept malformed/mismatched DELETE result: $response',
      () async {
        final api = _Api()..remove = () async => response;
        await expectLater(cancel(api), throwsStateError);
      },
    );
  }
  test('old session cannot send cancellation', () async {
    final api = _Api();
    await expectLater(cancel(api, current: () => false), throwsStateError);
    expect(api.calls, isEmpty);
  });
  test(
    'session changed during secure token read cannot send cancellation',
    () async {
      var checks = 0;
      final api = _Api();
      await expectLater(
        cancel(api, current: () => ++checks == 1),
        throwsStateError,
      );
      expect(api.calls, isEmpty);
    },
  );
  test(
    'session changed during DELETE cannot reconcile under new account',
    () async {
      var current = true;
      final response = Completer<dynamic>();
      final api = _Api()..remove = () => response.future;
      final result = cancel(api, current: () => current);
      final assertion = expectLater(result, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      current = false;
      response.completeError(missingMedia());
      await assertion;
      expect(api.calls, ['DELETE /checkins/photos/second']);
    },
  );
  for (final code in [401, 403, 500]) {
    test(
      'HTTP $code preserves failure instead of treating it as cancellation',
      () async {
        final api = _Api()
          ..remove = () async => throw ApiException(
            statusCode: code,
            data: {'message': 'Request failed'},
          );
        await expectLater(cancel(api), throwsA(isA<ApiException>()));
        expect(api.calls, hasLength(1));
      },
    );
  }
}
