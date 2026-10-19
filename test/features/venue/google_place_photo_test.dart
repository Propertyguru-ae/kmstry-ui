import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/media/media_network_url.dart';
import 'package:kmstry_frontend/core/media/media_reference.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
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

Widget _coverHost({
  String url = photo,
  GooglePhotoSourceLoader? loader,
  double width = 320,
  double scale = 1,
  bool dark = true,
}) => MaterialApp(
  theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      child: SizedBox(
        width: width,
        child: GooglePlacePhoto(
          url,
          showAuthorAttribution: true,
          creditsBelowPhotoHeight: 210,
          sourceLoader: loader ?? (_) async => source,
          errorWidget: (_) => const Text('Photo unavailable'),
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

  for (final dark in [true, false]) {
    for (final width in [320.0, 390.0]) {
      for (final scale in [1.0, 1.8]) {
        testWidgets(
          'cover footer stays below image: dark=$dark width=$width scale=$scale',
          (tester) async {
            final pending = _pendingPhoto(photo);
            pending.complete(await _decodedPhoto(tester));
            final contributors = GooglePhotoSource(
              photoUrl: photo,
              authors: [
                GooglePhotoAuthor(
                  name: 'A contributor with a very long display name',
                  profileUrl: source.authors.first.profileUrl,
                ),
                const GooglePhotoAuthor(name: 'Second contributor'),
              ],
              sourceUrl: source.sourceUrl,
              reportUrl: source.reportUrl,
              reportIsDirect: true,
            );
            await tester.pumpWidget(
              _coverHost(
                width: width,
                scale: scale,
                dark: dark,
                loader: (_) async => contributors,
              ),
            );
            await tester.pumpAndSettle();
            final imageRect = tester.getRect(
              find.byKey(const ValueKey('google-photo-cover-image')),
            );
            final footerRect = tester.getRect(
              find.byKey(const ValueKey('google-photo-credits-footer')),
            );
            expect(imageRect.height, 210);
            expect(footerRect.top, greaterThanOrEqualTo(imageRect.bottom));
            expect(find.text('Google Maps · Credits'), findsNothing);
            expect(find.text('Google Maps'), findsOneWidget);
            expect(
              find.text('A contributor with a very long display name'),
              findsOneWidget,
            );
            expect(find.text('Second contributor'), findsOneWidget);
            for (final text in [
              'Google Maps',
              'Credits',
              'A contributor with a very long display name',
              'Second contributor',
            ]) {
              final rect = tester.getRect(find.text(text));
              expect(rect.left, greaterThanOrEqualTo(footerRect.left));
              expect(rect.right, lessThanOrEqualTo(footerRect.right));
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets(
    'footer opens the unchanged credits sheet for the exact displayed source',
    (tester) async {
      const fresh = '$photo-fresh';
      _pendingPhoto(fresh).complete(await _decodedPhoto(tester));
      var loads = 0;
      final exactSource = GooglePhotoSource(
        photoUrl: fresh,
        authors: source.authors,
        sourceUrl: source.sourceUrl,
        reportUrl: source.reportUrl,
        reportIsDirect: true,
      );
      await tester.pumpWidget(
        _coverHost(
          loader: (_) async {
            loads++;
            return exactSource;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);
      await tester.tap(find.text('Credits'));
      await tester.pumpAndSettle();
      expect(find.byType(GooglePhotoSourceSheet), findsOneWidget);
      expect(find.text('Photo credits'), findsOneWidget);
      expect(find.text('Photo contributor'), findsOneWidget);
      expect(find.text('View on Google Maps'), findsOneWidget);
      expect(find.text('Report to Google Maps'), findsOneWidget);
      expect(find.byKey(ValueKey('credited-photo:$fresh')), findsOneWidget);
      expect(loads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed cover image has no orphaned footer or author', (
    tester,
  ) async {
    final pending = _pendingPhoto(photo);
    await tester.pumpWidget(_coverHost());
    await tester.pump();
    expect(
      find.byKey(const ValueKey('google-photo-credits-footer')),
      findsNothing,
    );
    pending.completeError(
      NetworkImageLoadException(statusCode: 404, uri: Uri.parse(photo)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Photo unavailable'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);
    expect(
      find.byKey(const ValueKey('google-photo-credits-footer')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cover without author metadata shows source but invents no author',
    (tester) async {
      _pendingPhoto(photo).complete(await _decodedPhoto(tester));
      await tester.pumpWidget(
        _coverHost(
          loader: (_) async => GooglePhotoSource(
            photoUrl: photo,
            authors: const [],
            sourceUrl: source.sourceUrl,
            reportUrl: source.reportUrl,
            reportIsDirect: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Photo by'), findsNothing);
      expect(find.text('Google Maps'), findsOneWidget);
      expect(find.text('Credits'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cover metadata retry keeps image height and never shows stale credits',
    (tester) async {
      _pendingPhoto(photo).complete(await _decodedPhoto(tester));
      var loads = 0;
      await tester.pumpWidget(
        _coverHost(
          loader: (_) async {
            if (++loads == 1) throw StateError('offline');
            return source;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(GooglePlacePhoto)).height, 210);
      expect(
        find.byKey(const ValueKey('google-photo-credits-footer')),
        findsNothing,
      );
      await tester.tap(find.text('Retry photo'));
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('google-photo-credits-footer')),
        findsOneWidget,
      );
      expect(loads, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cover URL replacement hides old author until the new exact photo loads',
    (tester) async {
      const replacement = '$photo-next';
      _pendingPhoto(photo).complete(await _decodedPhoto(tester));
      final newImage = _pendingPhoto(replacement);
      final newSource = Completer<GooglePhotoSource>();
      Future<GooglePhotoSource> loader(String url) =>
          url == photo ? Future.value(source) : newSource.future;
      await tester.pumpWidget(_coverHost(loader: loader));
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);
      await tester.pumpWidget(_coverHost(url: replacement, loader: loader));
      await tester.pump();
      expect(find.text('Alice'), findsNothing);
      expect(
        find.byKey(const ValueKey('google-photo-credits-footer')),
        findsNothing,
      );
      newSource.complete(
        GooglePhotoSource(
          photoUrl: replacement,
          authors: const [GooglePhotoAuthor(name: 'Bob')],
          sourceUrl: source.sourceUrl,
          reportUrl: source.reportUrl,
          reportIsDirect: true,
        ),
      );
      await tester.pump();
      expect(find.text('Bob'), findsNothing);
      newImage.complete(await _decodedPhoto(tester));
      await tester.pumpAndSettle();
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

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
    'credits pair a larger contained photo with attribution without a new fullscreen route',
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
      final preview = tester.widget<CachedImage>(
        find.byKey(ValueKey('credited-photo:${source.photoUrl}')),
      );
      expect(preview.url, source.photoUrl);
      expect(preview.fit, BoxFit.contain);
      expect(tester.getSize(find.byWidget(preview)).height, greaterThan(140));
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
    await tester.ensureVisible(find.text('View on Google Maps'));
    await tester.tap(find.text('View on Google Maps'));
    await tester.pump();
    await tester.ensureVisible(find.text('Alice'));
    await tester.tap(find.text('Alice'));
    await tester.pump();
    await tester.ensureVisible(find.text('Report to Google Maps'));
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
    'large covers show matching authors without replacing page navigation',
    (tester) async {
      const fresh = '$photo-fresh';
      final decoded = _pendingPhoto(fresh);
      decoded.complete(await _decodedPhoto(tester));
      final attributed = GooglePhotoSource(
        photoUrl: fresh,
        authors: source.authors,
        sourceUrl: source.sourceUrl,
        reportUrl: source.reportUrl,
        reportIsDirect: true,
      );
      var loads = 0;
      Future<GooglePhotoSource> loader(String _) async {
        loads++;
        return attributed;
      }

      Widget host() => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 210,
            child: GooglePlacePhoto(
              photo,
              showAuthorAttribution: true,
              mediaReference: const MediaReference(
                mediaId: 'old-photo',
                url: photo,
              ),
              sourceLoader: loader,
            ),
          ),
        ),
      );
      await tester.pumpWidget(host());
      await tester.pump();
      await tester.pump();
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Google Maps · Credits'), findsOneWidget);
      final preview = tester.widget<CachedImage>(find.byType(CachedImage));
      expect(preview.url, fresh);
      expect(preview.mediaReference, isNull);
      await tester.pumpWidget(host());
      await tester.pump();
      expect(loads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cover source failure is retryable without showing uncredited media',
    (tester) async {
      final decoded = _pendingPhoto(photo);
      decoded.complete(await _decodedPhoto(tester));
      var loads = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 210,
              child: GooglePlacePhoto(
                photo,
                showAuthorAttribution: true,
                sourceLoader: (_) async {
                  if (++loads == 1) throw StateError('offline');
                  return source;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Retry photo'), findsOneWidget);
      expect(find.byType(CachedImage), findsNothing);
      await tester.tap(find.text('Retry photo'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Alice'), findsOneWidget);
      expect(loads, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'source replacement never shows the old photo or author while loading',
    (tester) async {
      final pending = Completer<GooglePhotoSource>();
      Future<GooglePhotoSource> loader(String url) =>
          url == photo ? Future.value(source) : pending.future;
      Widget host(String url) => MaterialApp(
        home: Scaffold(
          body: GooglePhotoSourceSheet(photoUrl: url, sourceLoader: loader),
        ),
      );
      await tester.pumpWidget(host(photo));
      await tester.pump();
      expect(find.text('Alice'), findsOneWidget);
      await tester.pumpWidget(host('$photo-new'));
      expect(find.text('Alice'), findsNothing);
      expect(find.byType(CachedImage), findsNothing);
      pending.complete(
        GooglePhotoSource(
          photoUrl: '$photo-new',
          authors: const [GooglePhotoAuthor(name: 'Bob')],
          sourceUrl: source.sourceUrl,
          reportUrl: source.reportUrl,
          reportIsDirect: true,
        ),
      );
      await tester.pump();
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing optional authors never invents a contributor', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GooglePhotoSourceSheet(
            photoUrl: photo,
            sourceLoader: (_) async => GooglePhotoSource(
              photoUrl: photo,
              authors: const [],
              sourceUrl: source.sourceUrl,
              reportUrl: source.reportUrl,
              reportIsDirect: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('PHOTO BY'), findsNothing);
    expect(find.text('Photo contributor'), findsNothing);
    expect(find.text('View on Google Maps'), findsOneWidget);
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

  testWidgets(
    'map strip shows source only for decoded Google photos; card tap still opens venue',
    (tester) async {
      final pending = _pendingPhoto(photo);
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
      expect(find.text('Google Maps · Credits'), findsNothing);
      pending.complete(await _decodedPhoto(tester));
      await tester.pump();
      await tester.pump();
      expect(find.text('Google Maps · Credits'), findsOneWidget);
      await tester.tapAt(tester.getCenter(find.byType(CachedImage).first));
      expect(taps, 1);
      expect(find.byType(GooglePhotoSourceSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
