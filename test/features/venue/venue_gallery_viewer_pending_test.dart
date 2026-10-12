import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/ui/media_viewer_buttons.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_gallery_section.dart';

void main() {
  late PendingPublicMediaService service;
  setUp(() {
    service = PendingPublicMediaService.forTest(
      publishedLookup: (_) async => false,
      moderationLookup: (_) => Completer<MediaModerationSnapshot>().future,
      delay: (_) => Completer<void>().future,
    );
  });
  tearDown(() => service.clear());

  testWidgets(
    'not-shared gallery upload opens in the swipeable viewer with its status, no popup',
    (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.library == 'image resource service') return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      service.track(
        PendingPublicMedia(
          id: 'rejected',
          kind: PendingPublicMediaKind.venueGallery,
          venueId: 'venue-a',
          localPath: 'assets/images/kmstrylogo.png',
          isVideo: false,
          createdAt: DateTime.now(),
          state: PendingPublicMediaState.rejected,
          hasServerReceipt: true,
          message: 'This photo did not meet our content policy.',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: GalleryViewer(
            venueId: 'venue-a',
            items: const [
              VenueGalleryItem(
                id: 'published',
                url: 'https://example.invalid/published.jpg',
                mediaType: 'photo',
              ),
            ],
            initialIndex: 0,
            pendingUploads: service,
            onDelete: (_) async {},
          ),
        ),
      );
      await tester.pump();

      // Pending upload first (same order as the gallery grid).
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.text('Photo not shared'), findsOneWidget);
      expect(
        find.text('This photo did not meet our content policy.'),
        findsOneWidget,
      );
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      // Delete applies to published media only.
      expect(find.byType(MediaViewerDeleteButton), findsNothing);

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.text('Photo not shared'), findsNothing);
      expect(find.byType(MediaViewerDeleteButton), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
