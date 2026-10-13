import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kmstry_frontend/core/network/authenticated_multipart_upload.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/stories/data/story_repository.dart';
import 'package:kmstry_frontend/features/stories/data/story_upload_failure.dart';
import 'package:kmstry_frontend/features/venue_stories/data/venue_story_repository.dart';

String _token(int version) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'owner-1', 'version': version})))}.signature';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final venue in [false, true]) {
    for (final video in [false, true]) {
      test(
        '${venue ? "venue" : "personal"} ${video ? "video" : "photo"}: JWT retry keeps one unpublished receipt',
        () async {
          FlutterSecureStorage.setMockInitialValues({
            'access_token': _token(1),
          });
          final directory = await Directory.systemTemp.createTemp(
            'story-auth-test-',
          );
          final file = await File(
            '${directory.path}/clip.${video ? "mp4" : "jpg"}',
          ).writeAsBytes([1, 2, 3, 4]);
          final service = PendingPublicMediaService.forTest(
            publishedLookup: (_) async => false,
            moderationLookup: (_) async =>
                const MediaModerationSnapshot(status: 'PENDING'),
            delay: (_) => Completer<void>().future,
          );
          addTearDown(() async {
            service.clear();
            await service.flushPersistence();
            await directory.delete(recursive: true);
          });
          var refreshes = 0;
          final requests = <http.MultipartRequest>[];
          final payloads = <List<int>>[];
          final states = <PendingPublicMediaState>[];
          service.changes.addListener(() {
            states.addAll(service.items.map((item) => item.state));
          });
          final uploads = AuthenticatedMultipartUpload(
            readToken: SecureStorage.getAccessToken,
            refreshToken: () async {
              refreshes++;
              await SecureStorage.write('access_token', _token(2));
              return _token(2);
            },
            headers: ({String? accessToken}) async => {
              'Authorization': 'Bearer $accessToken',
              'x-kmstry-build-env': 'staging',
              'X-Firebase-AppCheck': 'app-check-test',
            },
            sender: (request, {required timeout, cancellation}) async {
              requests.add(request);
              payloads.add(await request.finalize().toBytes());
              return http.StreamedResponse(
                Stream.value(
                  utf8.encode(
                    requests.length == 1
                        ? '{"message":"Unauthorized"}'
                        : jsonEncode({
                            'id': 'server-story-1',
                            'media_type': video ? 'video' : 'photo',
                            'media_url':
                                null, // Pending media must remain non-public.
                            'created_at': DateTime.now()
                                .toUtc()
                                .toIso8601String(),
                            'expires_at': DateTime.now()
                                .add(const Duration(hours: 24))
                                .toUtc()
                                .toIso8601String(),
                            'venue': {'id': 'venue-1', 'name': 'Test Cafe'},
                          }),
                  ),
                ),
                requests.length == 1 ? 401 : 201,
              );
            },
          );
          final draft = PendingPublicMedia(
            id: 'upload-100-200',
            kind: venue
                ? PendingPublicMediaKind.venueStory
                : PendingPublicMediaKind.personalStory,
            venueId: 'venue-1',
            checkinId: venue ? null : 'checkin-1',
            localPath: file.path,
            isVideo: video,
            createdAt: DateTime.now(),
            hasServerReceipt: false,
          );
          service.prepareUpload(
            draft,
            expectedGeneration: service.sessionGeneration,
          );
          if (venue) {
            await VenueStoryRepository(
              uploads: uploads,
              uploadService: service,
            ).createVenueStory(
              venueId: 'venue-1',
              file: file,
              mediaType: video ? 'video' : 'photo',
              pendingDraft: draft,
              textOverlayJson: video ? '{"text":"safe caption"}' : null,
            );
          } else {
            await StoryRepository(
              uploads: uploads,
              uploadService: service,
            ).createStory(
              checkinId: 'checkin-1',
              file: file,
              mediaType: video ? 'video' : 'photo',
              pendingDraft: draft,
              textOverlayJson: '{"text":"safe caption"}',
            );
          }
          expect(refreshes, 1);
          expect(requests, hasLength(2));
          expect(
            requests.first.url.path,
            venue
                ? '/venues/venue-1/venue-stories'
                : '/checkins/checkin-1/stories',
          );
          expect(requests.first.fields, requests.last.fields);
          expect(requests.last.fields['upload_id'], draft.id);
          if (!venue || video) {
            expect(
              requests.last.fields['textOverlay'],
              '{"text":"safe caption"}',
            );
          }
          expect(requests.last.headers['Authorization'], 'Bearer ${_token(2)}');
          expect(
            payloads.every((bytes) => bytes.contains(1) && bytes.contains(4)),
            true,
          );
          expect(service.items, hasLength(1));
          expect(service.byId(draft.id)?.id, 'server-story-1');
          expect(service.byId(draft.id)?.hasServerReceipt, true);
          expect(
            service.byId(draft.id)?.state,
            PendingPublicMediaState.checking,
          );
          expect(service.wasPublished(draft.id), false);
          expect(states, isNot(contains(PendingPublicMediaState.failed)));
        },
      );
    }

    test(
      '${venue ? "venue" : "personal"}: persistent 401 has a definite safe failure after one retry',
      () async {
        FlutterSecureStorage.setMockInitialValues({'access_token': _token(1)});
        final directory = await Directory.systemTemp.createTemp(
          'story-auth-test-',
        );
        final file = await File(
          '${directory.path}/image.jpg',
        ).writeAsBytes([1]);
        final service = PendingPublicMediaService.forTest(
          publishedLookup: (_) async => false,
          moderationLookup: (_) async =>
              const MediaModerationSnapshot(status: 'PENDING'),
          delay: (_) => Completer<void>().future,
        );
        addTearDown(() async {
          service.clear();
          await service.flushPersistence();
          await directory.delete(recursive: true);
        });
        var sends = 0;
        final uploads = AuthenticatedMultipartUpload(
          readToken: SecureStorage.getAccessToken,
          refreshToken: () async {
            await SecureStorage.write('access_token', _token(2));
            return _token(2);
          },
          headers: ({String? accessToken}) async => {
            'Authorization': 'Bearer $accessToken',
          },
          sender: (request, {required timeout, cancellation}) async {
            sends++;
            return http.StreamedResponse(
              Stream.value(utf8.encode('{"message":"Unauthorized"}')),
              401,
            );
          },
        );
        await expectLater(
          venue
              ? VenueStoryRepository(
                  uploads: uploads,
                  uploadService: service,
                ).createVenueStory(
                  venueId: 'venue-1',
                  file: file,
                  mediaType: 'photo',
                )
              : StoryRepository(
                  uploads: uploads,
                  uploadService: service,
                ).createStory(
                  checkinId: 'checkin-1',
                  file: file,
                  mediaType: 'photo',
                ),
          throwsA(
            isA<StoryUploadFailure>().having(
              (e) => e.code,
              'safe code',
              'AUTH_REQUIRED',
            ),
          ),
        );
        expect(sends, 2);
        expect(service.items.single.state, PendingPublicMediaState.failed);
        expect(service.items.single.hasServerReceipt, false);
      },
    );
  }
}
