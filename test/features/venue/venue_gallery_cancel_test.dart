import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';

void main() {
  PendingPublicMedia item({String id = 'review', String venueId = 'alpha'}) =>
      PendingPublicMedia(
        id: id,
        kind: PendingPublicMediaKind.venueGallery,
        venueId: venueId,
        localPath: '',
        isVideo: false,
        createdAt: DateTime.now(),
        state: PendingPublicMediaState.underReview,
      );

  test(
    'cancellation suppresses late publication and only removes the exact venue photo',
    () async {
      final lookup = Completer<MediaModerationSnapshot>();
      final removal = Completer<void>();
      final removed = <String>[];
      var publicReads = 0;
      final service = PendingPublicMediaService.forTest(
        publishedLookup: (_) async {
          publicReads++;
          return true;
        },
        moderationLookup: (_) => lookup.future,
        delay: (_) => Completer<void>().future,
        removeGalleryPhoto: (photo, _) {
          removed.add('${photo.venueId}:${photo.id}');
          return removal.future;
        },
      );
      final photo = item();
      service.track(photo);
      final cancel = service.removeGalleryPhoto(
        photo,
        expectedGeneration: service.sessionGeneration,
      );
      lookup.complete(const MediaModerationSnapshot(status: 'APPROVED'));
      await Future<void>.delayed(Duration.zero);
      expect(publicReads, 0);
      expect(service.byId(photo.id), isNotNull);
      removal.complete();
      await cancel;
      expect(removed, ['alpha:review']);
      expect(service.byId(photo.id), isNull);
      service.clear();
    },
  );

  test(
    'old-account cancellation cannot remove the new account draft',
    () async {
      final removal = Completer<void>();
      var calls = 0;
      final service = PendingPublicMediaService.forTest(
        publishedLookup: (_) async => false,
        moderationLookup: (_) => Completer<MediaModerationSnapshot>().future,
        delay: (_) => Completer<void>().future,
        removeGalleryPhoto: (_, _) {
          calls++;
          return removal.future;
        },
      );
      final photo = item();
      service.track(photo);
      final oldSession = service.sessionGeneration;
      final cancel = service.removeGalleryPhoto(
        photo,
        expectedGeneration: oldSession,
      );
      service.clear();
      service.track(item(venueId: 'beta'));
      removal.complete();
      await cancel;
      expect(service.byId(photo.id)?.venueId, 'beta');
      await service.removeGalleryPhoto(photo, expectedGeneration: oldSession);
      expect(calls, 1);
      service.clear();
    },
  );
}
