import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
