import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/stories/data/story_repository.dart';
import 'package:kmstry_frontend/features/venue_stories/data/venue_story_repository.dart';

Future<void> flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

PendingPublicMedia item(PendingPublicMediaKind kind) => PendingPublicMedia(
  id: 'target-1',
  kind: kind,
  venueId: 'venue',
  checkinId: 'checkin',
  localPath: '',
  isVideo: false,
  createdAt: DateTime.now(),
);

Map<String, dynamic> hint(PendingPublicMedia entry) => {
  'userId': 'owner',
  'itemId': 'review-1',
  'targetType': entry.targetType,
  'targetId': entry.id,
};

void main() {
  for (final kind in [
    PendingPublicMediaKind.personalStory,
    PendingPublicMediaKind.checkinMoment,
    PendingPublicMediaKind.venueStory,
  ]) {
    test(
      'admin approval wakes $kind immediately without waiting for the 15 second poll',
      () async {
        var approved = false;
        var reads = 0;
        var publicReads = 0;
        final service = PendingPublicMediaService.forTest(
          moderationLookup: (_) async {
            reads++;
            return MediaModerationSnapshot(
              status: approved ? 'APPROVED' : 'NEEDS_REVIEW',
            );
          },
          publishedLookup: (_) async {
            publicReads++;
            return true;
          },
          delay: (_) => Completer<void>().future, // A timer that never fires.
        );
        final entry = item(kind);
        service.track(entry);
        await flush();
        expect(
          service.byId(entry.id)?.state,
          PendingPublicMediaState.underReview,
        );
        expect(publicReads, 0);
        final personalRevision = StoryRepository.changes.value;
        final venueRevision = VenueStoryRepository.changes.value;
        approved = true;
        service.handleModerationUpdate(hint(entry), currentUserId: 'owner');
        await flush();
        expect(reads, 2);
        expect(publicReads, 1);
        expect(service.wasPublished(entry.id), true);
        if (kind == PendingPublicMediaKind.personalStory) {
          expect(StoryRepository.changes.value, personalRevision + 1);
        }
        if (kind == PendingPublicMediaKind.venueStory) {
          expect(VenueStoryRepository.changes.value, venueRevision + 1);
        }
        if (kind == PendingPublicMediaKind.checkinMoment) {
          expect(service.publicationChanges.value, 1);
        }
        service.clear();
      },
    );
  }

  test(
    'event never publishes before the HTTP visibility check succeeds',
    () async {
      var status = 'NEEDS_REVIEW';
      var visible = false;
      final service = PendingPublicMediaService.forTest(
        moderationLookup: (_) async => MediaModerationSnapshot(status: status),
        publishedLookup: (_) async => visible,
        delay: (_) => Completer<void>().future,
      );
      final entry = item(PendingPublicMediaKind.personalStory);
      service.track(entry);
      await flush();
      status = 'APPROVED';
      service.handleModerationUpdate({
        ...hint(entry),
        'status': 'APPROVED',
      }, currentUserId: 'owner');
      await flush();
      expect(service.wasPublished(entry.id), false);
      visible = true;
      service.recheckPending();
      await flush();
      expect(service.wasPublished(entry.id), true);
      service.clear();
    },
  );

  test(
    'reconnect catches up pending review without a socket decision or reupload',
    () async {
      var status = 'NEEDS_REVIEW';
      final service = PendingPublicMediaService.forTest(
        moderationLookup: (_) async => MediaModerationSnapshot(status: status),
        publishedLookup: (_) async => true,
        delay: (_) => Completer<void>().future,
      );
      final entry = item(PendingPublicMediaKind.checkinMoment);
      service.track(entry);
      await flush();
      status = 'APPROVED';
      service.recheckPending();
      await flush();
      expect(service.wasPublished(entry.id), true);
      service.clear();
    },
  );

  test(
    'old-account hints and malformed payloads cannot refresh or publish the next account',
    () async {
      var reads = 0;
      final service = PendingPublicMediaService.forTest(
        moderationLookup: (_) async {
          reads++;
          return const MediaModerationSnapshot(status: 'NEEDS_REVIEW');
        },
        publishedLookup: (_) async => true,
        delay: (_) => Completer<void>().future,
      );
      final entry = item(PendingPublicMediaKind.checkinMoment);
      service.track(entry);
      await flush();
      service.handleModerationUpdate(
        hint(entry),
        currentUserId: 'different-owner',
      );
      service.handleModerationUpdate(hint(entry), currentUserId: null);
      service.handleModerationUpdate({
        'userId': 'owner',
      }, currentUserId: 'owner');
      await flush();
      expect(reads, 1);
      expect(service.publicationChanges.value, 0);
      expect(service.wasPublished(entry.id), false);
      service.clear();
    },
  );

  test(
    'many hints during an in-flight read coalesce and discard its stale decision',
    () async {
      final first = Completer<MediaModerationSnapshot>();
      var reads = 0;
      final service = PendingPublicMediaService.forTest(
        moderationLookup: (_) {
          reads++;
          return reads == 1
              ? first.future
              : Future.value(const MediaModerationSnapshot(status: 'APPROVED'));
        },
        publishedLookup: (_) async => true,
        delay: (_) => Completer<void>().future,
      );
      final entry = item(PendingPublicMediaKind.checkinMoment);
      service.track(entry);
      for (var i = 0; i < 10; i++) {
        service.handleModerationUpdate(hint(entry), currentUserId: 'owner');
      }
      expect(reads, 1);
      first.complete(const MediaModerationSnapshot(status: 'NEEDS_REVIEW'));
      await flush();
      expect(reads, 2);
      expect(service.wasPublished(entry.id), true);
      expect(service.publicationChanges.value, 1);
      service.clear();
    },
  );

  test(
    'a failed processor outcome can be rechecked after an admin decision',
    () async {
      var status = 'ERROR';
      final service = PendingPublicMediaService.forTest(
        moderationLookup: (_) async => MediaModerationSnapshot(status: status),
        publishedLookup: (_) async => true,
        delay: (_) => Completer<void>().future,
      );
      final entry = item(PendingPublicMediaKind.personalStory);
      service.track(entry);
      await flush();
      expect(service.byId(entry.id)?.state, PendingPublicMediaState.failed);
      status = 'APPROVED';
      service.handleModerationUpdate(hint(entry), currentUserId: 'owner');
      await flush();
      expect(service.wasPublished(entry.id), true);
      service.clear();
    },
  );

  test('logout invalidates an in-flight admin refresh', () async {
    final read = Completer<MediaModerationSnapshot>();
    final service = PendingPublicMediaService.forTest(
      moderationLookup: (_) => read.future,
      publishedLookup: (_) async => true,
      delay: (_) => Completer<void>().future,
    );
    final entry = item(PendingPublicMediaKind.checkinMoment);
    service.track(entry);
    service.handleModerationUpdate(hint(entry), currentUserId: 'owner');
    service.clear();
    read.complete(const MediaModerationSnapshot(status: 'APPROVED'));
    await flush();
    expect(service.items, isEmpty);
    expect(service.wasPublished(entry.id), false);
    expect(service.publicationChanges.value, 0);
  });
}
