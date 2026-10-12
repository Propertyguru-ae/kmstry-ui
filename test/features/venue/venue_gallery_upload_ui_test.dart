import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/content_moderation/presentation/pending_public_media_preview.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_gallery_section.dart';

class GalleryRepositoryStub extends VenueGalleryRepository {
  GalleryRepositoryStub(this.load);
  final Future<List<VenueGalleryItem>> Function(String) load;
  @override
  Future<List<VenueGalleryItem>> getGallery(String venueId) => load(venueId);
}

PendingPublicMedia item(
  String id, {
  String venue = 'venue-1',
  PendingPublicMediaState state = PendingPublicMediaState.preparing,
  String? message,
}) => PendingPublicMedia(
  id: id,
  kind: PendingPublicMediaKind.venueGallery,
  venueId: venue,
  localPath: '',
  isVideo: true,
  createdAt: DateTime(2026, 10, 1),
  state: state,
  message: message,
  hasServerReceipt: false,
);

PendingPublicMediaService uploads() => PendingPublicMediaService.forTest(
  publishedLookup: (_) async => false,
  moderationLookup: (_) async => const MediaModerationSnapshot(),
  delay: (_) => Completer<void>().future,
);

Widget screen(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets(
    'owner previews appear during initial gallery fetch with Add still available',
    (tester) async {
      final service = uploads();
      addTearDown(service.clear);
      service.track(item('photo-1'));
      service.track(item('video-2'));
      final repo = GalleryRepositoryStub(
        (_) => Completer<List<VenueGalleryItem>>().future,
      );
      await tester.pumpWidget(
        screen(
          VenueGallerySection.forTest(
            venueId: 'venue-1',
            canEdit: true,
            repository: repo,
            uploads: service,
          ),
        ),
      );
      expect(find.byType(PendingPublicMediaPreview), findsNWidgets(2));
      expect(find.text('Sharing'), findsNWidgets(2));
      expect(find.text('Add'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets('read-only gallery never displays owner-only upload previews', (
    tester,
  ) async {
    final service = uploads();
    addTearDown(service.clear);
    service.track(item('private'));
    await tester.pumpWidget(
      screen(
        VenueGallerySection.forTest(
          venueId: 'venue-1',
          canEdit: false,
          repository: GalleryRepositoryStub((_) async => []),
          uploads: service,
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(PendingPublicMediaPreview), findsNothing);
    expect(find.text('Sharing'), findsNothing);
    expect(find.text('Add'), findsNothing);
    expect(find.text('This venue has no gallery yet'), findsOneWidget);
  });

  testWidgets(
    'venue switch cannot show previous venue uploads or a late gallery response',
    (tester) async {
      final service = uploads();
      addTearDown(service.clear);
      service.track(item('old-private'));
      final oldResponse = Completer<List<VenueGalleryItem>>();
      final repo = GalleryRepositoryStub(
        (venue) => venue == 'venue-1' ? oldResponse.future : Future.value([]),
      );
      Widget section(String venue) => screen(
        VenueGallerySection.forTest(
          key: const ValueKey('gallery'),
          venueId: venue,
          canEdit: true,
          repository: repo,
          uploads: service,
        ),
      );
      await tester.pumpWidget(section('venue-1'));
      expect(find.byType(PendingPublicMediaPreview), findsOneWidget);
      await tester.pumpWidget(section('venue-2'));
      await tester.pump();
      oldResponse.complete([
        const VenueGalleryItem(id: 'old-public', url: '', mediaType: 'photo'),
      ]);
      await tester.pump();
      expect(find.byType(PendingPublicMediaPreview), findsNothing);
      expect(find.byType(GalleryTile), findsNothing);
      expect(find.text('No gallery yet'), findsOneWidget);
    },
  );

  testWidgets(
    'gallery publication signal refreshes the grid without a pull-to-refresh',
    (tester) async {
      final service = uploads();
      addTearDown(service.clear);
      var rows = <VenueGalleryItem>[];
      await tester.pumpWidget(
        screen(
          VenueGallerySection.forTest(
            venueId: 'venue-1',
            canEdit: true,
            repository: GalleryRepositoryStub((_) async => rows),
            uploads: service,
          ),
        ),
      );
      await tester.pump();
      rows = [
        const VenueGalleryItem(id: 'approved', url: '', mediaType: 'video'),
      ];
      VenueGalleryRepository.changes.value++;
      await tester.pump();
      expect(
        tester.widget<GalleryTile>(find.byType(GalleryTile)).item.id,
        'approved',
      );
    },
  );

  testWidgets(
    'gallery detail identifies the tapped rejection and keeps other outcomes',
    (tester) async {
      final service = uploads();
      addTearDown(service.clear);
      final rejected = item(
        'reject',
        state: PendingPublicMediaState.rejected,
        message: 'Text violates our guidelines.',
      );
      service.track(
        item(
          'other',
          state: PendingPublicMediaState.failed,
          message: 'Another upload failed.',
        ),
      );
      service.track(rejected);
      await tester.pumpWidget(
        screen(
          PublicMediaUploadDetails(
            item: rejected,
            service: service,
            onRetake: () {},
          ),
        ),
      );
      expect(
        find.text('Only shared gallery items are visible to others.'),
        findsOneWidget,
      );
      expect(find.byType(PendingPublicMediaPreview), findsNothing);
      expect(find.text('Text violates our guidelines.'), findsOneWidget);
      expect(find.text('Another upload failed.'), findsOneWidget);
      await tester.tap(find.text('Dismiss').first);
      await tester.pump();
      expect(service.byId('reject'), isNull);
      expect(service.byId('other'), isNotNull);
    },
  );

  testWidgets(
    'delayed gallery item explicitly stays private, no endless spinner',
    (tester) async {
      final service = uploads();
      addTearDown(service.clear);
      final delayed = item('delayed', state: PendingPublicMediaState.delayed);
      service.track(delayed);
      await tester.pumpWidget(
        screen(PublicMediaUploadDetails(item: delayed, service: service)),
      );
      expect(find.text('Taking longer'), findsOneWidget);
      expect(
        find.textContaining('This item is not visible to others yet'),
        findsOneWidget,
      );
      expect(
        find.textContaining('do not need to upload it again'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('full-colour gallery preview has no moderation veil', (
    tester,
  ) async {
    final gallery = PendingPublicMedia(
      id: 'photo',
      kind: PendingPublicMediaKind.venueGallery,
      venueId: 'venue-1',
      localPath: '/camera/photo.jpg',
      isVideo: false,
      createdAt: DateTime(2026, 10, 1),
    );
    await tester.pumpWidget(
      screen(
        SizedBox(
          width: 100,
          height: 100,
          child: PendingPublicMediaPreview(item: gallery),
        ),
      ),
    );
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.shield_outlined), findsNothing);
    final overlays = tester.widgetList<ColoredBox>(
      find.descendant(
        of: find.byType(PendingPublicMediaPreview),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(
      overlays.any((box) => box.color == Colors.black.withValues(alpha: .42)),
      false,
    );
  });
}
