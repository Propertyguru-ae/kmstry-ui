import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/stories/data/story_model.dart';
import 'package:kmstry_frontend/features/stories/presentation/story_viewer_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> openStory(
  WidgetTester tester, {
  required bool isVenueStory,
  bool isOwner = false,
  String? viewerVenueId,
  String? venueId = 'venue-1',
  String? venueName = 'Test Cafe',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: StoryViewerPage(
        groups: [
          StoryGroup(
            user: const StoryUser(id: 'story-owner', fullName: 'Story Owner'),
            isCurrentUserOwner: isOwner,
            stories: [
              StoryItem(
                id: 'story-1',
                mediaUrl: '',
                mediaType: 'photo',
                expiresAt: DateTime(2030),
                createdAt: DateTime(2026),
                user: const StoryUser(id: 'story-owner'),
                isVenueStory: isVenueStory,
                venueId: venueId,
                venueName: venueName,
              ),
            ],
          ),
        ],
        venueId: viewerVenueId,
        isManagedVenueContent: isVenueStory && isOwner,
        canDelete: isOwner,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  for (final isOwner in [true, false]) {
    testWidgets('venue story has no location tag; owner=$isOwner', (
      tester,
    ) async {
      await openStory(
        tester,
        isVenueStory: true,
        isOwner: isOwner,
        viewerVenueId: 'venue-1',
      );
      expect(find.text('at Test Cafe'), findsNothing);
      expect(find.byIcon(Icons.location_on), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('personal story keeps its check-in location; owner=$isOwner', (
      tester,
    ) async {
      await openStory(tester, isVenueStory: false, isOwner: isOwner);
      expect(find.text('at Test Cafe'), findsOneWidget);
      expect(find.byIcon(Icons.location_on), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('venue story in a general viewer still has no location tag', (
    tester,
  ) async {
    await openStory(tester, isVenueStory: true);
    expect(find.text('at Test Cafe'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('personal tag follows content type, not venue viewer context', (
    tester,
  ) async {
    await openStory(tester, isVenueStory: false, viewerVenueId: 'venue-1');
    expect(find.text('at Test Cafe'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final missing in ['id', 'name']) {
    testWidgets('personal story without venue $missing has no location tag', (
      tester,
    ) async {
      await openStory(
        tester,
        isVenueStory: false,
        venueId: missing == 'id' ? null : 'venue-1',
        venueName: missing == 'name' ? null : 'Test Cafe',
      );
      expect(find.byIcon(Icons.location_on), findsNothing);
      expect(find.textContaining('at '), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
