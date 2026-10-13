import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/features/venue/data/google_photo_source.dart';
import 'package:kmstry_frontend/features/venue/presentation/google_place_photo.dart';

const photo =
    'https://pre-prod-api.kmstry.net/venues/places/photo/payload.signature';

GooglePhotoSource source({bool reportIsDirect = true}) => GooglePhotoSource(
  photoUrl: photo,
  authors: [
    GooglePhotoAuthor(
      name: 'Alice',
      profileUrl: Uri.parse('https://www.google.com/maps/contrib/alice'),
    ),
  ],
  sourceUrl: Uri.parse('https://www.google.com/maps/photo/123'),
  reportUrl: Uri.parse('https://www.google.com/maps/photo/123'),
  reportIsDirect: reportIsDirect,
);

Future<void> openSheet(
  WidgetTester tester, {
  required ThemeData theme,
  GooglePhotoSource? photoSource,
  GooglePhotoLinkLauncher? launcher,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showGooglePhotoSourceSheet(
              context,
              photoUrl: photo,
              sourceLoader: (_) async => photoSource ?? source(),
              linkLauncher: launcher,
            ),
            child: const Text('Credits'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Credits'));
  await tester.pumpAndSettle();
}

void main() {
  for (final dark in [true, false]) {
    testWidgets(
      'credits sheet uses the app sheet style (${dark ? 'dark' : 'light'})',
      (tester) async {
        await openSheet(
          tester,
          theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        );
        final sheet = tester.widget<BottomSheet>(find.byType(BottomSheet));
        expect(
          sheet.backgroundColor,
          dark ? const Color(0xFF121A2B) : Colors.white,
        );
        expect(
          sheet.shape,
          const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
        );
        expect(sheet.showDragHandle, isNot(true));
        expect(find.text('Photo credits'), findsOneWidget);
        expect(find.text('PHOTO BY'), findsOneWidget);
        expect(find.text('GOOGLE MAPS'), findsOneWidget);
        expect(find.byType(ListTile), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a link that cannot open shows the app error toast', (
    tester,
  ) async {
    await openSheet(
      tester,
      theme: AppTheme.darkTheme,
      launcher: (_) async => false,
    );
    await tester.tap(find.text('View on Google Maps'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text("Couldn't open Google Maps. Please try again."),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsNothing);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('the Google report notice uses the app confirmation dialog', (
    tester,
  ) async {
    final opened = <Uri>[];
    await openSheet(
      tester,
      theme: AppTheme.darkTheme,
      photoSource: source(reportIsDirect: false),
      launcher: (uri) async {
        opened.add(uri);
        return true;
      },
    );
    await tester.tap(find.text('Report to Google Maps'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Continue on Google Maps?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    await tester.tap(find.text('Continue to Google Maps'));
    await tester.pumpAndSettle();
    expect(opened, [source().reportUrl]);
  });
}
