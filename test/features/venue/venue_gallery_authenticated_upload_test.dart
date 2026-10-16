import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/network/authenticated_multipart_upload.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_upload_coordinator.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_upload_failure.dart';

String token([int version = 1, String owner = 'owner']) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': owner, 'version': version})))}.signature';

http.StreamedResponse response(int status, [Object body = const {}]) =>
    http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))), status);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PendingPublicMediaService service;
  late File photo;
  var refreshes = 0;
  late List<http.MultipartRequest> requests;
  late List<List<int>> payloads;
  late Future<http.StreamedResponse> Function(http.MultipartRequest) respond;
  late Future<String?> Function() refresh;
  late VenueGalleryRepository repository;
  late VenueGalleryUploadCoordinator coordinator;

  Future<File> image(String name) =>
      File('${directory.path}/$name').writeAsBytes([1, 2, 3, 4]);

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({'access_token': token()});
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('gallery-auth-test-');
    photo = await image('photo.jpg');
    service = PendingPublicMediaService.forTest(
      publishedLookup: (_) async => false,
      moderationLookup: (_) async =>
          const MediaModerationSnapshot(status: 'PENDING'),
      delay: (_) => Completer<void>().future,
    );
    refreshes = 0;
    requests = [];
    payloads = [];
    refresh = () async {
      refreshes++;
      await SecureStorage.write('access_token', token(2));
      return token(2);
    };
    ApiClient.onRefreshToken = () => refresh();
    respond = (_) async =>
        response(201, {'id': 'receipt-${requests.length}', 'url': null});
    repository = VenueGalleryRepository(
      uploadService: service,
      uploads: AuthenticatedMultipartUpload(
        headers: ({String? accessToken}) async => {
          'Authorization': 'Bearer $accessToken',
        },
        appCheckHeaders: ({bool forceRefresh = false}) async => {
          'X-Firebase-AppCheck': 'fresh',
        },
        sender: (request, {required timeout, cancellation}) async {
          requests.add(request);
          payloads.add(await request.finalize().toBytes());
          return respond(request);
        },
      ),
    );
    coordinator = VenueGalleryUploadCoordinator.forTest(
      service: service,
      prepareImage: (file) async => file,
      prepareVideo: (file) async => file,
      videoDuration: (_) async => const Duration(seconds: 1),
      thumbnail: (_) async => null,
      sender: (draft, file, thumbnail, generation) async {
        await repository.uploadItem(
          draft.venueId!,
          file,
          thumbnail: thumbnail,
          pendingDraft: draft,
          uploadSession: generation,
        );
      },
    );
  });
  tearDown(() async {
    ApiClient.onRefreshToken = null;
    service.clear();
    await service.flushPersistence();
    await directory.delete(recursive: true);
  });

  test(
    'pending owner -> approved: same repository/session uploads without account switching',
    () async {
      var approved = false;
      respond = (request) async {
        if (!approved) {
          return response(403, {
            'message': 'You are not an active member of this venue',
          });
        }
        if (request.headers['Authorization'] == 'Bearer ${token()}') {
          return response(401);
        }
        return response(201, {'id': 'approved-venue-photo', 'url': null});
      };
      final generation = service.sessionGeneration;
      final revision = SecureStorage.sessionRevision;
      final pending = coordinator.share(venueId: 'new-venue', files: [photo]);
      await pending.completed;
      expect(service.byId(pending.ids.single)?.message, contains('permission'));
      expect(refreshes, 0);
      approved = true;
      final next = coordinator.share(venueId: 'new-venue', files: [photo]);
      await next.completed;
      expect(refreshes, 1);
      expect(requests, hasLength(3));
      expect(
        requests.every((r) => r.url.path == '/venues/new-venue/gallery'),
        true,
      );
      expect(identical(requests[1], requests[2]), false);
      expect(
        payloads.every((bytes) => bytes.contains(1) && bytes.contains(4)),
        true,
      );
      expect(service.sessionGeneration, generation);
      expect(SecureStorage.sessionRevision, revision);
      final item = service.byId(next.ids.single)!;
      expect(item.id, 'approved-venue-photo');
      expect(item.hasServerReceipt, true);
      expect(item.state, PendingPublicMediaState.checking);
      expect(service.wasPublished(next.ids.single), false);
    },
  );

  test(
    'three queued photos refresh once and each receives one private receipt',
    () async {
      final firstPair = Completer<void>();
      var rejected = 0;
      var accepted = 0;
      respond = (request) async {
        if (request.headers['Authorization'] == 'Bearer ${token()}') {
          rejected++;
          if (rejected == 2) firstPair.complete();
          await firstPair.future;
          return response(401);
        }
        return response(201, {'id': 'photo-${++accepted}', 'url': null});
      };
      final upload = coordinator.share(
        venueId: 'new-venue',
        files: [photo, await image('two.jpg'), await image('three.jpg')],
      );
      await upload.completed;
      expect(refreshes, 1);
      expect(accepted, 3);
      expect(requests, hasLength(5));
      expect(service.items, hasLength(3));
      expect(
        service.items.every(
          (i) =>
              i.hasServerReceipt && i.state == PendingPublicMediaState.checking,
        ),
        true,
      );
    },
  );

  test(
    'persistent 401 retries only once, then explains sign-in, not a bad file',
    () async {
      respond = (_) async => response(401);
      final upload = coordinator.share(venueId: 'venue', files: [photo]);
      await upload.completed;
      expect(requests, hasLength(2));
      expect(refreshes, 1);
      expect(
        service.byId(upload.ids.single)?.message,
        contains('Sign in again'),
      );
      expect(
        service.byId(upload.ids.single)?.state,
        PendingPublicMediaState.failed,
      );
    },
  );

  for (final (status, fragment) in [
    (403, 'permission'),
    (404, 'no longer available'),
    (413, 'too large'),
    (415, 'format'),
    (429, 'Wait a moment'),
    (400, 'not accepted'),
  ]) {
    test('$status has a separate safe message and is not retried', () async {
      respond = (_) async =>
          response(status, {'message': 'private signed-url secret'});
      final upload = coordinator.share(venueId: 'venue', files: [photo]);
      await upload.completed;
      expect(requests, hasLength(1));
      expect(refreshes, 0);
      expect(service.byId(upload.ids.single)?.message, contains(fragment));
      expect(
        service.byId(upload.ids.single)?.message,
        isNot(contains('secret')),
      );
    });
  }

  test(
    'App Check challenge is refreshed separately from the login token',
    () async {
      respond = (request) async =>
          request.headers['X-Firebase-AppCheck'] == 'fresh'
          ? response(201, {'id': 'photo', 'url': null})
          : response(401, {'errorCode': 'APP_CHECK_REQUIRED'});
      final upload = coordinator.share(venueId: 'venue', files: [photo]);
      await upload.completed;
      expect(requests, hasLength(2));
      expect(refreshes, 0);
      expect(service.byId(upload.ids.single)?.hasServerReceipt, true);
    },
  );

  test(
    'AWS permission refusal removes the draft instead of showing a failed photo',
    () async {
      respond = (_) async =>
          response(403, {'errorCode': 'AWS_SHARING_PERMISSION_REQUIRED'});
      final upload = coordinator.share(venueId: 'venue', files: [photo]);
      await upload.completed;
      expect(requests, hasLength(1));
      expect(service.items, isEmpty);
    },
  );

  for (final status in [408, 500, 503]) {
    test('$status keeps the outcome unconfirmed; no duplicate send', () async {
      respond = (_) async => response(status);
      final upload = coordinator.share(venueId: 'venue', files: [photo]);
      await upload.completed;
      expect(requests, hasLength(1));
      expect(refreshes, 0);
      expect(
        service.byId(upload.ids.single)?.state,
        PendingPublicMediaState.connectionIssue,
      );
      expect(
        service.byId(upload.ids.single)?.message,
        contains('could not confirm'),
      );
    });
  }

  for (final error in [
    const SocketException('offline'),
    TimeoutException('timeout'),
  ]) {
    test('${error.runtimeType} does not replay the photo', () async {
      respond = (_) async => throw error;
      final upload = coordinator.share(venueId: 'venue', files: [photo]);
      await upload.completed;
      expect(requests, hasLength(1));
      expect(
        service.byId(upload.ids.single)?.state,
        PendingPublicMediaState.connectionIssue,
      );
    });
  }

  for (final changeUser in [false, true]) {
    test(
      'logout/relogin ${changeUser ? "different user" : "same user"} during refresh cannot replay',
      () async {
        respond = (_) async => response(401);
        refresh = () async {
          refreshes++;
          await SecureStorage.clearSession();
          await SecureStorage.write(
            'access_token',
            token(2, changeUser ? 'other' : 'owner'),
          );
          return token(2, changeUser ? 'other' : 'owner');
        };
        final upload = coordinator.share(venueId: 'venue', files: [photo]);
        await upload.completed;
        expect(requests, hasLength(1));
        expect(refreshes, 1);
        expect(service.items.any((i) => i.hasServerReceipt), false);
      },
    );
  }

  test(
    'no access token produces sign-in guidance before sending anything',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final upload = coordinator.share(venueId: 'venue', files: [photo]);
      await upload.completed;
      expect(requests, isEmpty);
      expect(
        service.byId(upload.ids.single)?.message,
        contains('Sign in again'),
      );
    },
  );

  test(
    'safe mapper never exposes response bodies or mistakes app verification for login',
    () {
      final error = VenueGalleryUploadFailure.fromResponse(
        401,
        '{"errorCode":"APP_CHECK_REQUIRED","message":"private token"}',
      );
      expect(error.code, 'APP_CHECK_REQUIRED');
      expect(error.message, contains('App verification'));
      expect(error.toString(), isNot(contains('private')));
      expect(
        VenueGalleryUploadFailure.fromResponse(
          400,
          '<html>secret</html>',
        ).message,
        isNot(contains('secret')),
      );
    },
  );
}
