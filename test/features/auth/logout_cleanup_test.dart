import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
// Firebase's bundled platform test helper; already present transitively.
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/user/user_session.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/auth/data/auth_api.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/checkin/services/active_checkin_service.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';

class FakeAuthApi extends AuthApi {
  final refreshed = Completer<Map<String, dynamic>>();
  final refreshStarted = Completer<void>();
  int logoutCalls = 0;
  @override
  Future<Map<String, dynamic>> logout({required String refreshToken}) async {
    logoutCalls++;
    throw StateError('offline');
  }

  @override
  Future<Map<String, dynamic>> refresh({required String refreshToken}) {
    refreshStarted.complete();
    return refreshed.future;
  }
}

class LoginApi extends FakeAuthApi {
  final loginResponse = Completer<Map<String, dynamic>>();
  final loginStarted = Completer<void>();
  Completer<Map<String, dynamic>>? remoteLogout;
  final logoutStarted = Completer<void>();
  int loginCalls = 0;
  final contextResponse = Completer<Map<String, dynamic>>();
  final contextStarted = Completer<void>();
  @override
  Future<Map<String, dynamic>> switchContext({
    required String accessToken,
    required String lastActiveContext,
    String? activeVenueId,
  }) {
    contextStarted.complete();
    return contextResponse.future;
  }

  @override
  Future<Map<String, dynamic>> login({
    required String identifier,
    required String password,
  }) {
    loginCalls++;
    loginStarted.complete();
    return loginResponse.future;
  }

  @override
  Future<Map<String, dynamic>> logout({required String refreshToken}) {
    logoutCalls++;
    logoutStarted.complete();
    return remoteLogout?.future ?? Future.value({'success': true});
  }

  @override
  Future<Map<String, dynamic>> me({required String accessToken}) async => {
    'id': accessToken.contains('new-') ? 'new-owner' : 'old-owner',
    'lastActiveContext': accessToken.contains('new-') ? 'PERSONAL' : 'VENUE',
    'activeVenueId': accessToken.contains('new-') ? null : 'alpha',
  };
}

Map<String, dynamic> loginResult(String owner) => {
  'success': true,
  'accessToken': '$owner-access',
  'refreshToken': '$owner-refresh',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async => Firebase.initializeApp());
  setUp(() async {
    SharedPreferences.setMockInitialValues({'intro_seen': 'true'});
    FlutterSecureStorage.setMockInitialValues({});
    await SecureStorage.saveTokens(
      accessToken: 'old-access',
      refreshToken: 'old-refresh',
    );
    await SecureStorage.saveRegisteredDeviceToken('old-push');
    UserSession.instance.setPremium(true);
    ActiveCheckinService().setActiveCheckin(
      'old',
      userId: 'hilal',
      venueId: 'cafe',
    );
  });

  test(
    'offline backend and failing Google sign-out still clear all account state',
    () async {
      final api = FakeAuthApi();
      final repo = AuthRepository(
        api: api,
        signOutProvider: () async => throw StateError('Google unavailable'),
      );
      final session = PendingPublicMediaService.instance.sessionGeneration;
      await Future.wait([repo.logout(), repo.logout()]);
      expect(api.logoutCalls, 1);
      expect(await SecureStorage.getAccessToken(), isNull);
      expect(await SecureStorage.getRefreshToken(), isNull);
      expect(await SecureStorage.getSessionEnvironment(), isNull);
      expect(await SecureStorage.getRegisteredDeviceToken(), isNull);
      expect(ActiveCheckinService().hasActiveCheckin, isFalse);
      expect(UserSession.instance.isPremium, isFalse);
      expect(UserSession.instance.loaded, isFalse);
      expect(VenueSession.instance.venueId, isNull);
      expect(
        PendingPublicMediaService.instance.sessionGeneration,
        greaterThan(session),
      );
      expect(
        await SecureStorage.isIntroSeen(),
        isTrue,
      ); // Device preference, not account data.
    },
  );

  test('late refresh cannot restore the signed-out account', () async {
    final api = FakeAuthApi();
    final repo = AuthRepository(api: api, signOutProvider: () async {});
    final refresh = repo.refreshAccessToken();
    await api.refreshStarted.future;
    await repo.logout();
    api.refreshed.complete({
      'success': true,
      'accessToken': 'late-access',
      'refreshToken': 'late-refresh',
    });
    expect(await refresh, isNull);
    expect(await SecureStorage.getAccessToken(), isNull);
    expect(await SecureStorage.getRefreshToken(), isNull);
  });

  test('late refresh cannot replace a subsequent login', () async {
    final api = FakeAuthApi();
    final repo = AuthRepository(api: api, signOutProvider: () async {});
    final refresh = repo.refreshAccessToken();
    await api.refreshStarted.future;
    await repo.logout();
    await SecureStorage.saveTokens(
      accessToken: 'new-user',
      refreshToken: 'new-user-refresh',
    );
    api.refreshed.complete({
      'success': true,
      'accessToken': 'late-access',
      'refreshToken': 'late-refresh',
    });
    expect(await refresh, isNull);
    expect(await SecureStorage.getAccessToken(), 'new-user');
  });

  test(
    'token deletion is serialized after a rotation already being written',
    () async {
      final revision = SecureStorage.sessionRevision;
      final rotate = SecureStorage.saveRefreshedTokens(
        expectedRevision: revision,
        previousRefreshToken: 'old-refresh',
        accessToken: 'rotated',
        refreshToken: 'rotated-refresh',
      );
      final clear = SecureStorage.clearSession();
      await Future.wait([rotate, clear]);
      expect(await SecureStorage.getAccessToken(), isNull);
      expect(await SecureStorage.getRefreshToken(), isNull);
    },
  );

  test(
    'remote logout and provider cleanup run together; local tokens disappear without waiting',
    () async {
      final api = LoginApi()..remoteLogout = Completer<Map<String, dynamic>>();
      final providerStarted = Completer<void>();
      final provider = Completer<void>();
      final repo = AuthRepository(
        api: api,
        signOutProvider: () {
          providerStarted.complete();
          return provider.future;
        },
      );
      var done = false;
      final exit = repo.logout().then((_) => done = true);
      await Future.wait([api.logoutStarted.future, providerStarted.future]);
      await Future<void>.delayed(Duration.zero);
      expect(await SecureStorage.getAccessToken(), isNull);
      expect(await SecureStorage.getRegisteredDeviceToken(), isNull);
      expect(done, isFalse);
      await expectLater(
        repo.login('new', 'test'),
        throwsA(isA<AccountSessionChangedError>()),
      );
      expect(api.loginCalls, 0);
      provider.complete();
      api.remoteLogout!.complete({'success': true});
      await exit;
      expect(api.logoutCalls, 1);
    },
  );

  test('late password login cannot resurrect a logged-out session', () async {
    final api = LoginApi();
    final repo = AuthRepository(api: api, signOutProvider: () async {});
    final login = repo.login('old', 'test');
    final rejected = expectLater(
      login,
      throwsA(isA<AccountSessionChangedError>()),
    );
    await api.loginStarted.future;
    await repo.logout();
    api.loginResponse.complete(loginResult('late'));
    await rejected;
    expect(await SecureStorage.getAccessToken(), isNull);
  });

  test(
    'late login cannot overwrite a different account that signed in first',
    () async {
      final oldApi = LoginApi();
      final old = AuthRepository(api: oldApi).login('old', 'test');
      final rejected = expectLater(
        old,
        throwsA(isA<AccountSessionChangedError>()),
      );
      await oldApi.loginStarted.future;
      final freshApi = LoginApi()..loginResponse.complete(loginResult('new'));
      expect(await AuthRepository(api: freshApi).login('new', 'test'), isTrue);
      oldApi.loginResponse.complete(loginResult('late'));
      await rejected;
      expect(await SecureStorage.getAccessToken(), 'new-access');
    },
  );

  test(
    'fresh login clears previous personal/venue state and reads its own context',
    () async {
      final api = LoginApi()..loginResponse.complete(loginResult('new'));
      final repo = AuthRepository(api: api);
      // Use valid JWT subject so the owner-scoped account cache is initialized.
      final oldJwt =
          'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'old-owner'})))}.sig';
      await SecureStorage.saveTokens(
        accessToken: oldJwt,
        refreshToken: 'old-refresh',
      );
      await repo.getMe();
      unawaited(VenueSession.instance.load('alpha', VenueMemberRole.owner));
      expect(VenueSession.instance.venueId, 'alpha');
      expect(await repo.login('new', 'test'), isTrue);
      expect(VenueSession.instance.venueId, isNull);
      expect(UserSession.instance.loaded, isFalse);
      expect(ActiveCheckinService().hasActiveCheckin, isFalse);
      final me = await repo.getMe();
      expect(me['id'], 'new-owner');
      expect(me['lastActiveContext'], 'PERSONAL');
      expect(me['activeVenueId'], isNull);
    },
  );

  test(
    'logout queued during a login token write wins over that login',
    () async {
      final revision = SecureStorage.sessionRevision;
      final save = SecureStorage.saveLoginTokens(
        expectedRevision: revision,
        accessToken: 'late',
        refreshToken: 'late',
      );
      final clear = SecureStorage.clearSession();
      expect(await save, isFalse);
      await clear;
      expect(await SecureStorage.getAccessToken(), isNull);
    },
  );

  test(
    'a late personal-to-venue switch cannot complete for a new login',
    () async {
      final api = LoginApi();
      final repo = AuthRepository(api: api, signOutProvider: () async {});
      final switching = repo.switchContext(
        lastActiveContext: 'VENUE',
        activeVenueId: 'alpha',
      );
      final rejected = expectLater(
        switching,
        throwsA(isA<AccountSessionChangedError>()),
      );
      await api.contextStarted.future;
      await repo.logout();
      api.loginResponse.complete(loginResult('new'));
      await repo.login('new', 'test');
      api.contextResponse.complete({
        'lastActiveContext': 'VENUE',
        'activeVenueId': 'alpha',
      });
      await rejected;
      expect((await repo.getMe())['lastActiveContext'], 'PERSONAL');
      expect(VenueSession.instance.venueId, isNull);
    },
  );

  test('startup refresh cannot log out a replacement account', () async {
    final api = _ExpiredStartupApi();
    final repo = AuthRepository(api: api, signOutProvider: () async {});
    final restoring = repo.restoreSession();
    final rejected = expectLater(
      restoring,
      throwsA(isA<AccountSessionChangedError>()),
    );
    await api.refreshStarted.future;
    await SecureStorage.saveTokens(
      accessToken: 'new-access',
      refreshToken: 'new-refresh',
    );
    api.refreshed.complete({'success': false});
    await rejected;
    expect(api.logoutCalls, 0);
    expect(await SecureStorage.getAccessToken(), 'new-access');
  });
}

class _ExpiredStartupApi extends FakeAuthApi {
  @override
  Future<Map<String, dynamic>> me({required String accessToken}) async {
    throw ApiException(statusCode: 401, data: {'message': 'Expired'});
  }
}
