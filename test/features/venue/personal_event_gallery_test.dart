import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/user/user_session.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/personal_event_detail_page.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/event_gallery_viewer.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/venue_event_detail_page.dart';

const _photos = [
  'https://example.invalid/cover.jpg',
  'https://example.invalid/second.jpg',
  'https://example.invalid/third.jpg',
];

class _DetailApi extends ApiClient {
  _DetailApi(this.event, this.photos);
  final VenueUpcomingEvent event;
  final List<String> photos;

  @override
  Future<dynamic> get(
    String path, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 10),
  }) async => {
    'id': event.id,
    'title': event.title,
    'startAt': event.startAt.toUtc().toIso8601String(),
    'endAt': event.endAt.toUtc().toIso8601String(),
    'photo': photos.isEmpty ? null : photos.first,
    'photos': photos,
    'rsvpCount': 0,
    'userHasRsvp': false,
    'capacity': null,
  };
}

void main() {
  late VenueUpcomingEvent event;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'test-user'});
    SharedPreferences.setMockInitialValues({});
    PendingPublicMediaService.instance.clear();
    UserSession.instance.applyFromMe({'isPremium': false});
    final start = DateTime.now().add(const Duration(days: 1));
    event = VenueUpcomingEvent(
      id: 'event-a',
      title: 'Jazz Night',
      startAt: start,
      endAt: start.add(const Duration(hours: 3)),
    );
  });

  Future<void> open(WidgetTester tester, List<String> photos) async {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.library == 'image resource service') return;
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: PersonalEventDetailPage(
          event: event,
          venueId: 'venue-a',
          venueName: 'Test Cafe Alpha',
          apiClient: _DetailApi(event, photos),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'visitors see every event photo in the gallery, not only the cover',
    (tester) async {
      await open(tester, _photos);

      final grid = find.byType(EventGalleryGrid);
      await tester.ensureVisible(grid);
      expect(find.text('GALLERY'), findsOneWidget);
      expect(tester.widget<EventGalleryGrid>(grid).photos, _photos);
      expect(
        find.descendant(of: grid, matching: find.byType(Image)),
        findsNWidgets(3),
      );

      // Opens the swipeable full-screen viewer on the tapped photo.
      await tester.tap(
        find.descendant(of: grid, matching: find.byType(Image)).at(1),
      );
      await tester.pumpAndSettle();
      final viewer = tester.widget<EventGalleryViewer>(
        find.byType(EventGalleryViewer),
      );
      expect(viewer.photos, _photos);
      expect(viewer.initialIndex, 1);
      expect(viewer.includePendingUploads, isFalse);
    },
  );

  testWidgets('events without photos show no empty gallery', (tester) async {
    await open(tester, const []);
    expect(find.text('GALLERY'), findsNothing);
    expect(find.byType(EventGalleryGrid), findsNothing);
  });
}
