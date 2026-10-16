import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/auth/presentation/context_choice_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> open(WidgetTester tester, {required bool authenticated}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: ContextChoicePage(isAuthenticated: authenticated)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('signup choice hides the account types help link', (
    tester,
  ) async {
    await open(tester, authenticated: false);
    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Venue'), findsOneWidget);
    expect(find.textContaining('Learn about account types'), findsNothing);
    expect(find.textContaining('Not sure?'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signed-in profile setup still offers Log out', (tester) async {
    await open(tester, authenticated: true);
    expect(find.text('Log out'), findsOneWidget);
    expect(find.textContaining('Learn about account types'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
