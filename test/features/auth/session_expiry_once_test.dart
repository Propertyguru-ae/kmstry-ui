import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';

class _Pushes extends NavigatorObserver {
  final names = <String?>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      names.add(route.settings.name);
}

Future<_Pushes> _pumpApp(WidgetTester tester) async {
  final key = GlobalKey<NavigatorState>();
  final pushes = _Pushes();
  AuthRepository.init(navigatorKey: key);
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: key,
      navigatorObservers: [pushes],
      home: const Text('login'),
      routes: {AuthRoutes.startupGate: (_) => const Text('startup')},
    ),
  );
  pushes.names.clear();
  return pushes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Ending a session resets push registration, which needs a Firebase app.
  setupFirebaseCoreMocks();
  setUpAll(() async => Firebase.initializeApp());
  final originalRefresh = ApiClient.onRefreshToken;
  final originalExpired = ApiClient.onSessionExpired;
  tearDown(() {
    ApiClient.onRefreshToken = originalRefresh;
    ApiClient.onSessionExpired = originalExpired;
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'requests that fail after logout do not restart the login flow',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final pushes = await _pumpApp(tester);
      final session = PendingPublicMediaService.instance.sessionGeneration;

      for (var i = 0; i < 3; i++) {
        await tester.runAsync(() => ApiClient.onSessionExpired!());
        await tester.pumpAndSettle();
      }

      expect(pushes.names, isEmpty);
      expect(find.text('login'), findsOneWidget);
      // Nothing was cleared again, so open screens are not woken up.
      expect(PendingPublicMediaService.instance.sessionGeneration, session);
    },
  );

  testWidgets(
    'a real expiry ends the session once even when several requests fail together',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        'access_token': 'expired-access',
        'refresh_token': 'revoked-refresh',
      });
      final pushes = await _pumpApp(tester);

      await tester.runAsync(
        () => Future.wait([
          ApiClient.onSessionExpired!(),
          ApiClient.onSessionExpired!(),
          ApiClient.onSessionExpired!(),
        ]),
      );
      await tester.pumpAndSettle();

      expect(pushes.names, [AuthRoutes.startupGate]);
      expect(find.text('startup'), findsOneWidget);
      expect(await tester.runAsync(SecureStorage.getAccessToken), isNull);

      // A late 401 from the old session changes nothing.
      await tester.runAsync(() => ApiClient.onSessionExpired!());
      await tester.pumpAndSettle();
      expect(pushes.names, [AuthRoutes.startupGate]);
    },
  );
}
