import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/media/media_network_url.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/stories/data/story_model.dart';
import 'package:kmstry_frontend/features/stories/data/story_repository.dart';
import 'package:kmstry_frontend/features/venue/data/active_checkin_model.dart';
import 'package:kmstry_frontend/features/venue/data/external_partnership_model.dart';
import 'package:kmstry_frontend/features/venue/data/external_partnership_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_reporsitory.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';
import 'package:kmstry_frontend/features/venue/data/google_photo_source.dart';
import 'package:kmstry_frontend/features/venue/presentation/google_place_photo.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_detail_page.dart';
import 'package:kmstry_frontend/features/venue_stories/data/venue_story_model.dart';
import 'package:kmstry_frontend/features/venue_stories/data/venue_story_repository.dart';

class _Context extends VenueContextRepository {
  late Future<Map<String, dynamic>> Function() identity;
  late Future<List<VenueUpcomingEvent>> Function() events;
  Future<Map<String, dynamic>> Function()? google;
  int identityCalls = 0;
  int eventCalls = 0;
  int legacyCalls = 0;
  int resolutionCalls = 0;
  int photoSourceCalls = 0;
  Future<GooglePhotoSource> Function()? photoSource;
  @override
  Future<GooglePhotoSource> getGooglePhotoSource(String url) {
    photoSourceCalls++;
    return photoSource?.call() ??
        Future.error(StateError('Unexpected photo source lookup'));
  }

  Uri? venueReportUrl;
  @override
  Future<Uri?> getVenueReportUrl(String venueId) async => venueReportUrl;

  @override
  Future<Map<String, dynamic>> getVenueDetailIdentity(String id) {
    identityCalls++;
    return identity();
  }

  @override
  Future<List<VenueUpcomingEvent>> getVenueDetailUpcomingEvents(String id) {
    eventCalls++;
    return events();
  }

  @override
  Future<Map<String, dynamic>> getVenueById(String id) {
    legacyCalls++;
    throw StateError('Detail must not wait for the full event payload');
  }

  @override
  Future<Map<String, dynamic>> getVenueDetails(String id) =>
      google?.call() ?? Future.value({});
  @override
  Future<Map<String, dynamic>> resolveVenueFromPlace(String id) async {
    resolutionCalls++;
    return {'id': 'resolved'};
  }

  @override
  Future<Map<String, dynamic>> followVenue(String id) async => {
    'ok': true,
    'isFollowing': true,
    'followerCount': 10,
  };
}

class _Checkins extends VenueCheckinRepository {
  @override
  Future<ActiveCheckin?> getActiveCheckin() async => null;
}

class _Auth extends AuthRepository {
  @override
  Future<Map<String, dynamic>> getMe({bool forceRefresh = false}) async => {};
}

class _Gallery extends VenueGalleryRepository {
  int calls = 0;
  @override
  Future<List<VenueGalleryItem>> getGallery(String id) async {
    calls++;
    return [];
  }
}

class _VenueStories extends VenueStoryRepository {
  int calls = 0;
  @override
  Future<List<VenueStoryItem>> getVenueStories(String id) async {
    calls++;
    return [];
  }
}

class _Stories extends StoryRepository {
  @override
  Future<List<StoryGroup>> getVenueStories(String id) async => [];
  @override
  Future<List<StoryItem>> getMyStories() async => [];
}

class _Benefits extends ExternalPartnershipRepository {
  int calls = 0;
  Future<List<ExternalPartnershipModel>> Function()? read;
  @override
  Future<List<ExternalPartnershipModel>> getActivePartnerships(String id) {
    calls++;
    return read?.call() ?? Future.value([]);
  }
}

class _Api extends ApiClient {
  final paths = <String>[];
  final auth = <String?>[];
  dynamic response;
  @override
  Future<dynamic> get(
    String path, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    paths.add(path);
    auth.add(headers?['Authorization']);
    return response;
  }
}

VenueUpcomingEvent _event(String title) => VenueUpcomingEvent(
  id: title,
  title: title,
  description: 'Complete event description',
  startAt: DateTime.now().add(const Duration(hours: 1)),
  endAt: DateTime.now().add(const Duration(hours: 2)),
  priceAed: 40,
  currency: 'AED',
  capacity: 50,
  rsvpCount: 7,
);
Venue _venue({
  bool google = false,
  String photoUrl = '',
  List<VenueUpcomingEvent> events = const [],
}) => Venue(
  id: google ? 'place' : 'venue',
  placeId: google ? 'place' : null,
  name: 'Cafe Alpha',
  type: 'cafe',
  status: 'Active',
  address: 'Known address',
  city: 'Dubai',
  photoUrl: photoUrl,
  latitude: double.nan,
  longitude: double.nan,
  tag: '',
  source: google ? 'google' : 'db',
  isInDb: !google,
  canCheckin: !google,
  checkinCountActive: 0,
  checkinCountMale: 0,
  checkinCountFemale: 0,
  description: 'Known About from Home or Map',
  rating: 4.7,
  openNow: true,
  openingHours: {'open_now': true},
  upcomingEvents: events,
);
Map<String, dynamic> _identity({String about = 'Fresh About'}) => {
  'id': 'venue',
  'description': about,
  'isFollowing': false,
  'followerCount': 9,
  'photo': null,
  'openingHours': {'open_now': true},
};

Future<void> _pump(
  WidgetTester tester,
  _Context repo, {
  Venue? venue,
  _Benefits? benefits,
  _Gallery? gallery,
  _VenueStories? stories,
  GooglePhotoLinkLauncher? reportLinkLauncher,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: VenueDetailPage(
        venue: venue ?? _venue(),
        venueContextRepository: repo,
        checkinRepository: _Checkins(),
        authRepository: _Auth(),
        venueStoryRepository: stories ?? _VenueStories(),
        partnershipRepository: benefits ?? _Benefits(),
        storyRepository: _Stories(),
        galleryRepository: gallery ?? _Gallery(),
        reportLinkLauncher: reportLinkLauncher,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

// Dispose first; deferred GPS/auth callbacks are mounted-guarded, not timers
// that should keep a closed route alive.
Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PendingPublicMediaService.instance.clear();
  });

  testWidgets(
    'venue detail keeps Google credits below the cover and above identity',
    (tester) async {
      const url =
          'https://pre-prod-api.kmstry.net/venues/places/photo/cover-layout.signature';
      final decoded = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        ui.Canvas(recorder).drawColor(Colors.blue, ui.BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(1, 1);
        picture.dispose();
        return image;
      });
      PaintingBinding.instance.imageCache.putIfAbsent(
        NetworkImage(resolveMediaNetworkUrl(url)),
        () => OneFrameImageStreamCompleter(
          Future.value(ImageInfo(image: decoded!)),
        ),
      );
      addTearDown(() {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      });
      final repo = _Context();
      repo.identity = () async => {..._identity(), 'photo': url};
      repo.events = () async => [];
      repo.photoSource = () async => GooglePhotoSource(
        photoUrl: url,
        authors: const [GooglePhotoAuthor(name: 'Photo contributor')],
        sourceUrl: Uri.parse('https://www.google.com/maps/photo/example'),
        reportUrl: Uri.parse('https://www.google.com/maps/photo/example'),
        reportIsDirect: false,
      );
      await _pump(tester, repo, venue: _venue(photoUrl: url));
      await tester.pump();
      final cover = tester.getRect(
        find.byKey(const ValueKey('google-photo-cover-image')),
      );
      final credits = tester.getRect(
        find.byKey(const ValueKey('google-photo-credits-footer')),
      );
      final title = tester.getRect(find.text('Cafe Alpha'));
      expect(cover.height, 210);
      expect(credits.top, greaterThanOrEqualTo(cover.bottom));
      expect(title.top, greaterThanOrEqualTo(credits.bottom));
      final widget = tester.widget<GooglePlacePhoto>(
        find.byType(GooglePlacePhoto),
      );
      expect(widget.overlay, isNull);
      expect(tester.takeException(), isNull);
      await _close(tester);
    },
  );

  testWidgets(
    'venue report icon separates venue and photo without opening the avatar',
    (tester) async {
      const url =
          'https://kmstry-test-media.fra1.digitaloceanspaces.com/venue-photos/photos/current.jpg';
      final repo = _Context();
      repo.identity = () async => {..._identity(), 'photo': url};
      repo.events = () async => [];
      await _pump(tester, repo, venue: _venue(photoUrl: url));
      await tester.tap(find.byTooltip('Report'));
      await tester.pumpAndSettle();
      expect(find.text('Report venue'), findsOneWidget);
      expect(find.text('Report photo'), findsOneWidget);
      expect(find.text('Report Google photo'), findsNothing);
      expect(find.text('Reviewed by the KMSTRY team.'), findsOneWidget);
      await tester.tap(find.text('Report photo'));
      await tester.pumpAndSettle();
      expect(find.text('Why are you reporting this photo?'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(repo.photoSourceCalls, 0);
      await _close(tester);
    },
  );

  testWidgets('venue choice still opens the existing venue reason form', (
    tester,
  ) async {
    final repo = _Context();
    repo.identity = () async => _identity();
    repo.events = () async => [];
    await _pump(tester, repo);
    await tester.tap(find.byTooltip('Report'));
    await tester.pumpAndSettle();
    expect(find.text('Report photo'), findsNothing);
    await tester.tap(find.text('Report venue'));
    await tester.pumpAndSettle();
    expect(find.text('Why are you reporting this venue?'), findsOneWidget);
    await _close(tester);
  });

  testWidgets(
    'Google photo choice opens the KMSTRY form without external navigation',
    (tester) async {
      const url =
          'https://pre-prod-api.kmstry.net/venues/places/photo/payload.signature';
      final reportUrl = Uri.parse(
        'https://www.google.com/local/imagery/report?photo=123',
      );
      final repo = _Context();
      repo.identity = () async => {..._identity(), 'photo': url};
      repo.events = () async => [];
      repo.photoSource = () async => GooglePhotoSource(
        photoUrl: url,
        authors: [],
        sourceUrl: Uri.parse('https://www.google.com/maps/photo/123'),
        reportUrl: reportUrl,
        reportIsDirect: true,
      );
      final opened = <Uri>[];
      await _pump(
        tester,
        repo,
        venue: _venue(photoUrl: url),
        reportLinkLauncher: (uri) async {
          opened.add(uri);
          return true;
        },
      );
      // Large covers load their author credits without waiting for a tap.
      expect(repo.photoSourceCalls, 1);
      await tester.tap(find.byTooltip('Report'));
      await tester.pumpAndSettle();
      expect(find.text('Report photo'), findsOneWidget);
      expect(find.text('Report Google photo'), findsNothing);
      expect(find.text('Reviewed by the KMSTRY team.'), findsOneWidget);
      await tester.tap(find.text('Report photo'));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);
      expect(repo.photoSourceCalls, 2);
      expect(find.byType(GooglePhotoSourceSheet), findsNothing);
      expect(find.text('Why are you reporting this photo?'), findsOneWidget);
      await _close(tester);
    },
  );

  testWidgets('unclaimed imported venue uses the provider destination', (
    tester,
  ) async {
    final repo = _Context();
    repo.identity = () async => _identity();
    repo.events = () async => [];
    final destination = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=Place&query_place_id=place',
    );
    repo.venueReportUrl = destination;
    final opened = <Uri>[];
    await _pump(
      tester,
      repo,
      reportLinkLauncher: (uri) async {
        opened.add(uri);
        return true;
      },
    );
    await tester.tap(find.byTooltip('Report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report venue'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    expect(
      find.textContaining('reviewed by Google, not KMSTRY'),
      findsOneWidget,
    );
    await tester.tap(find.text('Continue to Google Maps'));
    await tester.pumpAndSettle();
    expect(opened, [destination]);
    expect(find.text('Why are you reporting this venue?'), findsNothing);
    await _close(tester);
  });

  testWidgets('canceling an external venue report never opens Google', (
    tester,
  ) async {
    final repo = _Context();
    repo.identity = () async => _identity();
    repo.events = () async => [];
    repo.venueReportUrl = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=Place',
    );
    final opened = <Uri>[];
    await _pump(
      tester,
      repo,
      reportLinkLauncher: (uri) async {
        opened.add(uri);
        return true;
      },
    );
    await tester.tap(find.byTooltip('Report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report venue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    expect(find.text('Continue on Google Maps?'), findsNothing);
    await tester.tap(find.byTooltip('Report'));
    await tester.pumpAndSettle();
    expect(find.text('Report venue'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('legacy Google photos also use the KMSTRY photo report form', (
    tester,
  ) async {
    const photoUrl =
        'https://pre-prod-api.kmstry.net/venues/places/photo/payload.signature';
    final mapsUrl = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=Place',
    );
    final repo = _Context();
    repo.identity = () async => {..._identity(), 'photo': photoUrl};
    repo.events = () async => [];
    repo.photoSource = () async => GooglePhotoSource(
      photoUrl: photoUrl,
      authors: [],
      sourceUrl: mapsUrl,
      reportUrl: mapsUrl,
      reportIsDirect: false,
    );
    final opened = <Uri>[];
    await _pump(
      tester,
      repo,
      venue: _venue(photoUrl: photoUrl),
      reportLinkLauncher: (uri) async {
        opened.add(uri);
        return true;
      },
    );
    await tester.tap(find.byTooltip('Report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report photo'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    expect(find.text('Why are you reporting this photo?'), findsOneWidget);
    expect(find.text('Continue to Google Maps'), findsNothing);
    expect(find.textContaining('Report submitted'), findsNothing);
    await _close(tester);
  });

  test(
    'section APIs are authenticated, separate and preserve event fields',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'access_token': 'test-viewer',
      });
      final api = _Api();
      final repo = VenueContextRepository(apiClient: api);
      api.response = _identity();
      expect(await repo.getVenueDetailIdentity('venue'), _identity());
      api.response = [
        {
          'id': 'event',
          'title': 'Event',
          'description': 'Full description',
          'startAt': DateTime.now().toIso8601String(),
          'endAt': DateTime.now()
              .add(const Duration(hours: 1))
              .toIso8601String(),
          'photo': 'https://example.test/signed.jpg',
          'photos': ['https://example.test/signed-gallery.jpg'],
          'priceAed': 40,
          'currency': 'AED',
          'capacity': 50,
          'rsvpCount': 7,
          'recurringRuleId': 'series',
          'recurrence': {'frequency': 'weekly', 'interval': 2},
          'partnershipCount': 1,
        },
      ];
      final event = (await repo.getVenueDetailUpcomingEvents('venue')).single;
      expect(event.description, 'Full description');
      expect(event.photo, 'https://example.test/signed.jpg');
      expect(event.photos, ['https://example.test/signed-gallery.jpg']);
      expect(event.currency, 'AED');
      expect(event.capacity, 50);
      expect(event.rsvpCount, 7);
      expect(event.recurringRuleId, 'series');
      expect(event.partnershipCount, 1);
      expect(api.paths, [
        '/venues/venue/detail/identity',
        '/venues/venue/detail/upcoming-events',
      ]);
      expect(api.auth, ['Bearer test-viewer', 'Bearer test-viewer']);
    },
  );

  test('section reads never send unauthenticated requests', () async {
    final api = _Api();
    final repo = VenueContextRepository(apiClient: api);
    await expectLater(repo.getVenueDetailIdentity('venue'), throwsException);
    await expectLater(
      repo.getVenueDetailUpcomingEvents('venue'),
      throwsException,
    );
    expect(api.paths, isEmpty);
  });

  testWidgets(
    'Home/Map snapshot paints before slow identity and events; all sections start independently',
    (tester) async {
      final identity = Completer<Map<String, dynamic>>();
      final events = Completer<List<VenueUpcomingEvent>>();
      final repo = _Context();
      repo.identity = () => identity.future;
      repo.events = () => events.future;
      final benefits = _Benefits();
      final gallery = _Gallery();
      final stories = _VenueStories();
      await _pump(
        tester,
        repo,
        venue: _venue(events: [_event('Known Event')]),
        benefits: benefits,
        gallery: gallery,
        stories: stories,
      );
      expect(find.text('Cafe Alpha'), findsOneWidget);
      expect(find.text('Known address'), findsOneWidget);
      expect(find.text('Known About from Home or Map'), findsOneWidget);
      expect(find.text('Known Event'), findsOneWidget);
      expect(find.text('4.7'), findsOneWidget);
      expect(find.text('Open now'), findsOneWidget);
      expect(repo.identityCalls, 1);
      expect(repo.eventCalls, 1);
      expect(repo.legacyCalls, 0);
      expect(benefits.calls, 1);
      expect(gallery.calls, 1);
      expect(stories.calls, 1);
      expect(tester.takeException(), isNull);
      await _close(tester);
    },
  );

  testWidgets('identity and benefits show while event media is still pending', (
    tester,
  ) async {
    final pending = Completer<List<VenueUpcomingEvent>>();
    final repo = _Context();
    repo.identity = () async => _identity();
    repo.events = () => pending.future;
    final benefits = _Benefits()
      ..read = () async => [
        ExternalPartnershipModel(
          id: 'benefit',
          venueId: 'venue',
          platform: ExternalPartnershipPlatform.OTHER,
          platformLabel: 'Partner',
          offerType: ExternalPartnershipOfferType.OTHER,
          offerLabel: 'Complete benefit',
          status: ExternalPartnershipStatus.ACTIVE,
          createdAt: DateTime.now(),
        ),
      ];
    await _pump(tester, repo, benefits: benefits);
    expect(find.text('Fresh About'), findsOneWidget);
    expect(find.text('Partner'), findsOneWidget);
    pending.complete([_event('Fresh Event')]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Fresh Event'), findsOneWidget);
    await _close(tester);
  });

  testWidgets(
    'events show even if identity is slow or fails; empty authoritative list clears old events',
    (tester) async {
      final identity = Completer<Map<String, dynamic>>();
      var events = [_event('Fresh Event')];
      final repo = _Context();
      repo.identity = () => identity.future;
      repo.events = () async => events;
      await _pump(tester, repo, venue: _venue(events: [_event('Old Event')]));
      expect(find.text('Fresh Event'), findsOneWidget);
      expect(find.text('Old Event'), findsNothing);
      expect(find.text('Known About from Home or Map'), findsOneWidget);
      identity.completeError(StateError('offline'));
      await tester.pump();
      events = [];
      unawaited(
        tester
            .state<RefreshIndicatorState>(find.byType(RefreshIndicator))
            .show(),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(repo.eventCalls, 2);
      expect(find.text('Fresh Event'), findsNothing);
      expect(find.text('Known About from Home or Map'), findsOneWidget);
      await _close(tester);
    },
  );

  testWidgets('older reads cannot overwrite refreshed sections', (
    tester,
  ) async {
    final firstIdentity = Completer<Map<String, dynamic>>();
    final firstEvents = Completer<List<VenueUpcomingEvent>>();
    var refreshing = false;
    final repo = _Context();
    repo.identity = () => refreshing
        ? Future.value(_identity(about: 'Newest About'))
        : firstIdentity.future;
    repo.events = () => refreshing
        ? Future.value([_event('Newest Event')])
        : firstEvents.future;
    await _pump(tester, repo);
    refreshing = true;
    unawaited(
      tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('Newest About'), findsOneWidget);
    expect(find.text('Newest Event'), findsOneWidget);
    firstIdentity.complete(_identity(about: 'Stale About'));
    firstEvents.complete([_event('Stale Event')]);
    await tester.pump();
    expect(find.text('Stale About'), findsNothing);
    expect(find.text('Stale Event'), findsNothing);
    expect(find.text('Newest About'), findsOneWidget);
    expect(find.text('Newest Event'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('late identity cannot undo a successful follow', (tester) async {
    final identity = Completer<Map<String, dynamic>>();
    final repo = _Context();
    repo.identity = () => identity.future;
    repo.events = () async => [];
    await _pump(tester, repo);
    await tester.ensureVisible(find.text('Follow'));
    await tester.tap(find.text('Follow'));
    await tester.pump();
    expect(find.text('Following'), findsOneWidget);
    identity.complete(_identity());
    await tester.pump();
    expect(find.text('Following'), findsOneWidget);
    expect(find.text('Follow'), findsNothing);
    await _close(tester);
  });

  testWidgets('late responses from a previous login session are ignored', (
    tester,
  ) async {
    final identity = Completer<Map<String, dynamic>>();
    final events = Completer<List<VenueUpcomingEvent>>();
    final repo = _Context();
    repo.identity = () => identity.future;
    repo.events = () => events.future;
    await _pump(tester, repo);
    PendingPublicMediaService.instance.clear();
    identity.complete(_identity(about: 'Other session About'));
    events.complete([_event('Other session Event')]);
    await tester.pump();
    expect(find.text('Other session About'), findsNothing);
    expect(find.text('Other session Event'), findsNothing);
    await _close(tester);
  });

  testWidgets(
    'Google-only Map snapshot appears immediately and resolves only once for stories',
    (tester) async {
      final google = Completer<Map<String, dynamic>>();
      final repo = _Context();
      repo.identity = () async => _identity();
      repo.events = () async => [];
      repo.google = () => google.future;
      final stories = _VenueStories();
      await _pump(tester, repo, venue: _venue(google: true), stories: stories);
      expect(find.text('Cafe Alpha'), findsOneWidget);
      expect(find.text('4.7'), findsOneWidget);
      expect(find.text('Known About from Home or Map'), findsOneWidget);
      expect(repo.resolutionCalls, 1);
      expect(stories.calls, 1);
      expect(repo.identityCalls, 0);
      expect(repo.eventCalls, 0);
      expect(repo.legacyCalls, 0);
      google.complete({
        'address': 'Fresh Google address',
        'openingHours': {'open_now': false},
      });
      await tester.pump();
      expect(find.text('Fresh Google address'), findsOneWidget);
      expect(find.text('Closed'), findsOneWidget);
      await _close(tester);
    },
  );

  testWidgets('a venue without a photo shows no stock cover or avatar', (
    tester,
  ) async {
    final repo = _Context();
    repo.identity = () async => _identity();
    repo.events = () async => const [];
    await _pump(tester, repo);

    expect(find.text('Cafe Alpha'), findsOneWidget);
    // Eskiden boş fotoğrafta Unsplash restoran görseli kapak ve avatar olurdu.
    expect(find.byType(GooglePlacePhoto), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) => w is CachedImage && w.url.contains('unsplash'),
      ),
      findsNothing,
    );
    expect(find.byIcon(Icons.storefront_rounded), findsNothing);
    await _close(tester);
  });
}
