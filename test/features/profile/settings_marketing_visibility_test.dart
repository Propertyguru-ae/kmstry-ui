import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/theme/theme_provider.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/profile/data/settings_device_permissions.dart';
import 'package:kmstry_frontend/features/profile/presentation/account_settings_page.dart';
import 'package:kmstry_frontend/features/profile/presentation/settings_page.dart';

class _Auth extends AuthRepository {
  _Auth(this.account);

  final Map<String, dynamic> account;
  final permissionWrites = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> getMe({bool forceRefresh = false}) async =>
      account;

  @override
  Future<void> updatePermissions(Map<String, dynamic> data) async {
    permissionWrites.add(data);
  }
}

Widget _screen(Widget page) => ChangeNotifierProvider(
  create: (_) => ThemeProvider(),
  child: MaterialApp(home: page),
);

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    AuthRepository.invalidateMeCache();
    PendingPublicMediaService.instance.clear();
  });

  tearDown(() {
    AuthRepository.invalidateMeCache();
    PendingPublicMediaService.instance.clear();
  });

  void showWholePage(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 2800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
  }

  for (final context in ['PERSONAL', 'VENUE']) {
    for (final optedIn in [false, true]) {
      testWidgets(
        '$context hides marketing settings without changing saved opt-in ($optedIn)',
        (tester) async {
          showWholePage(tester);
          final account = <String, dynamic>{
            'fullName': 'Alex',
            'hasPersonalProfile': true,
            'lastActiveContext': context,
            'activeVenueId': context == 'VENUE' ? 'cafe' : null,
            'marketingEmailOptIn': optedIn,
            'marketing_email_opt_in': optedIn,
            'memberVenues': [
              {
                'id': 'cafe',
                'name': 'Cafe Alpha',
                'role': 'OWNER',
                'status': 'ACTIVE',
              },
            ],
          };
          final auth = _Auth(account);
          await tester.pumpWidget(
            _screen(
              SettingsPage(
                authRepository: auth,
                permissionsReader: () async => const SettingsDevicePermissions(
                  camera: true,
                  location: true,
                  notifications: true,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.text(
              context == 'VENUE' ? 'Manage this venue' : 'Manage this profile',
            ),
            findsOneWidget,
          );
          expect(find.text('System notifications'), findsOneWidget);
          expect(find.text('Download your data'), findsOneWidget);
          expect(find.text('Privacy Policy'), findsOneWidget);
          expect(find.text('Marketing emails'), findsNothing);
          expect(find.byIcon(Icons.mark_email_read_outlined), findsNothing);
          expect(auth.permissionWrites, isEmpty);
          expect(account['marketingEmailOptIn'], optedIn);
          expect(account['marketing_email_opt_in'], optedIn);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'legacy account settings hide marketing while loading and after',
    (tester) async {
      showWholePage(tester);
      await tester.pumpWidget(_screen(const AccountSettingsPage()));
      expect(find.text('Marketing emails'), findsNothing);
      expect(find.text('Loading your preference...'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('Marketing emails'), findsNothing);
      expect(find.byIcon(Icons.campaign_outlined), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
