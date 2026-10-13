import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';

void main() {
  final rejected = ApiException(
    statusCode: 400,
    data: {'errorCode': 'PUBLIC_TEXT_NOT_ALLOWED'},
  );

  for (final dark in [true, false]) {
    testWidgets(
      '"Please edit your text" uses the app standard popup (${dark ? 'dark' : 'light'})',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showPremiumErrorDialog(
                    context,
                    title: publicTextErrorTitle(rejected),
                    message: publicTextErrorMessage(
                      rejected,
                      fallback: 'Could not save.',
                    ),
                    icon: publicTextErrorIcon(rejected),
                  ),
                  child: const Text('Save'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.byIcon(Icons.edit_note_rounded), findsOneWidget);
        expect(find.text('Please edit your text'), findsOneWidget);
        expect(find.text(publicTextRejectionMessage), findsOneWidget);
        // One action only: the standard dialog without "Not now".
        expect(find.text('Not now'), findsNothing);

        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('text check outcomes get their own icon', () {
    ApiException withCode(String code) =>
        ApiException(statusCode: 400, data: {'errorCode': code});
    expect(publicTextErrorIcon(rejected), Icons.edit_note_rounded);
    expect(
      publicTextErrorIcon(withCode('PUBLIC_TEXT_CHECK_UNAVAILABLE')),
      Icons.cloud_off_rounded,
    );
    expect(
      publicTextErrorIcon(withCode('PUBLIC_TEXT_TOO_LONG')),
      Icons.short_text_rounded,
    );
    expect(publicTextErrorIcon(Exception('x')), Icons.error_outline_rounded);
  });
}
