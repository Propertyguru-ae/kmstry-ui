import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/media/media_network_url.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/features/venue/data/google_photo_source.dart';
import 'package:kmstry_frontend/features/venue/presentation/google_place_photo.dart';

const photo =
    'https://pre-prod-api.kmstry.net/venues/places/photo/layout.signature';
final source = GooglePhotoSource(
  photoUrl: photo,
  authors: [
    GooglePhotoAuthor(
      name: 'Example Contributor',
      profileUrl: Uri.parse('https://www.google.com/maps/contrib/example'),
    ),
  ],
  sourceUrl: Uri.parse('https://www.google.com/maps/photo/example'),
  reportUrl: Uri.parse('https://www.google.com/maps/photo/example'),
  reportIsDirect: false,
);

Future<void> seedPhoto(WidgetTester tester) async {
  final image = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 480, 320),
      Paint()..color = const Color(0xFF27445A),
    );
    canvas.drawRect(
      const Rect.fromLTWH(24, 24, 200, 200),
      Paint()..color = const Color(0xFF4A7D87),
    );
    canvas.drawRect(
      const Rect.fromLTWH(248, 80, 208, 216),
      Paint()..color = const Color(0xFFBE986E),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(480, 320);
    picture.dispose();
    return image;
  });
  PaintingBinding.instance.imageCache.putIfAbsent(
    NetworkImage(resolveMediaNetworkUrl(photo)),
    () => OneFrameImageStreamCompleter(Future.value(ImageInfo(image: image!))),
  );
}

void main() {
  setUpAll(() async {
    // Optional real-font visual QA; no host-specific path is required in CI.
    final fonts = Platform.environment['KMSTRY_CAPTURE_FONTS'];
    if (fonts == null) return;
    for (final entry in {
      'Roboto': ['Roboto-Regular.ttf', 'Roboto-Bold.ttf'],
      'MaterialIcons': ['MaterialIcons-Regular.otf'],
    }.entries) {
      final loader = FontLoader(entry.key);
      for (final file in entry.value) {
        loader.addFont(
          File('$fonts/$file').readAsBytes().then(ByteData.sublistView),
        );
      }
      await loader.load();
    }
  });
  for (final sheet in [false, true]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets(
        '${sheet ? 'sheet' : 'cover'} on a narrow screen at text scale $scale',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(() {
            PaintingBinding.instance.imageCache.clear();
            PaintingBinding.instance.imageCache.clearLiveImages();
          });
          await seedPhoto(tester);
          final boundary = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.darkTheme.copyWith(
                textTheme: AppTheme.darkTheme.textTheme.apply(
                  fontFamily: 'Roboto',
                ),
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: RepaintBoundary(
                key: boundary,
                child: Scaffold(
                  body: SafeArea(
                    child: sheet
                        ? Align(
                            alignment: Alignment.bottomCenter,
                            child: GooglePhotoSourceSheet(
                              photoUrl: photo,
                              sourceLoader: (_) async => source,
                            ),
                          )
                        : SizedBox(
                            height: 210,
                            width: double.infinity,
                            child: GooglePlacePhoto(
                              photo,
                              showAuthorAttribution: true,
                              sourceLoader: (_) async => source,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Example Contributor'), findsOneWidget);
          expect(tester.takeException(), isNull);
          if (sheet) {
            await tester.ensureVisible(find.text('View on Google Maps'));
            expect(
              find.text('View on Google Maps').hitTestable(),
              findsOneWidget,
            );
            await tester.drag(
              find.byType(SingleChildScrollView),
              const Offset(0, 800),
            );
            await tester.pumpAndSettle();
          }
          // Optional visual QA output; normal CI tests do not write artifacts.
          final directory = Platform.environment['KMSTRY_CAPTURE_DIR'];
          if (directory != null && scale == 1) {
            await tester.runAsync(() async {
              final render =
                  boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await render.toImage();
              final png = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                '$directory/${sheet ? 'credits' : 'cover'}.png',
              ).writeAsBytes(png!.buffer.asUint8List());
              image.dispose();
            });
          }
        },
      );
    }
  }
}
