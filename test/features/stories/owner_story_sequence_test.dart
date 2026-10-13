import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/stories/data/owner_story_sequence.dart';
import 'package:kmstry_frontend/features/stories/data/story_model.dart';

PendingPublicMedia draft(
  String id, {
  PendingPublicMediaKind kind = PendingPublicMediaKind.personalStory,
  String venue = 'venue-1',
  bool receipt = false,
  PendingPublicMediaState state = PendingPublicMediaState.checking,
  String? uploadId,
}) => PendingPublicMedia(
  id: id,
  kind: kind,
  venueId: venue,
  localPath: '',
  isVideo: true,
  createdAt: DateTime(2026, 10, 1),
  hasServerReceipt: receipt,
  state: state,
  uploadId: uploadId,
);

StoryItem published(String id) => StoryItem(
  id: id,
  mediaUrl: '',
  mediaType: 'photo',
  createdAt: DateTime(2026),
  expiresAt: DateTime(2030),
);

Future<void> flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('published then pending, separated by personal/venue identity', () {
    final uploads = PendingPublicMediaService.forTest(
      publishedLookup: (_) async => false,
      moderationLookup: (_) async => const MediaModerationSnapshot(),
      delay: (_) => Completer<void>().future,
    );
    uploads.track(draft('personal'));
    uploads.track(draft('venue-one', kind: PendingPublicMediaKind.venueStory));
    uploads.track(
      draft(
        'venue-two',
        kind: PendingPublicMediaKind.venueStory,
        venue: 'venue-2',
      ),
    );
    final personal = OwnerStorySequence(
      kind: PendingPublicMediaKind.personalStory,
      published: [published('old')],
      uploads: uploads,
    );
    final venue = OwnerStorySequence(
      kind: PendingPublicMediaKind.venueStory,
      venueId: 'venue-1',
      published: [],
      uploads: uploads,
    );
    expect(personal.stories.map((s) => s.id), ['old', 'owner-upload:personal']);
    expect(venue.stories.single.ownerUploadId, 'venue-one');
    expect(personal.stories.last.mediaUrl, isEmpty);
    uploads.dismiss('personal');
    expect(personal.stories.map((s) => s.id), ['old']);
    personal.dispose();
    venue.dispose();
    uploads.clear();
  });

  test(
    'receipt keeps identity; only exact public item replaces its preview',
    () async {
      var status = 'PROCESSING';
      final pause = Completer<void>();
      final publicResult = Completer<List<StoryItem>>();
      final uploads = PendingPublicMediaService.forTest(
        publishedLookup: (_) async => true,
        moderationLookup: (_) async => MediaModerationSnapshot(status: status),
        delay: (_) => pause.future,
      );
      final sequence = OwnerStorySequence(
        kind: PendingPublicMediaKind.personalStory,
        published: [published('old')],
        uploads: uploads,
        loadPublished: () => publicResult.future,
      );
      await uploads.runTrackedUpload<String>(
        draft: draft('local'),
        expectedGeneration: uploads.sessionGeneration,
        send: (_) async => 'server',
        receiptId: (id) => id,
      );
      await flush();
      expect(sequence.stories.last.ownerUploadId, 'local');
      expect(sequence.pendingFor(sequence.stories.last)?.id, 'server');
      status = 'APPROVED';
      pause.complete();
      await flush();
      // Canonical fetch is still pending; do not drop or publicly render the draft.
      expect(uploads.byId('server'), isNull);
      expect(sequence.stories.last.isOwnerUpload, true);
      publicResult.complete([published('old'), published('server')]);
      await flush();
      expect(sequence.stories.map((s) => s.id), ['old', 'server']);
      expect(sequence.stories.any((s) => s.isOwnerUpload), false);
      sequence.dispose();
      uploads.clear();
    },
  );

  test(
    'canonical handoff never substitutes a different public story',
    () async {
      final uploads = PendingPublicMediaService.forTest(
        publishedLookup: (_) async => true,
        moderationLookup: (_) async =>
            const MediaModerationSnapshot(status: 'APPROVED'),
        delay: (_) => Completer<void>().future,
      );
      final sequence = OwnerStorySequence(
        kind: PendingPublicMediaKind.personalStory,
        published: [],
        uploads: uploads,
        loadPublished: () async => [published('different-story')],
      );
      uploads.track(draft('expected-story', receipt: true));
      await flush();
      expect(sequence.stories.last.isOwnerUpload, true);
      expect(sequence.pendingFor(sequence.stories.last)?.id, 'expected-story');
      sequence.dispose();
      uploads.clear();
    },
  );

  test(
    'logout clears all owner content and ignores a late public fetch',
    () async {
      final result = Completer<List<StoryItem>>();
      final uploads = PendingPublicMediaService.forTest(
        publishedLookup: (_) async => true,
        moderationLookup: (_) async =>
            const MediaModerationSnapshot(status: 'APPROVED'),
        delay: (_) => Completer<void>().future,
      );
      final sequence = OwnerStorySequence(
        kind: PendingPublicMediaKind.personalStory,
        published: [published('old')],
        uploads: uploads,
        loadPublished: () => result.future,
      );
      uploads.track(draft('new', receipt: true));
      await flush();
      uploads.clear();
      expect(sequence.sessionValid, false);
      expect(sequence.stories, isEmpty);
      result.complete([published('new')]);
      await flush();
      expect(sequence.stories, isEmpty);
      sequence.dispose();
    },
  );
}
