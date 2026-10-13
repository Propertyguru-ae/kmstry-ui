import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/theme/theme_provider.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/profile/data/settings_device_permissions.dart';
import 'package:kmstry_frontend/features/profile/presentation/settings_page.dart';

class _Auth extends AuthRepository {
  _Auth(this.read);
  final Future<Map<String, dynamic>> Function() read;
  final calls = <bool>[];
  @override
  Future<Map<String, dynamic>> getMe({bool forceRefresh = false}) {
    calls.add(forceRefresh);
    return read();
  }
}

Widget _screen(
  _Auth auth,
  Future<SettingsDevicePermissions> Function() permissions,
) => ChangeNotifierProvider(
  create: (_) => ThemeProvider(),
  child: MaterialApp(
    home: SettingsPage(authRepository: auth, permissionsReader: permissions),
  ),
);

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    PendingPublicMediaService.instance.clear();
  });
  tearDown(() => PendingPublicMediaService.instance.clear());
  const permissions = SettingsDevicePermissions(
    camera: true,
    location: true,
    notifications: false,
  );
  Map<String, dynamic> me(String name) => {
    'fullName': name,
    'hasPersonalProfile': true,
    'lastActiveContext': 'PERSONAL',
  };

  testWidgets(
    'account renders without waiting for device permission channels',
    (tester) async {
      final device = Completer<SettingsDevicePermissions>();
      var permissionCalls = 0;
      final auth = _Auth(() async => me('Alex'));
      await tester.pumpWidget(
        _screen(auth, () {
          permissionCalls++;
          return device.future;
        }),
      );
      await tester.pumpAndSettle();
      expect(find.text('Alex'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(permissionCalls, 1);
      expect(auth.calls, [false]);
      device.complete(permissions);
      await tester.pumpAndSettle();
      expect(find.text('Alex'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a platform permission failure cannot prevent account settings from loading',
    (tester) async {
      final auth = _Auth(() async => me('Alex'));
      await tester.pumpWidget(
        _screen(auth, () async => throw StateError('Platform unavailable')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Alex'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'approved photo refreshes account only and keeps the header while reading',
    (tester) async {
      final next = Completer<Map<String, dynamic>>();
      var count = 0;
      var permissionCalls = 0;
      final auth = _Auth(
        () => ++count == 1 ? Future.value(me('Alex')) : next.future,
      );
      await tester.pumpWidget(
        _screen(auth, () async {
          permissionCalls++;
          return permissions;
        }),
      );
      await tester.pumpAndSettle();
      PendingPublicMediaService.instance.avatarPublicationChanges.value++;
      await tester.pump();
      expect(find.text('Alex'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(permissionCalls, 1);
      expect(auth.calls, [false, true]);
      next.complete(me('Updated Alex'));
      await tester.pumpAndSettle();
      expect(find.text('Updated Alex'), findsOneWidget);
    },
  );

  testWidgets('a late former account response cannot enter the new session', (
    tester,
  ) async {
    final old = Completer<Map<String, dynamic>>();
    final auth = _Auth(() => old.future);
    await tester.pumpWidget(_screen(auth, () async => permissions));
    PendingPublicMediaService.instance.clear();
    old.complete(me('Old account'));
    await tester.pump();
    expect(find.text('Old account'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
