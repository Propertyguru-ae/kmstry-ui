import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media_store.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';

class MemoryUploadStore implements PendingPublicMediaStore {
  Map<String, dynamic>? value;
  final previews = <String>{};
  bool failWrites = false;
  Future<void> Function()? beforeRead;

  MemoryUploadStore([Map<String, dynamic>? initial]) {
    value = initial == null ? null : _copy(initial);
  }

  static Map<String, dynamic> _copy(Map<String, dynamic> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

  @override
  Future<Map<String, dynamic>?> read() async {
    await beforeRead?.call();
    return value == null ? null : _copy(value!);
  }

  @override
  Future<void> write(Map<String, dynamic> next) async {
    if (failWrites) throw StateError('Disk unavailable');
    value = _copy(next);
  }

  @override
  Future<String> retainPreview(String id, String sourcePath) async {
    final path = '/managed-preview/$id.jpg';
    previews.add(path);
    return path;
  }

  @override
  Future<void> prunePreviews(Set<String> retainedPaths) async {
    previews.retainAll(retainedPaths);
  }

  @override
  Future<void> clear() async {
    value = null;
    previews.clear();
  }
}

final _now = DateTime(2026, 10, 1, 12);

PendingPublicMedia _draft(
  String id, {
  PendingPublicMediaKind kind = PendingPublicMediaKind.personalStory,
}) => PendingPublicMedia(
  id: id,
  kind: kind,
  venueId: 'venue-1',
  checkinId: 'checkin-1',
  localPath: '/camera/private-original.jpg',
  isVideo: false,
  createdAt: _now,
  hasServerReceipt: false,
);

PendingPublicMediaService _service(
  MemoryUploadStore store, {
  PublishedMediaLookup? published,
  ModerationLookup? moderation,
}) => PendingPublicMediaService.forTest(
  store: store,
  now: () => _now,
  publishedLookup: published ?? (_) async => false,
  moderationLookup:
      moderation ??
      (_) async => const MediaModerationSnapshot(status: 'PENDING'),
  delay: (_) => Completer<void>().future,
);

Future<void> _bind(
  PendingPublicMediaService service, {
  String owner = 'owner-1',
  String environment = 'staging|https://api.kmstry.net',
}) => service.bindSession(
  ownerId: owner,
  environment: environment,
  expectedGeneration: service.sessionGeneration,
);

Future<void> _flush(PendingPublicMediaService service) async {
  for (var i = 0; i < 4; i++) {
    await Future<void>.delayed(Duration.zero);
    await service.flushPersistence();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final kind in [
    PendingPublicMediaKind.personalStory,
    PendingPublicMediaKind.venueStory,
  ]) {
    test(
      'viewed story rejection does not return after restart: $kind',
      () async {
        final store = MemoryUploadStore();
        final first = _service(store);
        await _bind(first);
        first.track(
          _draft('viewed-story', kind: kind)
              .withReceipt('rejected-story')
              .withState(
                PendingPublicMediaState.rejected,
                reason: 'Disallowed text.',
              ),
        );
        first.track(
          _draft('unread-story', kind: kind)
              .withReceipt('unread-rejection')
              .withState(
                PendingPublicMediaState.rejected,
                reason: 'Disallowed text.',
              ),
        );
        await _flush(first);
        first.acknowledgeStoryFeedback(
          'viewed-story',
          expectedGeneration: first.sessionGeneration,
        );
        await _flush(first);
        final restarted = _service(MemoryUploadStore(store.value));
        await _bind(restarted);
        expect(restarted.byId('rejected-story'), isNull);
        expect(
          restarted.byId('unread-rejection')?.state,
          PendingPublicMediaState.rejected,
        );
        first.clear();
        restarted.clear();
        await Future.wait([
          first.flushPersistence(),
          restarted.flushPersistence(),
        ]);
      },
    );
  }

  test(
    'completed avatar handover is not resurrected after app restart',
    () async {
      final store = MemoryUploadStore();
      final first = _service(store);
      await _bind(first);
      first.track(
        _draft('photo', kind: PendingPublicMediaKind.personalAvatar)
            .withReceipt('avatar-receipt')
            .withState(PendingPublicMediaState.published),
      );
      await _flush(first);
      expect(first.items, hasLength(1));
      final persisted = MemoryUploadStore(store.value);
      final restarted = _service(persisted);
      await _bind(restarted);
      await _flush(restarted);
      expect(restarted.items, isEmpty);
      expect(persisted.previews, isEmpty);
      first.clear();
      restarted.clear();
      await Future.wait([
        first.flushPersistence(),
        restarted.flushPersistence(),
      ]);
    },
  );

  for (final kind in [
    PendingPublicMediaKind.personalAvatar,
    PendingPublicMediaKind.venueAvatar,
  ]) {
    for (final publication in ['PUBLISHED', 'SUPERSEDED']) {
      test(
        '$kind rechecks a persisted false cancellation: $publication',
        () async {
          final store = MemoryUploadStore();
          final first = _service(store);
          await _bind(first);
          first.track(
            _draft('old-update', kind: kind)
                .withReceipt('old-receipt')
                .withState(PendingPublicMediaState.cancelled),
          );
          await _flush(first);
          final saved = MemoryUploadStore(store.value);
          final nextPoll = Completer<void>();
          var reads = 0;
          final restarted = PendingPublicMediaService.forTest(
            store: saved,
            now: () => _now,
            publishedLookup: (_) async =>
                throw StateError('Exact receipt required'),
            moderationLookup: (item) async {
              reads++;
              expect(item.id, 'old-receipt');
              expect(item.kind, kind);
              return MediaModerationSnapshot(
                status: 'APPROVED',
                photoPublication: publication,
              );
            },
            delay: (duration) => duration == const Duration(seconds: 10)
                ? Completer<void>().future
                : nextPoll.future,
          );
          await _bind(restarted);
          await _flush(restarted);
          if (publication == 'PUBLISHED') {
            expect(reads, 1);
            expect(
              restarted.byId('old-receipt')?.state,
              PendingPublicMediaState.published,
            );
            expect(restarted.wasPublished('old-receipt'), true);
          } else {
            expect(restarted.wasPublished('old-receipt'), false);
            nextPoll.complete();
            await _flush(restarted);
            expect(reads, 2);
            expect(restarted.byId('old-receipt'), isNull);
            expect(restarted.wasPublished('old-receipt'), false);
          }
          expect(restarted.avatarPublicationChanges.value, 1);
          first.clear();
          restarted.clear();
          await Future.wait([
            first.flushPersistence(),
            restarted.flushPersistence(),
          ]);
        },
      );
    }

    for (final changeEnvironment in [false, true]) {
      test(
        '$kind recovery never adopts another ${changeEnvironment ? 'environment' : 'account'}',
        () async {
          final store = MemoryUploadStore();
          final first = _service(store);
          await _bind(first);
          first.track(
            _draft('another-owner-update', kind: kind)
                .withReceipt('another-owner-receipt')
                .withState(PendingPublicMediaState.cancelled),
          );
          await _flush(first);
          var reads = 0;
          final restarted = _service(
            MemoryUploadStore(store.value),
            moderation: (_) async {
              reads++;
              return const MediaModerationSnapshot(
                status: 'APPROVED',
                photoPublication: 'PUBLISHED',
              );
            },
          );
          await _bind(
            restarted,
            owner: changeEnvironment ? 'owner-1' : 'owner-2',
            environment: changeEnvironment
                ? 'pre-prod|https://pre-prod-api.kmstry.net'
                : 'staging|https://api.kmstry.net',
          );
          await _flush(restarted);
          expect(reads, 0);
          expect(restarted.items, isEmpty);
          expect(restarted.avatarPublicationChanges.value, 0);
          first.clear();
          restarted.clear();
          await Future.wait([
            first.flushPersistence(),
            restarted.flushPersistence(),
          ]);
        },
      );
    }
  }

  test(
    'repository entry point restores the authenticated user partition',
    () async {
      final token =
          'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'owner-1'})))}.signature';
      FlutterSecureStorage.setMockInitialValues({'access_token': token});
      final store = MemoryUploadStore();
      final service = _service(store);
      final result = await service.runUpload(
        draft: _draft('repository-upload'),
        token: token,
        send: (_) async => 'repository-receipt',
        receiptId: (id) => id,
      );
      await _flush(service);
      expect(result, 'repository-receipt');
      expect(service.byId('repository-receipt')?.hasServerReceipt, true);
      expect(store.value!['scope'], isNotEmpty);
      expect(jsonEncode(store.value), isNot(contains(token)));
      service.clear();
      await service.flushPersistence();
    },
  );

  for (final duringRestore in [false, true]) {
    test(
      'same-owner token rotation does not invalidate upload: restoring=$duringRestore',
      () async {
        String token(int version, [String owner = 'owner-1']) =>
            'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': owner, 'version': version})))}.signature';
        FlutterSecureStorage.setMockInitialValues({'access_token': token(1)});
        final store = MemoryUploadStore();
        final service = _service(store);
        if (duringRestore) {
          store.beforeRead = () =>
              SecureStorage.write('access_token', token(2));
        } else {
          await SecureStorage.write('access_token', token(2));
        }
        final generation = service.sessionGeneration;
        final result = await service.runUpload(
          draft: _draft('rotating-upload'),
          token: token(1),
          expectedGeneration: generation,
          send: (_) async => 'rotating-receipt',
          receiptId: (id) => id,
        );
        expect(result, 'rotating-receipt');
        expect(service.sessionGeneration, generation);
        expect(service.byId('rotating-receipt')?.hasServerReceipt, true);
        service.clear();
        await service.flushPersistence();
      },
    );
  }

  test('different-owner token rotation while restoring blocks upload', () async {
    String token(String owner) =>
        'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': owner})))}.signature';
    FlutterSecureStorage.setMockInitialValues({
      'access_token': token('owner-1'),
    });
    final store = MemoryUploadStore()
      ..beforeRead = () =>
          SecureStorage.write('access_token', token('owner-2'));
    final service = _service(store);
    var sends = 0;
    await expectLater(
      service.runUpload(
        draft: _draft('other-owner-upload'),
        token: token('owner-1'),
        send: (_) async {
          sends++;
          return 'must-not-send';
        },
        receiptId: (id) => id,
      ),
      throwsStateError,
    );
    expect(sends, 0);
    service.clear();
    await service.flushPersistence();
  });

  test(
    'preparation failure stays visible after leaving the page and cannot cross logout',
    () async {
      final store = MemoryUploadStore();
      final service = _service(store);
      await _bind(service);
      final generation = service.sessionGeneration;
      service.recordPreparationFailure(
        expectedGeneration: generation,
        kind: PendingPublicMediaKind.venueGallery,
        venueId: 'venue-1',
        isVideo: true,
        message: 'Video is too large.',
      );
      await _flush(service);
      expect(service.items.single.state, PendingPublicMediaState.failed);
      expect(service.items.single.message, 'Video is too large.');
      expect(service.items.single.hasServerReceipt, false);
      service.clear();
      await _bind(service, owner: 'owner-2');
      service.recordPreparationFailure(
        expectedGeneration: generation,
        kind: PendingPublicMediaKind.venueGallery,
        message: 'Old account failure',
      );
      expect(service.items, isEmpty);
      service.clear();
    },
  );

  test(
    'transfer and server receipt survive a detached progress observer',
    () async {
      final store = MemoryUploadStore();
      final service = _service(store);
      await _bind(service);
      final response = Completer<String>();
      var sends = 0;
      final upload = service.runTrackedUpload(
        draft: _draft('local-1'),
        expectedGeneration: service.sessionGeneration,
        onProgress: (_, _) => throw StateError('Page disposed'),
        send: (progress) {
          sends++;
          expect(
            (store.value!['items'] as List).single['hasServerReceipt'],
            false,
          );
          progress(50, 100);
          return response.future;
        },
        receiptId: (id) => id,
      );
      await _flush(service);
      expect(service.byId('local-1')?.progress, .5);
      response.complete('server-1');
      expect(await upload, 'server-1');
      await _flush(service);
      expect(sends, 1);
      expect(service.byId('local-1')?.id, 'server-1');
      expect(service.byId('server-1')?.hasServerReceipt, true);
      expect(
        service.byId('server-1')?.previewPath,
        '/managed-preview/local-1.jpg',
      );
      expect(store.previews, {'/managed-preview/local-1.jpg'});
      expect(
        jsonEncode(store.value),
        isNot(contains('/camera/private-original')),
      );
      service.clear();
      await service.flushPersistence();
    },
  );

  test(
    'restart reconciles a received upload against public visibility',
    () async {
      final store = MemoryUploadStore();
      final original = _service(store);
      await _bind(original);
      await original.runTrackedUpload(
        draft: _draft('local-restart'),
        expectedGeneration: original.sessionGeneration,
        send: (_) async => 'server-restart',
        receiptId: (id) => id,
      );
      await _flush(original);
      final restartedStore = MemoryUploadStore(store.value);
      original.clear();
      final lookedUp = <String>[];
      final restarted = _service(
        restartedStore,
        moderation: (_) async =>
            const MediaModerationSnapshot(status: 'APPROVED'),
        published: (item) async {
          lookedUp.add(item.id);
          return true;
        },
      );
      await _bind(restarted);
      await _flush(restarted);
      expect(lookedUp, ['server-restart']);
      expect(restarted.items, isEmpty);
      expect(restarted.wasPublished('server-restart'), true);
      expect(restarted.wasPublished('local-restart'), true);
      expect(restartedStore.value!['items'], isEmpty);
      restarted.clear();
    },
  );

  test(
    'restart never re-posts an interrupted transfer or calls it published',
    () async {
      final store = MemoryUploadStore();
      final original = _service(store);
      await _bind(original);
      final response = Completer<String>();
      final transfer = original.runTrackedUpload(
        draft: _draft('interrupted'),
        expectedGeneration: original.sessionGeneration,
        send: (_) => response.future,
        receiptId: (id) => id,
      );
      await _flush(original);
      final restartedStore = MemoryUploadStore(store.value);
      original.clear();
      response.complete('late-server-id');
      await transfer;
      var queries = 0;
      final restarted = _service(
        restartedStore,
        published: (_) async {
          queries++;
          return true;
        },
      );
      await _bind(restarted);
      await _flush(restarted);
      final interrupted = restarted.byId('interrupted');
      expect(interrupted?.state, PendingPublicMediaState.connectionIssue);
      expect(interrupted?.hasServerReceipt, false);
      expect(interrupted?.message, contains('Check your content'));
      expect(queries, 0);
      expect(restarted.wasPublished('interrupted'), false);
      restarted.clear();
    },
  );

  for (final differentOwner in [false, true]) {
    test(
      'saved previews do not cross ${differentOwner ? 'accounts' : 'environments'}',
      () async {
        final store = MemoryUploadStore();
        final original = _service(store);
        await _bind(original);
        original.track(_draft('server-private').withReceipt('server-private'));
        await _flush(original);
        final restartedStore = MemoryUploadStore(store.value);
        original.clear();
        var reads = 0;
        final restarted = _service(
          restartedStore,
          published: (_) async {
            reads++;
            return false;
          },
        );
        await _bind(
          restarted,
          owner: differentOwner ? 'owner-2' : 'owner-1',
          environment: differentOwner
              ? 'staging|https://api.kmstry.net'
              : 'pre-prod|https://pre-prod-api.kmstry.net',
        );
        await _flush(restarted);
        expect(restarted.items, isEmpty);
        expect(restartedStore.value!['items'], isEmpty);
        expect(reads, 0);
        restarted.clear();
      },
    );
  }

  test('logout invalidates preparation and late upload responses', () async {
    final store = MemoryUploadStore();
    final service = _service(store);
    await _bind(service);
    final oldSession = service.sessionGeneration;
    final response = Completer<String>();
    final upload = service.runTrackedUpload(
      draft: _draft('old-upload'),
      expectedGeneration: oldSession,
      send: (_) => response.future,
      receiptId: (id) => id,
    );
    await _flush(service);
    service.clear();
    await _bind(service, owner: 'owner-2');
    response.complete('old-account-content');
    await upload;
    var sent = false;
    await expectLater(
      service.runTrackedUpload(
        draft: _draft('prepared-before-logout'),
        expectedGeneration: oldSession,
        send: (_) async {
          sent = true;
          return 'unexpected';
        },
        receiptId: (id) => id,
      ),
      throwsStateError,
    );
    await _flush(service);
    expect(sent, false);
    expect(service.items, isEmpty);
    expect(store.value!['items'], isEmpty);
    expect(store.previews, isEmpty);
    service.clear();
  });

  test('an in-flight local job cannot be launched twice', () async {
    final store = MemoryUploadStore();
    final service = _service(store);
    await _bind(service);
    final response = Completer<String>();
    var sends = 0;
    Future<String> start() => service.runTrackedUpload(
      draft: _draft('same-local-job'),
      expectedGeneration: service.sessionGeneration,
      send: (_) {
        sends++;
        return response.future;
      },
      receiptId: (id) => id,
    );
    final first = start();
    await _flush(service);
    await expectLater(start(), throwsStateError);
    response.complete('server-once');
    await first;
    expect(sends, 1);
    service.clear();
  });

  test(
    'storage failure cannot turn a successful upload into a replay',
    () async {
      final store = MemoryUploadStore();
      final service = _service(store);
      await _bind(service);
      store.failWrites = true;
      var sends = 0;
      final id = await service.runTrackedUpload(
        draft: _draft('disk-failure'),
        expectedGeneration: service.sessionGeneration,
        send: (_) async {
          sends++;
          return 'server-ok';
        },
        receiptId: (id) => id,
      );
      expect(id, 'server-ok');
      expect(sends, 1);
      expect(service.byId('server-ok')?.hasServerReceipt, true);
      service.clear();
    },
  );

  test(
    'confirmed request rejection stays distinct from uncertain transport failure',
    () async {
      final store = MemoryUploadStore();
      final service = _service(store);
      await _bind(service);
      await expectLater(
        service.runTrackedUpload<String>(
          draft: _draft('denied'),
          expectedGeneration: service.sessionGeneration,
          send: (_) async =>
              throw const PublicMediaUploadRejected('Upload failed (413)'),
          receiptId: (id) => id,
        ),
        throwsA(isA<PublicMediaUploadRejected>()),
      );
      expect(service.byId('denied')?.state, PendingPublicMediaState.failed);
      await _flush(service);
      final restarted = _service(MemoryUploadStore(store.value));
      service.clear();
      await _bind(restarted);
      expect(restarted.byId('denied')?.state, PendingPublicMediaState.failed);
      restarted.clear();
    },
  );

  test(
    'moderation rejection retains its reason and removes the managed preview',
    () async {
      final store = MemoryUploadStore();
      final decision = Completer<MediaModerationSnapshot>();
      final service = _service(store, moderation: (_) => decision.future);
      await _bind(service);
      await service.runTrackedUpload(
        draft: _draft('rejected-preview'),
        expectedGeneration: service.sessionGeneration,
        send: (_) async => 'server-rejected',
        receiptId: (id) => id,
      );
      await _flush(service);
      expect(store.previews, isNotEmpty);
      decision.complete(
        const MediaModerationSnapshot(
          status: 'REJECTED',
          message: 'Contains disallowed text.',
        ),
      );
      await _flush(service);
      expect(
        service.byId('server-rejected')?.message,
        'Contains disallowed text.',
      );
      expect(store.previews, isEmpty);
      service.clear();
    },
  );
}
