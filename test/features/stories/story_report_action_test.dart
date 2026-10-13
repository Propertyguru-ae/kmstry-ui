import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/ui/media_viewer_buttons.dart';
import 'package:kmstry_frontend/features/media/media_text_overlay.dart';
import 'package:kmstry_frontend/features/stories/data/story_model.dart';
import 'package:kmstry_frontend/features/stories/presentation/story_viewer_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

StoryItem _venueStory() => StoryItem(
  id: 'venue-story-1',
  mediaUrl: '',
  mediaType: 'photo',
  expiresAt: DateTime(2030),
  createdAt: DateTime(2026),
  user: const StoryUser(id: 'poster-user'),
  venueId: 'venue-1',
  venueName: 'Test Venue',
  isVenueStory: true,
  textOverlay: const MediaTextOverlay(
    text: 'Venue story',
    colorValue: 0xFFFFFFFF,
    fontSizeNorm: 0.07,
  ),
);

Future<void> _openVenueStory(
  WidgetTester tester, {
  required bool isManagedVenueContent,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    MaterialApp(
      home: StoryViewerPage(
        groups: [
          StoryGroup(
            user: const StoryUser(id: 'venue_venue-1', fullName: 'Test Venue'),
            stories: [_venueStory()],
          ),
        ],
        venueId: 'venue-1',
        isManagedVenueContent: isManagedVenueContent,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('venue manager cannot report the venue own story', (
    tester,
  ) async {
    await _openVenueStory(tester, isManagedVenueContent: true);

    expect(find.byTooltip('Report'), findsNothing);
    expect(find.byIcon(Icons.close), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('external viewer can still report a venue story', (tester) async {
    await _openVenueStory(tester, isManagedVenueContent: false);

    expect(find.byTooltip('Report'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('story uses the shared viewer buttons at the shared position', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(top: 59);
    addTearDown(tester.view.reset);

    await _openVenueStory(tester, isManagedVenueContent: false);

    expect(find.byType(MediaViewerReportButton), findsOneWidget);
    expect(find.byType(MediaViewerCloseButton), findsOneWidget);
    // Moment ve galeri ile aynı konum: güvenli alanın 38px altı, sağdan 12px.
    final close = find.byType(MediaViewerCloseButton);
    expect(tester.getTopLeft(close).dy, closeTo(59 + 38, 0.5));
    expect(390 - tester.getTopRight(close).dx, closeTo(12, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
