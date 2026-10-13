import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/checkin/data/moment_upload_coordinator.dart';
import 'package:kmstry_frontend/features/checkin/data/moment_upload_failure.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late PendingPublicMediaService service;
  final sent = <String>[];
  final overlays = <String?>[];
  Future<File> file(String name) =>
      File('${temp.path}/$name').writeAsBytes([1, 2, 3]);
  Future<void> flush() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
      await service.flushPersistence();
    }
  }

  MomentUploadCoordinator uploader({
    Future<File> Function(File)? prepare,
    Future<Duration> Function(File)? duration,
    Future<String> Function(PendingPublicMedia)? response,
  }) => MomentUploadCoordinator.forTest(
    service: service,
    prepareVideo: prepare ?? (f) async => f,
    videoDuration: duration ?? (_) async => const Duration(seconds: 60),
    thumbnail: (_) async => null,
    sender: (draft, prepared, session, overlay) async {
      overlays.add(overlay);
      await service.runTrackedUpload<String>(
        draft: draft,
        expectedGeneration: session,
        send: (_) async {
          sent.add(draft.id);
          return response == null
              ? 'receipt-${draft.id}'
              : await response(draft);
        },
        receiptId: (id) => id,
      );
    },
  );
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('moment-upload-test-');
    sent.clear();
    overlays.clear();
    service = PendingPublicMediaService.forTest(
      publishedLookup: (_) async => false,
      moderationLookup: (_) async =>
          const MediaModerationSnapshot(status: 'PENDING'),
      delay: (_) => Completer<void>().future,
    );
  });
  tearDown(() async {
    service.clear();
    await service.flushPersistence();
    await temp.delete(recursive: true);
  });

  test(
    'instant owner preview, bounded transfers and no duplicate tap uploads',
    () async {
      final responses = <Completer<String>>[];
      final queue = uploader(
        response: (_) {
          final c = Completer<String>();
          responses.add(c);
          return c.future;
        },
      );
      final files = [
        await file('one.jpg'),
        await file('two.jpg'),
        await file('three.jpg'),
      ];
      final jobs = files
          .map(
            (f) => queue.share(
              file: f,
              checkinId: 'active',
              venueId: 'alpha',
              expectedGeneration: 0,
            )!,
          )
          .toList();
      expect(service.items, hasLength(3));
      expect(
        queue.share(
          file: files.first,
          checkinId: 'active',
          expectedGeneration: 0,
        ),
        isNull,
      );
      await flush();
      expect(sent, hasLength(2));
      responses[0].complete('one');
      await flush();
      expect(sent, hasLength(3));
      responses[1].complete('two');
      responses[2].complete('three');
      await Future.wait(jobs.map((j) => j.completed));
      expect(
        service.items.every(
          (i) => i.hasServerReceipt && i.checkinId == 'active',
        ),
        true,
      );
      expect(
        service.items.any((i) => i.state == PendingPublicMediaState.published),
        false,
      );
    },
  );
  test('a rejected extra does not discard another upload', () async {
    final queue = uploader(
      response: (draft) async {
        if (draft.localPath.endsWith('bad.jpg')) {
          throw const PublicMediaUploadRejected('not allowed');
        }
        return 'ok';
      },
    );
    final bad = queue.share(
      file: await file('bad.jpg'),
      checkinId: 'c',
      expectedGeneration: 0,
    )!;
    final good = queue.share(
      file: await file('good.jpg'),
      checkinId: 'c',
      expectedGeneration: 0,
    )!;
    await Future.wait([bad.completed, good.completed]);
    expect(service.byId(bad.id)?.state, PendingPublicMediaState.failed);
    expect(service.byId(good.id)?.id, 'ok');
  });
  test('ambiguous transfer is retained without automatic replay', () async {
    final queue = uploader(
      response: (_) async => throw const HttpException('lost reply'),
    );
    final photo = await file('photo.jpg');
    final job = queue.share(
      file: photo,
      checkinId: 'c',
      expectedGeneration: 0,
    )!;
    await job.completed;
    expect(
      service.byId(job.id)?.state,
      PendingPublicMediaState.connectionIssue,
    );
    expect(
      queue.share(file: photo, checkinId: 'c', expectedGeneration: 0),
      isNull,
    );
    expect(sent, hasLength(1));
  });
  test(
    'server video limit is explained without claiming the check-in ended',
    () async {
      final failure = MomentUploadFailure.fromResponse(
        400,
        '{"message":"Maximum 1 video allowed per check-in"}',
      );
      final job = uploader(response: (_) async => throw failure).share(
        file: await file('movie.mp4'),
        checkinId: 'active',
        expectedGeneration: 0,
      )!;
      await job.completed;
      expect(service.byId(job.id)?.state, PendingPublicMediaState.failed);
      expect(service.byId(job.id)?.message, failure.message);
    },
  );
  test('unreadable video is not reported as an inactive check-in', () async {
    final job = uploader(duration: (_) async => throw StateError('decoder'))
        .share(
          file: await file('movie.mp4'),
          checkinId: 'active',
          expectedGeneration: 0,
        )!;
    await job.completed;
    expect(service.byId(job.id)?.message, contains('video could not be read'));
    expect(sent, isEmpty);
  });
  test(
    'session change while compressing cannot publish or send old media',
    () async {
      final compressed = Completer<File>();
      final movie = await file('movie.mp4');
      final queue = uploader(prepare: (_) => compressed.future);
      final job = queue.share(
        file: movie,
        checkinId: 'c',
        expectedGeneration: 0,
      )!;
      await flush();
      service.clear();
      compressed.complete(movie);
      await job.completed;
      expect(service.items, isEmpty);
      expect(sent, isEmpty);
      expect(
        queue.share(file: movie, checkinId: 'c', expectedGeneration: 0),
        isNull,
      );
    },
  );
  test('videos longer than 60 seconds fail before upload', () async {
    final job = uploader(duration: (_) async => const Duration(seconds: 61))
        .share(
          file: await file('long.mp4'),
          checkinId: 'c',
          expectedGeneration: 0,
        )!;
    await job.completed;
    expect(service.byId(job.id)?.state, PendingPublicMediaState.failed);
    expect(service.byId(job.id)?.message, contains('60 seconds'));
    expect(sent, isEmpty);
  });
  test(
    'exactly 60 seconds and caption are preserved through preparation',
    () async {
      final job = uploader().share(
        file: await file('valid.mp4'),
        checkinId: 'c',
        expectedGeneration: 0,
        textOverlayJson: '{"text":"hello"}',
      )!;
      await job.completed;
      expect(sent, hasLength(1));
      expect(overlays.single, '{"text":"hello"}');
      expect(service.byId(job.id)?.isVideo, true);
    },
  );
  test('different check-ins do not share duplicate detection', () async {
    final photo = await file('photo.jpg');
    final queue = uploader();
    final first = queue.share(
      file: photo,
      checkinId: 'c1',
      expectedGeneration: 0,
    )!;
    final second = queue.share(
      file: photo,
      checkinId: 'c2',
      expectedGeneration: 0,
    )!;
    await Future.wait([first.completed, second.completed]);
    expect(sent, hasLength(2));
    expect(service.items.map((i) => i.checkinId).toSet(), {'c1', 'c2'});
  });
}
