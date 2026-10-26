// Local iOS-only asset exporter. Never use this target for a store build.
// Restores the original Continue screen's system-font weight and blue shadow.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  if (kReleaseMode || !Platform.isIOS) {
    throw StateError('Run this local asset exporter in an iOS simulator.');
  }
  WidgetsFlutterBinding.ensureInitialized();
  final directory = Directory(
    '${(await getApplicationDocumentsDirectory()).path}/startup-wordmark',
  );
  await directory.create(recursive: true);
  for (final dark in [false, true]) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(4);
    final text = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: 'KMSTRY',
        style: TextStyle(
          fontFamily: 'CupertinoSystemText',
          color: dark ? Colors.white : const Color(0xFF111827),
          fontSize: 52,
          fontWeight: FontWeight.w900,
          letterSpacing: 7,
          height: 1,
          shadows: const [
            Shadow(
              color: Color(0x661A9FE8),
              blurRadius: 22,
              offset: Offset(0, 8),
            ),
          ],
        ),
      ),
    )..layout();
    // Same optical correction used by the original Continue screen.
    text.paint(canvas, Offset((339 - text.width) / 2 + 3.5, 250));
    text.dispose();
    final picture = recorder.endRecording();
    final image = await picture.toImage(1356, 1808);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '${directory.path}/${dark ? 'dark' : 'light'}.png',
    ).writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
    picture.dispose();
  }
  debugPrint('STARTUP_WORDMARK_EXPORTED ${directory.path}');
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Local wordmark export complete')),
      ),
    ),
  );
}
