import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/content_moderation/data/avatar_upload_coordinator.dart';
import 'package:kmstry_frontend/features/content_moderation/data/content_moderation_item.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';

class _LargePhoto extends Fake implements File {
  @override
  Future<int> length() async => 10 * 1024 * 1024 + 1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File photo;
  late PendingPublicMediaService service;
  var sends = 0;
  Future<void> flush() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
      await service.flushPersistence();
    }
  }

  PendingPublicMedia item(
    String id, {
    PendingPublicMediaKind kind = PendingPublicMediaKind.personalAvatar,
    String? venue,
  }) => PendingPublicMedia(
    id: id,
    kind: kind,
    venueId: venue,
    localPath: photo.path,
    isVideo: false,
    createdAt: DateTime.now(),
  );
  PendingPublicMediaService watch(
    MediaModerationSnapshot snapshot, {
    Future<void> Function(Duration)? delay,
  }) => PendingPublicMediaService.forTest(
    publishedLookup: (_) async =>
        throw StateError('Avatar must use its exact receipt'),
    moderationLookup: (_) async => snapshot,
    delay: delay ?? (_) => Completer<void>().future,
  );
  AvatarUploadCoordinator queue({
    Future<File> Function(File)? prepare,
    Future<String> Function()? response,
  }) => AvatarUploadCoordinator.forTest(
    service: service,
    prepare: prepare ?? (f) async => f,
    sender: (draft, file, generation) async {
      await service.runTrackedUpload<String>(
        draft: draft,
        expectedGeneration: generation,
        send: (progress) async {
          sends++;
          progress(1, 2);
          return response == null ? 'receipt-$sends' : await response();
        },
        receiptId: (id) => id,
      );
    },
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('avatar-upload-test-');
    photo = await File('${directory.path}/photo.jpg').writeAsBytes([1, 2, 3]);
    service = watch(
      const MediaModerationSnapshot(
        status: 'PENDING',
        photoPublication: 'WAITING',
      ),
    );
    sends = 0;
  });
  tearDown(() async {
    service.clear();
    await service.flushPersistence();
    await directory.delete(recursive: true);
  });

  test(
    'preview appears before preparation, duplicate selection cannot upload',
    () async {
      final prepare = Completer<File>();
      final uploader = queue(prepare: (_) => prepare.future);
      final generation = service.sessionGeneration;
      final upload = uploader.share(
        file: photo,
        kind: PendingPublicMediaKind.personalAvatar,
        expectedGeneration: generation,
      )!;
      expect(service.byId(upload.id)?.state, PendingPublicMediaState.preparing);
      expect(service.byId(upload.id)?.localPath, photo.path);
      expect(sends, 0);
      expect(
        uploader.share(
          file: photo,
          kind: PendingPublicMediaKind.personalAvatar,
          expectedGeneration: generation,
        ),
        isNull,
      );
      prepare.complete(photo);
      await upload.completed;
      expect(sends, 1);
      expect(service.byId(upload.id)?.id, 'receipt-1');
      expect(service.byId(upload.id)?.hasServerReceipt, true);
    },
  );

  test('personal and different venue slots are independent', () async {
    final prepare = Completer<File>();
    final uploader = queue(prepare: (_) => prepare.future);
    final uploads = [
      uploader.share(
        file: photo,
        kind: PendingPublicMediaKind.personalAvatar,
        expectedGeneration: 0,
      )!,
      uploader.share(
        file: photo,
        kind: PendingPublicMediaKind.venueAvatar,
        venueId: 'alpha',
        expectedGeneration: 0,
      )!,
      uploader.share(
        file: photo,
        kind: PendingPublicMediaKind.venueAvatar,
        venueId: 'beta',
        expectedGeneration: 0,
      )!,
    ];
    expect(service.items, hasLength(3));
    expect(
      service
          .latest(PendingPublicMediaKind.venueAvatar, venueId: 'beta')
          ?.venueId,
      'beta',
    );
    prepare.complete(photo);
    await Future.wait(uploads.map((u) => u.completed));
    expect(sends, 3);
  });

  test(
    'logout during compression cannot send or restore an old preview',
    () async {
      final prepare = Completer<File>();
      final uploader = queue(prepare: (_) => prepare.future);
      final upload = uploader.share(
        file: photo,
        kind: PendingPublicMediaKind.personalAvatar,
        expectedGeneration: 0,
      )!;
      service.clear();
      prepare.complete(photo);
      await upload.completed;
      expect(sends, 0);
      expect(service.items, isEmpty);
      expect(
        uploader.share(
          file: photo,
          kind: PendingPublicMediaKind.personalAvatar,
          expectedGeneration: 0,
        ),
        isNull,
      );
    },
  );

  test(
    'ambiguous response is not retried and blocks a second replacement',
    () async {
      final uploader = queue(
        response: () async => throw const HttpException('connection lost'),
      );
      final upload = uploader.share(
        file: photo,
        kind: PendingPublicMediaKind.personalAvatar,
        expectedGeneration: 0,
      )!;
      await upload.completed;
      expect(
        service.byId(upload.id)?.state,
        PendingPublicMediaState.connectionIssue,
      );
      expect(uploader.canSelect(PendingPublicMediaKind.personalAvatar), false);
      expect(sends, 1);
    },
  );

  test('confirmed failure keeps only actionable inline state', () async {
    final uploader = queue(
      response: () async =>
          throw const PublicMediaUploadRejected('private server detail'),
    );
    final upload = uploader.share(
      file: photo,
      kind: PendingPublicMediaKind.personalAvatar,
      expectedGeneration: 0,
    )!;
    await upload.completed;
    expect(service.byId(upload.id)?.state, PendingPublicMediaState.failed);
    expect(
      service.byId(upload.id)?.message,
      isNot(contains('private server detail')),
    );
    expect(uploader.canSelect(PendingPublicMediaKind.personalAvatar), true);
  });

  test('photo over the backend limit fails before network send', () async {
    final uploader = queue(prepare: (_) async => _LargePhoto());
    final upload = uploader.share(
      file: photo,
      kind: PendingPublicMediaKind.personalAvatar,
      expectedGeneration: 0,
    )!;
    await upload.completed;
    expect(service.byId(upload.id)?.state, PendingPublicMediaState.failed);
    expect(sends, 0);
  });

  test(
    'new selection replaces only this slot tracking, not other venue uploads',
    () async {
      service.track(
        item(
          'old-alpha',
          kind: PendingPublicMediaKind.venueAvatar,
          venue: 'alpha',
        ),
      );
      service.track(
        item(
          'old-beta',
          kind: PendingPublicMediaKind.venueAvatar,
          venue: 'beta',
        ),
      );
      final upload = queue().share(
        file: photo,
        kind: PendingPublicMediaKind.venueAvatar,
        venueId: 'alpha',
        expectedGeneration: 0,
      )!;
      expect(service.byId('old-alpha'), isNull);
      expect(service.byId('old-beta'), isNotNull);
      await upload.completed;
    },
  );

  test('invalid target and unresolved venue cannot start an upload', () {
    final uploader = queue();
    expect(
      () => uploader.share(
        file: photo,
        kind: PendingPublicMediaKind.venueAvatar,
        expectedGeneration: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => uploader.share(
        file: photo,
        kind: PendingPublicMediaKind.personalStory,
        expectedGeneration: 0,
      ),
      throwsArgumentError,
    );
    expect(service.items, isEmpty);
  });

  for (final kind in [
    PendingPublicMediaKind.personalAvatar,
    PendingPublicMediaKind.venueAvatar,
  ]) {
    test(
      '$kind approval without canonical publication is not completion',
      () async {
        service = watch(
          const MediaModerationSnapshot(
            status: 'APPROVED',
            photoPublication: 'WAITING',
          ),
        );
        service.track(item('candidate', kind: kind, venue: 'alpha'));
        await flush();
        expect(
          service.byId('candidate')?.state,
          PendingPublicMediaState.publishing,
        );
        expect(service.avatarPublicationChanges.value, 0);
        expect(service.wasPublished('candidate'), false);
      },
    );
  }

  test(
    'published photo signals refresh, then releases its handover preview',
    () async {
      final handover = Completer<void>();
      service = watch(
        const MediaModerationSnapshot(
          status: 'APPROVED',
          photoPublication: 'PUBLISHED',
        ),
        delay: (duration) {
          expect(duration, const Duration(seconds: 10));
          return handover.future;
        },
      );
      service.track(item('approved'));
      await flush();
      expect(
        service.byId('approved')?.state,
        PendingPublicMediaState.published,
      );
      expect(service.avatarPublicationChanges.value, 1);
      expect(service.wasPublished('approved'), true);
      handover.complete();
      await flush();
      expect(service.byId('approved'), isNull);
    },
  );

  test(
    'rejection remains the explanation even after pointer is cleared',
    () async {
      service = watch(
        const MediaModerationSnapshot(
          status: 'REJECTED',
          photoPublication: 'SUPERSEDED',
          message: 'Text policy',
        ),
      );
      service.track(item('rejected'));
      await flush();
      expect(service.byId('rejected')?.state, PendingPublicMediaState.rejected);
      expect(service.byId('rejected')?.message, 'Text policy');
      expect(service.avatarPublicationChanges.value, 0);
    },
  );

  test('superseded approval cannot replace a newer choice', () async {
    final nextPoll = Completer<void>();
    service = watch(
      const MediaModerationSnapshot(
        status: 'APPROVED',
        photoPublication: 'SUPERSEDED',
      ),
      delay: (_) => nextPoll.future,
    );
    service.track(item('older'));
    await flush();
    expect(service.byId('older')?.state, PendingPublicMediaState.publishing);
    expect(service.avatarPublicationChanges.value, 0);
    expect(service.wasPublished('older'), false);
    nextPoll.complete();
    await flush();
    expect(service.byId('older'), isNull);
    expect(service.avatarPublicationChanges.value, 1);
    expect(service.wasPublished('older'), false);
  });

  for (final kind in [
    PendingPublicMediaKind.personalAvatar,
    PendingPublicMediaKind.venueAvatar,
  ]) {
    for (final status in ['PROCESSING', 'APPROVED']) {
      test(
        '$kind recovers from a transient $status / SUPERSEDED response',
        () async {
          final nextPoll = Completer<void>();
          var reads = 0;
          service = PendingPublicMediaService.forTest(
            publishedLookup: (_) async =>
                throw StateError('Exact receipt required'),
            moderationLookup: (_) async => ++reads == 1
                ? MediaModerationSnapshot(
                    status: status,
                    photoPublication: 'SUPERSEDED',
                  )
                : const MediaModerationSnapshot(
                    status: 'APPROVED',
                    photoPublication: 'PUBLISHED',
                  ),
            delay: (duration) => duration == const Duration(seconds: 10)
                ? Completer<void>().future
                : nextPoll.future,
          );
          service.track(item('handover', kind: kind, venue: 'alpha'));
          await flush();
          expect(
            service.byId('handover')?.state,
            isNot(PendingPublicMediaState.cancelled),
          );
          expect(service.wasPublished('handover'), false);
          nextPoll.complete();
          await flush();
          expect(reads, 2);
          expect(
            service.byId('handover')?.state,
            PendingPublicMediaState.published,
          );
          expect(service.avatarPublicationChanges.value, 1);
          expect(service.wasPublished('handover'), true);
        },
      );
    }
  }

  for (final missing in [false, true]) {
    test(
      'cached superseded response is not confirmed by ${missing ? 'missing status' : 'failed read'}',
      () async {
        final polls = <Completer<void>>[];
        var reads = 0;
        service = PendingPublicMediaService.forTest(
          publishedLookup: (_) async =>
              throw StateError('Exact receipt required'),
          moderationLookup: (_) async {
            reads++;
            if (reads == 2) {
              if (missing) return const MediaModerationSnapshot();
              throw StateError('Temporary network failure');
            }
            return const MediaModerationSnapshot(
              status: 'APPROVED',
              photoPublication: 'SUPERSEDED',
            );
          },
          delay: (_) {
            final poll = Completer<void>();
            polls.add(poll);
            return poll.future;
          },
        );
        service.track(item('obsolete'));
        await flush();
        polls[0].complete();
        await flush();
        expect(service.byId('obsolete'), isNotNull);
        expect(service.avatarPublicationChanges.value, 0);
        polls[1].complete();
        await flush();
        expect(service.byId('obsolete'), isNotNull);
        polls[2].complete();
        await flush();
        expect(service.byId('obsolete'), isNull);
        expect(service.wasPublished('obsolete'), false);
      },
    );
  }

  test('late avatar approval cannot refresh or publish after logout', () async {
    final decision = Completer<MediaModerationSnapshot>();
    service = PendingPublicMediaService.forTest(
      publishedLookup: (_) async => throw StateError('Exact receipt required'),
      moderationLookup: (_) => decision.future,
      delay: (_) => Completer<void>().future,
    );
    service.track(item('old-session'));
    await flush();
    service.clear();
    decision.complete(
      const MediaModerationSnapshot(
        status: 'APPROVED',
        photoPublication: 'PUBLISHED',
      ),
    );
    await flush();
    expect(service.items, isEmpty);
    expect(service.avatarPublicationChanges.value, 0);
    expect(service.wasPublished('old-session'), false);
  });

  test('owner API publication proof survives JSON parsing', () {
    final row = ContentModerationItem.fromJson({
      'id': 'receipt',
      'target_type': 'USER_PROFILE_PHOTO',
      'status': 'APPROVED',
      'photo_publication': 'PUBLISHED',
    });
    expect(row.moderationSnapshot.photoPublication, 'PUBLISHED');
  });
}
