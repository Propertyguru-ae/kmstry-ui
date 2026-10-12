import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/stories/data/story_upload_coordinator.dart';
import 'package:kmstry_frontend/features/stories/data/story_upload_failure.dart';

PendingPublicMediaService _service({
  PublishedMediaLookup? published,
  ModerationLookup? moderation,
}) => PendingPublicMediaService.forTest(
  publishedLookup: published ?? (_) async => false,
  moderationLookup:
      moderation ??
      (_) async => const MediaModerationSnapshot(status: 'PENDING'),
  delay: (_) => Completer<void>().future,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final venueStory in [false, true]) {
    test(
      'queues ${venueStory ? "venue" : "personal"} video before preparation finishes',
      () async {
        final service = _service();
        final preparation = Completer<File>();
        final response = Completer<String>();
        final sent = Completer<void>();
        final directory = await Directory.systemTemp.createTemp(
          'story-upload-test-',
        );
        final file = await File(
          '${directory.path}/clip.mp4',
        ).writeAsBytes([1, 2, 3]);
        addTearDown(() async {
          service.clear();
          await directory.delete(recursive: true);
        });
        var sends = 0;
        final coordinator = StoryUploadCoordinator.forTest(
          service: service,
          prepareVideo: (_) => preparation.future,
          sender: (draft, prepared, session, overlay) async {
            sends++;
            expect(prepared.path, file.path);
            expect(draft.venueId, 'venue-1');
            expect(overlay, '{"text":"Hello Alpha"}');
            expect(draft.textOverlay?.text, 'Hello Alpha');
            await service.runTrackedUpload(
              draft: draft,
              expectedGeneration: session,
              send: (progress) {
                progress(1, 2);
                sent.complete();
                return response.future;
              },
              receiptId: (id) => id,
            );
          },
        );
        final upload = venueStory
            ? coordinator.shareVenue(
                file: file,
                venueId: 'venue-1',
                textOverlayJson: '{"text":"Hello Alpha"}',
              )
            : coordinator.sharePersonal(
                file: file,
                checkinId: 'checkin-1',
                venueId: 'venue-1',
                textOverlayJson: '{"text":"Hello Alpha"}',
              );
        expect(service.items.single.id, upload.id);
        expect(service.items.single.state, PendingPublicMediaState.preparing);
        expect(service.items.single.localPath, file.path);
        expect(sends, 0);
        preparation.complete(file);
        await sent.future;
        expect(service.items.single.state, PendingPublicMediaState.uploading);
        expect(service.items.single.progress, .5);
        expect(service.items.single.hasServerReceipt, false);
        response.complete('server-story');
        await upload.completed;
        expect(sends, 1);
        expect(service.items.single.id, 'server-story');
        expect(service.byId(upload.id)?.hasServerReceipt, true);
        expect(service.byId(upload.id)?.textOverlay?.text, 'Hello Alpha');
        expect(
          service.byId(upload.id)?.state,
          PendingPublicMediaState.checking,
        );
        expect(service.wasPublished(upload.id), false);
      },
    );
  }

  test(
    'photo adopts one prepared job and retains the same local preview',
    () async {
      final service = _service();
      addTearDown(service.clear);
      final coordinator = StoryUploadCoordinator.forTest(
        service: service,
        prepareVideo: (_) async =>
            throw StateError('Photos must not compress as video'),
        sender: (draft, file, session, _) async {
          await service.runTrackedUpload(
            draft: draft,
            expectedGeneration: session,
            send: (_) async => 'photo-receipt',
            receiptId: (id) => id,
          );
        },
      );
      final upload = coordinator.sharePersonal(
        file: File('/camera/photo.jpg'),
        checkinId: 'checkin-1',
        venueId: 'venue-1',
      );
      await upload.completed;
      await service.flushPersistence();
      expect(service.items, hasLength(1));
      expect(service.byId(upload.id)?.previewPath, '/camera/photo.jpg');
    },
  );

  test(
    'video preparation error becomes an inline failure, not an unhandled future',
    () async {
      final service = _service();
      addTearDown(service.clear);
      var sends = 0;
      final coordinator = StoryUploadCoordinator.forTest(
        service: service,
        prepareVideo: (_) async =>
            throw StateError('Video must be 60 seconds or shorter'),
        sender: (_, _, _, _) async {
          sends++;
        },
      );
      final upload = coordinator.shareVenue(
        file: File('/camera/clip.mp4'),
        venueId: 'venue-1',
      );
      await upload.completed;
      expect(sends, 0);
      expect(service.byId(upload.id)?.state, PendingPublicMediaState.failed);
      expect(
        service.byId(upload.id)?.message,
        contains('60 seconds or shorter'),
      );
    },
  );

  test(
    'logout during preparation cannot send or restore the old preview',
    () async {
      final service = _service();
      final preparation = Completer<File>();
      var sends = 0;
      final coordinator = StoryUploadCoordinator.forTest(
        service: service,
        prepareVideo: (_) => preparation.future,
        sender: (_, _, _, _) async {
          sends++;
        },
      );
      final upload = coordinator.shareVenue(
        file: File('/camera/clip.mp4'),
        venueId: 'venue-1',
      );
      service.clear();
      preparation.complete(File('/camera/clip.mp4'));
      await upload.completed;
      expect(sends, 0);
      expect(service.items, isEmpty);
    },
  );

  test(
    'ambiguous network result is not relabelled failed or automatically replayed',
    () async {
      final service = _service();
      addTearDown(service.clear);
      var sends = 0;
      final coordinator = StoryUploadCoordinator.forTest(
        service: service,
        prepareVideo: (file) async => file,
        sender: (draft, _, session, _) async {
          await service.runTrackedUpload<String>(
            draft: draft,
            expectedGeneration: session,
            send: (_) async {
              sends++;
              throw const SocketException('Disconnected');
            },
            receiptId: (id) => id,
          );
        },
      );
      final upload = coordinator.shareVenue(
        file: File('/camera/photo.jpg'),
        venueId: 'venue-1',
      );
      await upload.completed;
      expect(sends, 1);
      expect(
        service.byId(upload.id)?.state,
        PendingPublicMediaState.connectionIssue,
      );
      expect(service.byId(upload.id)?.message, contains('could not confirm'));
    },
  );

  test(
    'definite server rejection uses a safe actionable explanation',
    () async {
      final service = _service();
      addTearDown(service.clear);
      final coordinator = StoryUploadCoordinator.forTest(
        service: service,
        prepareVideo: (file) async => file,
        sender: (draft, _, session, _) async {
          await service.runTrackedUpload<String>(
            draft: draft,
            expectedGeneration: session,
            send: (_) async => throw const PublicMediaUploadRejected(
              'ANONYMOUS_STORY_BLOCKED',
            ),
            receiptId: (id) => id,
          );
        },
      );
      final upload = coordinator.sharePersonal(
        file: File('/camera/photo.jpg'),
        checkinId: 'checkin-1',
      );
      await upload.completed;
      expect(service.byId(upload.id)?.state, PendingPublicMediaState.failed);
      expect(
        service.byId(upload.id)?.message,
        'Turn off Anonymous Mode to share a story.',
      );
    },
  );

  test(
    'HTTP failure keeps its actionable reason in the owner preview',
    () async {
      final service = _service();
      addTearDown(service.clear);
      final coordinator = StoryUploadCoordinator.forTest(
        service: service,
        prepareVideo: (file) async => file,
        sender: (draft, _, session, _) async {
          await service.runTrackedUpload<String>(
            draft: draft,
            expectedGeneration: session,
            send: (_) async => throw StoryUploadFailure.fromResponse(
              401,
              '{"message":"Unauthorized"}',
            ),
            receiptId: (id) => id,
          );
        },
      );
      final upload = coordinator.sharePersonal(
        file: File('/camera/photo.jpg'),
        checkinId: 'checkin-1',
      );
      await upload.completed;
      expect(service.byId(upload.id)?.state, PendingPublicMediaState.failed);
      expect(service.byId(upload.id)?.message, contains('session expired'));
    },
  );

  test(
    'successful next story does not erase the earlier rejection reason',
    () async {
      final service = _service(
        published: (item) async => item.id == 'published-story',
        moderation: (item) async => MediaModerationSnapshot(
          status: item.id == 'published-story' ? 'APPROVED' : 'REJECTED',
        ),
      );
      addTearDown(service.clear);
      service.track(
        PendingPublicMedia(
          id: 'rejected-story',
          kind: PendingPublicMediaKind.personalStory,
          venueId: 'venue-1',
          localPath: '',
          isVideo: false,
          createdAt: DateTime.now(),
          state: PendingPublicMediaState.rejected,
          message: 'Disallowed text',
        ),
      );
      final coordinator = StoryUploadCoordinator.forTest(
        service: service,
        prepareVideo: (file) async => file,
        sender: (draft, _, session, _) async {
          await service.runTrackedUpload<String>(
            draft: draft,
            expectedGeneration: session,
            send: (_) async => 'published-story',
            receiptId: (id) => id,
          );
        },
      );
      final upload = coordinator.sharePersonal(
        file: File('/camera/photo.jpg'),
        checkinId: 'checkin-1',
      );
      await upload.completed;
      await Future<void>.delayed(Duration.zero);
      expect(service.wasPublished(upload.id), true);
      expect(service.items.single.id, 'rejected-story');
      expect(service.items.single.message, 'Disallowed text');
    },
  );
}
