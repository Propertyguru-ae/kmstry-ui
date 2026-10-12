import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/event_photo_uploads.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/venue_event_detail_page.dart';

void main() {
  late PendingPublicMediaService service;
  setUp(() {
    service = PendingPublicMediaService.forTest(
      publishedLookup: (_) async => false,
      moderationLookup: (_) async => const MediaModerationSnapshot(),
      delay: (_) => Completer<void>().future,
    );
  });
  tearDown(() => service.clear());

  PendingPublicMedia pending(String id, PendingPublicMediaState state) =>
      PendingPublicMedia(
        id: id,
        kind: PendingPublicMediaKind.eventPhoto,
        venueId: 'venue-a',
        eventId: 'event-a',
        localPath: 'assets/images/kmstrylogo.png',
        isVideo: false,
        createdAt: DateTime.now(),
        state: state,
        hasServerReceipt: false,
      );

  testWidgets(
    'published and not-yet-published photos sit side by side in one grid',
    (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.library == 'image resource service') return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 357,
              child: EventGalleryGrid(
                photos: const ['https://example.invalid/published.jpg'],
                pending: [
                  pending('sharing', PendingPublicMediaState.preparing),
                  pending('review', PendingPublicMediaState.delayed),
                ],
                service: service,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(GridView), findsOneWidget);
      final tiles = find.byType(EventPendingPhotoTile);
      expect(tiles, findsNWidgets(2));
      final published = tester.getRect(
        find
            .ancestor(
              of: find.byType(Image).first,
              matching: find.byType(ClipRRect),
            )
            .first,
      );
      final first = tester.getRect(tiles.at(0));
      final second = tester.getRect(tiles.at(1));
      // Same row, same square size, in order: published → pending.
      expect(first.top, published.top);
      expect(second.top, published.top);
      expect(first.size, published.size);
      expect(second.size, published.size);
      expect(first.left, greaterThan(published.left));
      expect(second.left, greaterThan(first.left));
      expect(published.width, closeTo(published.height, 0.01));
      expect(tester.takeException(), isNull);
    },
  );
}
