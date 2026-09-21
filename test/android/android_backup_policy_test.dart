import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android fresh installs cannot restore device-only preferences', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final legacyRules = File(
      'android/app/src/main/res/xml/backup_rules.xml',
    ).readAsStringSync();
    final modernRules = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
    expect(legacyRules, contains('domain="sharedpref" path="."'));
    expect(modernRules, contains('<cloud-backup>'));
    expect(modernRules, contains('<device-transfer>'));
    expect(
      RegExp('domain="sharedpref" path="\\."').allMatches(modernRules),
      hasLength(2),
    );
  });
}
