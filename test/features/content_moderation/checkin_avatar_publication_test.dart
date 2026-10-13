import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/content_moderation/presentation/owner_photo_preview.dart';

PendingPublicMedia crop(String id, String checkin) => PendingPublicMedia(
  id: id,
  kind: PendingPublicMediaKind.checkinAvatar,
  venueId: null,
  checkinId: checkin,
  localPath: '/tmp/owner-crop.jpg',
  previewPath: '/tmp/owner-crop.jpg',
  isVideo: false,
  createdAt: DateTime.now(),
);

Future<void> flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  testWidgets('profile and navbar use exactly the same owner-only crop', (
    tester,
  ) async {
    final service = PendingPublicMediaService.forTest(
      publishedLookup: (_) async => false,
      moderationLookup: (_) => Completer<MediaModerationSnapshot>().future,
      delay: (_) => Completer<void>().future,
    );
    addTearDown(service.clear);
    service.track(crop('receipt-new', 'checkin-a'));
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            for (final size in [132.0, 32.0])
              OwnerPhotoPreview(
                kind: PendingPublicMediaKind.personalAvatar,
                checkinId: 'checkin-a',
                width: size,
                height: size,
                service: service,
                child: const Text('Canonical avatar'),
              ),
            OwnerPhotoPreview(
              kind: PendingPublicMediaKind.personalAvatar,
              checkinId: 'different-checkin',
              width: 32,
              height: 32,
              service: service,
              child: const Text('Other check-in'),
            ),
          ],
        ),
      ),
    );
    expect(find.byType(Image), findsNWidgets(2));
    for (final widget in tester.widgetList<Image>(find.byType(Image))) {
      final provider = widget.image is ResizeImage
          ? (widget.image as ResizeImage).imageProvider
          : widget.image;
      expect((provider as FileImage).file.path, '/tmp/owner-crop.jpg');
    }
    expect(find.text('Other check-in'), findsOneWidget);
    expect(find.text('Canonical avatar'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final result in ['WAITING', 'PUBLISHED', 'SUPERSEDED', 'REJECTED']) {
    test('exact check-in crop receipt: $result', () async {
      final service = PendingPublicMediaService.forTest(
        publishedLookup: (_) async =>
            throw StateError('No full profile polling'),
        moderationLookup: (item) async {
          expect(item.id, 'receipt-new');
          expect(item.targetType, 'CHECKIN_AVATAR');
          return MediaModerationSnapshot(
            status: result == 'REJECTED' ? result : 'APPROVED',
            photoPublication: result == 'REJECTED' ? 'SUPERSEDED' : result,
          );
        },
        delay: (_) => Completer<void>().future,
      );
      addTearDown(service.clear);
      service.track(crop('receipt-new', 'checkin-a'));
      await flush();
      expect(service.byId('receipt-new')?.state, switch (result) {
        'PUBLISHED' => PendingPublicMediaState.published,
        'SUPERSEDED' => PendingPublicMediaState.cancelled,
        'REJECTED' => PendingPublicMediaState.rejected,
        _ => PendingPublicMediaState.publishing,
      });
      expect(
        service.avatarPublicationChanges.value,
        result == 'WAITING' ? 0 : 1,
      );
    });
  }
  test(
    'logout while approval is in flight cannot refresh the next account',
    () async {
      final decision = Completer<MediaModerationSnapshot>();
      final service = PendingPublicMediaService.forTest(
        publishedLookup: (_) async => false,
        moderationLookup: (_) => decision.future,
        delay: (_) => Completer<void>().future,
      );
      addTearDown(service.clear);
      service.track(crop('receipt-new', 'checkin-a'));
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
    },
  );
}
