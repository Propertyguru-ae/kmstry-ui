import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/venue_events/data/event_photo_upload_coordinator.dart';

class OversizedEventPhoto extends Fake implements File {
  @override
  Future<int> length() async => 20 * 1024 * 1024 + 1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PendingPublicMediaService service;
  setUp(() {
    service = PendingPublicMediaService.forTest(
      publishedLookup: (_) async =>
          throw StateError('Event photos use exact receipts, not public feeds'),
      moderationLookup: (_) async => const MediaModerationSnapshot(
        status: 'PENDING',
        photoPublication: 'WAITING',
      ),
      delay: (_) => Completer<void>().future,
    );
  });
  tearDown(() => service.clear());
  final file = File('assets/images/kmstrylogo.png');
  Future<void> flush() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  EventPhotoUploadCoordinator coordinator({
    Future<File> Function(File)? prepare,
    EventPhotoSender? sender,
  }) => EventPhotoUploadCoordinator.forTest(
    service: service,
    prepare: prepare ?? (file) async => file,
    sender:
        sender ??
        (draft, file, session) async {
          await service.runTrackedUpload(
            draft: draft,
            expectedGeneration: session,
            send: (progress) async {
              progress(1, 2);
              return 'review-${draft.id}';
            },
            receiptId: (id) => id,
          );
        },
  );

  test(
    'enqueue returns immediately with owner preview and follows an exact receipt',
    () async {
      final prepared = Completer<File>();
      final upload = coordinator(prepare: (_) => prepared.future).share(
        venueId: 'venue-a',
        eventId: 'event-a',
        files: [file],
        expectedGeneration: service.sessionGeneration,
      );
      expect(upload.ids, hasLength(1));
      expect(service.items.single.state, PendingPublicMediaState.preparing);
      expect(service.items.single.eventId, 'event-a');
      prepared.complete(file);
      await upload.completed;
      final item = service.byId(upload.ids.single)!;
      expect(item.id, startsWith('review-'));
      expect(item.uploadId, upload.ids.single);
      expect(item.usesExactReceipt, true);
      expect(item.targetType, 'EVENT_PHOTO');
      expect(item.previewPath, file.path);
      expect(item.eventId, 'event-a');
      expect(item.state, PendingPublicMediaState.checking);
      expect(service.wasPublished(item.id), false);
    },
  );

  test('oversized event photo fails locally without a server transfer', () async {
    var sends = 0;
    final upload = coordinator(prepare: (_) async => OversizedEventPhoto(), sender: (_, _, _) async => sends++)
      .share(venueId: 'venue-a', eventId: 'event-a', files: [file], expectedGeneration: service.sessionGeneration);
    await upload.completed;
    expect(sends, 0);
    expect(service.items.single.state, PendingPublicMediaState.failed);
    expect(service.items.single.hasServerReceipt, false);
  });

  test(
    'series context survives progress, receipt adoption and persistence',
    () async {
      final upload = coordinator().share(
        venueId: 'venue-a',
        recurringRuleId: 'series-a',
        files: [file, file],
        expectedGeneration: service.sessionGeneration,
      );
      await upload.completed;
      expect(upload.ids, hasLength(1));
      final item = PendingPublicMedia.fromJson(
        service.items.single
            .withState(PendingPublicMediaState.underReview)
            .toJson(),
      )!;
      expect(item.recurringRuleId, 'series-a');
      expect(item.eventId, isNull);
      expect(
        item.belongsToEvent('venue-a', 'occurrence-one', 'series-a'),
        true,
      );
      expect(
        item.belongsToEvent('venue-a', 'occurrence-two', 'series-a'),
        true,
      );
      expect(
        item.belongsToEvent('venue-b', 'occurrence-one', 'series-a'),
        false,
      );
      expect(
        item.belongsToEvent('venue-a', 'event-other', 'series-other'),
        false,
      );
    },
  );

  test(
    'same event uploads are ordered while another event can proceed',
    () async {
      final release = Completer<void>();
      final firstEventStarted = Completer<void>();
      final otherEventStarted = Completer<void>();
      final sent = <String>[];
      final c = coordinator(
        sender: (draft, uploadedFile, session) async {
          sent.add(draft.eventId!);
          // Different events prepare files concurrently: either can arrive
          // first. Hold the first file of event one, not the first global send.
          if (draft.eventId == 'one' && uploadedFile.path == file.path) {
            firstEventStarted.complete();
            await release.future;
          } else if (draft.eventId == 'two') {
            otherEventStarted.complete();
          }
        },
      );
      final one = c.share(
        venueId: 'venue-a',
        eventId: 'one',
        files: [file, File('assets/images/logo.png')],
        expectedGeneration: service.sessionGeneration,
      );
      final two = c.share(
        venueId: 'venue-a',
        eventId: 'two',
        files: [file],
        expectedGeneration: service.sessionGeneration,
      );
      try {
        await Future.wait([
          firstEventStarted.future,
          otherEventStarted.future,
        ]).timeout(const Duration(seconds: 5));
        expect(sent, unorderedEquals(['one', 'two']));
      } finally {
        release.complete();
      }
      await Future.wait([one.completed, two.completed]);
      expect(sent, hasLength(3));
      expect(sent.last, 'one');
    },
  );

  test(
    'logout during preparation never sends a photo under a new account',
    () async {
      final prepared = Completer<File>();
      var sends = 0;
      final upload =
          coordinator(
            prepare: (_) => prepared.future,
            sender: (_, _, _) async => sends++,
          ).share(
            venueId: 'venue-a',
            eventId: 'event-a',
            files: [file],
            expectedGeneration: service.sessionGeneration,
          );
      service.clear();
      prepared.complete(file);
      await upload.completed;
      expect(sends, 0);
      expect(service.items, isEmpty);
    },
  );

  test(
    'uncertain transport is not replayed or falsely reported as a failed rejection',
    () async {
      var sends = 0;
      final upload =
          coordinator(
            sender: (draft, file, session) async {
              await service.runTrackedUpload(
                draft: draft,
                expectedGeneration: session,
                send: (_) async {
                  sends++;
                  throw const HttpException('Connection lost');
                },
                receiptId: (_) => 'never',
              );
            },
          ).share(
            venueId: 'venue-a',
            eventId: 'event-a',
            files: [file],
            expectedGeneration: service.sessionGeneration,
          );
      await upload.completed;
      expect(sends, 1);
      expect(
        service.items.single.state,
        PendingPublicMediaState.connectionIssue,
      );
      expect(service.items.single.hasServerReceipt, false);
    },
  );

  test(
    'missing receipt cannot fall back to an old approval for the same event',
    () async {
      final upload =
          coordinator(
            sender: (draft, file, session) async {
              await service.runTrackedUpload(
                draft: draft,
                expectedGeneration: session,
                send: (_) async => {'id': 'event-a'},
                receiptId: (json) => json['moderation_item_id'],
              );
            },
          ).share(
            venueId: 'venue-a',
            eventId: 'event-a',
            files: [file],
            expectedGeneration: service.sessionGeneration,
          );
      await upload.completed;
      expect(
        service.items.single.state,
        PendingPublicMediaState.connectionIssue,
      );
      expect(service.items.single.hasServerReceipt, false);
    },
  );

  for (final scenario in [
    ('APPROVED', 'WAITING', PendingPublicMediaState.publishing, 0),
    ('APPROVED', 'PUBLISHED', PendingPublicMediaState.published, 1),
    ('APPROVED', 'SUPERSEDED', PendingPublicMediaState.cancelled, 0),
    ('PENDING', 'WAITING', PendingPublicMediaState.checking, 0),
    ('REJECTED', 'SUPERSEDED', PendingPublicMediaState.rejected, 0),
    ('NEEDS_REVIEW', 'WAITING', PendingPublicMediaState.underReview, 0),
  ]) {
    test(
      'exact event receipt ${scenario.$1} / ${scenario.$2} is ${scenario.$3}',
      () async {
        final tracker = PendingPublicMediaService.forTest(
          publishedLookup: (_) async =>
              throw StateError('Must not look at other event photo approvals'),
          moderationLookup: (_) async => MediaModerationSnapshot(
            status: scenario.$1,
            photoPublication: scenario.$2,
          ),
          delay: (_) => Completer<void>().future,
        );
        tracker.track(
          PendingPublicMedia(
            id: 'review-one',
            kind: PendingPublicMediaKind.eventPhoto,
            venueId: 'venue-a',
            eventId: 'event-a',
            localPath: '',
            isVideo: false,
            createdAt: DateTime.now(),
          ),
        );
        await flush();
        expect(tracker.items.single.state, scenario.$3);
        expect(tracker.eventPublicationChanges.value, scenario.$4);
        tracker.clear();
      },
    );
  }
}
