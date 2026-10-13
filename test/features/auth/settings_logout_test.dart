import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/theme/theme_provider.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/auth/presentation/logout_flow.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/profile/data/settings_device_permissions.dart';
import 'package:kmstry_frontend/features/profile/presentation/settings_page.dart';

class _Auth extends AuthRepository {
  _Auth(this.venue, {this.fail = false});
  final bool venue;
  final bool fail;
  final done = Completer<void>();
  int reads = 0;
  int logouts = 0;
  @override
  Future<Map<String, dynamic>> getMe({bool forceRefresh = false}) async {
    reads++;
    return {
      'id': 'test-owner',
      'fullName': 'Tester',
      'hasPersonalProfile': true,
      'lastActiveContext': venue ? 'VENUE' : 'PERSONAL',
      'activeVenueId': venue ? 'alpha' : null,
      'memberVenues': [
        {
          'id': 'alpha',
          'name': 'Cafe Alpha',
          'role': 'OWNER',
          'status': 'ACTIVE',
        },
      ],
    };
  }

  @override
  Future<void> logout() async {
    logouts++;
    if (fail) throw StateError('Secure cleanup failed');
    PendingPublicMediaService.instance.clear();
    await done.future;
  }
}

Future<GlobalKey<NavigatorState>> _open(WidgetTester tester, _Auth auth) async {
  final root = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: MaterialApp(
        navigatorKey: root,
        home: const Scaffold(body: Text('Previous route')),
        routes: {
          '/settings': (_) => SettingsPage(
            authRepository: auth,
            permissionsReader: () async => const SettingsDevicePermissions(
              camera: true,
              location: true,
              notifications: false,
            ),
          ),
          AuthRoutes.login: (_) =>
              const Scaffold(body: Text('Login destination')),
        },
      ),
    ),
  );
  root.currentState!.pushNamed('/settings');
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('Log out'),
    400,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
  return root;
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    PendingPublicMediaService.instance.clear();
  });
  for (final venue in [false, true]) {
    testWidgets(
      'Settings ${venue ? 'venue' : 'personal'} is stable, blocks back and double logout',
      (tester) async {
        final auth = _Auth(venue);
        final root = await _open(tester, auth);
        final state = tester.state(find.byType(SettingsPage));
        final reads = auth.reads;
        await tester.tap(find.text('Log out'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(state.mounted, true);
        expect(tester.state(find.byType(SettingsPage)), same(state));
        expect(auth.reads, reads);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text('Login destination'), findsNothing);
        await tester.tap(find.text('Log out'), warnIfMissed: false);
        await root.currentState!.maybePop();
        await tester.pump();
        expect(state.mounted, isTrue);
        expect(auth.logouts, 1);
        auth.done.complete();
        await tester.pumpAndSettle();
        expect(find.text('Login destination'), findsOneWidget);
        expect(root.currentState!.canPop(), false);
        expect(LogoutFlow.busy.value, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Settings shows a recoverable error rather than pretending local cleanup succeeded',
    (tester) async {
      final auth = _Auth(false, fail: true);
      await _open(tester, auth);
      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();
      expect(auth.logouts, 1);
      expect(find.text('Login destination'), findsNothing);
      expect(
        find.text('Could not finish signing out. Please try again.'),
        findsOneWidget,
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(LogoutFlow.busy.value, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
