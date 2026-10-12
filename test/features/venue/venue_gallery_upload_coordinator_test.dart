import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_upload_coordinator.dart';

class OversizedFile extends Fake implements File {
  @override
  Future<int> length() async => 100 * 1024 * 1024 + 1;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PendingPublicMediaService service;
  final sent = <String>[];

  Future<File> file(String name) =>
      File('${directory.path}/$name').writeAsBytes([1, 2, 3]);
  Future<void> flush() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(Duration.zero);
      await service.flushPersistence();
    }
  }

  VenueGalleryUploadCoordinator coordinator({
    Future<File> Function(File)? image,
    Future<File> Function(File)? video,
    Future<Duration> Function(File)? duration,
    Future<File?> Function(File)? thumbnail,
    Future<String> Function(PendingPublicMedia)? response,
  }) => VenueGalleryUploadCoordinator.forTest(
    service: service,
    prepareImage: image ?? (f) async => f,
    prepareVideo: video ?? (f) async => f,
    videoDuration: duration ?? (_) async => const Duration(seconds: 60),
    thumbnail: thumbnail ?? (_) async => null,
    sender: (draft, prepared, thumb, session) async {
      await service.runTrackedUpload<String>(
        draft: draft,
        expectedGeneration: session,
        send: (progress) async {
          sent.add(draft.id);
          progress(1, 2);
          return response == null
              ? 'receipt-${draft.id}'
              : await response(draft);
        },
        receiptId: (id) => id,
      );
    },
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('gallery-upload-test-');
    sent.clear();
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
    await directory.delete(recursive: true);
  });

  test(
    'all selected previews appear before preparation, transfers stay bounded',
    () async {
      final preparation = Completer<File>();
      final responses = <Completer<String>>[];
      final image = await file('one.jpg');
      final files = [image, await file('two.jpg'), await file('three.jpg')];
      final queue = coordinator(
        image: (_) => preparation.future,
        response: (_) {
          final done = Completer<String>();
          responses.add(done);
          return done.future;
        },
      );
      final upload = queue.share(venueId: 'venue-1', files: files);
      expect(upload.ids, hasLength(3));
      expect(
        service.items.every(
          (i) => i.state == PendingPublicMediaState.preparing,
        ),
        true,
      );
      expect(sent, isEmpty);
      preparation.complete(image);
      await flush();
      expect(sent, hasLength(2));
      expect(
        service.items.where(
          (i) => i.state == PendingPublicMediaState.uploading,
        ),
        hasLength(2),
      );
      responses[0].complete('one');
      await flush();
      expect(sent, hasLength(3));
      responses[1].complete('two');
      responses[2].complete('three');
      await upload.completed;
      expect(service.items, hasLength(3));
      expect(service.items.every((i) => i.hasServerReceipt), true);
      expect(service.items.every((i) => i.venueId == 'venue-1'), true);
      expect(
        service.items.every(
          (i) => i.state != PendingPublicMediaState.published,
        ),
        true,
      );
    },
  );

  test('a bad video does not block a valid photo or another video', () async {
    final files = [
      await file('long.mp4'),
      await file('photo.jpg'),
      await file('valid.mp4'),
    ];
    final upload = coordinator(
      duration: (f) async =>
          Duration(seconds: f.path.endsWith('long.mp4') ? 61 : 60),
    ).share(venueId: 'venue-1', files: files);
    await upload.completed;
    expect(sent, hasLength(2));
    expect(service.byId(upload.ids[0])?.state, PendingPublicMediaState.failed);
    expect(service.byId(upload.ids[0])?.message, contains('60 seconds'));
    expect(service.byId(upload.ids[1])?.hasServerReceipt, true);
    expect(service.byId(upload.ids[2])?.hasServerReceipt, true);
  });

  test(
    'zero duration and unreadable videos fail safely before upload',
    () async {
      final files = [await file('empty.mp4'), await file('broken.mp4')];
      final upload = coordinator(
        duration: (f) async {
          if (f.path.endsWith('empty.mp4')) return Duration.zero;
          throw StateError('unreadable');
        },
      ).share(venueId: 'venue-1', files: files);
      await upload.completed;
      expect(sent, isEmpty);
      expect(
        service.items.every((i) => i.state == PendingPublicMediaState.failed),
        true,
      );
    },
  );

  test(
    'converted image preview is retained before handing off to upload',
    () async {
      final jpeg = await file('converted.jpg');
      final upload = coordinator(
        image: (_) async => jpeg,
      ).share(venueId: 'venue-1', files: [await file('photo.heic')]);
      await upload.completed;
      expect(service.byId(upload.ids.single)?.previewPath, jpeg.path);
      expect(service.items, hasLength(1));
    },
  );

  test('video thumbnail failure does not discard a valid video', () async {
    final upload = coordinator(
      thumbnail: (_) async => throw StateError('thumbnail'),
    ).share(venueId: 'venue-1', files: [await file('clip.mp4')]);
    await upload.completed;
    expect(sent, hasLength(1));
    expect(service.byId(upload.ids.single)?.hasServerReceipt, true);
  });

  test(
    '100 MB gallery limit is checked before sending a prepared video',
    () async {
      final upload = coordinator(
        video: (_) async => OversizedFile(),
      ).share(venueId: 'venue-1', files: [await file('large.mp4')]);
      await upload.completed;
      expect(sent, isEmpty);
      expect(
        service.byId(upload.ids.single)?.state,
        PendingPublicMediaState.failed,
      );
      expect(service.byId(upload.ids.single)?.message, contains('too large'));
    },
  );

  test('logout prevents both prepared and queued jobs from sending', () async {
    final gate = Completer<File>();
    final files = [
      await file('one.jpg'),
      await file('two.jpg'),
      await file('three.jpg'),
    ];
    final upload = coordinator(
      image: (_) => gate.future,
    ).share(venueId: 'venue-1', files: files);
    service.clear();
    gate.complete(files.first);
    await upload.completed;
    expect(sent, isEmpty);
    expect(service.items, isEmpty);
  });

  test('a picker result from the previous session cannot enqueue', () async {
    final generation = service.sessionGeneration;
    service.clear();
    final upload = coordinator().share(
      venueId: 'venue-1',
      files: [await file('photo.jpg')],
      expectedGeneration: generation,
    );
    await upload.completed;
    expect(upload.ids, isEmpty);
    expect(service.items, isEmpty);
    expect(sent, isEmpty);
  });

  test(
    'uncertain network outcome is retained without replay or false success',
    () async {
      final upload = coordinator(
        response: (_) async => throw const SocketException('offline'),
      ).share(venueId: 'venue-1', files: [await file('photo.jpg')]);
      await upload.completed;
      expect(sent, hasLength(1));
      expect(
        service.byId(upload.ids.single)?.state,
        PendingPublicMediaState.connectionIssue,
      );
      expect(service.wasPublished(upload.ids.single), false);
    },
  );

  test('duplicate paths and non-media are not silently posted', () async {
    final photo = await file('photo.jpg');
    final upload = coordinator().share(
      venueId: 'venue-1',
      files: [photo, photo, await file('document.pdf')],
    );
    await upload.completed;
    expect(upload.ids, hasLength(1));
    expect(sent, hasLength(1));
  });

  test(
    'known server rejection stays actionable while other files finish',
    () async {
      final upload =
          coordinator(
            response: (draft) async {
              if (draft.localPath.endsWith('bad.jpg')) {
                throw const PublicMediaUploadRejected('Upload failed (413)');
              }
              return 'receipt-${draft.id}';
            },
          ).share(
            venueId: 'venue-1',
            files: [await file('bad.jpg'), await file('good.jpg')],
          );
      await upload.completed;
      expect(
        service.byId(upload.ids.first)?.state,
        PendingPublicMediaState.failed,
      );
      expect(service.byId(upload.ids.first)?.message, contains('too large'));
      expect(service.byId(upload.ids.last)?.hasServerReceipt, true);
    },
  );
}
