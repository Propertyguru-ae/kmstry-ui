import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/media/google_photo_updates.dart';
import 'package:kmstry_frontend/features/venue/presentation/google_place_photo.dart';

String _photo(String placeId, {String kind = 'place'}) {
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'v': 1,
            'kind': kind,
            'reference': kind == 'new'
                ? 'places/$placeId/photos/p1'
                : kind == 'legacy'
                ? 'legacy-photo'
                : placeId,
            if (kind == 'legacy') 'placeId': placeId,
          }),
        ),
      )
      .replaceAll('=', '');
  return 'http://localhost:3000/venues/places/photo/$payload.signature';
}

Completer<ImageInfo> _pending(String url) {
  final result = Completer<ImageInfo>();
  PaintingBinding.instance.imageCache.putIfAbsent(
    NetworkImage(GooglePhotoUpdates.instance.networkUrl(url)),
    () => OneFrameImageStreamCompleter(result.future),
  );
  return result;
}

Future<ImageInfo> _image(WidgetTester tester) async {
  final decoded = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(Colors.blue, ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(1, 1);
    picture.dispose();
    return image;
  });
  return ImageInfo(image: decoded!);
}

Widget _host(String url) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 200,
      height: 150,
      child: GooglePlacePhoto(url, errorWidget: (_) => const Text('No photo')),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  for (final kind in ['place', 'new', 'legacy']) {
    test(
      '$kind photo invalidation is targeted and preserves the signed token',
      () {
        final updates = GooglePhotoUpdates();
        final affected = _photo('ChIJaffected', kind: kind);
        final other = _photo('ChIJother', kind: kind);
        var notifications = 0;
        updates.addListener(() => notifications++);
        expect(GooglePhotoUpdates.placeIdFor(affected), 'ChIJaffected');
        updates.handleUpdate({'placeId': 'ChIJaffected'});
        final hidden = updates.networkUrl(affected);
        expect(Uri.parse(hidden).path, Uri.parse(affected).path);
        expect(hidden, startsWith(AppConfig.baseUrl));
        expect(updates.revisionFor(affected), isNotEmpty);
        expect(updates.revisionFor(other), isEmpty);
        updates.handleUpdate({'placeId': 'ChIJaffected'});
        expect(updates.networkUrl(affected), isNot(hidden));
        expect(notifications, 2);
        updates.dispose();
      },
    );
  }

  test('catch-up revalidates every Google URL but never owner uploads', () {
    final updates = GooglePhotoUpdates();
    final google = _photo('ChIJtest');
    const owned = 'https://media.example/venue-photos/upload.jpg?signature=abc';
    updates.handleUpdate({'placeId': 'ChIJtest'});
    final previous = updates.networkUrl(google);
    updates.revalidate();
    expect(updates.networkUrl(google), isNot(previous));
    expect(updates.revisionFor(_photo('ChIJother')), isNotEmpty);
    expect(updates.networkUrl(owned), owned);
    expect(updates.revisionFor(owned), isEmpty);
    final firstCatchup = updates.networkUrl(google);
    updates
        .revalidate(); // A reconnect immediately after resume must not be lost.
    expect(updates.networkUrl(google), isNot(firstCatchup));
    updates.dispose();
  });

  test(
    'malformed events/tokens do not crash or invalidate unrelated media',
    () {
      final updates = GooglePhotoUpdates();
      var changes = 0;
      updates.addListener(() => changes++);
      for (final value in [null, 42, '', '../secret', 'a' * 257]) {
        updates.handleUpdate({'placeId': value});
      }
      expect(changes, 0);
      expect(
        GooglePhotoUpdates.placeIdFor('https://example.com/a.jpg'),
        isNull,
      );
      expect(
        GooglePhotoUpdates.placeIdFor('/venues/places/photo/bad.token'),
        isNull,
      );
      updates.dispose();
    },
  );

  testWidgets(
    'visible photo disappears and restores in place, with credits, without page navigation',
    (tester) async {
      final url = _photo('ChIJlive');
      final initial = _pending(url);
      initial.complete(await _image(tester));
      await tester.pumpWidget(_host(url));
      await tester.pump();
      expect(find.text('Google Maps · Credits'), findsOneWidget);

      GooglePhotoUpdates.instance.handleUpdate({'placeId': 'ChIJlive'});
      final hidden = _pending(url);
      await tester.pump();
      expect(find.text('Google Maps · Credits'), findsNothing);
      hidden.completeError(
        NetworkImageLoadException(statusCode: 404, uri: Uri.parse(url)),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('No photo'), findsOneWidget);

      GooglePhotoUpdates.instance.handleUpdate({'placeId': 'ChIJlive'});
      final restored = _pending(url);
      restored.complete(await _image(tester));
      await tester.pump();
      await tester.pump();
      expect(find.text('Google Maps · Credits'), findsOneWidget);
      expect(find.text('No photo'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'an old download cannot repaint a hidden photo after invalidation',
    (tester) async {
      final url = _photo('ChIJrace');
      final oldDownload = _pending(url);
      await tester.pumpWidget(_host(url));
      GooglePhotoUpdates.instance.handleUpdate({'placeId': 'ChIJrace'});
      final newDownload = _pending(url);
      await tester.pump();
      newDownload.completeError(
        NetworkImageLoadException(statusCode: 404, uri: Uri.parse(url)),
      );
      await tester.pump();
      oldDownload.complete(await _image(tester));
      await tester.pump();
      await tester.pump();
      expect(find.text('No photo'), findsOneWidget);
      expect(find.text('Google Maps · Credits'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missed restore recovers after reconnect with the same mounted widget',
    (tester) async {
      final url = _photo('ChIJreconnect');
      final rejected = _pending(url);
      await tester.pumpWidget(_host(url));
      rejected.completeError(
        NetworkImageLoadException(statusCode: 404, uri: Uri.parse(url)),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('No photo'), findsOneWidget);
      GooglePhotoUpdates.instance.revalidate();
      final restored = _pending(url);
      restored.complete(await _image(tester));
      await tester.pump();
      await tester.pump();
      expect(find.text('Google Maps · Credits'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
