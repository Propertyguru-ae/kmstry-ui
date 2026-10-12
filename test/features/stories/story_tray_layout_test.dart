import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/content_moderation/presentation/pending_public_media_preview.dart';
import 'package:kmstry_frontend/features/stories/data/story_model.dart';
import 'package:kmstry_frontend/features/stories/data/story_repository.dart';
import 'package:kmstry_frontend/features/stories/presentation/story_tray.dart';

class _Repository extends StoryRepository {
  @override
  Future<List<StoryItem>> getMyStories() async => [];
  @override
  Future<List<StoryGroup>> getVenueStories(String venueId) async => [];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final scale in [1.0, 1.3, 2.0, 3.0]) {
    for (final state in [
      PendingPublicMediaState.preparing,
      PendingPublicMediaState.rejected,
      PendingPublicMediaState.underReview,
    ]) {
      testWidgets('venue detail story label fits at $scale with $state', (
        tester,
      ) async {
        final uploads = PendingPublicMediaService.forTest(
          publishedLookup: (_) async => false,
          moderationLookup: (_) async => const MediaModerationSnapshot(),
          delay: (_) async {},
        );
        final item = PendingPublicMedia(
          id: 'draft',
          kind: PendingPublicMediaKind.personalStory,
          venueId: 'venue',
          localPath: '',
          isVideo: true,
          createdAt: DateTime.now(),
          hasServerReceipt: false,
          state: state,
        );
        // No networking or moderation polling in this layout test.
        uploads.track(item);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: Column(
                  children: [
                    StoryTray(
                      venueId: 'venue',
                      onAddStory: () {},
                      repository: _Repository(),
                      uploads: uploads,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        final tray = tester.getRect(find.byType(StoryTray));
        final label = tester.getRect(find.byType(PublicMediaUploadStatus));
        expect(label.bottom, lessThanOrEqualTo(tray.bottom));
        await tester.pumpWidget(const SizedBox.shrink());
        uploads.clear();
        await uploads.flushPersistence();
      });
    }
  }
}
