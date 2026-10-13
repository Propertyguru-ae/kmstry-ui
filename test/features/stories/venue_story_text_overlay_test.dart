import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/media/media_text_overlay.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/stories/data/owner_story_sequence.dart';
import 'package:kmstry_frontend/features/stories/presentation/owner_story_upload.dart';
import 'package:kmstry_frontend/features/venue_stories/data/venue_story_model.dart';

const overlay = MediaTextOverlay(
  text: 'Hello Alpha',
  colorValue: 0xFFFFFF00,
  fontSizeNorm: .1,
  xNorm: .3,
  yNorm: .6,
  rotation: .2,
);

PendingPublicMedia draft({
  PendingPublicMediaState state = PendingPublicMediaState.checking,
}) => PendingPublicMedia(
  id: 'upload-1-2',
  kind: PendingPublicMediaKind.venueStory,
  venueId: 'alpha',
  localPath: '',
  previewPath: '/missing-local-preview.jpg',
  isVideo: true,
  textOverlay: overlay,
  createdAt: DateTime(2026),
  hasServerReceipt: false,
  state: state,
);

void main() {
  test(
    'venue story JSON and viewed state keep text and its exact placement',
    () {
      final story = VenueStoryItem.fromJson({
        'id': 'story',
        'media_type': 'video',
        'media_url': null,
        'created_at': '2026-10-05T00:00:00Z',
        'expires_at': '2026-10-06T00:00:00Z',
        'text_overlay': overlay.toJson(),
      });
      expect(story.textOverlay?.toJson(), overlay.toJson());
      expect(
        story.copyWith(viewedByMe: true).textOverlay?.toJson(),
        overlay.toJson(),
      );
    },
  );

  test('existing venue stories without text still parse', () {
    final story = VenueStoryItem.fromJson({
      'id': 'story',
      'media_type': 'video',
      'media_url': null,
      'created_at': '2026-10-05T00:00:00Z',
      'expires_at': '2026-10-06T00:00:00Z',
    });
    expect(story.textOverlay, isNull);
  });

  test(
    'text survives progress, retained poster, receipt, state and restart',
    () {
      final updated = draft()
          .withProgress(.5)
          .withPreview('/retained.jpg')
          .withReceipt('server-story')
          .withState(PendingPublicMediaState.underReview);
      expect(updated.textOverlay?.toJson(), overlay.toJson());
      final restored = PendingPublicMedia.fromJson(updated.toJson())!;
      expect(restored.textOverlay?.toJson(), overlay.toJson());
      expect(
        restored.localPath,
        isEmpty,
      ); // Not an automatically replayable upload.
    },
  );

  test(
    'pending venue text stays owner-only until the exact published story arrives',
    () {
      final uploads = PendingPublicMediaService.forTest(
        publishedLookup: (_) async => false,
        moderationLookup: (_) async =>
            const MediaModerationSnapshot(status: 'PENDING'),
        delay: (_) => Completer<void>().future,
      );
      final pending = draft();
      uploads.track(pending);
      final sequence = OwnerStorySequence(
        kind: PendingPublicMediaKind.venueStory,
        venueId: 'alpha',
        published: [],
        uploads: uploads,
      );
      final privateStory = sequence.stories.single;
      expect(privateStory.textOverlay?.text, 'Hello Alpha');
      expect(privateStory.isOwnerUpload, true);
      expect(privateStory.mediaUrl, isEmpty);
      expect(uploads.wasPublished(pending.id), false);
      sequence.dispose();
      uploads.clear();
    },
  );

  testWidgets(
    'owner poster shows caption while processing without duplicate rendering',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: OwnerStoryUploadMedia(item: draft())),
        ),
      );
      await tester.pump();
      expect(find.byType(MediaTextOverlayView), findsOneWidget);
      expect(find.text('Hello Alpha'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a rejected venue upload never renders its caption or preview', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OwnerStoryUploadMedia(
            item: draft(state: PendingPublicMediaState.rejected),
          ),
        ),
      ),
    );
    expect(find.byType(MediaTextOverlayView), findsNothing);
    expect(find.text('Hello Alpha'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
