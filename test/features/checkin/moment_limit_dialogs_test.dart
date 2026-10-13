import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/features/checkin/presentation/moment_limit_dialogs.dart';

Future<void> _open(
  WidgetTester tester,
  Future<void> Function(BuildContext) show, {
  bool dark = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'second video shows a friendly on-brand notice (${dark ? 'dark' : 'light'})',
      (tester) async {
        await _open(tester, showOneVideoLimitDialog, dark: dark);
        expect(tester.takeException(), isNull);
        expect(find.text('One video per check-in'), findsOneWidget);
        expect(find.textContaining('Snap a photo'), findsOneWidget);
        expect(find.text('Something went wrong'), findsNothing);
        expect(find.text('Not now'), findsNothing);
        await tester.tap(find.text('Got it'));
        await tester.pumpAndSettle();
        expect(find.text('One video per check-in'), findsNothing);
      },
    );
  }

  testWidgets('full Moments shows a friendly notice', (tester) async {
    await _open(tester, showMomentsFullDialog);
    expect(find.text('Your Moments are full'), findsOneWidget);
    expect(find.textContaining('up to 6 Moments'), findsOneWidget);
    expect(find.text('Something went wrong'), findsNothing);
  });
}
