import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/auth/presentation/login_page.dart';

class _Auth extends AuthRepository {
  final done = Completer<bool>();
  int passwords = 0;
  int googles = 0;
  @override
  Future<bool> login(String identifier, String password) {
    passwords++;
    return done.future;
  }

  @override
  Future<bool> loginWithGoogle({
    bool? consentGiven,
    String? termsVersionId,
    String? privacyVersionId,
    String? consentSource,
    bool reusePendingToken = false,
  }) {
    googles++;
    return done.future;
  }
}

Future<void> _mount(WidgetTester tester, _Auth auth) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: LoginPage(authRepository: auth),
      routes: {
        AuthRoutes.authGate: (_) =>
            const Scaffold(body: Text('Fresh account routing')),
      },
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });
  testWidgets('password login cannot race another tap or social login', (
    tester,
  ) async {
    final auth = _Auth();
    await _mount(tester, auth);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'test@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'test123!');
    await tester.tap(find.text('Log in'));
    await tester.pump();
    await tester.tap(find.text('G'), warnIfMissed: false);
    expect(auth.passwords, 1);
    expect(auth.googles, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    auth.done.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Fresh account routing'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('social cancellation unlocks login without navigation', (
    tester,
  ) async {
    final auth = _Auth();
    await _mount(tester, auth);
    await tester.tap(find.text('G'));
    await tester.pump();
    await tester.tap(find.text('Log in'), warnIfMissed: false);
    expect(auth.googles, 1);
    expect(auth.passwords, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    auth.done.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('Fresh account routing'), findsNothing);
    expect(find.text('G'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'late login error after route disposal does not setState on a dead page',
    (tester) async {
      final auth = _Auth();
      await _mount(tester, auth);
      await tester.enterText(
        find.byType(TextFormField).at(0),
        'test@example.com',
      );
      await tester.enterText(find.byType(TextFormField).at(1), 'test123!');
      await tester.tap(find.text('Log in'));
      await tester.pump();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      auth.done.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
