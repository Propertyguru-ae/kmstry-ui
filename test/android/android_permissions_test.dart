import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  String permission(String name) =>
      RegExp(
        '<uses-permission\\b[^>]*android:name="android.permission.$name"[^>]*/>',
      ).firstMatch(manifest)?.group(0) ??
      '';

  test('selected-file access does not request the entire media library', () {
    for (final name in [
      'READ_MEDIA_IMAGES',
      'READ_MEDIA_VIDEO',
      'READ_MEDIA_AUDIO',
    ]) {
      expect(permission(name), contains('tools:node="remove"'), reason: name);
    }
    expect(manifest, isNot(contains('MANAGE_EXTERNAL_STORAGE')));
    for (final name in ['READ_EXTERNAL_STORAGE', 'WRITE_EXTERNAL_STORAGE']) {
      expect(permission(name), contains('android:maxSdkVersion="28"'));
    }
  });

  test(
    'release declares internet and existing feature permissions explicitly',
    () {
      for (final name in [
        'INTERNET',
        'CAMERA',
        'RECORD_AUDIO',
        'ACCESS_FINE_LOCATION',
        'ACCESS_COARSE_LOCATION',
        'POST_NOTIFICATIONS',
      ]) {
        expect(permission(name), isNotEmpty, reason: name);
        expect(permission(name), isNot(contains('tools:node="remove"')));
      }
      expect(manifest, contains('android:usesCleartextTraffic="false"'));
    },
  );
}
