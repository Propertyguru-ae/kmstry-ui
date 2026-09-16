import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('auth tokens are bound to the API and build environment', () async {
    await SecureStorage.saveTokens(
      accessToken: 'access-test',
      refreshToken: 'refresh-test',
    );
    final binding = await SecureStorage.getSessionEnvironment();
    expect(binding?.apiOrigin, AppConfig.baseUrl);
    expect(binding?.buildEnv, AppConfig.buildEnv);
    expect(await SecureStorage.getAccessToken(), 'access-test');
    expect(await SecureStorage.getRefreshToken(), 'refresh-test');
  });

  test('clearing a session also clears its environment and FCM token', () async {
    await SecureStorage.saveTokens(
      accessToken: 'access-test',
      refreshToken: 'refresh-test',
    );
    await SecureStorage.saveRegisteredDeviceToken('fcm-test');
    await SecureStorage.clearSession();
    expect(await SecureStorage.getAccessToken(), isNull);
    expect(await SecureStorage.getRefreshToken(), isNull);
    expect(await SecureStorage.getSessionEnvironment(), isNull);
    expect(await SecureStorage.getRegisteredDeviceToken(), isNull);
  });

  test('an existing legacy session can be bound without replacing tokens', () async {
    await SecureStorage.write('access_token', 'legacy-access');
    await SecureStorage.write('refresh_token', 'legacy-refresh');
    await SecureStorage.bindExistingSessionToCurrentEnvironment();
    expect(await SecureStorage.getSessionEnvironment(), isNotNull);
    expect(await SecureStorage.getAccessToken(), 'legacy-access');
    expect(await SecureStorage.getRefreshToken(), 'legacy-refresh');
  });
}
