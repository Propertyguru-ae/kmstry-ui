import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/stories/data/story_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_repository.dart';
import 'package:kmstry_frontend/features/venue_stories/data/venue_story_repository.dart';
import 'package:kmstry_frontend/core/network/multipart_upload.dart';

PendingPublicMedia _item(String id) => PendingPublicMedia(
  id: id,
  kind: PendingPublicMediaKind.personalStory,
  venueId: 'venue-1',
  localPath: '/tmp/owner-preview.jpg',
  isVideo: false,
  createdAt: DateTime(2026, 9, 30),
);

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  for (final status in ['PENDING', 'NEEDS_REVIEW', 'APPROVED', 'REJECTED']) {
    test(
      'paused video ends its watch without a public read ($status)',
      () async {
        var publicReads = 0;
        var delays = 0;
        final service = PendingPublicMediaService.forTest(
          publishedLookup: (_) async {
            publicReads++;
            return true;
          },
          moderationLookup: (_) async => MediaModerationSnapshot(
            status: status,
            publicationDisabled: true,
            message:
                'Video sharing is currently unavailable. Please choose a photo.',
          ),
          delay: (_) {
            delays++;
            return Completer<void>().future;
          },
        );
        service.track(_item('paused'));
        await _flush();
        expect(publicReads, 0);
        expect(delays, 0);
        expect(service.wasPublished('paused'), false);
        expect(
          service.byId('paused')?.state,
          status == 'REJECTED'
              ? PendingPublicMediaState.rejected
              : PendingPublicMediaState.failed,
        );
        expect(service.byId('paused')?.message, contains('choose a photo'));
        service.clear();
      },
    );
  }

  test(
    'acknowledging not-shared story feedback is local and ignores other states/media',
    () {
      var cancellations = 0;
      final service = PendingPublicMediaService.forTest(
        publishedLookup: (_) async => false,
        moderationLookup: (_) async => const MediaModerationSnapshot(),
        delay: (_) => Completer<void>().future,
        cancelStory: (_) async => cancellations++,
      );
      for (final kind in PendingPublicMediaKind.values) {
        for (final state in PendingPublicMediaState.values) {
          final id = '${kind.name}-${state.name}';
          service.track(
            PendingPublicMedia(
              id: id,
              uploadId: 'local-$id',
              kind: kind,
              venueId: 'venue',
              localPath: '',
              isVideo: false,
              createdAt: DateTime.now(),
              state: state,
              hasServerReceipt: false,
            ),
          );
          service.acknowledgeStoryFeedback(
            'local-$id',
            expectedGeneration: service.sessionGeneration,
          );
          expect(
            service.byId(id) == null,
            (kind == PendingPublicMediaKind.personalStory ||
                    kind == PendingPublicMediaKind.venueStory) &&
                (state == PendingPublicMediaState.rejected ||
                    state == PendingPublicMediaState.failed),
            reason: '$kind / $state',
          );
        }
      }
      expect(cancellations, 0);
      service.clear();
    },
  );

  test(
    'late acknowledgement cannot affect a new login with the same upload ID',
    () {
      final service = PendingPublicMediaService.forTest(
        publishedLookup: (_) async => false,
        moderationLookup: (_) async => const MediaModerationSnapshot(),
        delay: (_) => Completer<void>().future,
      );
      final session = service.sessionGeneration;
      service.clear();
      service.track(
        _item('same-id').withState(PendingPublicMediaState.rejected),
      );
      service.acknowledgeStoryFeedback('same-id', expectedGeneration: session);
      expect(service.byId('same-id'), isNotNull);
      service.clear();
    },
  );

  test('cancelled preparation never starts a later network transfer', () async {
    var sent = false;
    final service = PendingPublicMediaService.forTest(
      publishedLookup: (_) async => false,
      moderationLookup: (_) async => const MediaModerationSnapshot(),
      delay: (_) => Completer<void>().future,
      cancelStory: (_) async {},
    );
    final draft = PendingPublicMedia(
      id: 'upload-1-1',
      kind: PendingPublicMediaKind.personalStory,
      venueId: 'venue',
      checkinId: 'checkin',
      localPath: '',
      isVideo: false,
      createdAt: DateTime.now(),
      hasServerReceipt: false,
    );
    service.prepareUpload(draft, expectedGeneration: service.sessionGeneration);
    await service.cancelStory(draft.id);
    expect(service.items, isEmpty);
    await expectLater(
      service.runTrackedUpload<String>(
        draft: draft,
        expectedGeneration: service.sessionGeneration,
        send: (_) async {
          sent = true;
          return 'server';
        },
        receiptId: (id) => id,
      ),
      throwsA(isA<PublicMediaUploadCancelled>()),
    );
    expect(sent, false);
    service.clear();
  });

  test('a late successful receipt cannot restore a cancelled story', () async {
    final receipt = Completer<String>();
    final started = Completer<void>();
    var decisions = 0;
    final service = PendingPublicMediaService.forTest(
      publishedLookup: (_) async => true,
      moderationLookup: (_) async {
        decisions++;
        return const MediaModerationSnapshot(status: 'APPROVED');
      },
      delay: (_) => Completer<void>().future,
      cancelStory: (_) async {},
    );
    final draft = PendingPublicMedia(
      id: 'upload-2-2',
      kind: PendingPublicMediaKind.personalStory,
      venueId: 'venue',
      checkinId: 'checkin',
      localPath: '',
      isVideo: false,
      createdAt: DateTime.now(),
      hasServerReceipt: false,
    );
    final upload = service.runTrackedUpload<String>(
      draft: draft,
      expectedGeneration: service.sessionGeneration,
      send: (_) {
        started.complete();
        return receipt.future;
      },
      receiptId: (id) => id,
    );
    final outcome = expectLater(
      upload,
      throwsA(isA<PublicMediaUploadCancelled>()),
    );
    await started.future;
    await service.cancelStory(draft.id);
    receipt.complete('server-story');
    await outcome;
    expect(service.items, isEmpty);
    expect(service.wasPublished('server-story'), false);
    expect(decisions, 0);
    service.clear();
  });

  test(
    'failed cancellation keeps the preview and allows another attempt',
    () async {
      var fail = true;
      final service = PendingPublicMediaService.forTest(
        publishedLookup: (_) async => false,
        moderationLookup: (_) => Completer<MediaModerationSnapshot>().future,
        delay: (_) => Completer<void>().future,
        cancelStory: (_) async {
          if (fail) throw StateError('offline');
        },
      );
      service.track(_item('server'));
      await expectLater(service.cancelStory('server'), throwsStateError);
      expect(service.byId('server'), isNotNull);
      expect(service.isCancellingStory('server'), false);
      fail = false;
      await service.cancelStory('server');
      expect(service.items, isEmpty);
      service.clear();
    },
  );

  test(
    'cancellation during a publication read cannot mark the story shared',
    () async {
      final publication = Completer<bool>();
      final cancelling = Completer<void>();
      final service = PendingPublicMediaService.forTest(
        publishedLookup: (_) => publication.future,
        moderationLookup: (_) async =>
            const MediaModerationSnapshot(status: 'APPROVED'),
        delay: (_) => Completer<void>().future,
        cancelStory: (_) => cancelling.future,
      );
      service.track(_item('server'));
      await _flush();
      final cancel = service.cancelStory('server');
      publication.complete(true);
      await _flush();
      expect(service.wasPublished('server'), false);
      cancelling.complete();
      await cancel;
      expect(service.items, isEmpty);
      service.clear();
    },
  );

  test(
    'pending decisions skip heavy public feeds; approval still confirms visibility',
    () async {
      var status = 'PROCESSING';
      var publicReads = 0;
      final waits = <Completer<void>>[];
      final service = PendingPublicMediaService.forTest(
        publishedLookup: (_) async {
          publicReads++;
          return true;
        },
        moderationLookup: (_) async => MediaModerationSnapshot(status: status),
        delay: (_) {
          final wait = Completer<void>();
          waits.add(wait);
          return wait.future;
        },
      );
      service.track(_item('decision-first'));
      await _flush();
      expect(publicReads, 0);
      expect(service.wasPublished('decision-first'), false);
      status = 'NEEDS_REVIEW';
      waits.last.complete();
      await _flush();
      expect(publicReads, 0);
      status = 'APPROVED';
      waits.last.complete();
      await _flush();
      expect(publicReads, 1);
      expect(service.wasPublished('decision-first'), true);
      service.clear();
    },
  );

  test('rejection never queries or trusts an older public feed', () async {
    var publicReads = 0;
    final service = PendingPublicMediaService.forTest(
      publishedLookup: (_) async {
        publicReads++;
        return true;
      },
      moderationLookup: (_) async =>
          const MediaModerationSnapshot(status: 'REJECTED'),
      delay: (_) async {},
    );
    service.track(_item('rejected-decision'));
    await _flush();
    expect(publicReads, 0);
    expect(
      service.byId('rejected-decision')?.state,
      PendingPublicMediaState.rejected,
    );
    expect(service.wasPublished('rejected-decision'), false);
    service.clear();
  });

  test(
    'upload stays owner-only until public endpoint confirms approval',
    () async {
      var published = false;
      final delay = Completer<void>();
      final service = PendingPublicMediaService.forTest(
        publishedLookup: (_) async => published,
        moderationLookup: (_) async =>
            const MediaModerationSnapshot(status: 'APPROVED'),
        delay: (_) => delay.future,
      );
      final before = StoryRepository.changes.value;

      service.track(_item('story-1'));
      await _flush();
      expect(
        service.latest(PendingPublicMediaKind.personalStory)?.state,
        PendingPublicMediaState.publishing,
      );
      expect(StoryRepository.changes.value, before);

      published = true;
      delay.complete();
      await _flush();
      expect(service.latest(PendingPublicMediaKind.personalStory), isNull);
      expect(StoryRepository.changes.value, before + 1);
      expect(service.wasPublished('story-1'), isTrue);
      service.clear();
    },
  );

  test('rejected upload keeps only an inline reason until dismissed', () async {
    final service = PendingPublicMediaService.forTest(
      publishedLookup: (_) async => false,
      moderationLookup: (_) async => const MediaModerationSnapshot(
        status: 'REJECTED',
        message: 'This image contains disallowed text.',
      ),
      delay: (_) async {},
    );
    service.track(_item('story-2'));
    await _flush();

    final rejected = service.latest(PendingPublicMediaKind.personalStory);
    expect(rejected?.state, PendingPublicMediaState.rejected);
    expect(rejected?.message, 'This image contains disallowed text.');
    service.dismiss('story-2');
    expect(service.wasPublished('story-2'), isFalse);
    expect(service.latest(PendingPublicMediaKind.personalStory), isNull);
  });

  test(
    'session clear removes previews and stops old publication watcher',
    () async {
      final delay = Completer<void>();
      final service = PendingPublicMediaService.forTest(
        publishedLookup: (_) async => false,
        moderationLookup: (_) async =>
            const MediaModerationSnapshot(status: 'PENDING'),
        delay: (_) => delay.future,
      );
      service.track(_item('story-3'));
      await _flush();
      service.clear();
      delay.complete();
      await _flush();
      expect(service.forKind(PendingPublicMediaKind.personalStory), isEmpty);
    },
  );

  test('approved Moment publishes a profile refresh signal', () async {
    final service = PendingPublicMediaService.forTest(
      publishedLookup: (_) async => true,
      moderationLookup: (_) async => const MediaModerationSnapshot(),
      delay: (_) async {},
    );
    final before = service.publicationChanges.value;
    service.track(
      PendingPublicMedia(
        id: 'moment-1',
        kind: PendingPublicMediaKind.checkinMoment,
        venueId: 'venue-1',
        checkinId: 'checkin-1',
        localPath: '/tmp/owner-moment.jpg',
        isVideo: false,
        createdAt: DateTime(2026, 9, 30),
      ),
    );
    await _flush();
    expect(service.publicationChanges.value, before + 1);
    expect(service.forKind(PendingPublicMediaKind.checkinMoment), isEmpty);
    service.clear();
  });

  test('provider failure stays unpublished and offers retry', () async {
    final service = PendingPublicMediaService.forTest(
      publishedLookup: (_) async => false,
      moderationLookup: (_) async =>
          const MediaModerationSnapshot(status: 'ERROR'),
      delay: (_) async {},
    );
    service.track(_item('story-error'));
    await _flush();
    expect(
      service.latest(PendingPublicMediaKind.personalStory)?.state,
      PendingPublicMediaState.failed,
    );
    service.clear();
  });

  test(
    'approved Moment keeps its owner preview during profile handover',
    () async {
      final handover = Completer<void>();
      final service = PendingPublicMediaService.forTest(
        publishedLookup: (_) async => true,
        moderationLookup: (_) async => const MediaModerationSnapshot(),
        delay: (duration) {
          expect(duration, const Duration(seconds: 10));
          return handover.future;
        },
      );
      final before = service.publicationChanges.value;
      service.track(
        PendingPublicMedia(
          id: 'handover-moment',
          kind: PendingPublicMediaKind.checkinMoment,
          venueId: 'venue-1',
          checkinId: 'checkin-1',
          localPath: '/tmp/owner-moment.jpg',
          isVideo: false,
          createdAt: DateTime(2026, 10, 1),
        ),
      );
      await _flush();
      expect(
        service.byId('handover-moment')?.state,
        PendingPublicMediaState.published,
      );
      expect(service.publicationChanges.value, before + 1);
      handover.complete();
      await _flush();
      expect(service.byId('handover-moment'), isNull);
      expect(service.wasPublished('handover-moment'), true);
      service.clear();
    },
  );

  test('slow pending upload becomes delayed, never manual review', () async {
    var now = DateTime(2026, 10, 1, 12);
    final waits = <Completer<void>>[];
    final service = PendingPublicMediaService.forTest(
      publishedLookup: (_) async => false,
      moderationLookup: (_) async =>
          const MediaModerationSnapshot(status: 'PROCESSING'),
      now: () => now,
      delay: (_) {
        final wait = Completer<void>();
        waits.add(wait);
        return wait.future;
      },
    );
    service.track(_item('slow-story'));
    await _flush();
    expect(service.byId('slow-story')?.state, PendingPublicMediaState.checking);
    now = now.add(const Duration(minutes: 1));
    waits.last.complete();
    await _flush();
    expect(service.byId('slow-story')?.state, PendingPublicMediaState.delayed);
    expect(service.wasPublished('slow-story'), isFalse);
    service.clear();
    waits.last.complete();
    await _flush();
  });

  test(
    'gallery, Moment and both story videos promptly discover minute-long approvals',
    () async {
      for (final kind in [
        PendingPublicMediaKind.venueGallery,
        PendingPublicMediaKind.checkinMoment,
        PendingPublicMediaKind.personalStory,
        PendingPublicMediaKind.venueStory,
      ]) {
        var now = DateTime(2026, 10, 2, 12);
        var status = 'PROCESSING';
        var publicReads = 0;
        final waits = <Completer<void>>[];
        final intervals = <Duration>[];
        final service = PendingPublicMediaService.forTest(
          publishedLookup: (_) async {
            publicReads++;
            return true;
          },
          moderationLookup: (_) async =>
              MediaModerationSnapshot(status: status),
          now: () => now,
          delay: (duration) {
            intervals.add(duration);
            final wait = Completer<void>();
            waits.add(wait);
            return wait.future;
          },
        );
        service.track(
          PendingPublicMedia(
            id: 'video-${kind.name}',
            kind: kind,
            venueId: 'venue-1',
            checkinId: 'checkin-1',
            localPath: '/tmp/owner-video.mp4',
            isVideo: true,
            createdAt: now,
          ),
        );
        await _flush();
        now = now.add(const Duration(seconds: 60));
        waits.last.complete();
        await _flush();
        expect(
          service.byId('video-${kind.name}')?.state,
          PendingPublicMediaState.checking,
        );
        expect(intervals.last, const Duration(seconds: 2));
        expect(publicReads, 0);
        status = 'APPROVED';
        waits.last.complete();
        await _flush();
        expect(service.wasPublished('video-${kind.name}'), true);
        expect(publicReads, 1);
        service.clear();
        for (final wait in waits.where((wait) => !wait.isCompleted)) {
          wait.complete();
        }
        await _flush();
      }
    },
  );

  test(
    'connection interruption recovers without rejecting the upload',
    () async {
      var offline = true;
      final waits = <Completer<void>>[];
      final service = PendingPublicMediaService.forTest(
        publishedLookup: (_) async {
          if (offline) throw StateError('offline');
          return false;
        },
        moderationLookup: (_) async {
          if (offline) throw StateError('offline');
          return const MediaModerationSnapshot(status: 'PROCESSING');
        },
        delay: (_) {
          final wait = Completer<void>();
          waits.add(wait);
          return wait.future;
        },
      );
      service.track(_item('offline-story'));
      await _flush();
      expect(
        service.byId('offline-story')?.state,
        PendingPublicMediaState.connectionIssue,
      );
      offline = false;
      waits.last.complete();
      await _flush();
      expect(
        service.byId('offline-story')?.state,
        PendingPublicMediaState.checking,
      );
      service.clear();
      waits.last.complete();
      await _flush();
    },
  );

  test(
    'technical review can recover through admin approval and publication',
    () async {
      var decision = const MediaModerationSnapshot(
        status: 'NEEDS_REVIEW',
        processingIssue: true,
      );
      var published = false;
      final waits = <Completer<void>>[];
      final service = PendingPublicMediaService.forTest(
        publishedLookup: (_) async => published,
        moderationLookup: (_) async => decision,
        delay: (_) {
          final wait = Completer<void>();
          waits.add(wait);
          return wait.future;
        },
      );
      service.track(_item('technical-story'));
      await _flush();
      expect(
        service.byId('technical-story')?.state,
        PendingPublicMediaState.underReview,
      );
      decision = const MediaModerationSnapshot(status: 'APPROVED');
      waits.last.complete();
      await _flush();
      expect(
        service.byId('technical-story')?.state,
        PendingPublicMediaState.publishing,
      );
      expect(service.wasPublished('technical-story'), isFalse);
      published = true;
      waits.last.complete();
      await _flush();
      expect(service.byId('technical-story'), isNull);
      expect(service.wasPublished('technical-story'), isTrue);
      service.clear();
      expect(service.wasPublished('technical-story'), isFalse);
    },
  );

  test(
    'venue story and gallery stay scoped to their venue until approval',
    () async {
      final published = <String>{};
      final waits = <Completer<void>>[];
      final service = PendingPublicMediaService.forTest(
        publishedLookup: (item) async => published.contains(item.id),
        moderationLookup: (item) async => MediaModerationSnapshot(
          status: published.contains(item.id) ? 'APPROVED' : 'PENDING',
        ),
        delay: (_) {
          final wait = Completer<void>();
          waits.add(wait);
          return wait.future;
        },
      );
      final storyBefore = VenueStoryRepository.changes.value;
      final galleryBefore = VenueGalleryRepository.changes.value;

      service.track(
        PendingPublicMedia(
          id: 'venue-story-1',
          kind: PendingPublicMediaKind.venueStory,
          venueId: 'venue-a',
          localPath: '/tmp/venue-story.jpg',
          isVideo: false,
          createdAt: DateTime(2026, 9, 30),
        ),
      );
      service.track(
        PendingPublicMedia(
          id: 'gallery-1',
          kind: PendingPublicMediaKind.venueGallery,
          venueId: 'venue-b',
          localPath: '/tmp/gallery.jpg',
          isVideo: false,
          createdAt: DateTime(2026, 9, 30),
        ),
      );
      await _flush();
      expect(
        service.forKind(PendingPublicMediaKind.venueStory, venueId: 'venue-b'),
        isEmpty,
      );
      expect(
        service.forKind(
          PendingPublicMediaKind.venueGallery,
          venueId: 'venue-a',
        ),
        isEmpty,
      );

      published.add('venue-story-1');
      for (final wait in List<Completer<void>>.of(waits)) {
        wait.complete();
      }
      await _flush();
      expect(
        service.forKind(PendingPublicMediaKind.venueStory, venueId: 'venue-a'),
        isEmpty,
      );
      expect(
        service.forKind(
          PendingPublicMediaKind.venueGallery,
          venueId: 'venue-b',
        ),
        hasLength(1),
      );
      expect(VenueStoryRepository.changes.value, storyBefore + 1);
      expect(VenueGalleryRepository.changes.value, galleryBefore);

      published.add('gallery-1');
      for (final wait in waits.where((wait) => !wait.isCompleted)) {
        wait.complete();
      }
      await _flush();
      expect(
        service.forKind(
          PendingPublicMediaKind.venueGallery,
          venueId: 'venue-b',
        ),
        isEmpty,
      );
      expect(VenueGalleryRepository.changes.value, galleryBefore + 1);
      service.clear();
    },
  );
}
