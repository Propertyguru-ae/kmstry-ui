import 'dart:async';
import 'package:flutter/material.dart';

/// Shared with the native launch image: 1017×1356 pixels displayed at 3x.
/// Never independently typeset the wordmark or animate this layer's geometry.
abstract final class StartupBrand {
  static const lightAsset = 'assets/images/startup_brand_light.png';
  static const darkAsset = 'assets/images/startup_brand_dark.png';
  static const size = Size(339, 452);
  static const lift = 32.0;
  static const logoCenter = Offset(169.5, 127.1666666667);
  static const wordmarkBottom = 301.3333333333;
  static const revealDuration = Duration(milliseconds: 350);
  static const imageKey = ValueKey('startup-brand-image');

  static String assetFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkAsset : lightAsset;

  /// Decode bundled artwork before runApp so the first Flutter frame doesn't
  /// replace the native logo with an empty image while decoding. No network.
  static Future<void> warmUp() =>
      Future.wait([_warmAsset(lightAsset), _warmAsset(darkAsset)]);

  static Future<void> _warmAsset(String asset) async {
    final ready = Completer<void>();
    final stream = AssetImage(asset).resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener(
      (image, synchronousCall) {
        image.dispose();
        if (!ready.isCompleted) ready.complete();
      },
      onError: (error, stack) {
        // A broken decorative asset must never prevent account access.
        debugPrint('Startup artwork could not be preloaded.');
        if (!ready.isCompleted) ready.complete();
      },
    );
    stream.addListener(listener);
    try {
      await ready.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    } finally {
      stream.removeListener(listener);
    }
  }
}
