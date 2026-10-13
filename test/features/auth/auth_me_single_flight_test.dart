import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/auth/data/auth_api.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';

String token(String owner, [int version = 1]) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': owner, 'version': version})))}.signature';

class _Api extends AuthApi {
  _Api(this.read);
  final Future<Map<String, dynamic>> Function(String) read;
  final calls = <String>[];
  Future<Map<String, dynamic>> Function(String)? refreshRead;
  Future<Map<String, dynamic>> Function()? switchRead;
  @override
  Future<Map<String, dynamic>> switchContext({
    required String accessToken,
    required String lastActiveContext,
    String? activeVenueId,
  }) => switchRead!();
  @override
  Future<Map<String, dynamic>> refresh({required String refreshToken}) =>
      refreshRead!(refreshToken);
  @override
  Future<Map<String, dynamic>> me({required String accessToken}) {
    calls.add(accessToken);
    return read(accessToken);
  }
}

Map<String, dynamic> account(String owner, [String name = 'Alex']) => {
  'id': owner,
  'fullName': name,
  'context': {
    'activeVenueId': 'venue-$owner',
    'memberVenues': [
      {
        'venue': {'id': 'venue-$owner', 'name': 'Cafe'},
        'status': 'ACTIVE',
      },
    ],
  },
  'legalConsent': {'required': false},
};

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'access_token': token('owner-a'),
    });
    SharedPreferences.setMockInitialValues({});
    PendingPublicMediaService.instance.clear();
    AuthRepository.invalidateMeCache();
  });
  tearDown(() {
    PendingPublicMediaService.instance.clear();
    AuthRepository.invalidateMeCache();
  });

  test(
    'different repositories share one concurrent account request, including force refresh',
    () async {
      final result = Completer<Map<String, dynamic>>();
      final api = _Api((_) => result.future);
      final repos = List.generate(4, (_) => AuthRepository(api: api));
      final responses = repos.map((r) => r.getMe(forceRefresh: true)).toList();
      await flush();
      expect(api.calls, hasLength(1));
      result.complete(account('owner-a'));
      for (final response in await Future.wait(responses)) {
        expect(response['id'], 'owner-a');
        expect(response['activeVenueId'], 'venue-owner-a');
        expect(response['legalConsent'], {'required': false});
      }
      await repos.first.getMe();
      expect(api.calls, hasLength(1));
    },
  );

  test(
    'each consumer and the short-lived cache own separate nested maps and lists',
    () async {
      final result = Completer<Map<String, dynamic>>();
      final api = _Api((_) => result.future);
      final repo = AuthRepository(api: api);
      final one = repo.getMe();
      final two = repo.getMe();
      await flush();
      result.complete(account('owner-a'));
      final a = await one;
      final b = await two;
      ((a['context'] as Map)['memberVenues'] as List).clear();
      (a['legalConsent'] as Map)['required'] = true;
      expect((b['context'] as Map)['memberVenues'], hasLength(1));
      expect(b['legalConsent'], {'required': false});
      final cached = await repo.getMe();
      expect((cached['context'] as Map)['memberVenues'], hasLength(1));
      expect(cached['legalConsent'], {'required': false});
    },
  );

  test(
    'mutation invalidation drops the old snapshot and joins the new read without failing consumers',
    () async {
      final old = Completer<Map<String, dynamic>>();
      final fresh = Completer<Map<String, dynamic>>();
      var count = 0;
      final api = _Api((_) => ++count == 1 ? old.future : fresh.future);
      final repo = AuthRepository(api: api);
      final previous = repo.getMe();
      await flush();
      AuthRepository.invalidateMeCache();
      final current = repo.getMe(forceRefresh: true);
      await flush();
      expect(api.calls, hasLength(2));
      old.complete(account('owner-a', 'Old'));
      await flush();
      // Finishing the old request cannot clear the newer in-flight request.
      final joined = repo.getMe(forceRefresh: true);
      await flush();
      expect(api.calls, hasLength(2));
      fresh.complete(account('owner-a', 'Updated'));
      expect((await current)['fullName'], 'Updated');
      expect((await joined)['fullName'], 'Updated');
      expect((await previous)['fullName'], 'Updated');
      expect((await repo.getMe())['fullName'], 'Updated');
      expect(api.calls, hasLength(2));
    },
  );

  test('many invalidated consumers share one automatic retry', () async {
    final old = Completer<Map<String, dynamic>>();
    var count = 0;
    final api = _Api(
      (_) =>
          ++count == 1 ? old.future : Future.value(account('owner-a', 'Fresh')),
    );
    final readers = List.generate(8, (_) => AuthRepository(api: api).getMe());
    await flush();
    AuthRepository.invalidateMeCache();
    old.complete(account('owner-a', 'Old'));
    final results = await Future.wait(readers);
    expect(results.map((me) => me['fullName']), everyElement('Fresh'));
    expect(api.calls, hasLength(2));
  });

  test(
    'a superseded reader can reuse the completed new-generation cache',
    () async {
      final old = Completer<Map<String, dynamic>>();
      var count = 0;
      final api = _Api(
        (_) => ++count == 1
            ? old.future
            : Future.value(account('owner-a', 'Fresh')),
      );
      final repo = AuthRepository(api: api);
      final previous = repo.getMe(forceRefresh: true);
      await flush();
      AuthRepository.invalidateMeCache();
      expect((await repo.getMe(forceRefresh: true))['fullName'], 'Fresh');
      old.complete(account('owner-a', 'Old'));
      expect((await previous)['fullName'], 'Fresh');
      expect(api.calls, hasLength(2));
    },
  );

  test('continual cache changes stop after one automatic retry', () async {
    final api = _Api((_) async {
      AuthRepository.invalidateMeCache();
      return account('owner-a');
    });
    await expectLater(AuthRepository(api: api).getMe(), throwsStateError);
    expect(api.calls, hasLength(2));
  });

  for (final reset in ['session', 'owner', 'same-owner-login']) {
    test('cache invalidation never retries across $reset changes', () async {
      final old = Completer<Map<String, dynamic>>();
      final api = _Api((_) => old.future);
      final pending = AuthRepository(api: api).getMe();
      final failure = expectLater(
        pending,
        throwsA(isA<AccountSessionChangedError>()),
      );
      await flush();
      AuthRepository.invalidateMeCache();
      if (reset == 'session') {
        PendingPublicMediaService.instance.clear();
      } else if (reset == 'owner') {
        await SecureStorage.write('access_token', token('owner-b'));
      } else {
        await SecureStorage.saveTokens(
          accessToken: token('owner-a', 2),
          refreshToken: 'new-login',
        );
      }
      old.complete(account('owner-a'));
      await failure;
      expect(api.calls, hasLength(1));
    });
  }

  for (final startedBeforeSwitch in [true, false]) {
    test(
      'context switching does not retry a read started ${startedBeforeSwitch ? 'before' : 'during'} the switch',
      () async {
        final old = Completer<Map<String, dynamic>>();
        final switched = Completer<Map<String, dynamic>>();
        final switchStarted = Completer<void>();
        final api = _Api((_) => old.future)
          ..switchRead = () {
            switchStarted.complete();
            return switched.future;
          };
        final repo = AuthRepository(api: api);
        Future<Map<String, dynamic>>? pending;
        Future<void>? failure;
        void startRead() {
          pending = repo.getMe();
          failure = expectLater(
            pending!,
            throwsA(isA<AccountSessionChangedError>()),
          );
        }

        if (startedBeforeSwitch) {
          startRead();
          await flush();
        }
        final switching = repo.switchContext(
          lastActiveContext: 'VENUE',
          activeVenueId: 'other-venue',
        );
        await switchStarted.future;
        if (!startedBeforeSwitch) {
          startRead();
          await flush();
        }
        switched.complete({'success': true});
        await switching;
        old.complete(account('owner-a'));
        await failure;
        expect(api.calls, hasLength(1));
      },
    );
  }

  test(
    'silent refresh plus cache invalidation retries with the same owner new token',
    () async {
      var count = 0;
      final api = _Api((_) async {
        if (++count == 1) {
          await SecureStorage.write('access_token', token('owner-a', 2));
          AuthRepository.invalidateMeCache();
        }
        return account('owner-a');
      });
      expect((await AuthRepository(api: api).getMe())['id'], 'owner-a');
      expect(api.calls, [token('owner-a'), token('owner-a', 2)]);
    },
  );

  for (final error in [
    ApiException(statusCode: 403, data: {'message': 'Forbidden'}),
    TimeoutException('offline'),
  ]) {
    test(
      'cache invalidation does not retry ${error.runtimeType} failures',
      () async {
        final api = _Api((_) async {
          AuthRepository.invalidateMeCache();
          throw error;
        });
        await expectLater(
          AuthRepository(api: api).getMe(),
          throwsA(same(error)),
        );
        expect(api.calls, hasLength(1));
      },
    );
  }

  test(
    'another stored owner cannot join or receive the previous owner response or cache',
    () async {
      final old = Completer<Map<String, dynamic>>();
      final api = _Api(
        (credential) => credential == token('owner-a')
            ? old.future
            : Future.value(account('owner-b', 'Bea')),
      );
      final repo = AuthRepository(api: api);
      final previous = repo.getMe();
      final previousFails = expectLater(previous, throwsStateError);
      await flush();
      await SecureStorage.write('access_token', token('owner-b'));
      final current = await repo.getMe();
      old.complete(account('owner-a'));
      await previousFails;
      expect(current['id'], 'owner-b');
      expect((await repo.getMe())['id'], 'owner-b');
      expect(api.calls, hasLength(2));
    },
  );

  test(
    'a logout/session reset while reading never returns the old account',
    () async {
      final result = Completer<Map<String, dynamic>>();
      final api = _Api((_) => result.future);
      final response = AuthRepository(api: api).getMe();
      final failure = expectLater(response, throwsStateError);
      await flush();
      PendingPublicMediaService.instance.clear();
      result.complete(account('owner-a'));
      await failure;
    },
  );

  test(
    'normal silent token refresh for the same owner remains valid and caches the new credential scope',
    () async {
      final api = _Api((_) async {
        await SecureStorage.write('access_token', token('owner-a', 2));
        return account('owner-a');
      });
      final repo = AuthRepository(api: api);
      expect((await repo.getMe())['id'], 'owner-a');
      expect((await repo.getMe())['id'], 'owner-a');
      expect(api.calls, hasLength(1));
    },
  );

  test(
    'a failed shared request propagates the real error and allows a fresh retry',
    () async {
      final result = Completer<Map<String, dynamic>>();
      var count = 0;
      final api = _Api(
        (_) => ++count == 1 ? result.future : Future.value(account('owner-a')),
      );
      final repo = AuthRepository(api: api);
      final first = repo.getMe();
      final second = repo.getMe(forceRefresh: true);
      final failures = Future.wait([
        expectLater(first, throwsA(isA<ApiException>())),
        expectLater(second, throwsA(isA<ApiException>())),
      ]);
      await flush();
      result.completeError(
        ApiException(statusCode: 403, data: {'message': 'Forbidden'}),
      );
      await failures;
      expect((await repo.getMe())['id'], 'owner-a');
      expect(api.calls, hasLength(2));
    },
  );

  test('force refresh does not reuse a completed cached response', () async {
    var count = 0;
    final api = _Api((_) async => account('owner-a', 'Version ${++count}'));
    final repo = AuthRepository(api: api);
    expect((await repo.getMe())['fullName'], 'Version 1');
    expect((await repo.getMe(forceRefresh: true))['fullName'], 'Version 2');
    expect((await repo.getMe())['fullName'], 'Version 2');
    expect(api.calls, hasLength(2));
  });

  test(
    'startup validates once and routing reuses that exact fresh consent/context response',
    () async {
      final api = _Api(
        (_) async => account('owner-a')..['legalConsent'] = {'required': true},
      );
      final repo = AuthRepository(api: api);
      expect(await repo.restoreSession(), isTrue);
      final me = await AuthRepository(api: api).getMe();
      expect(me['legalConsent'], {'required': true});
      expect(me['activeVenueId'], 'venue-owner-a');
      expect(api.calls, hasLength(1));
    },
  );

  test(
    'startup revalidates even if the short-lived account cache is already populated',
    () async {
      var count = 0;
      final api = _Api((_) async => account('owner-a', 'Version ${++count}'));
      final repo = AuthRepository(api: api);
      await repo.getMe();
      expect(await repo.restoreSession(), isTrue);
      expect((await repo.getMe())['fullName'], 'Version 2');
      expect(api.calls, hasLength(2));
    },
  );

  test(
    'startup JWT expiry refreshes then validates the new token and shares only that result',
    () async {
      await SecureStorage.write('refresh_token', 'old-refresh');
      final api =
          _Api((credential) async {
              if (credential == token('owner-a')) {
                throw ApiException(
                  statusCode: 401,
                  data: {'message': 'Expired'},
                );
              }
              return account('owner-a');
            })
            ..refreshRead = (refresh) async {
              expect(refresh, 'old-refresh');
              return {
                'success': true,
                'accessToken': token('owner-a', 2),
                'refreshToken': 'rotated-refresh',
              };
            };
      final repo = AuthRepository(api: api);
      expect(await repo.restoreSession(), isTrue);
      expect((await repo.getMe())['id'], 'owner-a');
      expect(api.calls, [token('owner-a'), token('owner-a', 2)]);
      expect(await SecureStorage.getRefreshToken(), 'rotated-refresh');
    },
  );

  test(
    'a new login after logout cannot reuse the former completed cache',
    () async {
      final api = _Api(
        (credential) async =>
            account(credential == token('owner-a') ? 'owner-a' : 'owner-b'),
      );
      final repo = AuthRepository(api: api);
      expect((await repo.getMe())['id'], 'owner-a');
      PendingPublicMediaService.instance.clear();
      await SecureStorage.write('access_token', token('owner-b'));
      expect((await repo.getMe())['id'], 'owner-b');
      expect((await repo.getMe())['id'], 'owner-b');
      expect(api.calls, hasLength(2));
    },
  );

  test(
    'signing in while the previous account still owns the upload session lands on the new account',
    () async {
      final api = _Api(
        (credential) async =>
            account(credential == token('owner-a') ? 'owner-a' : 'owner-b'),
      );
      final repo = AuthRepository(api: api);
      // owner-a's upload session got bound again (e.g. read during logout).
      expect((await repo.getMe())['id'], 'owner-a');
      // The next login stores owner-b's token; startup must not fail because
      // the first read swaps the upload session over to owner-b.
      await SecureStorage.write('access_token', token('owner-b'));
      expect(await repo.restoreSession(), isTrue);
      expect((await repo.getMe())['id'], 'owner-b');
    },
  );

  for (final status in [401, 403]) {
    test(
      'a fresh $status cannot leave a previous successful response in cache',
      () async {
        var count = 0;
        final api = _Api((_) async {
          if (++count == 1) return account('owner-a');
          throw ApiException(statusCode: status, data: {'message': 'Denied'});
        });
        final repo = AuthRepository(api: api);
        expect((await repo.getMe())['id'], 'owner-a');
        await expectLater(
          repo.getMe(forceRefresh: true),
          throwsA(isA<ApiException>()),
        );
        await expectLater(repo.getMe(), throwsA(isA<ApiException>()));
        expect(api.calls, hasLength(3));
      },
    );
  }
}
