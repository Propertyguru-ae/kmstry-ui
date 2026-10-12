import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_report_options_sheet.dart';

void main() {
  testWidgets('neutral choices disclose the photo recipient on small screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    VenueReportTarget? selected;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await showVenueReportOptions(
                  context,
                  hasPhoto: true,
                );
              },
              child: const Text('Open report'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open report'));
    await tester.pumpAndSettle();
    expect(find.text('Report venue'), findsOneWidget);
    expect(find.text('Report photo'), findsOneWidget);
    expect(find.text('Reviewed by the KMSTRY team.'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_new), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Report photo'));
    await tester.tap(find.text('Report photo'));
    await tester.pumpAndSettle();
    expect(selected, VenueReportTarget.photo);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dismissing the provider notice does not confirm navigation', (
    tester,
  ) async {
    bool? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                confirmed = await confirmGoogleReportNavigation(
                  context,
                  instructions: 'Open the photo and choose Report a problem.',
                );
              },
              child: const Text('Open report'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open report'));
    await tester.pumpAndSettle();
    expect(confirmed, isNull);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);
  });
}
