import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kmstry_frontend/core/network/authenticated_multipart_upload.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_repository.dart';

String token(int version) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'owner-a', 'version': version})))}.signature';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PendingPublicMediaService service;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'access_token': token(1)});
    service = PendingPublicMediaService.forTest(
      publishedLookup: (_) async => false,
      moderationLookup: (_) async => const MediaModerationSnapshot(
        status: 'PENDING',
        photoPublication: 'WAITING',
      ),
      delay: (_) => Completer<void>().future,
    );
  });
  tearDown(() => service.clear());
  PendingPublicMedia draft({bool series = false}) => PendingPublicMedia(
    id: 'upload-one',
    kind: PendingPublicMediaKind.eventPhoto,
    venueId: 'venue-a',
    eventId: series ? null : 'event-a',
    recurringRuleId: series ? 'series-a' : null,
    localPath: 'assets/images/kmstrylogo.png',
    isVideo: false,
    createdAt: DateTime.now(),
    hasServerReceipt: false,
  );

  for (final series in [false, true]) {
    test(
      '${series ? "series" : "single event"}: one JWT refresh preserves an exact, unpublished photo receipt',
      () async {
        var refreshes = 0;
        final requests = <http.MultipartRequest>[];
        final multipart = AuthenticatedMultipartUpload(
          readToken: SecureStorage.getAccessToken,
          refreshToken: () async {
            refreshes++;
            await SecureStorage.write('access_token', token(2));
            return token(2);
          },
          headers: ({String? accessToken}) async => {
            'Authorization': 'Bearer $accessToken',
            'x-kmstry-build-env': 'staging',
          },
          sender: (request, {required timeout, cancellation}) async {
            requests.add(request);
            await request.finalize().drain<void>();
            expect(timeout, const Duration(minutes: 5));
            return http.StreamedResponse(
              Stream.value(
                utf8.encode(
                  requests.length == 1
                      ? '{"message":"Unauthorized"}'
                      : '{"id":"event-a","photos":[],"moderation_item_id":"exact-review-one","moderation_status":"PENDING"}',
                ),
              ),
              requests.length == 1 ? 401 : 201,
            );
          },
        );
        final repo = VenueEventRepository(
          multipart: multipart,
          uploads: service,
        );
        final item = draft(series: series);
        service.prepareUpload(
          item,
          expectedGeneration: service.sessionGeneration,
        );
        final response = series
            ? await repo.uploadRecurringPhoto(
                venueId: 'venue-a',
                ruleId: 'series-a',
                file: File(item.localPath),
                pendingDraft: item,
                uploadSession: service.sessionGeneration,
              )
            : await repo.uploadPhoto(
                venueId: 'venue-a',
                eventId: 'event-a',
                file: File(item.localPath),
                pendingDraft: item,
                uploadSession: service.sessionGeneration,
              );
        expect(refreshes, 1);
        expect(requests, hasLength(2));
        expect(identical(requests[0], requests[1]), false);
        expect(
          requests.last.url.path,
          series
              ? '/venues/venue-a/events/recurring/series-a/photos'
              : '/venues/venue-a/events/event-a/photos',
        );
        expect(requests.last.headers['authorization'], 'Bearer ${token(2)}');
        expect(response['photos'], isEmpty);
        expect(service.items.single.id, 'exact-review-one');
        expect(service.items.single.eventId, item.eventId);
        expect(service.items.single.recurringRuleId, item.recurringRuleId);
        expect(service.wasPublished(item.id), false);
      },
    );
  }
  test('a timeout is ambiguous, not a retry or a rejection', () async {
    var sends = 0;
    final repo = VenueEventRepository(
      uploads: service,
      multipart: AuthenticatedMultipartUpload(
        readToken: SecureStorage.getAccessToken,
        headers: ({String? accessToken}) async => {},
        sender: (request, {required timeout, cancellation}) async {
          sends++;
          throw TimeoutException('Disconnected');
        },
      ),
    );
    final item = draft();
    await expectLater(
      repo.uploadPhoto(
        venueId: 'venue-a',
        eventId: 'event-a',
        file: File(item.localPath),
        pendingDraft: item,
        uploadSession: service.sessionGeneration,
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(sends, 1);
    expect(service.items.single.state, PendingPublicMediaState.connectionIssue);
    expect(service.items.single.hasServerReceipt, false);
  });
  test(
    'draft context cannot be attached to a different event or venue',
    () async {
      final repo = VenueEventRepository(uploads: service);
      final item = draft();
      await expectLater(
        repo.uploadPhoto(
          venueId: 'venue-b',
          eventId: 'event-a',
          file: File(item.localPath),
          pendingDraft: item,
          uploadSession: service.sessionGeneration,
        ),
        throwsArgumentError,
      );
      await expectLater(
        repo.uploadPhoto(
          venueId: 'venue-a',
          eventId: 'event-b',
          file: File(item.localPath),
          pendingDraft: item,
          uploadSession: service.sessionGeneration,
        ),
        throwsArgumentError,
      );
      expect(service.items, isEmpty);
    },
  );
}
