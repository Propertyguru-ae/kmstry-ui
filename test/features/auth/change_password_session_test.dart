import 'package:firebase_core/firebase_core.dart';
// Firebase's bundled platform test helper; already present transitively.
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/auth/data/auth_api.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/chat/data/chat_realtime_service.dart';

class ChangePasswordApi extends AuthApi {
  ChangePasswordApi(this.response);
  final Map<String, dynamic> response;
  String? sentAccessToken;

  @override
  Future<Map<String, dynamic>> changePassword({
    required String accessToken,
    required String currentPassword,
    required String newPassword,
  }) async {
    sentAccessToken = accessToken;
    return response;
  }

  @override
  Future<Map<String, dynamic>> confirmChangeEmail({
    required String accessToken,
    required String newEmail,
    required String otp,
  }) async {
    sentAccessToken = accessToken;
    return response;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  setUpAll(() async => Firebase.initializeApp());
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await SecureStorage.saveTokens(
      accessToken: 'old-access',
      refreshToken: 'old-refresh',
    );
  });
  tearDown(() => ChatRealtimeService().disconnect());

  test(
    'keeps this device signed in with the pair the backend returns',
    () async {
      final api = ChangePasswordApi({
        'success': true,
        'accessToken': 'new-access',
        'refreshToken': 'new-refresh',
      });
      final revision = SecureStorage.sessionRevision;

      await AuthRepository(api: api).changePassword(
        currentPassword: 'CurrentPass1!',
        newPassword: 'NewPassword2!',
      );

      expect(api.sentAccessToken, 'old-access');
      expect(await SecureStorage.getAccessToken(), 'new-access');
      expect(await SecureStorage.getRefreshToken(), 'new-refresh');
      // Same session: in-flight requests are not treated as another account's.
      expect(SecureStorage.sessionRevision, revision);
    },
  );

  test(
    'an older backend without tokens leaves the stored session as is',
    () async {
      final api = ChangePasswordApi({'success': true});

      await AuthRepository(api: api).changePassword(
        currentPassword: 'CurrentPass1!',
        newPassword: 'NewPassword2!',
      );

      expect(await SecureStorage.getAccessToken(), 'old-access');
      expect(await SecureStorage.getRefreshToken(), 'old-refresh');
    },
  );

  test('a failed change stores nothing', () async {
    final api = ChangePasswordApi({
      'success': false,
      'message': 'Current password is incorrect.',
      'accessToken': 'should-not-store',
      'refreshToken': 'should-not-store',
    });

    await expectLater(
      AuthRepository(
        api: api,
      ).changePassword(currentPassword: 'wrong', newPassword: 'NewPassword2!'),
      throwsA(isA<Exception>()),
    );
    expect(await SecureStorage.getAccessToken(), 'old-access');
  });

  test('a confirmed email change also keeps this device signed in', () async {
    final api = ChangePasswordApi({
      'success': true,
      'accessToken': 'email-access',
      'refreshToken': 'email-refresh',
    });

    await AuthRepository(
      api: api,
    ).confirmChangeEmail(newEmail: 'new@example.com', otp: '123456');

    expect(api.sentAccessToken, 'old-access');
    expect(await SecureStorage.getAccessToken(), 'email-access');
    expect(await SecureStorage.getRefreshToken(), 'email-refresh');
  });
}
