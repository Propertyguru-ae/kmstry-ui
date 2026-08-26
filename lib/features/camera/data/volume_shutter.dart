import 'package:flutter/services.dart';

/// Bridges supported hardware capture buttons to the active camera screen.
///
/// The native side only intercepts buttons while [setEnabled] is true. This
/// keeps the normal system volume behavior everywhere else in the app.
class VolumeShutter {
  static const MethodChannel _channel = MethodChannel('app/volume_shutter');

  static void listen(Future<void> Function() onPressed) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onVolumeShutter') {
        await onPressed();
      }
    });
  }

  static Future<void> setEnabled(bool enabled) async {
    await _channel.invokeMethod<void>('setEnabled', enabled);
  }

  static void stopListening() {
    _channel.setMethodCallHandler(null);
  }
}
