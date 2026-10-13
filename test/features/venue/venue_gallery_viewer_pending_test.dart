import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/ui/media_viewer_buttons.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_gallery_section.dart';

void main() {
  late PendingPublicMediaService service;
  late Future<void> Function(PendingPublicMedia, bool Function()) removePhoto;
  late List<PendingPublicMedia> removed;
  setUp(() {
    removed = [];
    removePhoto = (item, _) async {
      removed.add(item);
    };
    service = PendingPublicMediaService.forTest(
      publishedLookup: (_) async => false,
      moderationLookup: (_) => Completer<MediaModerationSnapshot>().future,
      delay: (_) => Completer<void>().future,
      removeGalleryPhoto: (item, current) => removePhoto(item, current),
    );
  });
  tearDown(() => service.clear());

  PendingPublicMedia reviewPhoto() => PendingPublicMedia(
    id: 'review',
    kind: PendingPublicMediaKind.venueGallery,
    venueId: 'venue-a',
    localPath: '',
    isVideo: false,
    createdAt: DateTime.now(),
    state: PendingPublicMediaState.underReview,
    hasServerReceipt: true,
  );

  Future<void> openReview(
    WidgetTester tester, {
    bool canEdit = true,
    bool published = false,
  }) async {
    service.track(reviewPhoto());
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => GalleryViewer(
                    venueId: 'venue-a',
                    items: published
                        ? const [
                            VenueGalleryItem(
                              id: 'existing',
                              url: '',
                              mediaType: 'photo',
                            ),
                          ]
                        : const [],
                    initialIndex: 0,
                    pendingUploads: service,
                    onDelete: canEdit ? (_) async {} : null,
                  ),
                ),
              ),
              child: const Text('Gallery'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'under-review photo can be removed, only after server acknowledgement',
    (tester) async {
      final request = Completer<void>();
      removePhoto = (item, _) {
        removed.add(item);
        return request.future;
      };
      await openReview(tester);
      expect(find.text('Under review'), findsOneWidget);
      await tester.tap(find.byType(MediaViewerDeleteButton));
      await tester.pumpAndSettle();
      expect(find.text('Remove this upload?'), findsOneWidget);
      expect(removed, isEmpty);
      await tester.tap(find.text('Remove upload').last);
      await tester.pump();
      expect(removed.single.id, 'review');
      expect(service.byId('review'), isNotNull);
      expect(service.isRemovingGalleryPhoto('review'), isTrue);
      request.complete();
      await tester.pumpAndSettle();
      expect(service.byId('review'), isNull);
      expect(find.text('Gallery'), findsOneWidget);
    },
  );

  testWidgets('declining cancellation keeps the photo under review', (
    tester,
  ) async {
    await openReview(tester);
    await tester.tap(find.byType(MediaViewerDeleteButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep photo'));
    await tester.pumpAndSettle();
    expect(removed, isEmpty);
    expect(service.byId('review'), isNotNull);
    expect(find.text('Under review'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failure retains the upload and permits a retry', (tester) async {
    removePhoto = (_, _) async => throw StateError('offline');
    await openReview(tester);
    await tester.tap(find.byType(MediaViewerDeleteButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove upload').last);
    await tester.pumpAndSettle();
    expect(service.byId('review'), isNotNull);
    expect(service.isRemovingGalleryPhoto('review'), isFalse);
    expect(find.textContaining('Could not remove this upload'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'approval during confirmation cannot close the dialog or lose the deletion target',
    (tester) async {
      await openReview(tester);
      await tester.tap(find.byType(MediaViewerDeleteButton));
      await tester.pumpAndSettle();
      // Publication normally removes the pending receipt from the local tracker.
      service.dismiss('review');
      await tester.pumpAndSettle();
      expect(find.text('Remove this upload?'), findsOneWidget);
      await tester.tap(find.text('Remove upload').last);
      await tester.pumpAndSettle();
      expect(removed.single.id, 'review');
      expect(removed.single.venueId, 'venue-a');
      expect(find.text('Gallery'), findsOneWidget);
    },
  );

  testWidgets('read-only gallery has no pending cancellation action', (
    tester,
  ) async {
    await openReview(tester, canEdit: false);
    expect(find.byType(MediaViewerDeleteButton), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

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
