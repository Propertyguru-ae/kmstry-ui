import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/ui/app_confirmation_dialog.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';

void main() {
  Future<bool?> confirm(
    WidgetTester tester, {
    required ThemeData theme,
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    bool? choice;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                choice = await showAppConfirmationDialog(
                  context,
                  title: 'Use a different account?',
                  message: 'You will be signed out. Your progress is saved.',
                  confirmLabel: 'Sign out',
                  icon: Icons.logout_rounded,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(PrimaryButton, 'Sign out'), findsOneWidget);
    expect(find.byIcon(Icons.logout_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Use a different account?'), findsNothing);
    return choice;
  }

  for (final dark in [false, true]) {
    testWidgets('confirm returns true; dark=$dark', (tester) async {
      final choice = await confirm(
        tester,
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      );
      expect(choice, isTrue);
    });
  }

  testWidgets('Cancel returns false and an outside tap keeps it open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    bool? choice;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                choice = await showAppConfirmationDialog(
                  context,
                  title: 'Title',
                  message: 'Message',
                  confirmLabel: 'Confirm',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text('Title'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(choice, isFalse);
  });

  testWidgets('buttons stay reachable on a small screen with large text', (
    tester,
  ) async {
    final choice = await confirm(
      tester,
      theme: AppTheme.darkTheme,
      size: const Size(320, 480),
      textScale: 1.6,
    );
    expect(choice, isTrue);
  });
}
