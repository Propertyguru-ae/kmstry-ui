import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/venue_event_detail_page.dart';

void main() {
  testWidgets(
    'Gallery title sits right above the photo grid on notched screens',
    (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(393 * 3, 852 * 3);
      tester.view.padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
      addTearDown(tester.view.reset);
      // Network photos cannot load in tests; only the layout is measured.
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.library == 'image resource service') return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);
      final event = VenueUpcomingEvent(
        id: 'e1',
        title: 'Ladies Night',
        startAt: DateTime(2026, 10, 8, 20),
        endAt: DateTime(2026, 10, 8, 23),
        photos: const [
          'https://example.invalid/1.jpg',
          'https://example.invalid/2.jpg',
          'https://example.invalid/3.jpg',
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: VenueEventDetailPage(event: event, venueId: 'v1'),
        ),
      );
      await tester.pump();
      final title = find.text('GALLERY');
      expect(title, findsOneWidget);
      await tester.pump();
      final grid = find.byType(GridView);
      expect(grid, findsOneWidget);
      final titleBottom = tester.getBottomLeft(title).dy;
      final firstPhotoTop = tester
          .getTopLeft(
            find.descendant(of: grid, matching: find.byType(ClipRRect)).first,
          )
          .dy;
      // ignore: avoid_print
      print('gap title→photos: ${firstPhotoTop - titleBottom}');
      expect(firstPhotoTop - titleBottom, lessThan(20));
    },
  );

  testWidgets('a single gallery photo is a square tile like 2-3 photos', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    addTearDown(tester.view.reset);
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.library == 'image resource service') return;
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    Future<Size> tileFor(List<String> photos) async {
      await tester.pumpWidget(
        MaterialApp(
          home: VenueEventDetailPage(
            event: VenueUpcomingEvent(
              id: 'e${photos.length}',
              title: 'Ladies Night',
              startAt: DateTime(2026, 10, 8, 20),
              endAt: DateTime(2026, 10, 8, 23),
              photos: photos,
            ),
            venueId: 'v1',
          ),
        ),
      );
      await tester.pump();
      final grid = find.byType(GridView);
      expect(grid, findsOneWidget);
      return tester.getSize(
        find.descendant(of: grid, matching: find.byType(ClipRRect)).first,
      );
    }

    final single = await tileFor(const ['https://example.invalid/1.jpg']);
    final triple = await tileFor(const [
      'https://example.invalid/1.jpg',
      'https://example.invalid/2.jpg',
      'https://example.invalid/3.jpg',
    ]);
    expect(single.width, closeTo(single.height, 0.01));
    expect(single, triple);
  });
}
