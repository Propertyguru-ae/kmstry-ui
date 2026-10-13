import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/media/media_network_url.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'package:kmstry_frontend/features/venue/data/google_photo_source.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/google_place_photo.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_list_item.dart';

const photo =
    'https://pre-prod-api.kmstry.net/venues/places/photo/payload.signature';
final source = GooglePhotoSource(
  photoUrl: photo,
  authors: [
    GooglePhotoAuthor(
      name: 'Alice',
      profileUrl: Uri.parse('https://www.google.com/maps/contrib/alice'),
    ),
  ],
  sourceUrl: Uri.parse('https://www.google.com/maps/photo/123'),
  reportUrl: Uri.parse('https://www.google.com/local/imagery/report?photo=123'),
  reportIsDirect: true,
);

class _Api extends ApiClient {
  final paths = <String>[];
  @override
  Future<dynamic> get(
    String path, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    paths.add(path);
    return {
      'provider': 'GOOGLE_MAPS',
      'photoUrl': photo,
      'authors': [],
      'sourceUrl': source.sourceUrl.toString(),
      'reportUrl': source.reportUrl.toString(),
      'reportIsDirect': true,
    };
  }
}

Completer<ImageInfo> _pendingPhoto(String url) {
  final result = Completer<ImageInfo>();
  PaintingBinding.instance.imageCache.putIfAbsent(
    NetworkImage(resolveMediaNetworkUrl(url)),
    () => OneFrameImageStreamCompleter(result.future),
  );
  return result;
}

Future<ImageInfo> _decodedPhoto(WidgetTester tester) async {
  final image = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(Colors.blue, ui.BlendMode.src);
    final picture = recorder.endRecording();
    final decoded = await picture.toImage(1, 1);
    picture.dispose();
    return decoded;
  });
  return ImageInfo(image: image!);
}

Widget _photoHost(
  String url, {
  Key? photoKey,
  GooglePhotoSourceLoader? sourceLoader,
  bool showSourceBadge = true,
}) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 240,
      height: 140,
      child: GooglePlacePhoto(
        url,
        key: photoKey,
        sourceLoader: sourceLoader,
        showSourceBadge: showSourceBadge,
        errorWidget: (_) => const Text('Photo unavailable'),
        overlay: const ColoredBox(
          key: ValueKey('photo-overlay'),
          color: Colors.transparent,
        ),
      ),
    ),
  ),
);

void main() {
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  test(
    'metadata calls current build API path, not the advertised origin',
    () async {
      final api = _Api();
      final result = await VenueContextRepository(
        apiClient: api,
      ).getGooglePhotoSource(photo);
      expect(api.paths, ['/venues/places/photo/payload.signature/source']);
      expect(result.photoUrl, startsWith(AppConfig.baseUrl));
    },
  );

  test('invalid/non-proxy URL never makes a metadata request', () async {
    final api = _Api();
    await expectLater(
      VenueContextRepository(
        apiClient: api,
      ).getGooglePhotoSource('https://evil.test/image.jpg'),
      throwsFormatException,
    );
    expect(api.paths, isEmpty);
  });

  test('metadata rejects unsafe source/report links', () {
    expect(
      () => GooglePhotoSource.fromJson({
        'provider': 'GOOGLE_MAPS',
        'photoUrl': photo,
        'sourceUrl': 'https://google.com.evil.test/',
        'reportUrl': source.reportUrl.toString(),
      }),
      throwsFormatException,
    );
    expect(safeGooglePhotoLink('javascript:alert(1)'), isNull);
    expect(safeGooglePhotoLink('https://www.google.com@evil.test/'), isNull);
    expect(
      safeGooglePhotoLink('https://www.google.com/url?q=https://evil.test/'),
      isNull,
    );
    expect(
      safeGooglePhotoLink('https://lh3.googleusercontent.com/alice'),
      isNull,
    );
    expect(
      safeGooglePhotoLink(
        'https://lh3.googleusercontent.com/alice',
        avatar: true,
      ),
      isNotNull,
    );
  });

  testWidgets(
    'owned photos keep existing rendering without provider metadata',
    (tester) async {
      var loads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 220,
              height: 130,
              child: GooglePlacePhoto(
                '',
                sourceLoader: (_) async {
                  loads++;
                  return source;
                },
              ),
            ),
          ),
        ),
      );
      expect(find.byType(CachedImage), findsOneWidget);
      expect(find.text('Google Maps · Credits'), findsNothing);
      expect(loads, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'credits expose the optional Google report link without a fullscreen photo',
    (tester) async {
      var loads = 0;
      final pending = Completer<GooglePhotoSource>();
      final image = _pendingPhoto(photo);
      image.complete(await _decodedPhoto(tester));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 240,
              height: 140,
              child: GooglePlacePhoto(
                photo,
                sourceLoader: (_) {
                  loads++;
                  return pending.future;
                },
                overlay: Container(color: Colors.transparent),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(loads, 0);
      await tester.tap(find.text('Google Maps · Credits'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(loads, 1);
      expect(find.byType(GooglePhotoSourceSheet), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsNothing);
      pending.complete(source);
      await tester.pump();
      await tester.pump();
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('View on Google Maps'), findsOneWidget);
      expect(find.text('Report Google photo'), findsNothing);
      expect(find.text('Report photo'), findsNothing);
      expect(find.text('Report to Google Maps'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('credits appear only once the Google photo is decoded', (
    tester,
  ) async {
    final pending = _pendingPhoto(photo);
    await tester.pumpWidget(_photoHost(photo));
    expect(find.text('Google Maps · Credits'), findsNothing);
    expect(find.byKey(const ValueKey('photo-overlay')), findsOneWidget);
    pending.complete(await _decodedPhoto(tester));
    await tester.pump();
    await tester.pump();
    expect(find.text('Google Maps · Credits'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'removed photo hides credits; a restored photo shows them again',
    (tester) async {
      var sourceLoads = 0;
      Future<GooglePhotoSource> loader(String _) async {
        sourceLoads++;
        return source;
      }

      final rejected = _pendingPhoto(photo);
      await tester.pumpWidget(_photoHost(photo, sourceLoader: loader));
      rejected.completeError(
        NetworkImageLoadException(statusCode: 404, uri: Uri.parse(photo)),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Photo unavailable'), findsOneWidget);
      expect(find.text('Google Maps · Credits'), findsNothing);
      expect(find.byKey(const ValueKey('photo-overlay')), findsOneWidget);
      expect(sourceLoads, 0);
      expect(tester.takeException(), isNull);

      // Reopening after an admin restores the source resolves the same URL.
      await tester.pumpWidget(const SizedBox());
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      final restored = _pendingPhoto(photo);
      restored.complete(await _decodedPhoto(tester));
      await tester.pumpWidget(_photoHost(photo, sourceLoader: loader));
      await tester.pump();
      expect(find.text('Photo unavailable'), findsNothing);
      expect(find.text('Google Maps · Credits'), findsOneWidget);
      expect(sourceLoads, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a replacement URL cannot retain the previous photo credits', (
    tester,
  ) async {
    final initial = _pendingPhoto(photo);
    initial.complete(await _decodedPhoto(tester));
    await tester.pumpWidget(_photoHost(photo));
    await tester.pump();
    expect(find.text('Google Maps · Credits'), findsOneWidget);

    const replacement = '$photo-new';
    final pending = _pendingPhoto(replacement);
    await tester.pumpWidget(_photoHost(replacement));
    expect(find.text('Google Maps · Credits'), findsNothing);
    pending.completeError(
      NetworkImageLoadException(statusCode: 404, uri: Uri.parse(replacement)),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Google Maps · Credits'), findsNothing);
    expect(find.text('Photo unavailable'), findsOneWidget);

    await tester.pumpWidget(_photoHost(''));
    expect(find.text('Google Maps · Credits'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('explicitly disabled source badges stay hidden on valid photos', (
    tester,
  ) async {
    final image = _pendingPhoto(photo);
    image.complete(await _decodedPhoto(tester));
    await tester.pumpWidget(_photoHost(photo, showSourceBadge: false));
    await tester.pump();
    expect(find.text('Google Maps · Credits'), findsNothing);
    expect(find.text('Photo unavailable'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('credits keep valid contributor and source links', (
    tester,
  ) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GooglePhotoSourceSheet(
            photoUrl: photo,
            sourceLoader: (_) async => source,
            linkLauncher: (uri) async {
              opened.add(uri);
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('View on Google Maps'));
    await tester.pump();
    await tester.tap(find.text('Alice'));
    await tester.pump();
    await tester.tap(find.text('Report to Google Maps'));
    await tester.pump();
    expect(opened, [
      source.sourceUrl,
      source.authors.single.profileUrl,
      source.reportUrl,
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('source errors can retry without navigation or a stale author', (
    tester,
  ) async {
    var loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GooglePhotoSourceSheet(
            photoUrl: photo,
            sourceLoader: (_) {
              loads++;
              return loads == 1
                  ? Future.error(StateError('expired'))
                  : Future.value(source);
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Alice'), findsOneWidget);
    expect(loads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('source sheet scrolls on small screens with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: Scaffold(
          body: GooglePhotoSourceSheet(
            photoUrl: photo,
            sourceLoader: (_) async => source,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'map venue photo strips preserve card navigation without a new photo/report interaction',
    (tester) async {
      var taps = 0;
      final venue = Venue(
        id: 'google:ChIJVenue123',
        name: 'Test venue',
        type: 'CAFE',
        status: 'ACTIVE',
        address: 'Dubai',
        city: 'Dubai',
        photoUrl: photo,
        latitude: 25,
        longitude: 55,
        tag: '',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: VenueListItem(venue: venue, onTap: (_) => taps++),
            ),
          ),
        ),
      );
      // CachedImage is decorative; its parent venue card owns this gesture.
      await tester.tapAt(tester.getCenter(find.byType(CachedImage).first));
      await tester.pump();
      expect(taps, 1);
      expect(find.byType(GooglePlacePhoto), findsNothing);
      expect(find.byType(GooglePhotoSourceSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
