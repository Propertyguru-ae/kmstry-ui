import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kmstry_frontend/features/stories/presentation/story_viewer_page.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_gallery_section.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_home_media_cards.dart';
import 'package:kmstry_frontend/features/venue_stories/data/venue_story_model.dart';
import 'package:kmstry_frontend/features/venue_stories/data/venue_story_repository.dart';

class _Gallery extends VenueGalleryRepository {
  _Gallery([this.read]);
  final Future<List<VenueGalleryItem>> Function()? read;
  int calls = 0;
  @override
  Future<List<VenueGalleryItem>> getGallery(String id) {
    calls++;
    return read?.call() ?? Future.value([]);
  }
}

class _Stories extends VenueStoryRepository {
  int calls = 0;
  @override
  Future<List<VenueStoryItem>> getVenueStories(String id) async {
    calls++;
    return [];
  }
}

class _StatisticsStories extends _Stories {
  int viewerCalls = 0;
  @override
  Future<List<VenueStoryItem>> getVenueStories(String id) async => [
    VenueStoryItem(
      id: 'story',
      mediaUrl: '',
      mediaType: 'photo',
      createdAt: DateTime(2026),
      expiresAt: DateTime(2030),
      viewCount: 7,
      canViewStats: true,
    ),
  ];
  @override
  Future<List<Map<String, dynamic>>> getViewers(String id) async {
    viewerCalls++;
    return [
      {'story_id': 'story', 'view_count': 7, 'viewers': []},
    ];
  }
}

void main() {
  for (final canPost in [false, true]) {
    for (final canView in [false, true]) {
      testWidgets('home separates posting=$canPost from statistics=$canView', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        });
        final stories = _StatisticsStories();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: VenueHomeMediaCards(
                venueId: 'venue',
                venueName: 'Cafe',
                canEditStory: canPost,
                canViewStoryStats: canView,
                canEditGallery: false,
                storyRepository: stories,
                galleryRepository: _Gallery(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Story').first);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        expect(find.byType(StoryViewerPage), findsOneWidget);
        expect(
          find.byIcon(Icons.remove_red_eye_outlined),
          canView ? findsOneWidget : findsNothing,
        );
        expect(find.text('7'), canView ? findsOneWidget : findsNothing);
        expect(stories.viewerCalls, canView ? 1 : 0);
      });
    }
  }
  testWidgets(
    'Home media stays warm and hidden changes refresh each section once on return, never on upload progress',
    (tester) async {
      final gallery = _Gallery();
      final stories = _Stories();
      Widget page(bool active) => MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              VenueHomeMediaCards(
                venueId: 'venue',
                venueName: 'Cafe',
                canEditStory: true,
                canEditGallery: true,
                isActive: active,
                galleryRepository: gallery,
                storyRepository: stories,
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(page(true));
      await tester.pumpAndSettle();
      await tester.pumpWidget(page(false));
      await tester.pumpWidget(page(true));
      await tester.pumpAndSettle();
      expect(gallery.calls, 1);
      expect(stories.calls, 1);
      // Only a repaint/owner preview update, not an authenticated media query.
      PendingPublicMediaService.instance.changes.value++;
      await tester.pumpAndSettle();
      expect(gallery.calls, 1);
      expect(stories.calls, 1);
      await tester.pumpWidget(page(false));
      VenueGalleryRepository.changes.value++;
      VenueGalleryRepository.changes.value++;
      VenueStoryRepository.changes.value++;
      await tester.pumpAndSettle();
      expect(gallery.calls, 1);
      expect(stories.calls, 1);
      await tester.pumpWidget(page(true));
      await tester.pumpAndSettle();
      expect(gallery.calls, 2);
      expect(stories.calls, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Profile gallery defers hidden changes and respects explicit refresh without a full-grid spinner',
    (tester) async {
      final gallery = _Gallery();
      Widget page(bool active, [int revision = 0]) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: VenueGallerySection(
              venueId: 'venue',
              canEdit: false,
              isActive: active,
              repository: gallery,
              refreshRevision: revision,
            ),
          ),
        ),
      );
      await tester.pumpWidget(page(true));
      await tester.pumpAndSettle();
      await tester.pumpWidget(page(false));
      VenueGalleryRepository.changes.value++;
      VenueGalleryRepository.changes.value++;
      await tester.pumpAndSettle();
      expect(gallery.calls, 1);
      await tester.pumpWidget(page(true));
      await tester.pumpAndSettle();
      expect(gallery.calls, 2);
      await tester.pumpWidget(page(true, 1));
      await tester.pumpAndSettle();
      expect(gallery.calls, 3);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'gallery publication bursts during a query are coalesced into one fresh follow-up',
    (tester) async {
      final first = Completer<List<VenueGalleryItem>>();
      var calls = 0;
      final gallery = _Gallery(
        () => ++calls == 1 ? first.future : Future.value([]),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VenueGallerySection(
                venueId: 'venue',
                canEdit: false,
                repository: gallery,
              ),
            ),
          ),
        ),
      );
      VenueGalleryRepository.changes.value++;
      VenueGalleryRepository.changes.value++;
      expect(gallery.calls, 1);
      first.complete([]);
      await tester.pumpAndSettle();
      expect(gallery.calls, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
