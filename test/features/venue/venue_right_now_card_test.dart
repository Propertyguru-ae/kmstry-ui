import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_account_home_page.dart';

Future<void> _pump(WidgetTester tester, Widget card, {bool dark = false}) =>
    tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(16), child: card),
        ),
      ),
    );

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'live card shows count, gender split and guests in one card (${dark ? 'dark' : 'light'})',
      (tester) async {
        await _pump(
          tester,
          VenueLivePulseCard(
            activeNow: 6,
            maleNow: 2,
            femaleNow: 2,
            guests: SizedBox(
              key: const ValueKey('guests'),
              height: 88,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: List.generate(
                  8,
                  (i) => const SizedBox(width: 52, height: 88),
                ),
              ),
            ),
          ),
          dark: dark,
        );
        expect(tester.takeException(), isNull);
        expect(find.text('LIVE NOW'), findsOneWidget);
        expect(find.text('6'), findsOneWidget);
        expect(find.text('guests here'), findsOneWidget);
        expect(find.byKey(const ValueKey('guests')), findsOneWidget);
        expect(find.byType(Divider), findsOneWidget);
        // Guests sit inside the card, below the live number.
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('guests'))).dy,
          greaterThan(tester.getBottomLeft(find.text('6')).dy),
        );
      },
    );
  }

  testWidgets('quiet card explains where guests will appear', (tester) async {
    await _pump(
      tester,
      const VenueLivePulseCard(activeNow: 0, maleNow: 0, femaleNow: 0),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('QUIET'), findsOneWidget);
    expect(find.text('Guests appear here as they check in.'), findsOneWidget);
    expect(find.byType(Divider), findsNothing);
  });
}
